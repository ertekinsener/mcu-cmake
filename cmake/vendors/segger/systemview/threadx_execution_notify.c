// ThreadX scheduler hooks for SEGGER SystemView.
//
// With TX_ENABLE_EXECUTION_CHANGE_NOTIFY, the ThreadX ports call these
// functions from the scheduler (PendSV on Cortex-M) and from
// _tx_thread_context_save() / _tx_thread_context_restore(). SEGGER's ThreadX
// interface (SEGGER_SYSVIEW_ThreadX.c) only provides the task list and system
// time, so the hooks live here.
//
// Cortex-M ISRs do not call _tx_thread_context_save(); record them in the ISR
// itself with SEGGER_SYSVIEW_RecordEnterISR() / SEGGER_SYSVIEW_RecordExitISR().
//
// The SystemView calls lock on their own (SEGGER_SYSVIEW_LOCK), so the hooks
// do not depend on the interrupt state the port calls them with.

#include "SEGGER_SYSVIEW.h"
#include "tx_api.h"
#include "tx_thread.h"

#ifndef TX_ENABLE_EXECUTION_CHANGE_NOTIFY
#error "SystemView for ThreadX needs TX_ENABLE_EXECUTION_CHANGE_NOTIFY (tx_user.h)"
#endif
#ifdef TX_EXECUTION_PROFILE_ENABLE
#error "TX_EXECUTION_PROFILE_ENABLE defines the same hooks; use one of them"
#endif

// Called by tx_kernel_enter() right before the scheduler starts. SystemView
// is set up by the application (SEGGER_SYSVIEW_Conf()).
VOID _tx_execution_initialize(VOID) {}

// The current thread is about to stop running (preempted, suspended or
// finished).
VOID _tx_execution_thread_exit(VOID) {
  TX_THREAD* thread = _tx_thread_current_ptr;
  // A preempted thread stays ready; only report threads that block.
  if (thread != TX_NULL && thread->tx_thread_state != TX_READY) {
    SEGGER_SYSVIEW_OnTaskStopReady(TX_POINTER_TO_ULONG_CONVERT(thread), thread->tx_thread_state);
  }
  if (_tx_thread_execute_ptr == TX_NULL) {
    SEGGER_SYSVIEW_OnIdle();
  }
}

// _tx_thread_current_ptr has just been switched to the next thread.
VOID _tx_execution_thread_enter(VOID) {
  TX_THREAD* thread = _tx_thread_current_ptr;
  if (thread != TX_NULL) {
    SEGGER_SYSVIEW_OnTaskStartExec(TX_POINTER_TO_ULONG_CONVERT(thread));
  }
}

VOID _tx_execution_isr_enter(VOID) {
  SEGGER_SYSVIEW_RecordEnterISR();
}

VOID _tx_execution_isr_exit(VOID) {
  if (_tx_thread_execute_ptr != _tx_thread_current_ptr) {
    SEGGER_SYSVIEW_RecordExitISRToScheduler();
  } else {
    SEGGER_SYSVIEW_RecordExitISR();
  }
}
