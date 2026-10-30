// Bare-metal SEGGER SystemView demo, built for both STM32H755ZI cores from
// this one source (CORE_CM7 / CORE_CM4 come from the chip target).
//
// A small cooperative scheduler runs the jobs in kJobs. Each job is reported
// to SystemView as a task, so the timeline looks like an RTOS trace; this is
// how a home-grown scheduler or super loop is instrumented. The demo also
// shows:
//   - ISRs: SysTick on both cores, the USER button (B1, PC13) on the CM7
//   - a marker around each FIR block (SEGGER_SYSVIEW_MarkStart/MarkStop)
//   - user module events ("App": FilterBlock, FilterDone)
//   - a data plot of the filter output peak (SEGGER_SYSVIEW_SampleData)
//   - text formatted by the host (SEGGER_SYSVIEW_PrintfHost), and a warning
//     (SEGGER_SYSVIEW_Warn) when a job misses its deadline
//
// On the CM7, B1 toggles a heavy filter load (128 instead of 1 block) that overruns the filter job's
// period: watch the job grow in the timeline and the warnings appear.

#include <algorithm>
#include <array>
#include <cstddef>
#include <cstdint>
#include <cstdlib>
#include <span>

#include "SEGGER_SYSVIEW.h"
#include "stm32h7xx_hal.h"
#include "sysview_h755.h"

