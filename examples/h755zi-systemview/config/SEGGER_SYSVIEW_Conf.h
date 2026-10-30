#ifndef EXAMPLES_H755ZI_SYSTEMVIEW_CONFIG_SEGGER_SYSVIEW_CONF_H_
#define EXAMPLES_H755ZI_SYSTEMVIEW_CONFIG_SEGGER_SYSVIEW_CONF_H_

// Project SystemView configuration, passed to segger_add_systemview() as
// CONFIG. Only values that differ from SEGGER_SYSVIEW_ConfDefaults.h; the
// timestamp (DWT->CYCCNT) and interrupt ID (ICSR) defaults fit Cortex-M.

// RTT buffer for the SysView channel (default 1 KiB). The filter job records a
// burst of events every 10 ms; a larger buffer rides out probe polling gaps
// instead of dropping events (SystemView then shows an overflow marker).
#define SEGGER_SYSVIEW_RTT_BUFFER_SIZE  4096

// Longest string in a packet (task names, SEGGER_SYSVIEW_PrintfHost format
// strings, module descriptions); default 128.
#define SEGGER_SYSVIEW_MAX_STRING_LEN   96

#endif  // EXAMPLES_H755ZI_SYSTEMVIEW_CONFIG_SEGGER_SYSVIEW_CONF_H_
