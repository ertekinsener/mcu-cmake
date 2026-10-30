// Cortex-M4 image: a ThreadX thread blinks LD2 (PE1 on NUCLEO-H755ZI-Q) and
// publishes a counter in the shared mailbox.

#include <array>
#include <cstdint>

#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"
#include "tx_api.h"
#include "tx_glue.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

constexpr std::uint32_t kLedPin = GPIO_PIN_1;
constexpr ULONG kBlinkPeriodTicks = 250;  // TX_TIMER_TICKS_PER_SECOND = 1000
constexpr UINT kBlinkPriority = 10;

alignas(8) std::array<std::uint8_t, 1024> blink_stack;
TX_THREAD blink_thread;
char blink_name[] = "blink";

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

void BlinkThread(ULONG /*input*/) {
  std::uint32_t counter = 0;
  while (true) {
    shared_mailbox.cm4_counter = ++counter;
    HAL_GPIO_TogglePin(GPIOE, kLedPin);
    tx_thread_sleep(kBlinkPeriodTicks);
  }
}

}  // namespace

extern "C" void tx_application_define(void* /*first_unused_memory*/) {
  tx_thread_stack_error_notify(TxStackErrorHandler);
  tx_thread_create(&blink_thread, blink_name, BlinkThread, 0, blink_stack.data(),
                   blink_stack.size(), kBlinkPriority, kBlinkPriority,
                   TX_NO_TIME_SLICE, TX_AUTO_START);
}

int main() {
  HAL_Init();
  InitLed();

  __disable_irq();  // see tx_glue.h
  tx_kernel_enter();

  // tx_kernel_enter() does not return.
  while (true) {
  }
}
