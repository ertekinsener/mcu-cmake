#ifndef EXAMPLES_H755ZI_DUAL_CORE_COMMON_SHARED_MAILBOX_H_
#define EXAMPLES_H755ZI_DUAL_CORE_COMMON_SHARED_MAILBOX_H_

#include <cstdint>

// Layout of the D3 SRAM block shared by both cores. Each image places its
// instance in section .shared_d3 at the same address (0x38000000), so this
// struct is the contract between the two firmware images.
//
// The CM7 D-cache is off after reset. Once it is enabled, mark D3 SRAM as
// non-cacheable in the MPU or use cache maintenance around accesses.
struct SharedMailbox {
  std::uint32_t cm7_counter;
  std::uint32_t cm4_counter;
};

#endif  // EXAMPLES_H755ZI_DUAL_CORE_COMMON_SHARED_MAILBOX_H_
