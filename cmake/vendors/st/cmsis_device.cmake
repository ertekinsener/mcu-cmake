# ST CMSIS device package (register headers, startup and system files).
#
#   include(vendors/st/cmsis_device)
#
#   st_fetch_cmsis_device(
#     FAMILY <family>               # e.g. H7, F4, G4
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. v1.10.7
#     [GIT_REPOSITORY <url>])       # default: STMicroelectronics/cmsis-device-<family>
#
# Creates the header-only target st::cmsis_device::<family>, linked to
# arm::cmsis_core (call arm_fetch_cmsis_core() first).
#
#   st_add_cmsis_startup(<name>     # may be namespaced, e.g. board::startup_cm7
#     CHIP <chip target>            # chip with FAMILY set
#     STARTUP <file>                # name in Source/Templates/gcc or a path
#     SYSTEM <file>                 # name in Source/Templates or a path
#     [HAL <hal target>])           # compile system file with the HAL config
#
# Creates the OBJECT library <name> with ST's startup and system files plus
# the mcu runtime support (see mcu_target_add_runtime()). Link it to exactly
# one executable.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/../arm/cmsis_core.cmake")

# Returns the upper-case family of a chip target, or fails.
function(_st_chip_family context chip out_var)
  if(NOT TARGET ${chip})
    message(FATAL_ERROR "${context}: unknown chip '${chip}'. Call mcu_add_chip() first.")
  endif()
  get_target_property(family ${chip} MCU_FAMILY)
  if(NOT family)
    message(FATAL_ERROR "${context}: ${chip} has no FAMILY. Add FAMILY to its mcu_add_chip() call.")
  endif()
  set(${out_var} ${family} PARENT_SCOPE)
endfunction()

function(st_fetch_cmsis_device)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "FAMILY;GIT_REPOSITORY;GIT_TAG" "")
  set(context "st_fetch_cmsis_device(${arg_FAMILY})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_FAMILY MATCHES "^[A-Z][A-Z0-9]+$")
    message(FATAL_ERROR "${context}: FAMILY is required, upper case (e.g. H7)")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. v1.10.7)")
  endif()
  if(NOT TARGET arm::cmsis_core)
    message(FATAL_ERROR "${context}: call arm_fetch_cmsis_core(GIT_TAG <tag>) first")
  endif()

  string(TOLOWER ${arg_FAMILY} family_l)
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/STMicroelectronics/cmsis-device-${family_l}.git)
  endif()

  mcu_fetch_package(st_cmsis_device_${family_l}
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    SPARSE_PATHS Include Source
    OUT_SOURCE_DIR source_dir
  )
  if(TARGET st_cmsis_device_${family_l})
    return()
  endif()

  if(NOT EXISTS "${source_dir}/Include/stm32${family_l}xx.h")
    message(FATAL_ERROR "${context}: ${source_dir} is not an ST CMSIS device package "
      "(Include/stm32${family_l}xx.h missing)")
  endif()

  add_library(st_cmsis_device_${family_l} INTERFACE)
  add_library(st::cmsis_device::${arg_FAMILY} ALIAS st_cmsis_device_${family_l})
  target_include_directories(st_cmsis_device_${family_l} SYSTEM INTERFACE "${source_dir}/Include")
  target_link_libraries(st_cmsis_device_${family_l} INTERFACE arm::cmsis_core)
endfunction()

function(st_add_cmsis_startup name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CHIP;STARTUP;SYSTEM;HAL" "")
  set(context "st_add_cmsis_startup(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  foreach(required CHIP STARTUP SYSTEM)
    if(NOT arg_${required})
      message(FATAL_ERROR "${context}: ${required} is required")
    endif()
  endforeach()
  if(arg_HAL AND NOT TARGET ${arg_HAL})
    message(FATAL_ERROR "${context}: HAL '${arg_HAL}' is not a target")
  endif()
  get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  if(NOT ASM IN_LIST languages OR NOT C IN_LIST languages)
    message(FATAL_ERROR "${context}: enable C and ASM in project(), e.g. project(<name> C CXX ASM)")
  endif()

  _st_chip_family("${context}" ${arg_CHIP} family)
  string(TOLOWER ${family} family_l)
  mcu_get_package_dir(st_cmsis_device_${family_l} device_dir
    "Call st_fetch_cmsis_device(FAMILY ${family} GIT_TAG <tag>) first.")
  set(templates "${device_dir}/Source/Templates")

  if(IS_ABSOLUTE "${arg_STARTUP}")
    set(startup "${arg_STARTUP}")
  else()
    set(startup "${templates}/gcc/${arg_STARTUP}")
  endif()
  if(NOT EXISTS "${startup}")
    file(GLOB available RELATIVE "${templates}/gcc" "${templates}/gcc/startup_*.s")
    message(FATAL_ERROR "${context}: startup file not found: ${startup}. Available: ${available}")
  endif()

  if(IS_ABSOLUTE "${arg_SYSTEM}")
    set(system "${arg_SYSTEM}")
  else()
    set(system "${templates}/${arg_SYSTEM}")
  endif()
  if(NOT EXISTS "${system}")
    file(GLOB available RELATIVE "${templates}" "${templates}/system_*.c")
    message(FATAL_ERROR "${context}: system file not found: ${system}. Available: ${available}")
  endif()

  mcu_add_named_library(${name} OBJECT target "${startup}" "${system}")
  target_link_libraries(${target} PUBLIC ${arg_CHIP} st::cmsis_device::${family})
  if(arg_HAL)
    # system_*.c includes the HAL config (HSE_VALUE, ...) through USE_HAL_DRIVER.
    target_link_libraries(${target} PUBLIC ${arg_HAL})
  endif()
  mcu_target_add_runtime(${target})
endfunction()
