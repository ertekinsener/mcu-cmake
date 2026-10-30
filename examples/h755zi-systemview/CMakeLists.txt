cmake_minimum_required(VERSION 3.25)
project(h755zi_systemview C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(mcu)
include(vendors/st/hal)
include(vendors/segger/rtt)
include(vendors/segger/systemview)

# Vendor package versions are chosen here, not in the module. Override on the
# command line, e.g. -DSEGGER_SYSTEMVIEW_VERSION=V4.10. A commit hash also
# works.
if(NOT DEFINED CMSIS_CORE_VERSION)
  set(CMSIS_CORE_VERSION v6.1.0)
endif()
if(NOT DEFINED ST_CMSIS_DEVICE_H7_VERSION)
  set(ST_CMSIS_DEVICE_H7_VERSION v1.10.7)
endif()
if(NOT DEFINED ST_HAL_H7_VERSION)
  set(ST_HAL_H7_VERSION v1.11.6)
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
segger_fetch_rtt(GIT_TAG ${SEGGER_RTT_VERSION})
segger_fetch_systemview(GIT_TAG ${SEGGER_SYSTEMVIEW_VERSION})

include("${CMAKE_CURRENT_SOURCE_DIR}/../common/stm32h755zi/stm32h755zi.cmake")

# Project SystemView configuration (SEGGER_SYSVIEW_Conf.h: 4 KiB buffer),
# shared by both cores.
mcu_add_named_library(h755::sysview_conf INTERFACE sysview_conf_target)
target_include_directories(${sysview_conf_target} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/config")

# Both images are built from app/main.cc; CORE_CM7 / CORE_CM4 select the
# per-core parts. No RTOS: the application's cooperative scheduler reports its
# jobs to SystemView itself (no OS / OS_TARGET).
foreach(core CM7 CM4)
  string(TOLOWER ${core} suffix)

  st_add_hal(h755::hal_${suffix}
    CHIP stm32::H755ZI::${core}
    CONFIG h755::hal_conf
    MODULES GPIO HSEM PWR
  )
  st_add_cmsis_startup(h755::startup_${suffix}
    CHIP stm32::H755ZI::${core}
    STARTUP ${h755_startup}
    SYSTEM ${h755_system}
    HAL h755::hal_${suffix}
  )
  # RTT only as SystemView's transport; no log channel use, so no PRINTF.
  segger_add_rtt(h755::rtt_${suffix} CHIP stm32::H755ZI::${core})
  segger_add_systemview(h755::sysview_${suffix}
    RTT h755::rtt_${suffix}
    CONFIG h755::sysview_conf
  )

  add_executable(firmware_${suffix} app/main.cc ${h755_sysview_sources})
  target_compile_features(firmware_${suffix} PRIVATE cxx_std_23)
  target_link_libraries(firmware_${suffix} PRIVATE
    h755::startup_${suffix}
    h755::hal_${suffix}
    h755::rtt_${suffix}
    h755::sysview_${suffix}
    h755::common
    mcu::cxx_bare_metal
    mcu::newlib_nano
    mcu::warnings
  )
endforeach()

# CM7: .data/.bss/stack in DTCM (not cached, so RTT needs no cache care).
mcu_add_linker_script(firmware_cm7
  CHIP stm32::H755ZI::CM7
  FLASH_REGION FLASH
  RAM_REGION DTCMRAM
  STACK_SIZE 0x1000
  HEAP_SIZE 0
)
# CM4: D2 SRAM; the CM4 has no data cache.
mcu_add_linker_script(firmware_cm4
  CHIP stm32::H755ZI::CM4
  FLASH_REGION FLASH
  RAM_REGION RAM_D2
  STACK_SIZE 0x1000
  HEAP_SIZE 0
)
foreach(core cm7 cm4)
  mcu_add_firmware_outputs(firmware_${core} BIN HEX MAP MEMORY_USAGE)
endforeach()
