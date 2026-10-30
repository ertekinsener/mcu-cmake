# mcu-cmake

A small, target-based CMake module for bare-metal MCU firmware. The core is
vendor-neutral; vendor packages (CMSIS, HAL, FreeRTOS, ThreadX, ...) live in separate modules,
one file per package, and are fetched from upstream git at versions chosen by
the project.

- No device database: the project describes its chip with values from the
  datasheet / reference manual, and the module validates them.
- No pinned versions: every vendor package takes a `GIT_TAG` from the
  project.
- Changing the MCU model or vendor changes the chip description and the
  vendor modules in the project, not the core.

Exercised with the STM32H755ZI (dual core, Cortex-M7 + Cortex-M4) in two
examples, [examples/h755zi-freertos](../examples/h755zi-freertos) and
[examples/h755zi-threadx](../examples/h755zi-threadx), and with an
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
| [cmake/mcu/naming.cmake](../cmake/mcu/naming.cmake) | `mcu_add_named_library()`, `mcu_resolve_target()` |
| [cmake/mcu/chip.cmake](../cmake/mcu/chip.cmake) | `mcu_add_chip()` |
| [cmake/mcu/arch/arm.cmake](../cmake/mcu/arch/arm.cmake) | Cortex-M flag handler used by `mcu_add_chip()` |
| [cmake/mcu/linker.cmake](../cmake/mcu/linker.cmake) | `mcu_add_linker_script()` |
| [cmake/mcu/linker/default.ld.in](../cmake/mcu/linker/default.ld.in) | Default linker script template. |
| [cmake/mcu/package.cmake](../cmake/mcu/package.cmake) | `mcu_fetch_package()`: git fetch helper for vendor modules |
| [cmake/mcu/git_sparse_fetch.cmake](../cmake/mcu/git_sparse_fetch.cmake) | Sparse partial clone script used by `mcu_fetch_package(SPARSE_PATHS ...)` |
| [cmake/mcu/runtime.cmake](../cmake/mcu/runtime.cmake) | `mcu_target_add_runtime()` and [runtime/](../cmake/mcu/runtime) sources |
| [cmake/mcu/outputs.cmake](../cmake/mcu/outputs.cmake) | `mcu_add_firmware_outputs()` |
| [cmake/mcu/support_targets.cmake](../cmake/mcu/support_targets.cmake) | `mcu::cxx_bare_metal`, `mcu::newlib_nano`, `mcu::warnings` |
| [cmake/vendors/arm/cmsis_core.cmake](../cmake/vendors/arm/cmsis_core.cmake) | `arm_fetch_cmsis_core()` |
| [cmake/vendors/st/cmsis_device.cmake](../cmake/vendors/st/cmsis_device.cmake) | `st_fetch_cmsis_device()`, `st_add_cmsis_startup()` |
| [cmake/vendors/st/hal.cmake](../cmake/vendors/st/hal.cmake) | `st_fetch_hal()`, `st_add_hal()` |
| [cmake/vendors/freertos/kernel.cmake](../cmake/vendors/freertos/kernel.cmake) | `freertos_fetch_kernel()`, `freertos_add_kernel()` |
| [cmake/vendors/threadx/kernel.cmake](../cmake/vendors/threadx/kernel.cmake) | `threadx_fetch_kernel()`, `threadx_add_kernel()` |
| [cmake/vendors/threadx/filex.cmake](../cmake/vendors/threadx/filex.cmake) | `threadx_fetch_filex()`, `threadx_add_filex()` |
| [cmake/vendors/threadx/levelx.cmake](../cmake/vendors/threadx/levelx.cmake) | `threadx_fetch_levelx()`, `threadx_add_levelx()` |
| [cmake/vendors/threadx/netxduo.cmake](../cmake/vendors/threadx/netxduo.cmake) | `threadx_fetch_netxduo()`, `threadx_add_netxduo()` |
| [cmake/vendors/threadx/usbx.cmake](../cmake/vendors/threadx/usbx.cmake) | `threadx_fetch_usbx()`, `threadx_add_usbx()` |
| [cmake/vendors/threadx/guix.cmake](../cmake/vendors/threadx/guix.cmake) | `threadx_fetch_guix()`, `threadx_add_guix()` |
| [cmake/vendors/threadx/common.cmake](../cmake/vendors/threadx/common.cmake) | Shared helpers of the ThreadX modules |

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

