# Entry point of the STM32 CMake support module.
#
# Usage (after project()):
#   list(APPEND CMAKE_MODULE_PATH <repo>/cmake)
#   include(stm32)

include_guard(GLOBAL)

if(CMAKE_VERSION VERSION_LESS 3.25)
  message(FATAL_ERROR "stm32: CMake 3.25 or newer is required (found ${CMAKE_VERSION})")
endif()

get_property(_stm32_languages GLOBAL PROPERTY ENABLED_LANGUAGES)
if(NOT _stm32_languages)
  message(FATAL_ERROR "stm32: include(stm32) must come after project()")
endif()

if(NOT CMAKE_SYSTEM_NAME STREQUAL "Generic")
  message(FATAL_ERROR
    "stm32: not a bare-metal build (CMAKE_SYSTEM_NAME=${CMAKE_SYSTEM_NAME}). "
    "Configure with -DCMAKE_TOOLCHAIN_FILE=<repo>/cmake/toolchain/arm-none-eabi-gcc.cmake")
endif()

# Functions run in the caller's directory scope, so module paths are kept in
# global properties instead of variables.
set_property(GLOBAL PROPERTY STM32_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}/stm32")

include("${CMAKE_CURRENT_LIST_DIR}/stm32/chip.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/stm32/linker.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/stm32/outputs.cmake")
include("${CMAKE_CURRENT_LIST_DIR}/stm32/support_targets.cmake")