namespace {

// --- Board ------------------------------------------------------------------

#if defined(CORE_CM7)
// LD1 (green), USER button B1 = PC13 (high when pressed), both on the CM7.
GPIO_TypeDef* const kLedPort = GPIOB;
constexpr std::uint32_t kLedPin = GPIO_PIN_0;
constexpr std::uint32_t kBlinkPeriodMs = 250;
constexpr std::uint32_t kButtonPin = GPIO_PIN_13;
constexpr const char* kDescription =
    "N=h755zi-systemview cm7,O=cooperative scheduler,I#56=EXTI15_10";
#elif defined(CORE_CM4)
// LD2 (yellow).
GPIO_TypeDef* const kLedPort = GPIOE;
constexpr std::uint32_t kLedPin = GPIO_PIN_1;
constexpr std::uint32_t kBlinkPeriodMs = 500;
constexpr const char* kDescription = "N=h755zi-systemview cm4,O=cooperative scheduler";
#endif

void InitLed() {
#if defined(CORE_CM7)
  __HAL_RCC_GPIOB_CLK_ENABLE();
#else
  __HAL_RCC_GPIOE_CLK_ENABLE();
#endif
  GPIO_InitTypeDef init{
      .Pin = kLedPin,
      .Mode = GPIO_MODE_OUTPUT_PP,
      .Pull = GPIO_NOPULL,
      .Speed = GPIO_SPEED_FREQ_LOW,
      .Alternate = 0,
  };
  HAL_GPIO_Init(kLedPort, &init);
}

// --- FIR filter job ---------------------------------------------------------

constexpr std::size_t kBlockSize = 64;
constexpr std::uint32_t kLightBlocks = 1;
// Light: ~1 ms in Debug at 64 MHz. Heavy: overruns the 5 ms period also in
// MinSizeRel.
constexpr std::uint32_t kHeavyBlocks = 128;

// Triangular low-pass taps 1..8..1; they sum to 64, hence the shift by 6.
constexpr std::size_t kTapCount = 15;
constexpr int kTapShift = 6;
constexpr std::array<std::int16_t, kTapCount> MakeTaps() {
  std::array<std::int16_t, kTapCount> taps{};
  constexpr int kCenter = kTapCount / 2;
  for (int i = 0; i < static_cast<int>(kTapCount); ++i) {
    taps[i] = static_cast<std::int16_t>(kCenter + 1 - std::abs(i - kCenter));
  }
  return taps;
}
constexpr std::array<std::int16_t, kTapCount> kTaps = MakeTaps();
static_assert([] {
  int sum = 0;
  for (const auto tap : kTaps) sum += tap;
  return sum == (1 << kTapShift);
}());

std::array<std::int16_t, kBlockSize> input_block;
std::array<std::int16_t, kBlockSize> output_block;
std::uint32_t noise_state = 1;
volatile std::uint32_t filter_blocks = kLightBlocks;  // written by the button ISR

// Sawtooth with LCG noise on top.
void FillInput(std::span<std::int16_t> block) {
  for (std::size_t i = 0; i < block.size(); ++i) {
    noise_state = noise_state * 1664525u + 1013904223u;
    const int saw = static_cast<int>(i * 256) - 8192;
    const int noise = static_cast<int>(noise_state >> 20) - 2048;
    block[i] = static_cast<std::int16_t>(saw + noise);
  }
}

// Returns the output peak (absolute value).
std::int32_t Filter(std::span<const std::int16_t> input, std::span<std::int16_t> output) {
  std::int32_t peak = 0;
  for (std::size_t n = kTapCount - 1; n < input.size(); ++n) {
    std::int32_t acc = 0;
    for (std::size_t k = 0; k < kTapCount; ++k) {
      acc += static_cast<std::int32_t>(input[n - k]) * kTaps[k];
    }
    const std::int32_t value = acc >> kTapShift;
    output[n] = static_cast<std::int16_t>(value);
    peak = std::max(peak, std::abs(value));
  }
  return peak;
}

// User module: event IDs are offsets into the module's range, assigned by
// SEGGER_SYSVIEW_RegisterModule(). The description tells SystemView how to
// print them.
enum AppEvent : unsigned { kFilterBlock = 0, kFilterDone = 1, kAppEventCount };
SEGGER_SYSVIEW_MODULE app_module{
    .sModule = "M=App,0 FilterBlock samples=%u,1 FilterDone peak=%d",
    .NumEvents = kAppEventCount,
    .EventOffset = 0,
    .pfSendModuleDesc = nullptr,
    .pNext = nullptr,
};

constexpr unsigned kFilterMarker = 0;
constexpr std::uint32_t kPeakPlotId = 0;
std::int32_t last_peak = 0;

void FilterJob() {
  const std::uint32_t blocks = filter_blocks;
  for (std::uint32_t block = 0; block < blocks; ++block) {
    SEGGER_SYSVIEW_MarkStart(kFilterMarker);
    SEGGER_SYSVIEW_RecordU32(app_module.EventOffset + kFilterBlock, kBlockSize);
    FillInput(input_block);
    last_peak = Filter(input_block, output_block);
    SEGGER_SYSVIEW_RecordU32(app_module.EventOffset + kFilterDone,
                             static_cast<U32>(last_peak));
    SEGGER_SYSVIEW_MarkStop(kFilterMarker);
  }
  const SEGGER_SYSVIEW_DATA_SAMPLE sample{.ID = kPeakPlotId, .pValue = {.pI32 = &last_peak}};
  SEGGER_SYSVIEW_SampleData(&sample);
}

// --- Other jobs ---------------------------------------------------------------

std::uint32_t blink_count = 0;
volatile std::uint32_t button_presses = 0;

void BlinkJob() {
  HAL_GPIO_TogglePin(kLedPort, kLedPin);
  ++blink_count;
}

void ReportJob() {
  // Formatted by the SystemView application: the target sends the format
  // string and the raw arguments, no printf code runs here.
  SEGGER_SYSVIEW_PrintfHost("blinks=%u filter blocks/run=%u button presses=%u",
                            static_cast<unsigned>(blink_count),
                            static_cast<unsigned>(filter_blocks),
                            static_cast<unsigned>(button_presses));
}

// --- Cooperative scheduler ----------------------------------------------------

struct Job {
  const char* name;
  std::uint32_t period_ms;
  void (*run)();
};

constexpr std::array kJobs{
    Job{"filter", 5, FilterJob},
    Job{"blink", kBlinkPeriodMs, BlinkJob},
    Job{"report", 1000, ReportJob},
};

struct JobState {
  std::uint32_t next_run_ms;
  std::uint32_t overruns;
};
std::array<JobState, kJobs.size()> job_states{};

// SystemView task IDs are addresses (shrunk by the RAM base); each job's
// state in RAM gives it a stable, unique one.
U32 TaskId(std::size_t job) {
  return static_cast<U32>(reinterpret_cast<std::uintptr_t>(&job_states[job]));
}

[[noreturn]] void RunScheduler() {
  bool idle = false;
  while (true) {
    bool ran = false;
    for (std::size_t i = 0; i < kJobs.size(); ++i) {
      JobState& state = job_states[i];
      if (static_cast<std::int32_t>(HAL_GetTick() - state.next_run_ms) < 0) {
        continue;
      }
      SEGGER_SYSVIEW_OnTaskStartExec(TaskId(i));
      kJobs[i].run();
      SEGGER_SYSVIEW_OnTaskStopExec();
      ran = true;

      state.next_run_ms += kJobs[i].period_ms;
      const std::uint32_t now = HAL_GetTick();
      if (static_cast<std::int32_t>(now - state.next_run_ms) >= 0) {
        // Already due again: the job took longer than its period.
        ++state.overruns;
        SEGGER_SYSVIEW_Warn("job overran its period");
        state.next_run_ms = now + kJobs[i].period_ms;
      }
    }
    // One idle event per idle phase, not per loop pass.
    if (ran) {
      idle = false;
    } else if (!idle) {
      SEGGER_SYSVIEW_OnIdle();
      idle = true;
    }
  }
}

// --- SystemView ---------------------------------------------------------------

U64 GetTimeUs() { return static_cast<U64>(HAL_GetTick()) * 1000; }

void SendTaskList() {
  for (std::size_t i = 0; i < kJobs.size(); ++i) {
    const SEGGER_SYSVIEW_TASKINFO info{
        .TaskID = TaskId(i),
        .sName = kJobs[i].name,
        .Prio = 0,  // cooperative: no priorities
        .StackBase = 0,
        .StackSize = 0,
        .StackUsage = 0,
    };
    SEGGER_SYSVIEW_SendTaskInfo(&info);
  }
}

SEGGER_SYSVIEW_DATA_REGISTER peak_plot{
    .ID = kPeakPlotId,
    .DataType = SEGGER_SYSVIEW_TYPE_I32,
    .Offset = 0,
    .RangeMin = 0,
    .RangeMax = 32767,
    .ScalingFactor = 1.0f,
    .sName = "FIR peak",
    .sUnit = "LSB",
};

// Runs on every recording start, after the system description and task list.
void OnSysviewStart() {
  SEGGER_SYSVIEW_NameMarker(kFilterMarker, "FIR block");
  SEGGER_SYSVIEW_RegisterData(&peak_plot);
}

#if defined(CORE_CM7)
void InitButton() {
  __HAL_RCC_GPIOC_CLK_ENABLE();
  GPIO_InitTypeDef init{
      .Pin = kButtonPin,
      .Mode = GPIO_MODE_IT_RISING,
      .Pull = GPIO_NOPULL,  // external pull-down on the Nucleo board
      .Speed = GPIO_SPEED_FREQ_LOW,
      .Alternate = 0,
  };
  HAL_GPIO_Init(GPIOC, &init);
  HAL_NVIC_SetPriority(EXTI15_10_IRQn, 5, 0);
  HAL_NVIC_EnableIRQ(EXTI15_10_IRQn);
}
#endif

}  // namespace

