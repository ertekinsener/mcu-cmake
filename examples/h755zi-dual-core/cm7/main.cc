// Cortex-M7 image: a FreeRTOS task blinks LD1 (PB0 on NUCLEO-H755ZI-Q) and
// publishes a counter in the shared mailbox. Runs on the reset clock
// (HSI 64 MHz); no clock tree or power supply configuration yet.

#include <array>
#include <cstdint>

#include "FreeRTOS.h"
#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"
#include "task.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

// Large buffer in AXI SRAM (D1) instead of DTCM, e.g. for MDMA/DMA transfers.
[[gnu::section(".ram_d1")]] std::array<std::uint8_t, 4096> frame_buffer;

constexpr std::uint32_t kLedPin = GPIO_PIN_0;
constexpr TickType_t kBlinkPeriod = pdMS_TO_TICKS(500);

constexpr std::uint32_t kBlinkStackWords = 256;
std::array<StackType_t, kBlinkStackWords> blink_stack;
StaticTask_t blink_tcb;

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

void BlinkTask(void* /*context*/) {
  std::uint32_t counter = 0;
  TickType_t last_wake = xTaskGetTickCount();
  while (true) {
    ++counter;
    frame_buffer[counter % frame_buffer.size()] = static_cast<std::uint8_t>(counter);
    shared_mailbox.cm7_counter = counter;
    HAL_GPIO_TogglePin(GPIOB, kLedPin);
    xTaskDelayUntil(&last_wake, kBlinkPeriod);
  }
}

}  // namespace

int main() {
  HAL_Init();
  InitLed();

  xTaskCreateStatic(BlinkTask, "blink", blink_stack.size(), nullptr,
                    tskIDLE_PRIORITY + 1, blink_stack.data(), &blink_tcb);
  vTaskStartScheduler();

  // Only reached if the scheduler could not start.
  while (true) {
  }
}
