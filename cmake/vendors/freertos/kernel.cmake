# FreeRTOS kernel, vendor-neutral.
#
#   include(vendors/freertos/kernel)
#
#   freertos_fetch_kernel(
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. V11.3.2
#     [GIT_REPOSITORY <url>])       # default: FreeRTOS/FreeRTOS-Kernel
#
#   freertos_add_kernel(<name>
#     CHIP <chip target>            # provides the CPU flags
#     CONFIG <target>               # provides FreeRTOSConfig.h
#     PORT <port>                   # directory under portable/GCC, e.g.
#                                   # ARM_CM4F, ARM_CM7/r0p1, ARM_CM33_NTZ/non_secure
#     HEAP <1|2|3|4|5|NONE>)        # portable/MemMang/heap_<n>.c, NONE for
#                                   # static allocation only
#
# freertos_add_kernel() creates the STATIC library <name>, built once with the
# chip's flags. The kernel's own CMakeLists.txt is not used: it supports one
# kernel per build tree (a single global freertos_config target), which does
# not fit multi-core parts that need one kernel per core.
#
# The port is an explicit choice. Example: Cortex-M7 r0p1 needs ARM_CM7/r0p1,
# later Cortex-M7 revisions use ARM_CM4F (see the port's readme).
# MPU ports (ARM_CM*_MPU) also need portable/Common sources and are not
# covered yet.

include_guard(GLOBAL)

if(NOT COMMAND mcu_fetch_package)
  message(FATAL_ERROR "vendors/freertos/kernel: include(mcu) first")
endif()

function(freertos_fetch_kernel)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "GIT_REPOSITORY;GIT_TAG" "")
  set(context "freertos_fetch_kernel()")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. V11.3.2)")
  endif()
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/FreeRTOS/FreeRTOS-Kernel.git)
  endif()

  mcu_fetch_package(freertos_kernel
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    OUT_SOURCE_DIR source_dir
  )
  if(NOT EXISTS "${source_dir}/tasks.c" OR NOT EXISTS "${source_dir}/include/FreeRTOS.h")
    message(FATAL_ERROR "${context}: ${source_dir} is not a FreeRTOS kernel (tasks.c or include/FreeRTOS.h missing)")
  endif()
endfunction()

function(freertos_add_kernel name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CHIP;CONFIG;PORT;HEAP" "")
  set(context "freertos_add_kernel(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  foreach(required CHIP CONFIG PORT HEAP)
    if(NOT DEFINED arg_${required} OR arg_${required} STREQUAL "")
      message(FATAL_ERROR "${context}: ${required} is required")
    endif()
  endforeach()
  if(NOT TARGET ${arg_CHIP})
    message(FATAL_ERROR "${context}: unknown chip '${arg_CHIP}'. Call mcu_add_chip() first.")
  endif()
  if(NOT TARGET ${arg_CONFIG})
    message(FATAL_ERROR "${context}: CONFIG '${arg_CONFIG}' is not a target")
  endif()
  if(NOT arg_HEAP MATCHES "^([1-5]|NONE)$")
    message(FATAL_ERROR "${context}: HEAP must be 1, 2, 3, 4, 5 or NONE, got '${arg_HEAP}'")
  endif()

  mcu_get_package_dir(freertos_kernel kernel_dir
    "Call freertos_fetch_kernel(GIT_TAG <tag>) first.")

  # The config target must expose FreeRTOSConfig.h. Skipped when its include
  # directories use generator expressions.
  get_target_property(config_dirs ${arg_CONFIG} INTERFACE_INCLUDE_DIRECTORIES)
  if(config_dirs AND NOT config_dirs MATCHES "\\$<")
    set(found_config FALSE)
    foreach(dir IN LISTS config_dirs)
      if(EXISTS "${dir}/FreeRTOSConfig.h")
        set(found_config TRUE)
      endif()
    endforeach()
    if(NOT found_config)
      message(FATAL_ERROR
        "${context}: FreeRTOSConfig.h not found in the include directories of "
        "${arg_CONFIG} (${config_dirs})")
    endif()
  endif()

  set(port_dir "${kernel_dir}/portable/GCC/${arg_PORT}")
  if(NOT EXISTS "${port_dir}/portmacro.h")
    file(GLOB_RECURSE port_headers RELATIVE "${kernel_dir}/portable/GCC"
      "${kernel_dir}/portable/GCC/*/portmacro.h")
    list(TRANSFORM port_headers REPLACE "/portmacro.h$" "")
    list(FILTER port_headers INCLUDE REGEX "^ARM_CM")
    message(FATAL_ERROR
      "${context}: no GCC port '${arg_PORT}' (${port_dir}/portmacro.h missing). "
      "Cortex-M ports: ${port_headers}")
  endif()
  if(arg_PORT MATCHES "_MPU")
    message(FATAL_ERROR "${context}: MPU ports are not supported yet")
  endif()
  file(GLOB port_sources "${port_dir}/*.c")

  set(sources
    "${kernel_dir}/croutine.c"
    "${kernel_dir}/event_groups.c"
    "${kernel_dir}/list.c"
    "${kernel_dir}/queue.c"
    "${kernel_dir}/stream_buffer.c"
    "${kernel_dir}/tasks.c"
    "${kernel_dir}/timers.c"
    ${port_sources}
  )
  if(NOT arg_HEAP STREQUAL "NONE")
    list(APPEND sources "${kernel_dir}/portable/MemMang/heap_${arg_HEAP}.c")
  endif()

  add_library(${name} STATIC ${sources})
  # SYSTEM: kernel headers do not trigger the project's warning set.
  target_include_directories(${name} SYSTEM PUBLIC
    "${kernel_dir}/include"
    "${port_dir}"
  )
  target_link_libraries(${name} PUBLIC ${arg_CHIP} ${arg_CONFIG})
endfunction()
