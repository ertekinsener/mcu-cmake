# SEGGER SystemView target sources, vendor-neutral.
#
#   include(vendors/segger/systemview)
#
#   segger_fetch_systemview(
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. V4.12.0
#     [GIT_REPOSITORY <url>])       # default: SEGGERMicro/SystemView
#
#   segger_add_systemview(<name>    # may be namespaced, e.g. board::sysview_cm7
#     RTT <rtt target>              # from segger_add_rtt(); SystemView records
#                                   # into its own RTT channel ("SysView")
#     [CONFIG <target>]             # provides SEGGER_SYSVIEW_Conf.h; without it
#                                   # the package's default Config/ is used
#     [OS <FreeRTOSV11|ThreadX|...>] # RTOS interface from Sample/<OS>/
#     [OS_TARGET <rtos target>])    # the RTOS library, required with OS
#
# Creates a STATIC library built with the RTT target's chip flags, holding the
# SystemView core and, with OS, SEGGER's interface for that RTOS. OS names the
# directory under Sample/ (FreeRTOSV10, FreeRTOSV11, ThreadX, embOS, ...);
# FreeRTOSV11 and ThreadX are the ones used by the examples.
#
# OS_TARGET and the SystemView library are linked both ways: the RTOS hooks
# (FreeRTOS trace macros, ThreadX execution-change notification) call into
# SystemView, and the RTOS interface calls back into the RTOS.
#   FreeRTOS  FreeRTOSConfig.h must end with #include "SEGGER_SYSVIEW_FreeRTOS.h".
#   ThreadX   tx_user.h must define TX_ENABLE_EXECUTION_CHANGE_NOTIFY; the hooks
#             come from systemview/threadx_execution_notify.c.
#
# The application provides the runtime configuration, SEGGER_SYSVIEW_Conf()
# (application name, timestamp source and frequency, RAM base), and calls it
# once at startup. The package's Sample/<OS>/Config/ files are a starting
# point.

include_guard(GLOBAL)

if(NOT COMMAND mcu_fetch_package)
  message(FATAL_ERROR "vendors/segger/systemview: include(mcu) first")
endif()

set(_SEGGER_SYSVIEW_MODULE_DIR "${CMAKE_CURRENT_LIST_DIR}/systemview")

function(segger_fetch_systemview)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "GIT_REPOSITORY;GIT_TAG" "")
  set(context "segger_fetch_systemview()")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. V4.12.0)")
  endif()
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/SEGGERMicro/SystemView.git)
  endif()

  mcu_fetch_package(segger_systemview
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    SPARSE_PATHS SEGGER SYSVIEW Config Sample
    OUT_SOURCE_DIR source_dir
  )
  if(NOT EXISTS "${source_dir}/SYSVIEW/SEGGER_SYSVIEW.c")
    message(FATAL_ERROR "${context}: ${source_dir} is not SEGGER SystemView (SYSVIEW/SEGGER_SYSVIEW.c missing)")
  endif()
endfunction()