// The scheduler's interface for SystemView (task list, system time).
extern "C" const SEGGER_SYSVIEW_OS_API SYSVIEW_X_OS_TraceAPI{
    .pfGetTime = GetTimeUs,
    .pfSendTaskList = SendTaskList,
};

extern "C" void SysTick_Handler() {
  SEGGER_SYSVIEW_RecordEnterISR();
  HAL_IncTick();
  SEGGER_SYSVIEW_RecordExitISR();
}

#if defined(CORE_CM7)
extern "C" void EXTI15_10_IRQHandler() {
  SEGGER_SYSVIEW_RecordEnterISR();
  HAL_GPIO_EXTI_IRQHandler(kButtonPin);
  SEGGER_SYSVIEW_RecordExitISR();
}

extern "C" void HAL_GPIO_EXTI_Callback(std::uint16_t pin) {
  if (pin == kButtonPin) {
    button_presses = button_presses + 1;
    filter_blocks = filter_blocks == kLightBlocks ? kHeavyBlocks : kLightBlocks;
  }
}
#endif

int main() {
  HAL_Init();
  InitLed();
  h755::ConfigureSysview(kDescription, OnSysviewStart);
  SEGGER_SYSVIEW_RegisterModule(&app_module);
#if defined(CORE_CM7)
  InitButton();
#endif
  RunScheduler();
}
