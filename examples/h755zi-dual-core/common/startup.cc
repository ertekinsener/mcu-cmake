// Minimal Cortex-M startup for the example, used until the CMSIS startup
// files (startup_stm32h755xx_CM7.s / _CM4.s) are wired in through the vendor
// wrapper. Only the 16 core exception vectors are provided.
//
// Linked with -nostartfiles: crt0/crti are not used, so static constructors
// are run here directly instead of through __libc_init_array().

#include <cstdint>

using Handler = void (*)();

extern "C" {

// Provided by the generated linker script.
extern std::uint32_t _sidata;
extern std::uint32_t _sdata;
extern std::uint32_t _edata;
extern std::uint32_t _sbss;
extern std::uint32_t _ebss;
extern std::uint32_t _estack;
extern const Handler __preinit_array_start[];
extern const Handler __preinit_array_end[];
extern const Handler __init_array_start[];
extern const Handler __init_array_end[];

int main();

[[noreturn]] void Reset_Handler();
// Not [[noreturn]]: the weak handler aliases below must match its attributes.
void Default_Handler();

[[gnu::weak, gnu::alias("Default_Handler")]] void NMI_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void HardFault_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void MemManage_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void BusFault_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void UsageFault_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void SVC_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void DebugMon_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void PendSV_Handler();
[[gnu::weak, gnu::alias("Default_Handler")]] void SysTick_Handler();

[[gnu::used, gnu::section(".isr_vector")]] const Handler kVectorTable[16] = {
    reinterpret_cast<Handler>(&_estack),
    Reset_Handler,
    NMI_Handler,
    HardFault_Handler,
    MemManage_Handler,
    BusFault_Handler,
    UsageFault_Handler,
    nullptr,
    nullptr,
    nullptr,
    nullptr,
    SVC_Handler,
    DebugMon_Handler,
    nullptr,
    PendSV_Handler,
    SysTick_Handler,
};

void Reset_Handler() {
  // Enable CP10/CP11 (FPU) before any floating-point instruction runs.
  constexpr std::uintptr_t kCpacrAddress = 0xE000ED88;
  auto& cpacr = *reinterpret_cast<volatile std::uint32_t*>(kCpacrAddress);
  cpacr = cpacr | (0xFu << 20);
  asm volatile("dsb\n\tisb" ::: "memory");

  const std::uint32_t* src = &_sidata;
  for (std::uint32_t* dst = &_sdata; dst < &_edata; ++dst, ++src) {
    *dst = *src;
  }
  for (std::uint32_t* dst = &_sbss; dst < &_ebss; ++dst) {
    *dst = 0;
  }

  for (const Handler* init = __preinit_array_start; init < __preinit_array_end; ++init) {
    (*init)();
  }
  for (const Handler* init = __init_array_start; init < __init_array_end; ++init) {
    (*init)();
  }

  main();
  while (true) {
  }
}

void Default_Handler() {
  while (true) {
  }
}

}  // extern "C"

// GCC 15 enables _GLIBCXX_ASSERTIONS at -O0. The libstdc++ handler prints via
// fprintf and calls abort, which pulls stdio, malloc and the nosys stubs.
// Overriding it keeps the checks but just traps into the debugger.
namespace std {
[[noreturn]] void __glibcxx_assert_fail(const char* /*file*/, int /*line*/,
                                        const char* /*function*/,
                                        const char* /*condition*/) noexcept {
  __builtin_trap();
}
}  // namespace std
