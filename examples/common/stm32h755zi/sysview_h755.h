#ifndef EXAMPLES_COMMON_STM32H755ZI_SYSVIEW_H755_H_
#define EXAMPLES_COMMON_STM32H755ZI_SYSVIEW_H755_H_

#include "SEGGER_SYSVIEW.h"

// RTOS interface of the image: SEGGER's FreeRTOS / ThreadX interface, or the
// application's own (h755zi-systemview).
extern "C" const SEGGER_SYSVIEW_OS_API SYSVIEW_X_OS_TraceAPI;

namespace h755 {

// Sets up SystemView for the core this image runs on: DWT cycle counter as
// timestamp (SystemCoreClock), device name and lowest RAM address of the core,
// SysTick as interrupt 15. `description` names the application and the OS,
// e.g. "N=h755zi-freertos cm7,O=FreeRTOS"; it must outlive the program.
//
// Call once, after the clock setup and before the RTOS creates its first task.
// Recording starts when the SystemView application (or sysview-bridge
// --record) sends the start command; `on_start` then runs after the system
// description and task list went out, e.g. to name markers or register data
// plots. It may run in interrupt context (inside any recorded event).
void ConfigureSysview(const char* description,
                      SEGGER_SYSVIEW_START_CALLBACK* on_start = nullptr);

}  // namespace h755

#endif  // EXAMPLES_COMMON_STM32H755ZI_SYSVIEW_H755_H_
