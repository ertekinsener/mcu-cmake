// Cortex-M7 image: blinks LD1 (PB0 on NUCLEO-H755ZI-Q) and publishes a
// counter in the shared mailbox. Runs on the reset clock (HSI 64 MHz); no
// clock tree or power supply configuration yet.

#include <array>
#include <cstdint>

#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

// Large buffer in AXI SRAM (D1) instead of DTCM, e.g. for MDMA/DMA transfers.
[[gnu::section(".ram_d1")]] std::array<std::uint8_t, 4096> frame_buffer;

constexpr std::uint32_t kLedPin = GPIO_PIN_0;
constexpr std::uint32_t kBlinkPeriodMs = 500;

void InitLed() {
  __HAL_RCC_GPIOB_CLK_ENABLE();
  GPIO_InitTypeDef init{
      .Pin = kLedPin,
      .Mode = GPIO_MODE_OUTPUT_PP,
      .Pull = GPIO_NOPULL,
      .Speed = GPIO_SPEED_FREQ_LOW,
      .Alternate = 0,
  };
  HAL_GPIO_Init(GPIOB, &init);
}

}  // namespace

extern "C" void SysTick_Handler() { HAL_IncTick(); }

int main() {
  HAL_Init();
  InitLed();

  std::uint32_t counter = 0;
  while (true) {
    ++counter;
    frame_buffer[counter % frame_buffer.size()] = static_cast<std::uint8_t>(counter);
    shared_mailbox.cm7_counter = counter;
    HAL_GPIO_TogglePin(GPIOB, kLedPin);
    HAL_Delay(kBlinkPeriodMs);
  }
}
