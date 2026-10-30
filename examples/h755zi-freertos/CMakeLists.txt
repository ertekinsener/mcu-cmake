cmake_minimum_required(VERSION 3.25)
project(h755zi_freertos C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(mcu)
include(vendors/st/hal)
include(vendors/segger/rtt)
include(vendors/segger/systemview)
include(vendors/freertos/kernel)

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
if(NOT DEFINED FREERTOS_KERNEL_VERSION)
  set(FREERTOS_KERNEL_VERSION V11.3.2)
endif()
if(NOT DEFINED SEGGER_RTT_VERSION)
  set(SEGGER_RTT_VERSION V8.58.0)
endif()
if(NOT DEFINED SEGGER_SYSTEMVIEW_VERSION)
  set(SEGGER_SYSTEMVIEW_VERSION V4.12.0)
endif()

arm_fetch_cmsis_core(GIT_TAG ${CMSIS_CORE_VERSION})
st_fetch_cmsis_device(FAMILY H7 GIT_TAG ${ST_CMSIS_DEVICE_H7_VERSION})
st_fetch_hal(FAMILY H7 GIT_TAG ${ST_HAL_H7_VERSION})
freertos_fetch_kernel(GIT_TAG ${FREERTOS_KERNEL_VERSION})
segger_fetch_rtt(GIT_TAG ${SEGGER_RTT_VERSION})
segger_fetch_systemview(GIT_TAG ${SEGGER_SYSTEMVIEW_VERSION})

include("${CMAKE_CURRENT_SOURCE_DIR}/../common/stm32h755zi/stm32h755zi.cmake")

# FreeRTOS configuration shared by both cores (FreeRTOSConfig.h, which pulls
# in the SystemView trace macros).
mcu_add_named_library(h755::freertos_conf INTERFACE freertos_conf_target)
target_include_directories(${freertos_conf_target} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/common")

# One FreeRTOS kernel per core, static allocation only (HEAP NONE).
# ARM_CM4F on the CM7 assumes its core revision is not r0p1; r0p1 cores need
# ARM_CM7/r0p1 (FreeRTOS portable/GCC/ARM_CM7/ReadMe.txt). Verify the core
# revision in the device errata sheet.
set(h755_rtos_port_cm7 ARM_CM4F)
set(h755_rtos_port_cm4 ARM_CM4F)

# --- Cortex-M7 -------------------------------------------------------------

st_add_hal(h755::hal_cm7
  CHIP stm32::H755ZI::CM7
  CONFIG h755::hal_conf
  MODULES GPIO HSEM PWR
)
st_add_cmsis_startup(h755::startup_cm7
  CHIP stm32::H755ZI::CM7
  STARTUP ${h755_startup}
  SYSTEM ${h755_system}
  HAL h755::hal_cm7
)
freertos_add_kernel(h755::rtos_cm7
  CHIP stm32::H755ZI::CM7
  CONFIG h755::freertos_conf
  PORT ${h755_rtos_port_cm7}
  HEAP NONE
)

# RTT log channel 0; the control block lands in DTCM (.bss), which is not
# cached, so the probe sees writes immediately.
segger_add_rtt(h755::rtt_cm7 CHIP stm32::H755ZI::CM7 PRINTF)

# SystemView records into its own RTT channel ("SysView", 1 KiB, also in
# .bss). The FreeRTOS kernel is linked against it for the trace hooks.
segger_add_systemview(h755::sysview_cm7
  RTT h755::rtt_cm7
  OS FreeRTOSV11
  OS_TARGET h755::rtos_cm7
)

add_executable(firmware_cm7 cm7/main.cc common/rtos_glue.cc ${h755_sysview_sources})
target_compile_features(firmware_cm7 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm7 PRIVATE
  h755::startup_cm7
  h755::hal_cm7
  h755::rtos_cm7
  h755::rtt_cm7
  h755::sysview_cm7
  h755::common
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

# --- Cortex-M4 -------------------------------------------------------------

st_add_hal(h755::hal_cm4
  CHIP stm32::H755ZI::CM4
  CONFIG h755::hal_conf
  MODULES GPIO HSEM PWR
)
st_add_cmsis_startup(h755::startup_cm4
  CHIP stm32::H755ZI::CM4
  STARTUP ${h755_startup}
  SYSTEM ${h755_system}
  HAL h755::hal_cm4
)
freertos_add_kernel(h755::rtos_cm4
  CHIP stm32::H755ZI::CM4
  CONFIG h755::freertos_conf
  PORT ${h755_rtos_port_cm4}
  HEAP NONE
)

# RTT log channel 0; the control block lands in D2 SRAM (.bss). The CM4 has
# no data cache.
segger_add_rtt(h755::rtt_cm4 CHIP stm32::H755ZI::CM4 PRINTF)

segger_add_systemview(h755::sysview_cm4
  RTT h755::rtt_cm4
  OS FreeRTOSV11
  OS_TARGET h755::rtos_cm4
)

add_executable(firmware_cm4 cm4/main.cc common/rtos_glue.cc ${h755_sysview_sources})
target_compile_features(firmware_cm4 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm4 PRIVATE
  h755::startup_cm4
  h755::hal_cm4
  h755::rtos_cm4
  h755::rtt_cm4
  h755::sysview_cm4
  h755::common
  mcu::cxx_bare_metal
  mcu::newlib_nano
  mcu::warnings
)
mcu_add_linker_script(firmware_cm4
  CHIP stm32::H755ZI::CM4
  FLASH_REGION FLASH
  RAM_REGION RAM_D2
  STACK_SIZE 0x1000
  HEAP_SIZE 0
)
mcu_add_firmware_outputs(firmware_cm4 BIN HEX MAP MEMORY_USAGE)
