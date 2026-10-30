cmake_minimum_required(VERSION 3.25)
project(h755zi_dual_core C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(stm32)

# STM32H755ZI memory map, from RM0399 (STM32H745/755/747/757) "Memory map".
# Verify against the current reference manual before changing.
#
# Split used here:
#   CM7: flash bank 1, DTCM for .data/.bss/stack, AXI SRAM (D1) for buffers.
#   CM4: flash bank 2, D2 SRAM1..3 through the CM4 alias at 0x10000000.
#   Both: D3 SRAM4 as shared memory; both images must use the same layout
#         there (see common/shared_mailbox.h).
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

stm32_add_chip(H755ZI
  CORE CM4
  CPU cortex-m4
  FPU fpv4-sp-d16
  FLOAT_ABI hard
  DEFINITIONS STM32H755xx CORE_CM4
  MEMORY
    FLASH     rx  0x08100000 1024K
    RAM_D2    xrw 0x10000000 288K
    SHARED_D3 xrw 0x38000000 64K
)

# Startup shared by both cores. INTERFACE sources are compiled inside each
# consumer, so every core builds it with its own CPU flags.
add_library(example_startup INTERFACE)
target_sources(example_startup INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/common/startup.cc"
)
target_include_directories(example_startup INTERFACE
  "${CMAKE_CURRENT_SOURCE_DIR}/common"
)
# Own Reset_Handler: skip crt0 (it pulls exit/atexit and the nosys stubs).
target_link_options(example_startup INTERFACE -nostartfiles)

add_executable(firmware_cm7 cm7/main.cc)
target_compile_features(firmware_cm7 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm7 PRIVATE
  stm32::H755ZI::CM7
  example_startup
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

add_executable(firmware_cm4 cm4/main.cc)
target_compile_features(firmware_cm4 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm4 PRIVATE
  stm32::H755ZI::CM4
  example_startup
  stm32::cxx_bare_metal
  stm32::newlib_nano
  stm32::warnings
)
stm32_add_linker_script(firmware_cm4
  CHIP stm32::H755ZI::CM4
  FLASH_REGION FLASH
  RAM_REGION RAM_D2
  STACK_SIZE 0x1000
  HEAP_SIZE 0
)
stm32_add_firmware_outputs(firmware_cm4 BIN HEX MAP MEMORY_USAGE)