mcu_add_chip(stm32::H755ZI::CM7
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

# Provides stm32h7xx_hal_conf.h
mcu_add_named_library(board::hal_conf INTERFACE hal_conf_target)
target_include_directories(${hal_conf_target} INTERFACE config)

st_add_hal(board::hal_cm7
  CHIP stm32::H755ZI::CM7
  CONFIG board::hal_conf
  MODULES GPIO PWR
)
st_add_cmsis_startup(board::startup_cm7
  CHIP stm32::H755ZI::CM7
  STARTUP startup_stm32h755xx.s
  SYSTEM system_stm32h7xx_dualcore_boot_cm4_cm7.c
  HAL board::hal_cm7
)

add_executable(firmware_cm7 main.cc)
target_link_libraries(firmware_cm7 PRIVATE
  board::startup_cm7
  board::hal_cm7
  mcu::cxx_bare_metal
  mcu::newlib_nano
  mcu::warnings
)
mcu_add_linker_script(firmware_cm7
  CHIP stm32::H755ZI::CM7
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
cd examples/h755zi-freertos      # or examples/h755zi-threadx
cmake --preset debug
cmake --build --preset debug
```

## Core API (vendor-neutral)

### Target naming

Libraries created by the `*_add_*()` functions are named by the project and
may carry a namespace, e.g. `st_add_hal(board::hal_cm7 ...)`. A namespaced
name becomes an `ALIAS` of a real target with `::` replaced by `_`
(`board_hal_cm7`). Link against the namespaced name: CMake treats names
containing `::` as targets and fails at configure time on a typo, while an
unknown plain name silently becomes a `-l<name>` linker flag.

Why not fixed namespaces like ObKo/stm32-cmake (`FreeRTOS::ARM_CM4F`,
`HAL::STM32::F4::GPIO`)? Those were IMPORTED INTERFACE targets carrying
sources, so every consumer compiled its own copy (duplicate objects when a
library and the executable both link them), and a predefined name cannot
express project-specific parameters such as the config header, port, heap
or two configurations on one core. Here every library is a real STATIC (or
OBJECT) target, built once, with a name the project chooses.

Chip targets follow the same rule: `mcu_add_chip(stm32::H755ZI::CM7 ...)`.
The core is vendor-neutral, so it does not impose a vendor prefix; functions
that take a `CHIP` check its properties, not its name. Only targets that
exist once and take no project parameters use fixed namespaces:
`mcu::warnings`, `mcu::cxx_bare_metal`, `mcu::newlib_nano`,
`arm::cmsis_core`, `st::cmsis_device::<family>`. Lower-case namespaces are
used throughout; `st::` is taken by the ST package targets, so the examples
use `stm32::` for chips and `h755::` for project libraries.

```
mcu_add_named_library(<name> <STATIC|OBJECT|INTERFACE> <out_var> [<source>...])
mcu_resolve_target(<name> <out_var>)
```

`mcu_add_named_library()` creates the target (and alias) and returns the
real name for `target_*()` calls, which do not accept aliases; it fails on
invalid names and on collisions (`a::b_c` vs. `a_b::c`).
`mcu_resolve_target()` returns the real target behind an alias; the core
functions that modify a given target (`mcu_add_linker_script()`,
`mcu_add_firmware_outputs()`, `mcu_target_add_runtime()`) use it, so they
accept aliases.

### `mcu_add_chip()`

```
mcu_add_chip(<name>
  [ARCH <arch>]
  [FAMILY <family>]
  [CORE <core>]
  CPU <cpu>
  [FPU <fpu>]
  [FLOAT_ABI <soft|softfp|hard>]
  [DEFINITIONS <define>...]
  MEMORY <name> <attributes> <origin> <length> [...])
```

- Creates the INTERFACE target `<name>`, chosen by the project and
  optionally namespaced (`stm32::H755ZI::CM7`, see
  [Target naming](#target-naming)). A dual-core part gets one chip target
  per core. `CORE` is informational (shown in the generated linker script
  header).
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
origin, duplicate or overlapping regions, `FAMILY` not upper case, invalid
name, or a name (or its real target name) that already exists.

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
  [SPARSE_PATHS <dir>...]
  [OUT_SOURCE_DIR <var>])
```

The building block for vendor modules.

- With `SPARSE_PATHS` (used by all vendor modules): fetches only `GIT_TAG`
  with depth 1 as a partial clone (`--filter=blob:none`) and a cone-mode
  sparse checkout of the listed directories plus top-level files. Works for
  tags and full commit hashes (on hosts that allow fetching reachable
  commits by hash, such as GitHub and GitLab). A stamp file skips the fetch
  on reconfigure. Example: GUIX drops from more than 300 MB (shallow clone,
  not finished after 10 minutes) to 21 MB in 2 s.
- Without `SPARSE_PATHS`: `GIT_TAG` is cloned shallow; a full 40-character
  commit hash falls back to a full clone.
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
project. Including a module also includes the modules it depends on. Every
`<vendor>_add_<package>(<name> ...)` accepts a namespaced `<name>` (see
[Target naming](#target-naming)), and every fetch is sparse: only the
directories the module builds from are downloaded.

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

### FreeRTOS: `vendors/freertos/kernel`

```
freertos_fetch_kernel(GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])

freertos_add_kernel(<name>
  CHIP <chip target>
  CONFIG <target>
  PORT <port>
  HEAP <1|2|3|4|5|NONE>)
```

- Vendor-neutral: `CHIP` only provides the CPU flags, no `FAMILY` needed.
  Default repository: `FreeRTOS/FreeRTOS-Kernel`.
- `freertos_add_kernel()` creates the **STATIC** library `<name>` (kernel
  sources, port, optional heap), compiled once with the chip's flags. The
  kernel's own `CMakeLists.txt` is not used: it supports only one kernel per
  build tree (a single global `freertos_config` target), which does not fit
  dual-core parts that need one kernel per core.
- `CONFIG` is a target whose include directories contain `FreeRTOSConfig.h`.
- `PORT` is a directory under `portable/GCC` (`ARM_CM4F`, `ARM_CM7/r0p1`,
  `ARM_CM33_NTZ/non_secure`, ...). The choice is explicit: e.g. only
  Cortex-M7 r0p1 cores need `ARM_CM7/r0p1`, other Cortex-M7 revisions use
  `ARM_CM4F`. MPU ports are rejected for now (they need extra common
  sources).
- `HEAP` selects `portable/MemMang/heap_<n>.c`; `NONE` links no heap, for
  static allocation only.
- Kernel and port headers are `SYSTEM` includes.

### ThreadX: `vendors/threadx/kernel`

```
threadx_fetch_kernel(GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])

threadx_add_kernel(<name>
  CHIP <chip target>
  PORT <port>
  [CONFIG <target>])
```

- Vendor-neutral: `CHIP` only provides the CPU flags. Default repository:
  `eclipse-threadx/threadx`.
- `threadx_add_kernel()` creates the **STATIC** library `<name>` (all
  `common/src` sources plus the GNU port), compiled once with the chip's
  flags. ThreadX's own `CMakeLists.txt` is not used: it builds one global
  `threadx` target per build tree from `THREADX_ARCH`, which does not fit
  dual-core parts.
- `PORT` is a directory under `ports/` with a `gnu` toolchain directory
  (`cortex_m4`, `cortex_m7`, `cortex_m33`, ...). The port's source list is
  read from `ports/<port>/gnu/CMakeLists.txt`, so per-port differences
  follow upstream. SMP and module ports are not covered.
- `CONFIG` (optional) is a target whose include directories contain
  `tx_user.h`; it adds `TX_INCLUDE_USER_DEFINE_FILE`.
- Requires C and ASM enabled in `project()` (the port is assembly).
- The application provides `_tx_initialize_low_level()` (system stack
  pointer, tick timer, exception priorities) and calls
  `_tx_timer_interrupt()` from its tick ISR. Upstream's
  `example_build/tx_initialize_low_level.S` depends on its own linker
  symbols and clock value, so it is not used. The port already defines
  `PendSV_Handler` under its CMSIS name.

### ThreadX middleware: FileX, LevelX, NetX Duo, USBX, GUIX

One file each under `vendors/threadx/`, same pattern:

```
threadx_fetch_<component>(GIT_TAG <tag|commit> [GIT_REPOSITORY <url>])

threadx_add_filex(<name>   KERNEL <kernel> [PORT <port>] [CONFIG <target>])
threadx_add_levelx(<name>  KERNEL <kernel> [FILEX <filex>] [CONFIG <target>])
threadx_add_netxduo(<name> KERNEL <kernel> [PORT <port>] [CONFIG <target>]
                           [ADDONS <addon>...] [SECURE])
threadx_add_usbx(<name>    KERNEL <kernel> [PORT <port>] [CONFIG <target>]
                           [NETX <netxduo>] [FILEX <filex>] [PARTS <part>...])
threadx_add_guix(<name>    KERNEL <kernel> [PORT <port>] [CONFIG <target>])
```

- Each creates a **STATIC** library linked to the ThreadX kernel target
  (which brings the chip's CPU flags and the ThreadX headers), so a
  component is built per core like the kernel. `PORT` defaults to the
  kernel's port; `CONFIG` provides the component's `*_user.h` and adds its
  `*_INCLUDE_USER_DEFINE_FILE` define.
- Drivers are the application's. Bundled RAM-backed drivers that need no
  hardware: FileX `_fx_ram_driver`, LevelX NOR / NAND simulators (and, with
  `FILEX`, the FileX media drivers on top of them), NetX Duo
  `_nx_ram_network_driver`.
- NetX Duo: `ADDONS` selects directories under `addons/` (`dhcp`, `dns`,
  `mqtt`, `sntp`, `http`, ...; the message lists them, `azure_iot` is not
  supported). `SECURE` adds NetX Secure (TLS/DTLS) and the crypto library
  with its port.
- USBX: `PARTS` selects `device_classes`, `host_classes`,
  `host_controllers`, `network`, `pictbridge` (default: all; core is always
  built). Classes whose header includes `nx_api.h` (CDC-ECM, RNDIS, ASIX,
  network) are built only with `NETX`, those including `fx_api.h` (host
  storage) only with `FILEX`; `NETX` also adds the network part. The STM32
  device / host controller drivers are no longer part of the USBX
  repository.
- GUIX: only `common/` and `ports/` are fetched; there is no GNU port for
  `cortex_m33`.

### Vendor module errors

`FATAL_ERROR` when: `GIT_TAG` or `FAMILY` is missing, the call order is
wrong (`st_fetch_cmsis_device()` before `arm_fetch_cmsis_core()`,
`st_add_hal()` / `st_add_cmsis_startup()` / `freertos_add_kernel()` /
`threadx_add_kernel()` / `threadx_add_<component>()` before the matching
fetch), an unknown FreeRTOS or ThreadX port (the message lists the
available ports), a component `KERNEL` that was not created by
`threadx_add_kernel()`, an unknown NetX Duo addon or USBX part, USBX
`PARTS network` without `NETX`, a FreeRTOS MPU port, an invalid `HEAP`, a
missing `FreeRTOSConfig.h`, `tx_user.h` or component `*_user.h`, a
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

Checked with the unchanged module files:

- STM32F411CE (single core, `FAMILY F4`, cmsis-device-f4 v2.6.11,
  stm32f4xx-hal-driver v1.8.5, CMSIS_6 v6.1.0): HAL blinky builds without
  warnings.
- A generic Cortex-M4F chip without any vendor package (nRF52840 memory
  map): the FreeRTOS kernel (`ARM_CM4F`, `HEAP 4`) and the ThreadX kernel
  (`cortex_m4`, no `CONFIG`) build without warnings.
- The same STM32H755ZI chip description runs under FreeRTOS and under
  ThreadX; only the RTOS module calls, the RTOS config header and the
  application's task code differ between the two examples.

## H755ZI examples

Two examples run both cores of the STM32H755ZI, one under FreeRTOS and one
under ThreadX. They share
[examples/common/stm32h755zi](../examples/common/stm32h755zi): the chip
description (`stm32h755zi.cmake` with both `mcu_add_chip()` calls, the HAL
config target and the startup / system file names), `stm32h7xx_hal_conf.h`
and `shared_mailbox.h`.

| | CM7 | CM4 |
|---|---|---|
| Chip target | `stm32::H755ZI::CM7` | `stm32::H755ZI::CM4` |
| CPU flags | `cortex-m7`, `fpv5-d16`, hard | `cortex-m4`, `fpv4-sp-d16`, hard |
| HAL library | `hal_cm7` (GPIO, HSEM, PWR + CORTEX, RCC) | `hal_cm4` (same modules) |
| RTOS kernel | FreeRTOS `rtos_cm7`, port `ARM_CM4F`, `HEAP NONE`; ThreadX `rtos_cm7`, port `cortex_m7` | FreeRTOS `rtos_cm4`, port `ARM_CM4F`, `HEAP NONE`; ThreadX `rtos_cm4`, port `cortex_m4` |
| Startup | `startup_cm7` | `startup_cm4` |
| Flash | bank 1, `0x08000000`, 1024K | bank 2, `0x08100000`, 1024K |
| `.data` / `.bss` / stack | DTCM, `0x20000000`, 128K | D2 SRAM via CM4 alias, `0x10000000`, 288K |
| Extra regions | ITCM, AXI SRAM (`.ram_d1`), D3 SRAM (`.shared_d3`) | D3 SRAM (`.shared_d3`) |
| LED task (NUCLEO-H755ZI-Q) | LD1, PB0, 500 ms | LD2, PE1, 250 ms |

- D3 SRAM at `0x38000000` is shared. Both images place their `.shared_d3`
  section at the same address, so `shared_mailbox.h` is the layout contract
  between the two images.
- The CM7 D-cache is off after reset. Once it is enabled, mark D3 SRAM
  non-cacheable in the MPU or use cache maintenance around shared accesses.
- Both cores use `startup_stm32h755xx.s` and
  `system_stm32h7xx_dualcore_boot_cm4_cm7.c` (both cores boot at reset);
  `CORE_CM7` / `CORE_CM4` from the chip targets select the core-specific
  code in the system file.
- `stm32h7xx_hal_conf.h` is ST's unmodified template (all modules enabled).

### FreeRTOS: `examples/h755zi-freertos`

- Package versions are set at the top of the example's `CMakeLists.txt`
  (`CMSIS_CORE_VERSION`, `ST_CMSIS_DEVICE_H7_VERSION`, `ST_HAL_H7_VERSION`,
  `FREERTOS_KERNEL_VERSION`) and can be overridden with `-D`, e.g.
  `-DST_HAL_H7_VERSION=v1.11.5`.
- Each core runs its own FreeRTOS kernel with one statically allocated blink
  task (`xTaskCreateStatic`, `xTaskDelayUntil`). `common/FreeRTOSConfig.h`
  is shared: static allocation only (`configSUPPORT_DYNAMIC_ALLOCATION 0`,
  `configKERNEL_PROVIDED_STATIC_MEMORY 1` for the idle task), no software
  timers, stack overflow check 2, 4 NVIC priority bits, API calls allowed
  from ISRs with priority 5..15. `vPortSVCHandler` / `xPortPendSVHandler` are
  mapped to the CMSIS names `SVC_Handler` / `PendSV_Handler`.
- `common/rtos_glue.cc` defines `SysTick_Handler`, which drives both the HAL
  tick and the FreeRTOS tick (both 1 kHz), and the stack overflow hook
  (trap into the debugger).
- The CM7 uses the `ARM_CM4F` port, which assumes its core revision is not
  r0p1 (r0p1 cores need `ARM_CM7/r0p1`); verify in the device errata sheet.

### ThreadX: `examples/h755zi-threadx`

- Same chip description, HAL and startup as the FreeRTOS example;
  `THREADX_KERNEL_VERSION` selects the kernel tag.
- One ThreadX kernel per core: port `cortex_m7` on the CM7, `cortex_m4` on
  the CM4, shared `common/tx_user.h` (1 kHz tick, stack checking, timer
  processing in the tick ISR).
- Each core creates one blink thread with a static stack in
  `tx_application_define()`; no byte pool, no `malloc`.
- `common/tx_glue.cc` provides `_tx_initialize_low_level()`: system stack
  pointer from the first word of the active vector table (`SCB->VTOR`),
  PendSV / SVCall at the lowest priority, SysTick at 1 kHz with priority 4.
  Its `SysTick_Handler` drives the HAL tick and, once the low-level init has
  run, `_tx_timer_interrupt()`.
- `main()` calls `__disable_irq()` before `tx_kernel_enter()`: ThreadX does
  not disable interrupts during kernel entry, but `HAL_Init()` has already
  started SysTick (see [Toolchain pitfalls](#toolchain-pitfalls)).
- The CM7 image also links FileX, LevelX (with FileX), NetX Duo, USBX
  (`device_classes`, with `NETX`) and GUIX, all with their default
  configuration. `cm7/middleware_demo.cc` runs in its own thread: FileX on a
  64 KiB RAM disk in AXI SRAM, FileX on the LevelX NOR simulator, a ping
  from 1.2.3.4 to 1.2.3.5 between two IP instances on the NetX RAM driver,
  USBX and GUIX system initialization. Each step's status goes into
  `middleware_demo_status` for inspection in a debugger. Large buffers and
  thread stacks are in `.ram_d1`; the LevelX simulator's 64 KiB array sits
  in DTCM `.bss`.
- `THREADX_FILEX_VERSION`, ... default to `THREADX_KERNEL_VERSION` and can
  be overridden one by one (e.g. the NetX Duo hotfix tag
  `v6.5.2.202603a_rel`).

### Verified build results

arm-none-eabi-gcc 15.2.0, CMake 4.3, Ninja; CMSIS_6 v6.1.0, cmsis-device-h7
v1.10.7, stm32h7xx-hal-driver v1.11.6, FreeRTOS-Kernel V11.3.2, ThreadX
v6.5.2.202603_rel. Both examples build without warnings in both presets,
including the HAL and kernel sources and `mcu::warnings` on the application
code. Not yet run on hardware.

FreeRTOS example:

| | CM7 | CM4 |
|---|---|---|
| Vector table | ST `g_pfnVectors` at `0x08000000`, 664 B (166 entries) | at `0x08100000` |
| `SVC_Handler`, `PendSV_Handler` in the vector table | FreeRTOS port handlers | same |
| `SysTick_Handler` | `rtos_glue.cc` (HAL + FreeRTOS tick) | same |
| `shared_mailbox` | `0x38000000` | `0x38000000` |
| `crt0.o`, `malloc`, heap linked | no | no |
| Flash used, Debug / MinSizeRel | 9260 B / 5332 B | 8632 B / 5176 B |

- Each HAL library and each kernel is compiled once per core (8 objects
  each), with that core's CPU flags.

ThreadX example:

| | CM7 | CM4 |
|---|---|---|
| `PendSV_Handler` in the vector table | ThreadX port | same |
| `SysTick_Handler` | `tx_glue.cc` (HAL + ThreadX tick) | same |
| `malloc` linked | no | no |
| Kernel | 192 objects, `cortex_m7`, `-mfpu=fpv5-d16` | 192 objects, `cortex_m4`, `-mfpu=fpv4-sp-d16` |
| Middleware | FileX 212, LevelX 65, NetX Duo 511, USBX 447, GUIX 1315 objects, CM7 flags | none |
| Flash used, Debug / MinSizeRel | 124264 B / 65740 B | 11292 B / 6356 B |
| DTCM / RAM used, Debug | DTCM 117088 B of 128 KiB, AXI SRAM 128 KiB | RAM_D2 5744 B |

The middleware symbols checked in the CM7 image: `_fx_media_format`,
`_fx_ram_driver`, `_fx_nor_flash_simulator_driver`, `_lx_nor_flash_open`,
`_nx_icmp_ping`, `_nx_ram_network_driver`, `_ux_system_initialize`,
`_gx_system_initialize`; no `malloc`.

Also built without warnings on a generic Cortex-M4F chip (no vendor
package): NetX Duo with `ADDONS dhcp dns mqtt sntp SECURE` (879 objects),
USBX without dependencies (832 objects, no CDC-ECM / host storage) and with
`NETX` + `FILEX` (919 objects), LevelX without FileX.
- The flash LOAD segment is `R E`, not RWX.
- With sparse fetches the FreeRTOS example downloads about 93 MB (CMSIS_6
  3.8 MB, cmsis-device-h7 47 MB, HAL 18 MB, FreeRTOS-Kernel 24 MB, including
  `.git`) and configures in about 17 s here (55 s with full shallow
  clones). The ThreadX example adds the kernel (49 MB), FileX (3.2 MB),
  LevelX (1.2 MB), NetX Duo (30 MB), USBX (14 MB) and GUIX (21 MB); about
  42 s.

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

### `SystemCoreClock` conflicting declaration in C++

A typical `FreeRTOSConfig.h` declares `extern uint32_t SystemCoreClock;` for
`configCPU_CLOCK_HZ`. Included from C++ (through `FreeRTOS.h`), that
declaration gets C++ linkage and conflicts with the `extern "C"` declaration
in ST's `system_stm32h7xx.h`. The example's config wraps it in
`extern "C"` when `__cplusplus` is defined.

### ThreadX internal headers in C++

`tx_api.h` has C++ guards, but internal headers such as `tx_initialize.h`
and `tx_thread.h` (needed in `_tx_initialize_low_level()` for
`_tx_thread_system_stack_ptr`) do not. Included from C++, their function
declarations get C++ linkage and conflict with an `extern "C"` definition.
`tx_glue.cc` includes them inside an `extern "C"` block.

### ThreadX timer interrupt before kernel start

`tx_kernel_enter()` neither disables interrupts nor initializes the timer
before calling `_tx_initialize_low_level()`; the scheduler enables
interrupts when the first thread runs. `HAL_Init()` has already started
SysTick, so a tick ISR calling `_tx_timer_interrupt()` too early would use
uninitialized timer state. The example disables interrupts before
`tx_kernel_enter()` and only forwards ticks to ThreadX after its low-level
init has run.

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
- SysTick is shared by the HAL tick and the RTOS tick. ST recommends a basic
  timer (e.g. TIM6/TIM7) as HAL time base when an RTOS uses SysTick; switch
  to that once the HAL is used beyond simple GPIO.
- `stm32h7xx_hal_conf.h` is the unmodified template; set `HSE_VALUE` and
  disable unused modules for the real board.
- Packages are cloned per build tree (Debug and Release each clone once).
  Use `FETCHCONTENT_SOURCE_DIR_*` to share one local copy.
- Fetching by commit hash is tested for sparse fetches (depth 1); the
  non-sparse path (full clone) is not exercised.
- Defining the same chip twice is a `FATAL_ERROR`, also when two
  subprojects of one superbuild do it.
- Not covered yet: FreeRTOS MPU ports, FreeRTOS+ libraries (TCP, CLI, ...),
  ThreadX SMP / module ports, NetX Duo `azure_iot`, TSN and utilities.
- The ThreadX middleware runs with RAM-backed drivers only. Real drivers
  (SDMMC / QSPI flash for FileX and LevelX, the H7 Ethernet MAC for NetX
  Duo, the USB OTG controller for USBX, a display for GUIX) are the next
  step; the STM32 USBX controller drivers come from ST, not from the USBX
  repository.
- DTCM of the ThreadX CM7 image is 89 % used, mostly by the LevelX NOR
  simulator (64 KiB) and the two `FX_MEDIA` blocks; drop the simulator or
  move `.data` / `.bss` to AXI SRAM (`RAM_REGION RAM_D1`) when adding more.