function(segger_add_systemview name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "RTT;CONFIG;OS;OS_TARGET" "")
  set(context "segger_add_systemview(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_RTT)
    message(FATAL_ERROR "${context}: RTT is required (a target from segger_add_rtt())")
  endif()
  if(NOT TARGET ${arg_RTT})
    message(FATAL_ERROR "${context}: unknown RTT target '${arg_RTT}'. Call segger_add_rtt() first.")
  endif()
  if(arg_OS AND NOT arg_OS_TARGET)
    message(FATAL_ERROR "${context}: OS ${arg_OS} needs OS_TARGET (the RTOS library)")
  endif()
  if(arg_OS_TARGET AND NOT arg_OS)
    message(FATAL_ERROR "${context}: OS_TARGET needs OS (e.g. FreeRTOSV11, ThreadX)")
  endif()
  if(arg_OS_TARGET AND NOT TARGET ${arg_OS_TARGET})
    message(FATAL_ERROR "${context}: unknown OS_TARGET '${arg_OS_TARGET}'")
  endif()
  mcu_get_package_dir(segger_systemview dir "Call segger_fetch_systemview(GIT_TAG <tag>) first.")

  set(sources "${dir}/SYSVIEW/SEGGER_SYSVIEW.c")
  set(includes "${dir}/SEGGER" "${dir}/SYSVIEW")

  if(arg_OS)
    set(os_dir "${dir}/Sample/${arg_OS}")
    # The interface sources are named after the RTOS, not the directory
    # (Sample/FreeRTOSV11/SEGGER_SYSVIEW_FreeRTOS.c); Config/ holds samples.
    file(GLOB os_sources "${os_dir}/SEGGER_SYSVIEW_*.c")
    if(NOT os_sources)
      file(GLOB available LIST_DIRECTORIES true RELATIVE "${dir}/Sample" "${dir}/Sample/*")
      list(REMOVE_ITEM available COMM NoOS)
      message(FATAL_ERROR "${context}: no RTOS interface in ${os_dir}. Available: ${available}")
    endif()
    # embOS ships a second variant for embOS-Ultra; keep the classic one.
    list(FILTER os_sources EXCLUDE REGEX "_Ultra\\.c$")
    list(APPEND sources ${os_sources})
    list(APPEND includes "${os_dir}")
    if(arg_OS STREQUAL "ThreadX")
      # SEGGER's ThreadX interface has no scheduler hooks of its own.
      list(APPEND sources "${_SEGGER_SYSVIEW_MODULE_DIR}/threadx_execution_notify.c")
    endif()
  endif()

  if(arg_CONFIG)
    if(NOT TARGET ${arg_CONFIG})
      message(FATAL_ERROR "${context}: CONFIG '${arg_CONFIG}' is not a target")
    endif()
    # The project's SEGGER_SYSVIEW_Conf.h replaces Config/; skipped when the
    # include directories use generator expressions.
    get_target_property(config_dirs ${arg_CONFIG} INTERFACE_INCLUDE_DIRECTORIES)
    set(config_has_global FALSE)
    if(config_dirs AND NOT config_dirs MATCHES "\\$<")
      set(found_config FALSE)
      foreach(config_dir IN LISTS config_dirs)
        if(EXISTS "${config_dir}/SEGGER_SYSVIEW_Conf.h")
          set(found_config TRUE)
        endif()
        if(EXISTS "${config_dir}/Global.h")
          set(config_has_global TRUE)
        endif()
      endforeach()
      if(NOT found_config)
        message(FATAL_ERROR
          "${context}: SEGGER_SYSVIEW_Conf.h not found in the include directories of "
          "${arg_CONFIG} (${config_dirs}). Start from ${dir}/Config/SEGGER_SYSVIEW_Conf.h")
      endif()
    endif()
    # Config/ also holds Global.h (U8, U32, ... used by SEGGER.h). Without
    # Config/ on the include path, forward to it unless the project has one.
    if(NOT config_has_global)
      string(MAKE_C_IDENTIFIER "${name}" forward_name)
      set(forward_dir "${CMAKE_CURRENT_BINARY_DIR}/segger_systemview/${forward_name}")
      file(CONFIGURE OUTPUT "${forward_dir}/Global.h"
        CONTENT "// Generated by segger_add_systemview(): the package's Global.h.\n#include \"${dir}/Config/Global.h\"\n")
      list(APPEND includes "${forward_dir}")
    endif()
  else()
    list(APPEND includes "${dir}/Config")
  endif()

  mcu_add_named_library(${name} STATIC target ${sources})
  # SYSTEM: vendor headers do not trigger the project's warning set.
  target_include_directories(${target} SYSTEM PUBLIC ${includes})
  if(arg_CONFIG)
    target_link_libraries(${target} PUBLIC ${arg_CONFIG})
  endif()
  # The RTT target brings the chip flags and SEGGER_RTT.h.
  target_link_libraries(${target} PUBLIC ${arg_RTT})

  if(arg_OS_TARGET)
    mcu_resolve_target(${arg_OS_TARGET} os_target)
    get_target_property(os_type ${os_target} TYPE)
    if(NOT os_type STREQUAL "STATIC_LIBRARY")
      message(FATAL_ERROR "${context}: OS_TARGET '${arg_OS_TARGET}' must be a STATIC library (is ${os_type})")
    endif()
    # Circular on purpose; CMake repeats static libraries on the link line.
    target_link_libraries(${target} PUBLIC ${os_target})
    target_link_libraries(${os_target} PUBLIC ${target})
  endif()
endfunction()
