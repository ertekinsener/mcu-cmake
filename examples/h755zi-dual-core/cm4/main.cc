// Cortex-M4 image: blinks LD2 (PE1 on NUCLEO-H755ZI-Q) and publishes a
// counter in the shared mailbox.

#include <cstdint>

#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

constexpr std::uint32_t kLedPin = GPIO_PIN_1;
constexpr std::uint32_t kBlinkPeriodMs = 250;

void InitLed() {
  __HAL_RCC_GPIOE_CLK_ENABLE();
  GPIO_InitTypeDef init{
      .Pin = kLedPin,
      .Mode = GPIO_MODE_OUTPUT_PP,
      .Pull = GPIO_NOPULL,
      .Speed = GPIO_SPEED_FREQ_LOW,
      .Alternate = 0,
  };
  HAL_GPIO_Init(GPIOE, &init);
}

}  // namespace

extern "C" void SysTick_Handler() { HAL_IncTick(); }

int main() {
  HAL_Init();
  InitLed();

  std::uint32_t counter = 0;
  while (true) {
    shared_mailbox.cm4_counter = ++counter;
    HAL_GPIO_TogglePin(GPIOE, kLedPin);
    HAL_Delay(kBlinkPeriodMs);
  }
}
