#ifndef EXAMPLES_H755ZI_FREERTOS_COMMON_FREERTOSCONFIG_H_
#define EXAMPLES_H755ZI_FREERTOS_COMMON_FREERTOSCONFIG_H_

// FreeRTOS configuration shared by both cores. Each core runs its own kernel
// instance; core-specific values (clock) come from the core's own
// SystemCoreClock.

#if !defined(__ASSEMBLER__)
#include <stdint.h>
// C linkage also when included from C++: it must match the declaration in
// ST's system_stm32h7xx.h.
#ifdef __cplusplus
extern "C" {
#endif
extern uint32_t SystemCoreClock;
#ifdef __cplusplus
}
#endif
#endif

// Scheduler.
#define configUSE_PREEMPTION                      1
#define configUSE_PORT_OPTIMISED_TASK_SELECTION   1
#define configUSE_TICKLESS_IDLE                   0
#define configCPU_CLOCK_HZ                        (SystemCoreClock)
#define configTICK_RATE_HZ                        1000
#define configMAX_PRIORITIES                      8
#define configMINIMAL_STACK_SIZE                  128
#define configMAX_TASK_NAME_LEN                   16
#define configTICK_TYPE_WIDTH_IN_BITS             TICK_TYPE_WIDTH_32_BITS
#define configIDLE_SHOULD_YIELD                   1
#define configUSE_TIME_SLICING                    1

// Features.
#define configUSE_TASK_NOTIFICATIONS              1
#define configUSE_MUTEXES                         1
#define configUSE_RECURSIVE_MUTEXES               0
#define configUSE_COUNTING_SEMAPHORES             1
#define configQUEUE_REGISTRY_SIZE                 0
#define configUSE_QUEUE_SETS                      0
#define configUSE_TIMERS                          0
#define configUSE_CO_ROUTINES                     0
#define configUSE_NEWLIB_REENTRANT                0
#define configENABLE_BACKWARD_COMPATIBILITY       0

// Memory: static allocation only (no heap_x.c is linked). The kernel provides
// the idle task's TCB and stack.
#define configSUPPORT_STATIC_ALLOCATION           1
#define configSUPPORT_DYNAMIC_ALLOCATION          0
#define configKERNEL_PROVIDED_STATIC_MEMORY       1

// Hooks.
#define configUSE_IDLE_HOOK                       0
#define configUSE_TICK_HOOK                       0
#define configUSE_MALLOC_FAILED_HOOK              0
#define configCHECK_FOR_STACK_OVERFLOW            2

// Cortex-M interrupt priorities. STM32H7 implements 4 priority bits
// (__NVIC_PRIO_BITS). ISRs that call FreeRTOS API functions must use a
// priority numerically >= configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY.
#define configPRIO_BITS                           4
#define configLIBRARY_LOWEST_INTERRUPT_PRIORITY   15
#define configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY 5
#define configKERNEL_INTERRUPT_PRIORITY \
  (configLIBRARY_LOWEST_INTERRUPT_PRIORITY << (8 - configPRIO_BITS))
#define configMAX_SYSCALL_INTERRUPT_PRIORITY \
  (configLIBRARY_MAX_SYSCALL_INTERRUPT_PRIORITY << (8 - configPRIO_BITS))

#define configASSERT(x)       \
  if ((x) == 0) {             \
    taskDISABLE_INTERRUPTS(); \
    __builtin_trap();         \
  }

// Optional API functions.
#define INCLUDE_vTaskDelay                        1
#define INCLUDE_xTaskDelayUntil                   1
#define INCLUDE_xTaskGetSchedulerState            1
#define INCLUDE_vTaskSuspend                      1
// SystemView: tells the idle task apart (trace macros) and reports the stack
// high-water mark in the task list.
#define INCLUDE_xTaskGetIdleTaskHandle            1
#define INCLUDE_uxTaskGetStackHighWaterMark       1

// Port handlers under their CMSIS vector names. SysTick_Handler is defined in
// rtos_glue.cc because it also drives the HAL tick.
#define vPortSVCHandler     SVC_Handler
#define xPortPendSVHandler  PendSV_Handler

// SEGGER SystemView trace macros (traceTASK_SWITCHED_IN, traceISR_ENTER, ...).
// Must come last: the header tests the INCLUDE_ and config values above.
#if !defined(__ASSEMBLER__)
#include "SEGGER_SYSVIEW_FreeRTOS.h"
#endif

#endif  // EXAMPLES_H755ZI_FREERTOS_COMMON_FREERTOSCONFIG_H_
