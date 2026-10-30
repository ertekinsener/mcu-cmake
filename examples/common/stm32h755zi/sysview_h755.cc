#include "sysview_h755.h"

#include <cstdint>

#include "stm32h7xx.h"

namespace h755 {
namespace {

#if defined(CORE_CM7)
constexpr const char* kDeviceDescription = "D=STM32H755ZI CM7,I#15=SysTick";
// DTCM; the CM7's .data/.bss (and so all kernel objects) live at or above it.
constexpr std::uint32_t kRamBase = 0x20000000;
#elif defined(CORE_CM4)
constexpr const char* kDeviceDescription = "D=STM32H755ZI CM4,I#15=SysTick";
// D2 SRAM through the CM4 alias.
constexpr std::uint32_t kRamBase = 0x10000000;
#else
#error "Define CORE_CM7 or CORE_CM4 (set by the chip target)"
#endif

// CoreSight lock access register (offset 0xFB0) and its unlock key.
constexpr std::uint32_t kLockAccessOffset = 0xFB0;
constexpr std::uint32_t kLockAccessKey = 0xC5ACCE55;

const char* app_description = "";

void SendSystemDescription() {
  SEGGER_SYSVIEW_SendSysDesc(app_description);
  SEGGER_SYSVIEW_SendSysDesc(kDeviceDescription);
}

// SystemView's default Cortex-M timestamp is DWT->CYCCNT. A debugger usually
// enables it, but not always, and recording also has to work after a reset
// without one.
void EnableCycleCounter() {
  CoreDebug->DEMCR |= CoreDebug_DEMCR_TRCENA_Msk;
  // The CM7 DWT is write-locked after reset (CoreSight lock); the CM4 ignores
  // the write. CMSIS has no DWT_Type::LAR member.
  *reinterpret_cast<volatile std::uint32_t*>(DWT_BASE + kLockAccessOffset) = kLockAccessKey;
  DWT->CYCCNT = 0;
  DWT->CTRL |= DWT_CTRL_CYCCNTENA_Msk;
}

}  // namespace

void ConfigureSysview(const char* description, SEGGER_SYSVIEW_START_CALLBACK* on_start) {
  app_description = description;
  EnableCycleCounter();
  SEGGER_SYSVIEW_Init_Ex(SystemCoreClock, SystemCoreClock, &SYSVIEW_X_OS_TraceAPI,
                         SendSystemDescription, on_start, nullptr);
  SEGGER_SYSVIEW_SetRAMBase(kRamBase);
}

}  // namespace h755
