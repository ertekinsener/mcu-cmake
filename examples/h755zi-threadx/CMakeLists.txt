cmake_minimum_required(VERSION 3.25)
project(h755zi_threadx C CXX ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(mcu)
include(vendors/st/hal)
include(vendors/segger/rtt)
include(vendors/segger/systemview)
include(vendors/threadx/kernel)
include(vendors/threadx/filex)
include(vendors/threadx/levelx)
include(vendors/threadx/netxduo)
include(vendors/threadx/usbx)
include(vendors/threadx/guix)

# Vendor package versions are chosen here, not in the module. Override on the
# command line, e.g. -DTHREADX_KERNEL_VERSION=v6.5.1.202602_rel. A commit hash
# also works.
if(NOT DEFINED CMSIS_CORE_VERSION)
  set(CMSIS_CORE_VERSION v6.1.0)
endif()
if(NOT DEFINED ST_CMSIS_DEVICE_H7_VERSION)
  set(ST_CMSIS_DEVICE_H7_VERSION v1.10.7)
endif()
if(NOT DEFINED ST_HAL_H7_VERSION)
  set(ST_HAL_H7_VERSION v1.11.6)
endif()
if(NOT DEFINED THREADX_KERNEL_VERSION)
  set(THREADX_KERNEL_VERSION v6.5.2.202603_rel)
endif()
if(NOT DEFINED SEGGER_RTT_VERSION)
  set(SEGGER_RTT_VERSION V8.58.0)
endif()
if(NOT DEFINED SEGGER_SYSTEMVIEW_VERSION)
  set(SEGGER_SYSTEMVIEW_VERSION V4.12.0)
endif()
# The middleware follows the kernel release unless set separately.
foreach(component FILEX LEVELX NETXDUO USBX GUIX)
  if(NOT DEFINED THREADX_${component}_VERSION)
    set(THREADX_${component}_VERSION ${THREADX_KERNEL_VERSION})
  endif()
endforeach()

arm_fetch_cmsis_core(GIT_TAG ${CMSIS_CORE_VERSION})
st_fetch_cmsis_device(FAMILY H7 GIT_TAG ${ST_CMSIS_DEVICE_H7_VERSION})
st_fetch_hal(FAMILY H7 GIT_TAG ${ST_HAL_H7_VERSION})
threadx_fetch_kernel(GIT_TAG ${THREADX_KERNEL_VERSION})
threadx_fetch_filex(GIT_TAG ${THREADX_FILEX_VERSION})
threadx_fetch_levelx(GIT_TAG ${THREADX_LEVELX_VERSION})
threadx_fetch_netxduo(GIT_TAG ${THREADX_NETXDUO_VERSION})
threadx_fetch_usbx(GIT_TAG ${THREADX_USBX_VERSION})
threadx_fetch_guix(GIT_TAG ${THREADX_GUIX_VERSION})
segger_fetch_rtt(GIT_TAG ${SEGGER_RTT_VERSION})
segger_fetch_systemview(GIT_TAG ${SEGGER_SYSTEMVIEW_VERSION})

include("${CMAKE_CURRENT_SOURCE_DIR}/../common/stm32h755zi/stm32h755zi.cmake")

# ThreadX configuration shared by both cores (tx_user.h) and the board glue
# (_tx_initialize_low_level, SysTick_Handler) compiled into each image.
mcu_add_named_library(h755::threadx_conf INTERFACE threadx_conf_target)
target_include_directories(${threadx_conf_target} INTERFACE "${CMAKE_CURRENT_SOURCE_DIR}/common")

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
threadx_add_kernel(h755::rtos_cm7
  CHIP stm32::H755ZI::CM7
  PORT cortex_m7
  CONFIG h755::threadx_conf
)

# RTT log channel 0; the control block lands in DTCM (.bss), which is not
# cached, so the probe sees writes immediately.
segger_add_rtt(h755::rtt_cm7 CHIP stm32::H755ZI::CM7 PRINTF)

# SystemView in its own RTT channel ("SysView"). tx_user.h enables the
# kernel's execution-change hooks, which the module implements.
segger_add_systemview(h755::sysview_cm7
  RTT h755::rtt_cm7
  OS ThreadX
  OS_TARGET h755::rtos_cm7
)

# ThreadX middleware on the CM7, default configuration (no *_user.h) and the
# kernel's port. Drivers: FileX RAM disk, LevelX NOR simulator, NetX Duo RAM
# network driver; USBX and GUIX are only initialized.
threadx_add_filex(h755::filex_cm7 KERNEL h755::rtos_cm7)
threadx_add_levelx(h755::levelx_cm7 KERNEL h755::rtos_cm7 FILEX h755::filex_cm7)
threadx_add_netxduo(h755::netx_cm7 KERNEL h755::rtos_cm7)
threadx_add_usbx(h755::usbx_cm7 KERNEL h755::rtos_cm7 NETX h755::netx_cm7 PARTS device_classes)
threadx_add_guix(h755::guix_cm7 KERNEL h755::rtos_cm7)

add_executable(firmware_cm7 cm7/main.cc cm7/middleware_demo.cc common/tx_glue.cc
  ${h755_sysview_sources})
target_compile_features(firmware_cm7 PRIVATE cxx_std_23)
target_link_libraries(firmware_cm7 PRIVATE
  h755::startup_cm7
  h755::hal_cm7
  h755::rtos_cm7
  h755::rtt_cm7
  h755::sysview_cm7
  h755::filex_cm7
  h755::levelx_cm7
  h755::netx_cm7
  h755::usbx_cm7
  h755::guix_cm7
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
threadx_add_kernel(h755::rtos_cm4
  CHIP stm32::H755ZI::CM4
  PORT cortex_m4
  CONFIG h755::threadx_conf
)

# RTT log channel 0; the control block lands in D2 SRAM (.bss). The CM4 has
# no data cache.
segger_add_rtt(h755::rtt_cm4 CHIP stm32::H755ZI::CM4 PRINTF)

segger_add_systemview(h755::sysview_cm4
  RTT h755::rtt_cm4
  OS ThreadX
  OS_TARGET h755::rtos_cm4
)

add_executable(firmware_cm4 cm4/main.cc common/tx_glue.cc ${h755_sysview_sources})
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
