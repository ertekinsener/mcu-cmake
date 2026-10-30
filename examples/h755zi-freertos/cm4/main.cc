// Cortex-M4 image: a FreeRTOS task blinks LD2 (PE1 on NUCLEO-H755ZI-Q) and
// publishes a counter in the shared mailbox.

#include <array>
#include <cstdint>

#include "FreeRTOS.h"
#include "SEGGER_RTT.h"
#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"
#include "sysview_h755.h"
#include "task.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

constexpr std::uint32_t kLedPin = GPIO_PIN_1;
constexpr TickType_t kBlinkPeriod = pdMS_TO_TICKS(250);

constexpr std::uint32_t kBlinkStackWords = 256;
std::array<StackType_t, kBlinkStackWords> blink_stack;
StaticTask_t blink_tcb;

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

void BlinkTask(void* /*context*/) {
  std::uint32_t counter = 0;
  TickType_t last_wake = xTaskGetTickCount();
  while (true) {
    shared_mailbox.cm4_counter = ++counter;
    HAL_GPIO_TogglePin(GPIOE, kLedPin);
    SEGGER_RTT_printf(0, "cm4: blink %u\r\n", static_cast<unsigned>(counter));
    xTaskDelayUntil(&last_wake, kBlinkPeriod);
  }
}

}  // namespace

int main() {
  HAL_Init();
  InitLed();
  SEGGER_RTT_Init();
  SEGGER_RTT_WriteString(0, "cm4: FreeRTOS start\r\n");
  h755::ConfigureSysview("N=h755zi-freertos cm4,O=FreeRTOS");

  xTaskCreateStatic(BlinkTask, "blink", blink_stack.size(), nullptr,
                    tskIDLE_PRIORITY + 1, blink_stack.data(), &blink_tcb);
  vTaskStartScheduler();

  // Only reached if the scheduler could not start.
  while (true) {
  }
}
