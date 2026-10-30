# Arm CMSIS-Core headers, shared by all Cortex-M vendors.
#
#   include(vendors/arm/cmsis_core)
#   arm_fetch_cmsis_core(
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. v6.1.0
#     [GIT_REPOSITORY <url>])       # default: ARM-software/CMSIS_6
#
# Creates the header-only target arm::cmsis_core. Both the Arm layout
# (CMSIS/Core/Include) and vendor mirrors with a top-level Include/ (e.g.
# STMicroelectronics/cmsis_core) are accepted.

include_guard(GLOBAL)

if(NOT COMMAND mcu_fetch_package)
  message(FATAL_ERROR "vendors/arm/cmsis_core: include(mcu) first")
endif()

function(arm_fetch_cmsis_core)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "GIT_REPOSITORY;GIT_TAG" "")
  set(context "arm_fetch_cmsis_core()")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. v6.1.0)")
  endif()
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/ARM-software/CMSIS_6.git)
  endif()

  mcu_fetch_package(arm_cmsis_core
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    # Arm layout and vendor mirrors with a top-level Include/.
    SPARSE_PATHS CMSIS/Core Include
    OUT_SOURCE_DIR source_dir
  )
  if(TARGET arm_cmsis_core)
    return()
  endif()

  set(include_dir "")
  foreach(candidate "${source_dir}/CMSIS/Core/Include" "${source_dir}/Include")
    if(EXISTS "${candidate}/cmsis_compiler.h")
      set(include_dir "${candidate}")
      break()
    endif()
  endforeach()
  if(NOT include_dir)
    message(FATAL_ERROR
      "${context}: cmsis_compiler.h not found in ${source_dir}/CMSIS/Core/Include "
      "or ${source_dir}/Include")
  endif()

  add_library(arm_cmsis_core INTERFACE)
  add_library(arm::cmsis_core ALIAS arm_cmsis_core)
  # SYSTEM: vendor headers do not trigger the project's warning set.
  target_include_directories(arm_cmsis_core SYSTEM INTERFACE "${include_dir}")
endfunction()
