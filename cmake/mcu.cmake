# Entry point of the vendor-neutral MCU CMake module.
#
# Usage (after project()):
#   list(APPEND CMAKE_MODULE_PATH <repo>/cmake)
#   include(mcu)
#   include(vendors/st/hal)     # optional vendor packages, one file each

include_guard(GLOBAL)

if(CMAKE_VERSION VERSION_LESS 3.25)
  message(FATAL_ERROR "mcu: CMake 3.25 or newer is required (found ${CMAKE_VERSION})")
endif()

get_property(_mcu_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
if(NOT _mcu_languages)
  message(FATAL_ERROR "mcu: include(mcu) must come after project()")
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Generic")
  message(FATAL_ERROR
    "mcu: not a bare-metal build (CMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}). "
    "Configure with -DCMAKE_TOOLCHAIN_FILE=<repo>/cmake/toolchain/<toolchain>.cmake")
endif()

# Functions run in the caller's directory scope, so module paths are kept in
# global properties instead of variables.
set_property(GLOBAL PROPERTY MCU_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}/mcu")

include("${CMAKE_CURRENT_LIST_DIR}/mcu/naming.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/arch/arm.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/chip.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/linker.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/outputs.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/flash.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/package.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/runtime.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/mcu/support_targets.cmake")
