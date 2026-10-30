#ifndef EXAMPLES_H755ZI_THREADX_COMMON_TX_USER_H_
#define EXAMPLES_H755ZI_THREADX_COMMON_TX_USER_H_

// ThreadX configuration shared by both cores. Each core runs its own kernel
// instance. Included by tx_port.h through TX_INCLUDE_USER_DEFINE_FILE.

// 1 kHz tick: SysTick also drives the HAL tick (see tx_glue.cc).
#define TX_TIMER_TICKS_PER_SECOND 1000UL

// Stack overflow / corruption detection, reported through
// tx_thread_stack_error_notify().
#define TX_ENABLE_STACK_CHECKING

// No ThreadX timer thread: expirations run in the tick ISR. Fine as long as
// timer callbacks are short.
#define TX_TIMER_PROCESS_IN_ISR

#endif  // EXAMPLES_H755ZI_THREADX_COMMON_TX_USER_H_
