#include "middleware_demo.h"

#include <array>
#include <cstdint>
#include <cstring>
#include <initializer_list>
#include <utility>

#include "fx_api.h"
#include "gx_api.h"
#include "lx_api.h"
#include "SEGGER_RTT.h"
#include "nx_api.h"
#include "ux_api.h"

// Drivers that ship with the middleware libraries but have no public
// declaration.
extern "C" {
VOID _fx_ram_driver(FX_MEDIA* media_ptr);
VOID _fx_nor_flash_simulator_driver(FX_MEDIA* media_ptr);
UINT _lx_nor_flash_simulator_erase_all(VOID);
VOID _nx_ram_network_driver(NX_IP_DRIVER* driver_req_ptr);
}

volatile MiddlewareDemoStatus middleware_demo_status;

namespace {

constexpr UINT kDemoPriority = 12;  // below the blink thread
constexpr ULONG kSectorSize = 512;

// --- FileX helpers ------------------------------------------------------------

constexpr char kFileContent[] = "Hello from mcu-cmake";

// Creates HELLO.TXT, writes kFileContent, reads it back and compares.
UINT WriteAndVerifyFile(FX_MEDIA& media) {
  static char file_name[] = "HELLO.TXT";
  FX_FILE file;

  if (UINT status = fx_file_create(&media, file_name); status != FX_SUCCESS) return status;
  if (UINT status = fx_file_open(&media, &file, file_name, FX_OPEN_FOR_WRITE); status != FX_SUCCESS) {
    return status;
  }
  std::array<char, sizeof(kFileContent)> buffer{};
  std::memcpy(buffer.data(), kFileContent, sizeof(kFileContent));
  if (UINT status = fx_file_write(&file, buffer.data(), buffer.size()); status != FX_SUCCESS) return status;
  if (UINT status = fx_file_close(&file); status != FX_SUCCESS) return status;

  buffer.fill(0);
  ULONG actual = 0;
  if (UINT status = fx_file_open(&media, &file, file_name, FX_OPEN_FOR_READ); status != FX_SUCCESS) {
    return status;
  }
  if (UINT status = fx_file_read(&file, buffer.data(), buffer.size(), &actual); status != FX_SUCCESS) {
    return status;
  }
  if (UINT status = fx_file_close(&file); status != FX_SUCCESS) return status;
  if (actual != sizeof(kFileContent) ||
      std::memcmp(buffer.data(), kFileContent, sizeof(kFileContent)) != 0) {
    return FX_IO_ERROR;
  }
  return fx_media_flush(&media);
}

// --- FileX on a RAM disk -------------------------------------------------------

constexpr ULONG kRamDiskSectors = 128;  // 64 KiB
[[gnu::section(".ram_d1")]] alignas(4) std::array<std::uint8_t, kRamDiskSectors * kSectorSize> ram_disk;
alignas(4) std::array<std::uint8_t, kSectorSize> ram_media_buffer;
FX_MEDIA ram_media;

UINT RunFileXRamDisk() {
  static char volume_name[] = "RAMDISK";
  if (UINT status = fx_media_format(&ram_media, _fx_ram_driver, ram_disk.data(),
                                    ram_media_buffer.data(), ram_media_buffer.size(), volume_name,
                                    1, 32, 0, kRamDiskSectors, kSectorSize, 1, 1, 1);
      status != FX_SUCCESS) {
    return status;
  }
  if (UINT status = fx_media_open(&ram_media, volume_name, _fx_ram_driver, ram_disk.data(),
                                  ram_media_buffer.data(), ram_media_buffer.size());
      status != FX_SUCCESS) {
    return status;
  }
  UINT status = WriteAndVerifyFile(ram_media);
  fx_media_close(&ram_media);
  return status;
}

// --- FileX on the LevelX NOR simulator ----------------------------------------

constexpr ULONG kNorDiskSectors = 120;  // fits the simulator's 8 x 16 sectors
alignas(4) std::array<std::uint8_t, kSectorSize> nor_media_buffer;
FX_MEDIA nor_media;

UINT RunLevelXNorDisk() {
  static char volume_name[] = "NORDISK";
  lx_nor_flash_initialize();
  if (UINT status = _lx_nor_flash_simulator_erase_all(); status != LX_SUCCESS) return status;
  if (UINT status = fx_media_format(&nor_media, _fx_nor_flash_simulator_driver, FX_NULL,
                                    nor_media_buffer.data(), nor_media_buffer.size(), volume_name,
                                    1, 32, 0, kNorDiskSectors, kSectorSize, 1, 1, 1);
      status != FX_SUCCESS) {
    return status;
  }
  if (UINT status = fx_media_open(&nor_media, volume_name, _fx_nor_flash_simulator_driver, FX_NULL,
                                  nor_media_buffer.data(), nor_media_buffer.size());
      status != FX_SUCCESS) {
    return status;
  }
  UINT status = WriteAndVerifyFile(nor_media);
  fx_media_close(&nor_media);
  return status;
}

// --- NetX Duo on the RAM network driver ---------------------------------------

constexpr ULONG kPacketPayload = 1536;
constexpr ULONG kNetmask = 0xFFFFFF00UL;
constexpr UINT kIpThreadPriority = 1;

// IP_ADDRESS() without the C-style casts of the NetX macro.
constexpr ULONG IpAddress(std::uint8_t a, std::uint8_t b, std::uint8_t c, std::uint8_t d) {
  return (ULONG{a} << 24) | (ULONG{b} << 16) | (ULONG{c} << 8) | ULONG{d};
}
constexpr ULONG kIp0Address = IpAddress(1, 2, 3, 4);
constexpr ULONG kIp1Address = IpAddress(1, 2, 3, 5);

// Packet pool and thread stacks in AXI SRAM; DTCM holds .data/.bss (incl. the
// 64 KiB LevelX NOR simulator array) and the main stack. Stacks need no zero
// initialization, so the NOLOAD .ram_d1 section is fine for them.
[[gnu::section(".ram_d1")]] alignas(4) std::array<std::uint8_t, 32 * 1024> packet_pool_area;
[[gnu::section(".ram_d1")]] alignas(8) std::array<std::uint8_t, 2048> ip0_stack;
[[gnu::section(".ram_d1")]] alignas(8) std::array<std::uint8_t, 2048> ip1_stack;
alignas(4) std::array<std::uint8_t, 1024> ip0_arp_cache;
alignas(4) std::array<std::uint8_t, 1024> ip1_arp_cache;
NX_PACKET_POOL packet_pool;
NX_IP ip0;
NX_IP ip1;

UINT RunNetXPing() {
  static char pool_name[] = "pool";
  static char ip0_name[] = "ip0";
  static char ip1_name[] = "ip1";
  static char ping_data[] = "mcu-cmake";

  nx_system_initialize();
  if (UINT status = nx_packet_pool_create(&packet_pool, pool_name, kPacketPayload,
                                          packet_pool_area.data(), packet_pool_area.size());
      status != NX_SUCCESS) {
    return status;
  }
  if (UINT status = nx_ip_create(&ip0, ip0_name, kIp0Address, kNetmask, &packet_pool,
                                 _nx_ram_network_driver, ip0_stack.data(), ip0_stack.size(),
                                 kIpThreadPriority);
      status != NX_SUCCESS) {
    return status;
  }
  if (UINT status = nx_ip_create(&ip1, ip1_name, kIp1Address, kNetmask, &packet_pool,
                                 _nx_ram_network_driver, ip1_stack.data(), ip1_stack.size(),
                                 kIpThreadPriority);
      status != NX_SUCCESS) {
    return status;
  }
  for (auto [ip, cache] : {std::pair{&ip0, &ip0_arp_cache}, std::pair{&ip1, &ip1_arp_cache}}) {
    if (UINT status = nx_arp_enable(ip, cache->data(), cache->size()); status != NX_SUCCESS) {
      return status;
    }
    if (UINT status = nx_icmp_enable(ip); status != NX_SUCCESS) return status;
  }

  NX_PACKET* response = nullptr;
  UINT status = nx_icmp_ping(&ip0, kIp1Address, ping_data, sizeof(ping_data) - 1,
                             &response, NX_IP_PERIODIC_RATE);
  if (status == NX_SUCCESS) {
    nx_packet_release(response);
  }
  return status;
}

// --- USBX / GUIX ----------------------------------------------------------------

[[gnu::section(".ram_d1")]] alignas(8) std::array<std::uint8_t, 16 * 1024> usbx_memory;

UINT RunUsbxInit() { return ux_system_initialize(usbx_memory.data(), usbx_memory.size(), UX_NULL, 0); }

UINT RunGuixInit() { return gx_system_initialize(); }

// --- Demo thread ----------------------------------------------------------------

[[gnu::section(".ram_d1")]] alignas(8) std::array<std::uint8_t, 8 * 1024> demo_stack;
TX_THREAD demo_thread;

void DemoThread(ULONG /*input*/) {
  fx_system_initialize();
  middleware_demo_status.filex_ram_disk = RunFileXRamDisk();
  middleware_demo_status.levelx_nor_disk = RunLevelXNorDisk();
  middleware_demo_status.netx_ping = RunNetXPing();
  middleware_demo_status.usbx_init = RunUsbxInit();
  middleware_demo_status.guix_init = RunGuixInit();
  middleware_demo_status.done = true;

  SEGGER_RTT_printf(0,
                    "cm7: middleware demo: filex=%u levelx=%u netx=%u usbx=%u guix=%u "
                    "(0 = ok)\r\n",
                    middleware_demo_status.filex_ram_disk, middleware_demo_status.levelx_nor_disk,
                    middleware_demo_status.netx_ping, middleware_demo_status.usbx_init,
                    middleware_demo_status.guix_init);
}

}  // namespace

void StartMiddlewareDemo() {
  static char name[] = "middleware";
  tx_thread_create(&demo_thread, name, DemoThread, 0, demo_stack.data(), demo_stack.size(),
                   kDemoPriority, kDemoPriority, TX_NO_TIME_SLICE, TX_AUTO_START);
}
