cmake_minimum_required(VERSION 3.25)
project(h755zi_dual_core C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(mcu)
include(vendors/st/hal)

# Vendor package versions are chosen here, not in the module. Override on the
# command line, e.g. -DST_HAL_H7_VERSION=v1.11.5. A commit hash also works.
if(NOT DEFINED CMSIS_CORE_VERSION)
  set(CMSIS_CORE_VERSION v6.1.0)
endif()
if(NOT DEFINED ST_CMSIS_DEVICE_H7_VERSION)
  set(ST_CMSIS_DEVICE_H7_VERSION v1.10.7)
endif()
if(NOT DEFINED ST_HAL_H7_VERSION)
  set(ST_HAL_H7_VERSION v1.11.6)
endif()

arm_fetch_cmsis_core(GIT_TAG ${CMSIS_CORE_VERSION})
st_fetch_cmsis_device(FAMILY H7 GIT_TAG ${ST_CMSIS_DEVICE_H7_VERSION})
st_fetch_hal(FAMILY H7 GIT_TAG ${ST_HAL_H7_VERSION})

# STM32H755ZI memory map, from RM0399 (STM32H745/755/747/757) "Memory map".
# Verify against the current reference manual before changing.
#
# Split used here:
#   CM7: flash bank 1, DTCM for .data/.bss/stack, AXI SRAM (D1) for buffers.
#   CM4: flash bank 2, D2 SRAM1..3 through the CM4 alias at 0x10000000.
#   Both: D3 SRAM4 as shared memory; both images must use the same layout
#         there (see common/shared_mailbox.h).
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

mcu_add_chip(STM32H755ZI
  FAMILY H7
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

# HAL configuration shared by both cores (stm32h7xx_hal_conf.h).
add_library(h755_hal_conf INTERFACE)
target_include_directories(h755_hal_conf INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/common")

# Headers shared by both firmware images.
add_library(h755_common INTERFACE)
target_include_directories(h755_common INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/common")

# Both images boot at the same time (option bytes BCM7 = BCM4 = 1), hence the
# dualcore_boot_cm4_cm7 system file. startup_stm32h755xx.s serves both cores.
set(h755_startup startup_stm32h755xx.s)
set(h755_system system_stm32h7xx_dualcore_boot_cm4_cm7.c)

# --- Cortex-M7 -------------------------------------------------------------

st_add_hal(hal_cm7
  CHIP mcu::STM32H755ZI::CM7
  CONFIG h755_hal_conf
  MODULES GPIO HSEM PWR
)
st_add_cmsis_startup(startup_cm7
  CHIP mcu::STM32H755ZI::CM7
  STARTUP ${h755_startup}
  SYSTEM ${h755_system}
  HAL hal_cm7
)

add_executable(firmware_cm7 cm7/main.cc)
target_compile_features(firmware_cm7 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm7 PRIVATE
  startup_cm7
  hal_cm7
  h755_common
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

# --- Cortex-M4 -------------------------------------------------------------

st_add_hal(hal_cm4
  CHIP mcu::STM32H755ZI::CM4
  CONFIG h755_hal_conf
  MODULES GPIO HSEM PWR
)
st_add_cmsis_startup(startup_cm4
  CHIP mcu::STM32H755ZI::CM4
  STARTUP ${h755_startup}
  SYSTEM ${h755_system}
  HAL hal_cm4
)

add_executable(firmware_cm4 cm4/main.cc)
target_compile_features(firmware_cm4 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm4 PRIVATE
  startup_cm4
  hal_cm4
  h755_common
  mcu::cxx_bare_metal
  mcu::newlib_nano
  mcu::warnings
)
mcu_add_linker_script(firmware_cm4
  CHIP mcu::STM32H755ZI::CM4
  FLASH_REGION FLASH
  RAM_REGION RAM_D2
  STACK_SIZE 0x1000
  HEAP_SIZE 0
)
mcu_add_firmware_outputs(firmware_cm4 BIN HEX MAP MEMORY_USAGE)
