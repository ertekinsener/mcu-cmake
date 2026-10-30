#ifndef EXAMPLES_H755ZI_THREADX_CM7_MIDDLEWARE_DEMO_H_
#define EXAMPLES_H755ZI_THREADX_CM7_MIDDLEWARE_DEMO_H_

#include "tx_api.h"

// Exercises the Eclipse ThreadX middleware without hardware drivers:
//   FileX    RAM disk (_fx_ram_driver) in AXI SRAM
//   LevelX   FileX on the RAM-backed NOR flash simulator
//   NetX Duo two IP instances on the RAM network driver, 1.2.3.4 pings 1.2.3.5
//   USBX     system initialization with a static memory pool
//   GUIX     system initialization (no display driver)
//
// Each field holds the status of its step (0 = success for all of them);
// inspect middleware_demo_status in a debugger.
struct MiddlewareDemoStatus {
  UINT filex_ram_disk;
  UINT levelx_nor_disk;
  UINT netx_ping;
  UINT usbx_init;
  UINT guix_init;
  bool done;
};

extern volatile MiddlewareDemoStatus middleware_demo_status;

// Creates the demo thread; call from tx_application_define().
void StartMiddlewareDemo();

#endif  // EXAMPLES_H755ZI_THREADX_CM7_MIDDLEWARE_DEMO_H_
