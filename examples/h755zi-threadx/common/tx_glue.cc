// Board glue for ThreadX on the STM32H755, compiled into each core's image:
// low-level initialization, tick ISR, stack error handler.

#include <cstdint>

#include "SEGGER_SYSVIEW.h"
#include "stm32h7xx_hal.h"
#include "tx_api.h"
#include "tx_glue.h"

// ThreadX internal headers (for _tx_thread_system_stack_ptr and
// _tx_initialize_unused_memory) have no C++ guards of their own.
extern "C" {
#include "tx_initialize.h"
#include "tx_thread.h"

// Defined by the port (tx_timer_interrupt.S); not declared in a header.
void _tx_timer_interrupt();
}

namespace {

// Set by _tx_initialize_low_level(). HAL_Init() starts SysTick before the
// kernel exists, and _tx_timer_interrupt() must not run until then.
volatile bool tick_enabled = false;

// Exception priorities, 4 NVIC priority bits on the STM32H7.
constexpr std::uint32_t kPendSvPriority = 15;   // lowest, required by ThreadX
constexpr std::uint32_t kSvCallPriority = 15;
constexpr std::uint32_t kSysTickPriority = 4;

}  // namespace

// Called by tx_kernel_enter() with interrupts disabled (see tx_glue.h).
extern "C" void _tx_initialize_low_level() {
  // ISRs and the scheduler use the main stack; its top is the initial MSP,
  // the first word of the active vector table.
  const auto* vector_table = reinterpret_cast<const std::uint32_t*>(SCB->VTOR);
  _tx_thread_system_stack_ptr = reinterpret_cast<VOID*>(vector_table[0]);

  // All memory is allocated statically; tx_application_define() gets no
  // unused-memory pointer.
  _tx_initialize_unused_memory = TX_NULL;

  NVIC_SetPriority(PendSV_IRQn, kPendSvPriority);
  NVIC_SetPriority(SVCall_IRQn, kSvCallPriority);

  // Same rate as the HAL tick, so HAL_GetTick() stays in milliseconds.
  SysTick_Config(SystemCoreClock / TX_TIMER_TICKS_PER_SECOND);
  NVIC_SetPriority(SysTick_IRQn, kSysTickPriority);

  tick_enabled = true;
}

// SysTick drives both the HAL tick (HAL_Delay, HAL timeouts) and the ThreadX
// tick. Recorded for SystemView here: Cortex-M ISRs do not go through
// _tx_thread_context_save(), so the kernel's ISR hooks never run.
extern "C" void SysTick_Handler() {
  SEGGER_SYSVIEW_RecordEnterISR();
  HAL_IncTick();
  if (tick_enabled) {
    _tx_timer_interrupt();
  }
  // A thread woken by the tick (sleep timeout) runs after this ISR.
  if (_tx_thread_execute_ptr != _tx_thread_current_ptr) {
    SEGGER_SYSVIEW_RecordExitISRToScheduler();
  } else {
    SEGGER_SYSVIEW_RecordExitISR();
  }
}

void TxStackErrorHandler(TX_THREAD* /*thread*/) {
  __disable_irq();
  __builtin_trap();
}
