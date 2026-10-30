# mcu-cmake

A small, target-based CMake module for bare-metal MCU firmware. The core is
vendor-neutral; vendor packages (CMSIS, HAL, ...) live in separate modules,
one file per package, and are fetched from upstream git at versions chosen by
the project.

- No device database: the project describes its chip with values from the
  datasheet / reference manual, and the module validates them.
- No pinned versions: every vendor package takes a `GIT_TAG` from the
  project.
- Changing the MCU model or vendor changes the chip description and the
  vendor modules in the project, not the core.

Exercised with the STM32H755ZI (dual core, Cortex-M7 + Cortex-M4) in
[examples/h755zi-dual-core](../examples/h755zi-dual-core), and with an
STM32F411CE build as a portability check (see
[Portability](#portability)).

Diagrams:

- [target-architecture.puml](target-architecture.puml): CMake target graph.
- [repo-structure.puml](repo-structure.puml): repository layout and vendor
  dependencies.

## Layout

| File | Purpose |
|---|---|
| [cmake/toolchain/arm-none-eabi-gcc.cmake](../cmake/toolchain/arm-none-eabi-gcc.cmake) | Finds the compiler and binutils. No CPU flags. |
| [cmake/mcu.cmake](../cmake/mcu.cmake) | Entry point, `include(mcu)` after `project()`. |
| [cmake/mcu/chip.cmake](../cmake/mcu/chip.cmake) | `mcu_add_chip()` |
| [cmake/mcu/arch/arm.cmake](../cmake/mcu/arch/arm.cmake) | Cortex-M flag handler used by `mcu_add_chip()` |
| [cmake/mcu/linker.cmake](../cmake/mcu/linker.cmake) | `mcu_add_linker_script()` |
| [cmake/mcu/linker/default.ld.in](../cmake/mcu/linker/default.ld.in) | Default linker script template. |
| [cmake/mcu/package.cmake](../cmake/mcu/package.cmake) | `mcu_fetch_package()`: git fetch helper for vendor modules |
| [cmake/mcu/runtime.cmake](../cmake/mcu/runtime.cmake) | `mcu_target_add_runtime()` and [runtime/](../cmake/mcu/runtime) sources |
| [cmake/mcu/outputs.cmake](../cmake/mcu/outputs.cmake) | `mcu_add_firmware_outputs()` |
| [cmake/mcu/support_targets.cmake](../cmake/mcu/support_targets.cmake) | `mcu::cxx_bare_metal`, `mcu::newlib_nano`, `mcu::warnings` |
| [cmake/vendors/arm/cmsis_core.cmake](../cmake/vendors/arm/cmsis_core.cmake) | `arm_fetch_cmsis_core()` |
| [cmake/vendors/st/cmsis_device.cmake](../cmake/vendors/st/cmsis_device.cmake) | `st_fetch_cmsis_device()`, `st_add_cmsis_startup()` |
| [cmake/vendors/st/hal.cmake](../cmake/vendors/st/hal.cmake) | `st_fetch_hal()`, `st_add_hal()` |

Requirements: CMake 3.25+, git, arm-none-eabi-gcc with newlib-nano,
binutils 2.38+ (for `READONLY` in the linker script).

## Usage

```cmake
cmake_minimum_required(VERSION 3.25)
project(my_firmware C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "<repo>/cmake")
include(mcu)
include(vendors/st/hal)   # also includes vendors/st/cmsis_device, vendors/arm/cmsis_core

# Versions are the project's choice.
arm_fetch_cmsis_core(GIT_TAG v6.1.0)
st_fetch_cmsis_device(FAMILY H7 GIT_TAG v1.10.7)
st_fetch_hal(FAMILY H7 GIT_TAG v1.11.6)

mcu_add_chip(STM32H755ZI
  FAMILY H7
  CORE CM7
  CPU cortex-m7
  FPU fpv5-d16
  FLOAT_ABI hard
  DEFINITIONS STM32H755xx CORE_CM7
  MEMORY
    ITCMRAM   xrw 0x00000000 64K
    FLASH     rx  0x08000000 1024K
    DTCMRAM   xrw 0x20000000 128K
    RAM_D1    xrw 0x24000000 512K
    SHARED_D3 xrw 0x38000000 64K
)

add_library(hal_conf INTERFACE)                 # provides stm32h7xx_hal_conf.h
target_include_directories(hal_conf INTERFACE config)

st_add_hal(hal_cm7
  CHIP mcu::STM32H755ZI::CM7
  CONFIG hal_conf
  MODULES GPIO PWR
)
st_add_cmsis_startup(startup_cm7
  CHIP mcu::STM32H755ZI::CM7
  STARTUP startup_stm32h755xx.s
  SYSTEM system_stm32h7xx_dualcore_boot_cm4_cm7.c
  HAL hal_cm7
)

add_executable(firmware_cm7 main.cc)
target_link_libraries(firmware_cm7 PRIVATE
  startup_cm7
  hal_cm7
  mcu::cxx_bare_metal
  mcu::newlib_nano
  mcu::warnings
)
mcu_add_linker_script(firmware_cm7
  CHIP mcu::STM32H755ZI::CM7
  FLASH_REGION FLASH
  RAM_REGION DTCMRAM
  STACK_SIZE 0x2000
  HEAP_SIZE 0
)
mcu_add_firmware_outputs(firmware_cm7 BIN HEX MAP MEMORY_USAGE)
```

Configure with the toolchain file, for example through the presets of the
example:

```
cd examples/h755zi-dual-core
cmake --preset debug
cmake --build --preset debug
```

## Core API (vendor-neutral)

### `mcu_add_chip()`

```
mcu_add_chip(<chip>
  [ARCH <arch>]
  [FAMILY <family>]
  [CORE <core>]
  CPU <cpu>
  [FPU <fpu>]
  [FLOAT_ABI <soft|softfp|hard>]
  [DEFINITIONS <define>...]
  MEMORY <name> <attributes> <origin> <length> [...])
```

- Creates the INTERFACE target `mcu::<chip>`, or `mcu::<chip>::<core>`
  when `CORE` is given. A dual-core part gets one call per core.
- `ARCH` selects the flag handler `_mcu_arch_<arch>_flags()` in
  [arch/](../cmake/mcu/arch); default and currently only handler: `arm`
  (Cortex-M). For `arm`, `CPU` is the `-mcpu` value (must be a Cortex-M
  core), `FPU` the `-mfpu` value, `FLOAT_ABI` defaults to `hard` with an FPU
  and `soft` without.
- The target carries the architecture flags for compile and link (so the
  linker picks the matching multilib), `-ffunction-sections
  -fdata-sections`, `--gc-sections` and the definitions.
- `FAMILY` is a free-form, upper-case vendor family (e.g. `H7`). The core
  only stores it; vendor modules use it to select their packages.
- `MEMORY` is a flat list of 4-tuples, written like a GNU ld `MEMORY` block:
  attributes such as `rx` / `xrw`, origin in hex, length as `64K`, `1M`,
  hex or decimal bytes. Stored in the `MCU_MEMORY` target property.

`FATAL_ERROR` when: unsupported `ARCH`, missing or non-Cortex-M `CPU`,
`FLOAT_ABI` `hard` / `softfp` without `FPU`, `MEMORY` empty or not a
multiple of 4 values, invalid region name / attributes / length, non-hex
origin, duplicate or overlapping regions, `FAMILY` not upper case, chip
(and core) defined twice.

### `mcu_add_linker_script()`

```
mcu_add_linker_script(<target>
  CHIP <chip target>
  FLASH_REGION <region>
  RAM_REGION <region>
  STACK_SIZE <bytes>
  HEAP_SIZE <bytes>
  [TEMPLATE <file>])
```

- Generates `<target>.ld` at configure time in the target's binary
  directory, adds `-T` and `LINK_DEPENDS` (relink when the script changes).
- `FLASH_REGION` holds code, read-only data and the `.data` load image.
  `RAM_REGION` holds `.data`, `.bss`, heap and stack; `_estack` is the end of
  this region.
- Every other writable region gets a `NOLOAD` output section named after it
  in lower case (`RAM_D1` -> `.ram_d1`). Place objects there with
  `[[gnu::section(".ram_d1")]]`. These sections are **not** initialized by
  the startup code.
- Symbol names (`_sidata`, `_sdata`, `_edata`, `_sbss`, `_ebss`, `_estack`)
  follow the CMSIS / ST startup convention. Vendors with other names use
  `TEMPLATE`, which receives the same `@MCU_LD_*@` variables.

`FATAL_ERROR` when the chip target is unknown, `FLASH_REGION` /
`RAM_REGION` is not in the chip's memory map, or a required argument is
missing.

### `mcu_fetch_package()`

```
mcu_fetch_package(<name>
  GIT_REPOSITORY <url>
  GIT_TAG <tag|commit>
  [OUT_SOURCE_DIR <var>])
```

The building block for vendor modules.

- Clones `GIT_TAG` shallow; a full 40-character commit hash falls back to a
  full clone (git cannot shallow-fetch an arbitrary commit).
- Only downloads; never calls `add_subdirectory()`, so repositories with
  their own `CMakeLists.txt` do not inject targets.
- Fetching the same `<name>` again with the same repository and tag is a
  no-op; a different repository or tag is a `FATAL_ERROR`, so two parts of a
  project cannot silently use different versions.
- Local checkout instead of a download (offline work, patched drivers):
  `-DFETCHCONTENT_SOURCE_DIR_<NAME>=/path`, `<NAME>` in upper case, e.g.
  `FETCHCONTENT_SOURCE_DIR_ST_HAL_H7`.

### `mcu_target_add_runtime()`

```
mcu_target_add_runtime(<target>)
```

For images with their own `Reset_Handler`. `<target>` is the OBJECT library
holding the startup code or the executable. Adds empty `_init()` / `_fini()`
([startup_support.c](../cmake/mcu/runtime/startup_support.c)), the trapping
`std::__glibcxx_assert_fail` when C++ is enabled
([cxx_support.cc](../cmake/mcu/runtime/cxx_support.cc)), and links with
`-nostartfiles`. See [Toolchain pitfalls](#toolchain-pitfalls).

### `mcu_add_firmware_outputs()`

```
mcu_add_firmware_outputs(<target> [BIN] [HEX] [MAP] [MEMORY_USAGE] [SIZE])
```

Adds post-build `.bin` / `.hex` generation, a linker map file, the linker's
per-region usage report, and `arm-none-eabi-size` output.

### Support targets

| Target | Effect |
|---|---|
| `mcu::cxx_bare_metal` | C++ only: `-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit` |
| `mcu::newlib_nano` | `--specs=nano.specs --specs=nosys.specs` |
| `mcu::warnings` | `-Wall -Wextra -Wshadow -Wdouble-promotion`, plus `-Wold-style-cast -Wnon-virtual-dtor` for C++. Intended for own code, not vendor code. |

## Vendor modules

Each vendor package has its own file under `cmake/vendors/<vendor>/` and a
`<vendor>_fetch_<package>()` function that takes the version from the
project. Including a module also includes the modules it depends on.

### Arm: `vendors/arm/cmsis_core`

```
arm_fetch_cmsis_core(GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])
```

Creates `arm::cmsis_core` (headers, `SYSTEM` include). Default repository:
`ARM-software/CMSIS_6`. Vendor mirrors with a top-level `Include/` (e.g.
`STMicroelectronics/cmsis_core`, CMSIS 5) also work through
`GIT_REPOSITORY`. Shared by all Cortex-M vendors.

### ST: `vendors/st/cmsis_device`

```
st_fetch_cmsis_device(FAMILY <family> GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])

st_add_cmsis_startup(<name>
  CHIP <chip target>
  STARTUP <file>
  SYSTEM <file>
  [HAL <hal target>])
```

- `st_fetch_cmsis_device()` creates `st::cmsis_device::<family>`, linked to
  `arm::cmsis_core`. Default repository:
  `STMicroelectronics/cmsis-device-<family>`.
- `st_add_cmsis_startup()` creates the **OBJECT** library `<name>` with ST's
  startup and system files plus the runtime support. Link it to exactly one
  executable. `STARTUP` is a file name in `Source/Templates/gcc` (or a path),
  `SYSTEM` a file name in `Source/Templates` (or a path); the choice is
  explicit, since e.g. STM32H7 dual-core parts have several system file
  variants. `HAL` compiles the system file against the HAL configuration
  (`HSE_VALUE` etc.).
- Requires C and ASM enabled in `project()`.

### ST: `vendors/st/hal`

```
st_fetch_hal(FAMILY <family> GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])

st_add_hal(<name>
  CHIP <chip target>
  CONFIG <target>
  [MODULES <module>...]
  [LL_MODULES <module>...])
```

- `st_fetch_hal()` default repository:
  `STMicroelectronics/stm32<family>xx-hal-driver`.
- `st_add_hal()` creates the **STATIC** library `<name>`, compiled once with
  the chip's flags. Everything that uses the HAL links to this one library,
  so no HAL object is compiled twice. A dual-core part needs one HAL library
  per core (different CPU flags).
- `CONFIG` is a target whose include directories contain
  `stm32<family>xx_hal_conf.h`; the error message names the template to start
  from.
- `MODULES`: HAL modules (`GPIO`, `UART`, ...); `CORTEX` and `RCC` are always
  included, the matching `_ex.c` is added when it exists. `LL_MODULES`: LL
  drivers, defines `USE_FULL_LL_DRIVER`.
- Public usage requirements: `USE_HAL_DRIVER`, HAL / CMSIS include
  directories (`SYSTEM`), the chip target and the config target.

### Vendor module errors

`FATAL_ERROR` when: `GIT_TAG` or `FAMILY` is missing, the call order is
wrong (`st_fetch_cmsis_device()` before `arm_fetch_cmsis_core()`,
`st_add_hal()` / `st_add_cmsis_startup()` before the matching fetch), a
package is fetched twice with different versions, the fetched repository
does not look like the expected package, the chip has no `FAMILY`, the HAL
config header is missing, or a HAL / LL module, startup or system file does
not exist (the message lists what is available).

### Adding another vendor

1. Add `cmake/vendors/<vendor>/<package>.cmake` with a
   `<vendor>_fetch_<package>(GIT_TAG ...)` function built on
   `mcu_fetch_package()`.
2. Create header-only INTERFACE targets for headers, STATIC libraries for
   drivers (linked to the chip target), and an OBJECT library for startup
   code that calls `mcu_target_add_runtime()`.
3. If the vendor's startup uses other symbol names than the default linker
   template, ship a template and pass it via `TEMPLATE`.

A non-Arm architecture (e.g. RISC-V) additionally needs a toolchain file and
a `cmake/mcu/arch/<arch>.cmake` handler.

## Portability

What changes when the firmware moves:

| Move | Project changes | Module changes |
|---|---|---|
| Other ST model, same family | `mcu_add_chip()` values, startup file | none |
| Other ST family (e.g. H7 -> F4) | chip values, `FAMILY`, package `GIT_TAG`s, HAL config header, startup / system file | none |
| Other Cortex-M vendor | chip values, vendor module calls, application drivers | a `vendors/<vendor>/` module if none exists |
| Other architecture | toolchain, chip `ARCH` / values | toolchain file and `arch/` handler |

Checked: an STM32F411CE (single core, `FAMILY F4`, cmsis-device-f4 v2.6.11,
stm32f4xx-hal-driver v1.8.5, CMSIS_6 v6.1.0) builds a HAL blinky without
warnings using the unchanged module files.

## H755ZI dual-core example

| | CM7 | CM4 |
|---|---|---|
| Chip target | `mcu::STM32H755ZI::CM7` | `mcu::STM32H755ZI::CM4` |
| CPU flags | `cortex-m7`, `fpv5-d16`, hard | `cortex-m4`, `fpv4-sp-d16`, hard |
| HAL library | `hal_cm7` (GPIO, HSEM, PWR + CORTEX, RCC) | `hal_cm4` (same modules) |
| Startup | `startup_cm7` | `startup_cm4` |
| Flash | bank 1, `0x08000000`, 1024K | bank 2, `0x08100000`, 1024K |
| `.data` / `.bss` / stack | DTCM, `0x20000000`, 128K | D2 SRAM via CM4 alias, `0x10000000`, 288K |
| Extra regions | ITCM, AXI SRAM (`.ram_d1`), D3 SRAM (`.shared_d3`) | D3 SRAM (`.shared_d3`) |
| LED (NUCLEO-H755ZI-Q) | LD1, PB0, 500 ms | LD2, PE1, 250 ms |

- Package versions are set at the top of the example's `CMakeLists.txt`
  (`CMSIS_CORE_VERSION`, `ST_CMSIS_DEVICE_H7_VERSION`, `ST_HAL_H7_VERSION`)
  and can be overridden with `-D`, e.g. `-DST_HAL_H7_VERSION=v1.11.5`.
- Both cores use `startup_stm32h755xx.s` and
  `system_stm32h7xx_dualcore_boot_cm4_cm7.c` (both cores boot at reset);
  `CORE_CM7` / `CORE_CM4` from the chip targets select the core-specific
  code in the system file.
- `common/stm32h7xx_hal_conf.h` is ST's unmodified template (all modules
  enabled), shared by both cores through the `h755_hal_conf` target.
- D3 SRAM at `0x38000000` is shared. Both images place their `.shared_d3`
  section at the same address, so `common/shared_mailbox.h` is the layout
  contract between the two images.
- The CM7 D-cache is off after reset. Once it is enabled, mark D3 SRAM
  non-cacheable in the MPU or use cache maintenance around shared accesses.

### Verified build results

arm-none-eabi-gcc 15.2.0, CMake 4.3, Ninja; CMSIS_6 v6.1.0, cmsis-device-h7
v1.10.7, stm32h7xx-hal-driver v1.11.6. Both presets build without warnings,
including the HAL sources and `mcu::warnings` on the application code. Not
yet run on hardware.

| | CM7 | CM4 |
|---|---|---|
| Vector table | ST `g_pfnVectors` at `0x08000000`, 664 B (166 entries) | at `0x08100000` |
| `SysTick_Handler` | application handler (overrides the weak one) | same |
| `shared_mailbox` | `0x38000000` | `0x38000000` |
| `crt0.o` linked | no | no |
| Flash used, Debug / MinSizeRel | 4228 B / 2472 B | 3600 B / 2312 B |

- Each HAL library is compiled once per core (8 objects each).
- The flash LOAD segment is `R E`, not RWX.
- The first configure clones about 100 MB (CMSIS_6 33 MB, cmsis-device-h7
  52 MB, HAL 19 MB, including `.git`) and took about 55 s here.

## Toolchain pitfalls

### RWX LOAD segment warning

`.preinit_array`, `.init_array`, `.fini_array` and the `.ARM*` sections are
flagged writable but live in flash, so ld merged them into an RWX flash
segment and warned. The template marks them `(READONLY)`, which requires
binutils 2.38+.

### nosys "is not implemented and will always fail" warnings

The default `crt0.o` is linked even when the image has its own
`Reset_Handler`, and it references `exit` / `atexit`, which pull in stdio and
the nosys stubs. `mcu_target_add_runtime()` therefore links with
`-nostartfiles`. ST's startup code still calls `__libc_init_array()`, which
calls `_init()` from `crti.o`; empty `_init()` / `_fini()` are provided
instead.

### Extra ~5 KB in Debug builds with GCC 15

GCC 15 defines `_GLIBCXX_ASSERTIONS` for unoptimized (`-O0`) builds, so
`std::array::operator[]` gets bounds checks. The libstdc++ failure handler
calls `fprintf` and `abort`, which pull in stdio, malloc and the nosys stubs.
The runtime overrides `std::__glibcxx_assert_fail` with `__builtin_trap()`:
the checks stay active in Debug, and a failure stops in the debugger.

## Open points

- The memory values in the example come from the RM0399 memory map but have
  not been checked against the PDF. Verify them against the current
  reference manual.
- The example has not been run on hardware. It runs on the reset clock and
  has no power supply (`HAL_PWREx_ConfigSupply`), clock tree or HSEM boot
  synchronization between the cores yet.
- `stm32h7xx_hal_conf.h` is the unmodified template; set `HSE_VALUE` and
  disable unused modules for the real board.
- Packages are cloned per build tree (Debug and Release each clone once).
  Use `FETCHCONTENT_SOURCE_DIR_*` to share one local copy.
- Fetching by full commit hash (non-shallow clone) is implemented but not
  yet exercised.
- Defining the same chip twice is a `FATAL_ERROR`, also when two
  subprojects of one superbuild do it.
- FreeRTOS: FreeRTOS-Kernel has native CMake support (`FREERTOS_PORT` and a
  user-provided `freertos_config` target); a `vendors/freertos/kernel.cmake`
  module can wrap it the same way.
