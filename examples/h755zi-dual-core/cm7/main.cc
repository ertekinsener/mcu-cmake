#include <array>
#include <cstdint>

#include "shared_mailbox.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

// Large buffer in AXI SRAM (D1) instead of DTCM, e.g. for MDMA/DMA transfers.
[[gnu::section(".ram_d1")]] std::array<std::uint8_t, 4096> frame_buffer;

}  // namespace

int main() {
  std::uint32_t counter = 0;
  while (true) {
    ++counter;
    frame_buffer[counter % frame_buffer.size()] = static_cast<std::uint8_t>(counter);
    shared_mailbox.cm7_counter = counter;
  }
}
