# Configure-only checks of the module's error handling; one CASE per run,
# driven by tests/CMakeLists.txt. Every case except "ok" must stop with a
# FATAL_ERROR whose text the test matches.
#
# No network: vendor packages are small fake trees written into the build
# directory and handed to mcu_fetch_package() through
# FETCHCONTENT_SOURCE_DIR_<NAME>.

cmake_minimum_required(VERSION 3.25)
project(mcu_cmake_errors C ASM)

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/../../cmake")
include(mcu)
include(vendors/segger/rtt)
include(vendors/segger/systemview)

if(NOT DEFINED CASE)
  message(FATAL_ERROR "set -DCASE=<case>")
endif()

# --- Fake vendor packages ---------------------------------------------------

set(fake "${CMAKE_BINARY_DIR}/fake")
foreach(file
    segger_rtt/RTT/SEGGER_RTT.c
    segger_rtt/RTT/SEGGER_RTT.h
    segger_rtt/RTT/SEGGER_RTT_printf.c
    segger_rtt/RTT/SEGGER_RTT_ASM_ARMv7M.S
    segger_rtt/Config/SEGGER_RTT_Conf.h
    segger_rtt/Syscalls/SEGGER_RTT_Syscalls_GCC.c
    segger_systemview/SEGGER/SEGGER.h
    segger_systemview/SYSVIEW/SEGGER_SYSVIEW.c
    segger_systemview/Config/Global.h
    segger_systemview/Config/SEGGER_SYSVIEW_Conf.h
    segger_systemview/Sample/ThreadX/SEGGER_SYSVIEW_ThreadX.c
    segger_systemview/Sample/FreeRTOSV11/SEGGER_SYSVIEW_FreeRTOS.c
    segger_systemview/Sample/NoOS/Config/Cortex-M/SEGGER_SYSVIEW_Config_NoOS.c
    empty_config/README)
  file(CONFIGURE OUTPUT "${fake}/${file}" CONTENT "")
endforeach()
set(FETCHCONTENT_SOURCE_DIR_SEGGER_RTT "${fake}/segger_rtt")
set(FETCHCONTENT_SOURCE_DIR_SEGGER_SYSTEMVIEW "${fake}/segger_systemview")
set(FETCHCONTENT_SOURCE_DIR_DEMO "${fake}/segger_rtt")

# --- Shared setup -----------------------------------------------------------

function(add_test_chip)
  mcu_add_chip(test::chip
    CPU cortex-m4 FPU fpv4-sp-d16
    MEMORY
      FLASH rx  0x08000000 512K
      RAM   xrw 0x20000000 128K
  )
endfunction()

function(add_rtt_and_systemview)
  add_test_chip()
  segger_fetch_rtt(GIT_TAG V8.58.0)
  segger_add_rtt(test::rtt CHIP test::chip)
  segger_fetch_systemview(GIT_TAG V4.12.0)
endfunction()

add_library(fake_os STATIC IMPORTED)
add_library(interface_lib INTERFACE)
add_library(empty_config INTERFACE)
target_include_directories(empty_config INTERFACE "${fake}/empty_config")
file(CONFIGURE OUTPUT "${CMAKE_BINARY_DIR}/main.c" CONTENT "int main(void) { return 0; }\n")

# --- Cases --------------------------------------------------------------------

if(CASE STREQUAL "ok")
  # Everything valid: must configure.
  add_rtt_and_systemview()
  add_library(rtos STATIC "${CMAKE_BINARY_DIR}/main.c")
  segger_add_systemview(test::sysview RTT test::rtt OS ThreadX OS_TARGET rtos)
  add_executable(fw "${CMAKE_BINARY_DIR}/main.c")
  mcu_add_linker_script(fw CHIP test::chip FLASH_REGION FLASH RAM_REGION RAM
    STACK_SIZE 0x400 HEAP_SIZE 0)
  mcu_add_flash_target(flash FIRMWARE fw PROBE_RS_CHIP STM32F411CEUx)

# Core: chip description.
elseif(CASE STREQUAL "chip_no_memory")
  mcu_add_chip(test::chip CPU cortex-m4)
elseif(CASE STREQUAL "chip_memory_groups")
  mcu_add_chip(test::chip CPU cortex-m4 MEMORY FLASH rx 0x08000000)
elseif(CASE STREQUAL "chip_overlap")
  mcu_add_chip(test::chip CPU cortex-m4
    MEMORY RAM xrw 0x20000000 128K RAM2 xrw 0x2001F000 16K)
