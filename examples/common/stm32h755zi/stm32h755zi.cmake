# STM32H755ZI chip description shared by the H755 examples.
#
# Include after include(mcu) and the ST vendor modules:
#   include(${CMAKE_CURRENT_SOURCE_DIR}/../common/stm32h755zi/stm32h755zi.cmake)
#
# Defines:
#   stm32::H755ZI::CM7, stm32::H755ZI::CM4   chip targets
#   h755::hal_conf    INTERFACE, provides stm32h7xx_hal_conf.h
#   h755::common      INTERFACE, shared headers (shared_mailbox.h)
#   h755_startup      startup file name for st_add_cmsis_startup()
#   h755_system       system file name for st_add_cmsis_startup()

# STM32H755ZI memory map, from RM0399 (STM32H745/755/747/757) "Memory map".
# Verify against the current reference manual before changing.
#
# Split used here:
#   CM7: flash bank 1, DTCM for .data/.bss/stack, AXI SRAM (D1) for buffers.
#   CM4: flash bank 2, D2 SRAM1..3 through the CM4 alias at 0x10000000.
#   Both: D3 SRAM4 as shared memory; both images must use the same layout
#         there (see shared_mailbox.h).
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

mcu_add_chip(stm32::H755ZI::CM4
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

# HAL configuration shared by both cores.
mcu_add_named_library(h755::hal_conf INTERFACE h755_hal_conf_target)
target_include_directories(${h755_hal_conf_target} INTERFACE "${CMAKE_CURRENT_LIST_DIR}")

# Headers shared by both firmware images.
mcu_add_named_library(h755::common INTERFACE h755_common_target)
target_include_directories(${h755_common_target} INTERFACE "${CMAKE_CURRENT_LIST_DIR}")

# Both images boot at the same time (option bytes BCM7 = BCM4 = 1), hence the
# dualcore_boot_cm4_cm7 system file. startup_stm32h755xx.s serves both cores.
set(h755_startup startup_stm32h755xx.s)
set(h755_system system_stm32h7xx_dualcore_boot_cm4_cm7.c)
