#ifndef EXAMPLES_H755ZI_THREADX_COMMON_TX_GLUE_H_
#define EXAMPLES_H755ZI_THREADX_COMMON_TX_GLUE_H_

#include "tx_api.h"

// Board glue for ThreadX (tx_glue.cc).
//
// tx_kernel_enter() does not disable interrupts itself; the scheduler enables
// them when the first thread starts. Call __disable_irq() before
// tx_kernel_enter(), since HAL_Init() has already started SysTick.

// Stack error handler for tx_thread_stack_error_notify(): traps into the
// debugger.
void TxStackErrorHandler(TX_THREAD* thread);

#endif  // EXAMPLES_H755ZI_THREADX_COMMON_TX_GLUE_H_