elseif(CASE STREQUAL "chip_decimal_origin")
  mcu_add_chip(test::chip CPU cortex-m4 MEMORY FLASH rx 134217728 512K)
elseif(CASE STREQUAL "chip_duplicate_region")
  mcu_add_chip(test::chip CPU cortex-m4
    MEMORY RAM xrw 0x20000000 64K RAM xrw 0x24000000 64K)
elseif(CASE STREQUAL "chip_not_cortex_m")
  mcu_add_chip(test::chip CPU cortex-a7 MEMORY RAM xrw 0x20000000 64K)
elseif(CASE STREQUAL "chip_hard_float_without_fpu")
  mcu_add_chip(test::chip CPU cortex-m4 FLOAT_ABI hard MEMORY RAM xrw 0x20000000 64K)

# Core: naming.
elseif(CASE STREQUAL "name_invalid")
  mcu_add_named_library(bad-name INTERFACE target)
elseif(CASE STREQUAL "name_collision")
  mcu_add_named_library(demo::lib INTERFACE first)
  mcu_add_named_library(demo_lib INTERFACE second)

# Core: linker script.
elseif(CASE STREQUAL "linker_unknown_region")
  add_test_chip()
  add_executable(fw "${CMAKE_BINARY_DIR}/main.c")
  mcu_add_linker_script(fw CHIP test::chip FLASH_REGION FLASH RAM_REGION DTCM
    STACK_SIZE 0x400 HEAP_SIZE 0)
elseif(CASE STREQUAL "linker_unknown_chip")
  add_executable(fw "${CMAKE_BINARY_DIR}/main.c")
  mcu_add_linker_script(fw CHIP test::missing FLASH_REGION FLASH RAM_REGION RAM
    STACK_SIZE 0x400 HEAP_SIZE 0)

# Core: packages.
elseif(CASE STREQUAL "package_version_conflict")
  mcu_fetch_package(demo GIT_REPOSITORY https://example.invalid/demo.git GIT_TAG v1)
  mcu_fetch_package(demo GIT_REPOSITORY https://example.invalid/demo.git GIT_TAG v2)
elseif(CASE STREQUAL "package_not_fetched")
  mcu_get_package_dir(demo dir "Call demo_fetch() first.")

# Core: flash target.
elseif(CASE STREQUAL "flash_no_chip")
  add_executable(fw "${CMAKE_BINARY_DIR}/main.c")
  mcu_add_flash_target(flash FIRMWARE fw)
elseif(CASE STREQUAL "flash_not_executable")
  mcu_add_flash_target(flash FIRMWARE interface_lib PROBE_RS_CHIP STM32F411CEUx)

# SEGGER RTT.
elseif(CASE STREQUAL "rtt_no_tag")
  segger_fetch_rtt()
elseif(CASE STREQUAL "rtt_before_fetch")
  add_test_chip()
  segger_add_rtt(test::rtt CHIP test::chip)
elseif(CASE STREQUAL "rtt_config_without_header")
  add_test_chip()
  segger_fetch_rtt(GIT_TAG V8.58.0)
  segger_add_rtt(test::rtt CHIP test::chip CONFIG empty_config)

# SEGGER SystemView.
elseif(CASE STREQUAL "sysview_before_fetch")
  add_test_chip()
  segger_fetch_rtt(GIT_TAG V8.58.0)
  segger_add_rtt(test::rtt CHIP test::chip)
  segger_add_systemview(test::sysview RTT test::rtt)
elseif(CASE STREQUAL "sysview_no_rtt")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview)
elseif(CASE STREQUAL "sysview_os_without_target")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview RTT test::rtt OS ThreadX)
elseif(CASE STREQUAL "sysview_target_without_os")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview RTT test::rtt OS_TARGET fake_os)
elseif(CASE STREQUAL "sysview_unknown_os")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview RTT test::rtt OS Zephyr OS_TARGET fake_os)
elseif(CASE STREQUAL "sysview_os_target_not_static")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview RTT test::rtt OS ThreadX OS_TARGET interface_lib)
elseif(CASE STREQUAL "sysview_config_without_header")
  add_rtt_and_systemview()
  segger_add_systemview(test::sysview RTT test::rtt CONFIG empty_config)

else()
  message(FATAL_ERROR "unknown CASE '${CASE}'")
endif()
