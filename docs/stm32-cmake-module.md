# STM32 CMake support module

A small, target-based CMake module for STM32 firmware. It replaces the
device database approach of ObKo/stm32-cmake with explicit, validated chip
descriptions: the project passes the values from the datasheet / reference
manual, and the module checks them.

Currently exercised with the STM32H755ZI (dual core, Cortex-M7 + Cortex-M4)
in [examples/h755zi-dual-core](../examples/h755zi-dual-core).

Diagrams:

- [target-architecture.puml](target-architecture.puml): CMake target graph.
- [repo-structure.puml](repo-structure.puml): planned repository layout and
  vendor dependencies.

## Layout

| File | Purpose |
|---|---|
| [cmake/toolchain/arm-none-eabi-gcc.cmake](../cmake/toolchain/arm-none-eabi-gcc.cmake) | Finds the compiler and binutils. No CPU flags. |
| [cmake/stm32.cmake](../cmake/stm32.cmake) | Entry point, `include(stm32)` after `project()`. |
| [cmake/stm32/chip.cmake](../cmake/stm32/chip.cmake) | `stm32_add_chip()` |
| [cmake/stm32/linker.cmake](../cmake/stm32/linker.cmake) | `stm32_add_linker_script()` |
| [cmake/stm32/linker/default.ld.in](../cmake/stm32/linker/default.ld.in) | Default linker script template. |
| [cmake/stm32/outputs.cmake](../cmake/stm32/outputs.cmake) | `stm32_add_firmware_outputs()` |
| [cmake/stm32/support_targets.cmake](../cmake/stm32/support_targets.cmake) | `stm32::cxx_bare_metal`, `stm32::newlib_nano`, `stm32::warnings` |

Requirements: CMake 3.25+, arm-none-eabi-gcc, binutils 2.38+ (for
`READONLY` in the linker script).

## Usage

```cmake
cmake_minimum_required(VERSION 3.25)
project(my_firmware C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "<repo>/cmake")
include(stm32)

stm32_add_chip(H755ZI
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

add_executable(firmware_cm7 main.cc)
target_link_libraries(firmware_cm7 PRIVATE
  stm32::H755ZI::CM7
  stm32::cxx_bare_metal
  stm32::newlib_nano
  stm32::warnings
)
stm32_add_linker_script(firmware_cm7
  CHIP stm32::H755ZI::CM7
  FLASH_REGION FLASH
  RAM_REGION DTCMRAM
  STACK_SIZE 0x2000
  HEAP_SIZE 0
)
stm32_add_firmware_outputs(firmware_cm7 BIN HEX MAP MEMORY_USAGE)
```

Configure with the toolchain file, for example through the presets of the
example:

```
cd examples/h755zi-dual-core
cmake --preset debug
cmake --build --preset debug
```

## API

### `stm32_add_chip()`

```
stm32_add_chip(<chip>
  [CORE <core>]
  CPU <cpu>
  [FPU <fpu>]
  [FLOAT_ABI <soft|softfp|hard>]
  [DEFINITIONS <define>...]
  MEMORY <name> <attributes> <origin> <length> [...])
```

- Creates the INTERFACE target `stm32::<chip>`, or `stm32::<chip>::<core>`
  when `CORE` is given. A dual-core part gets one call per core.
- The target carries `-mcpu`, `-mthumb`, `-mfpu`, `-mfloat-abi` (for compile
  and link, so the linker picks the matching multilib),
  `-ffunction-sections -fdata-sections`, `--gc-sections` and the
  definitions.
- `FLOAT_ABI` defaults to `hard` when `FPU` is given, `soft` otherwise.
- `MEMORY` is a flat list of 4-tuples, written like a GNU ld `MEMORY` block:
  attributes such as `rx` / `xrw`, origin in hex, length as `64K`, `1M`,
  hex or decimal bytes.
- The memory map is stored in the `STM32_MEMORY` target property and read by
  `stm32_add_linker_script()`.

Configuration stops with `FATAL_ERROR` when:

- `CPU` is missing,
- `MEMORY` is empty or not a multiple of 4 values,
- a region name, attribute string or length is invalid,
- an origin is not hex,
- two regions have the same name or overlap,
- `FLOAT_ABI` is `hard` / `softfp` without an `FPU`,
- the same chip (and core) is defined twice.

### `stm32_add_linker_script()`

