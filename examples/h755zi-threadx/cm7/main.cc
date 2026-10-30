// Cortex-M7 image: a ThreadX thread blinks LD1 (PB0 on NUCLEO-H755ZI-Q) and
// publishes a counter in the shared mailbox; a second thread exercises the
// ThreadX middleware (middleware_demo.h). Runs on the reset clock
// (HSI 64 MHz); no clock tree or power supply configuration yet.

#include <array>
#include <cstdint>

#include "middleware_demo.h"
#include "SEGGER_RTT.h"
#include "shared_mailbox.h"
#include "stm32h7xx_hal.h"
#include "sysview_h755.h"
#include "tx_api.h"
#include "tx_glue.h"

namespace {

[[gnu::section(".shared_d3")]] volatile SharedMailbox shared_mailbox;

// Large buffer in AXI SRAM (D1) instead of DTCM, e.g. for MDMA/DMA transfers.
[[gnu::section(".ram_d1")]] std::array<std::uint8_t, 4096> frame_buffer;

constexpr std::uint32_t kLedPin = GPIO_PIN_0;
constexpr ULONG kBlinkPeriodTicks = 500;  // TX_TIMER_TICKS_PER_SECOND = 1000
constexpr UINT kBlinkPriority = 10;

alignas(8) std::array<std::uint8_t, 1024> blink_stack;
TX_THREAD blink_thread;
char blink_name[] = "blink";

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

void BlinkThread(ULONG /*input*/) {
  std::uint32_t counter = 0;
  while (true) {
    ++counter;
    frame_buffer[counter % frame_buffer.size()] = static_cast<std::uint8_t>(counter);
    shared_mailbox.cm7_counter = counter;
    HAL_GPIO_TogglePin(GPIOB, kLedPin);
    SEGGER_RTT_printf(0, "cm7: blink %u\r\n", static_cast<unsigned>(counter));
    tx_thread_sleep(kBlinkPeriodTicks);
  }
}

}  // namespace

extern "C" void tx_application_define(void* /*first_unused_memory*/) {
  tx_thread_stack_error_notify(TxStackErrorHandler);
  tx_thread_create(&blink_thread, blink_name, BlinkThread, 0, blink_stack.data(),
                   blink_stack.size(), kBlinkPriority, kBlinkPriority,
                   TX_NO_TIME_SLICE, TX_AUTO_START);
  StartMiddlewareDemo();
}

int main() {
  HAL_Init();
  InitLed();
  SEGGER_RTT_Init();
  SEGGER_RTT_WriteString(0, "cm7: ThreadX start\r\n");
  // Before tx_kernel_enter(): SystemView asks for the thread list on start.
  h755::ConfigureSysview("N=h755zi-threadx cm7,O=ThreadX");

  __disable_irq();  // see tx_glue.h
  tx_kernel_enter();

  // tx_kernel_enter() does not return.
  while (true) {
  }
}
