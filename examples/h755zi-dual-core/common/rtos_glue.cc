// Glue between the HAL and FreeRTOS, compiled into each core's image.

#include "FreeRTOS.h"
#include "stm32h7xx_hal.h"
#include "task.h"

// Defined by the FreeRTOS port; not declared in a public header.
extern "C" void xPortSysTickHandler();

// SysTick drives both the HAL tick (HAL_Delay, HAL timeouts) and the FreeRTOS
// tick. Both run at 1 kHz: HAL_InitTick() before the scheduler starts, the
// port's own SysTick setup (configTICK_RATE_HZ) after.
extern "C" void SysTick_Handler() {
  HAL_IncTick();
  if (xTaskGetSchedulerState() != taskSCHEDULER_NOT_STARTED) {
    xPortSysTickHandler();
  }
}

// configCHECK_FOR_STACK_OVERFLOW: stop in the debugger on overflow.
extern "C" void vApplicationStackOverflowHook(TaskHandle_t /*task*/, char* /*task_name*/) {
  taskDISABLE_INTERRUPTS();
  __builtin_trap();
}