```
stm32_add_linker_script(<target>
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
  match ST's CMSIS startup files.
- `TEMPLATE` replaces the default template; it receives the same
  `@STM32_LD_*@` variables.

Stops with `FATAL_ERROR` when the chip target is unknown (not created by
`stm32_add_chip()`), when `FLASH_REGION` / `RAM_REGION` is not in the chip's
memory map, or when a required argument is missing.

### `stm32_add_firmware_outputs()`

```
stm32_add_firmware_outputs(<target> [BIN] [HEX] [MAP] [MEMORY_USAGE] [SIZE])
```

Adds post-build `.bin` / `.hex` generation, a linker map file, the linker's
per-region usage report, and `arm-none-eabi-size` output.

### Support targets

| Target | Effect |
|---|---|
| `stm32::cxx_bare_metal` | C++ only: `-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit` |
| `stm32::newlib_nano` | `--specs=nano.specs --specs=nosys.specs` |
| `stm32::warnings` | `-Wall -Wextra -Wshadow -Wdouble-promotion`, plus `-Wold-style-cast -Wnon-virtual-dtor` for C++. Intended for own code, not vendor code. |

## H755ZI dual-core example

The two cores are two separate executables in one build tree, each linked to
its own chip target:

| | CM7 | CM4 |
|---|---|---|
| Chip target | `stm32::H755ZI::CM7` | `stm32::H755ZI::CM4` |
| CPU flags | `cortex-m7`, `fpv5-d16`, hard | `cortex-m4`, `fpv4-sp-d16`, hard |
| Flash | bank 1, `0x08000000`, 1024K | bank 2, `0x08100000`, 1024K |
| `.data` / `.bss` / stack | DTCM, `0x20000000`, 128K | D2 SRAM via CM4 alias, `0x10000000`, 288K |
| Extra regions | ITCM, AXI SRAM (`.ram_d1`), D3 SRAM (`.shared_d3`) | D3 SRAM (`.shared_d3`) |

- D3 SRAM at `0x38000000` is shared. Both images place their `.shared_d3`
  section at the same address, so `common/shared_mailbox.h` is the layout
  contract between the two images.
- The CM7 D-cache is off after reset. Once it is enabled, mark D3 SRAM
  non-cacheable in the MPU or use cache maintenance around shared accesses.
- `example_startup` is an INTERFACE library with `startup.cc` as its source,
  so each core compiles it with its own CPU flags.

### Verified build results

Built with arm-none-eabi-gcc 15.2.0, CMake 4.3, Ninja. Both presets build
without warnings.

| | CM7 | CM4 |
|---|---|---|
| Reset_Handler | `0x080000cc` | `0x0810005c` |
| `_estack` | `0x20020000` (end of DTCM) | `0x10048000` (end of RAM_D2) |
| `shared_mailbox` | `0x38000000` | `0x38000000` |
| `frame_buffer` | `0x24000000` (AXI SRAM) | n/a |
| Flash used, Debug / MinSizeRel | 688 B / 220 B | 300 B / 220 B |

- The vector table is statically initialized: first word `0x20020000`
  (initial SP), second word `0x080000cd` (Reset_Handler with the Thumb bit).
- The flash LOAD segment is `R E`, not RWX.

## Toolchain pitfalls found during bring-up

### RWX LOAD segment warning

`.preinit_array`, `.init_array`, `.fini_array` and the `.ARM*` sections are
flagged writable but live in flash, so ld merged them into an RWX flash
segment and warned. The template marks them `(READONLY)`, which requires
binutils 2.38+.

### nosys "is not implemented and will always fail" warnings

The default `crt0.o` is linked even with a custom `Reset_Handler`, and it
references `exit` / `atexit`, which pull in stdio and the nosys stubs. The
example links with `-nostartfiles` and runs `__preinit_array` /
`__init_array` itself instead of calling `__libc_init_array()`.

When ST's CMSIS startup file is used instead, it calls `__libc_init_array()`,
which needs `_init` from `crti.o`; do not combine it with `-nostartfiles`
without providing that symbol.

### Extra ~5 KB in Debug builds with GCC 15

GCC 15 defines `_GLIBCXX_ASSERTIONS` for unoptimized (`-O0`) builds, so
`std::array::operator[]` gets bounds checks. The libstdc++ failure handler
calls `fprintf` and `abort`, which pull in stdio, malloc and the nosys stubs.
The example overrides `std::__glibcxx_assert_fail` with `__builtin_trap()`:
the checks stay active in Debug, and a failure stops in the debugger instead
of linking the stdio machinery.

## Open points

- The memory values in the example come from the RM0399 memory map but have
  not been checked against the PDF. Verify them against the current
  reference manual.
- The example startup only provides the 16 core exception vectors, no
  peripheral IRQs. It will be replaced by ST's `startup_stm32h755xx_CM7.s` /
  `_CM4.s` through the vendor wrappers.
- Defining the same chip twice is a `FATAL_ERROR`, also when two
  subprojects of one superbuild do it. This may need to change if a
  superbuild layout is adopted.
- Next step: vendor wrappers that fetch CMSIS and the H7 HAL by pinned tag and
  build the HAL once as a `STATIC` library tied to a user-provided
  `hal_conf` target.
