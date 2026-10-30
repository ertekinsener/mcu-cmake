#include <cstdint>

#include "shared_mailbox.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

}  // namespace

int main() {
  std::uint32_t counter = 0;
  while (true) {
    shared_mailbox.cm4_counter = ++counter;
  }
}
