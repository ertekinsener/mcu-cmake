# Eclipse ThreadX kernel, vendor-neutral.
#
#   include(vendors/threadx/kernel)
#
#   threadx_fetch_kernel(
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. v6.5.2.202603_rel
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/threadx
#
#   threadx_add_kernel(<name>       # may be namespaced, e.g. board::rtos_cm7
#     CHIP <chip target>            # provides the CPU flags
#     PORT <port>                   # directory under ports/, e.g. cortex_m4,
#                                   # cortex_m7, cortex_m33
#     [CONFIG <target>])            # provides tx_user.h; defines
#                                   # TX_INCLUDE_USER_DEFINE_FILE
#
# threadx_add_kernel() creates the STATIC library <name> (common sources and
# the GNU port), built once with the chip's flags. ThreadX's own
# CMakeLists.txt is not used: it builds one global "threadx" target per build
# tree from THREADX_ARCH, which does not fit multi-core parts that need one
# kernel per core.
#
# The port's source list is read from ports/<port>/gnu/CMakeLists.txt, so
# per-port differences follow upstream. SMP and module ports are not covered.
#
# The application provides _tx_initialize_low_level() (system stack pointer,
# tick timer, exception priorities) and calls _tx_timer_interrupt() from its
# tick ISR; both depend on the board and the startup code.
#
# The middleware modules (filex, netxduo, usbx, levelx, guix) take the kernel
# target via KERNEL and default to its port.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/common.cmake")

function(threadx_fetch_kernel)
  _threadx_fetch(threadx_kernel "threadx_fetch_kernel()" threadx common/inc/tx_api.h "common;ports" ${ARGN})
endfunction()

function(threadx_add_kernel name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CHIP;PORT;CONFIG" "")
  set(context "threadx_add_kernel(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  foreach(required CHIP PORT)
    if(NOT arg_${required})
      message(FATAL_ERROR "${context}: ${required} is required")
    endif()
  endforeach()
  if(NOT TARGET ${arg_CHIP})
    message(FATAL_ERROR "${context}: unknown chip '${arg_CHIP}'. Call mcu_add_chip() first.")
  endif()
  if(arg_CONFIG AND NOT TARGET ${arg_CONFIG})
    message(FATAL_ERROR "${context}: CONFIG '${arg_CONFIG}' is not a target")
  endif()
  get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  if(NOT ASM IN_LIST languages OR NOT C IN_LIST languages)
    message(FATAL_ERROR "${context}: enable C and ASM in project(), e.g. project(<name> C CXX ASM)")
  endif()

  mcu_get_package_dir(threadx_kernel kernel_dir
    "Call threadx_fetch_kernel(GIT_TAG <tag>) first.")

  set(port_dir "${kernel_dir}/ports/${arg_PORT}/gnu")
  if(NOT EXISTS "${port_dir}/inc/tx_port.h")
    file(GLOB port_candidates RELATIVE "${kernel_dir}/ports" "${kernel_dir}/ports/*/gnu/inc/tx_port.h")
    list(TRANSFORM port_candidates REPLACE "/gnu/inc/tx_port.h$" "")
    message(FATAL_ERROR
      "${context}: no GNU port '${arg_PORT}' (${port_dir}/inc/tx_port.h missing). "
      "Available: ${port_candidates}")
  endif()

  # Port sources as listed by upstream (ports/<port>/gnu/CMakeLists.txt).
  set(port_sources "")
  if(EXISTS "${port_dir}/CMakeLists.txt")
    file(READ "${port_dir}/CMakeLists.txt" port_cmake)
    string(REGEX MATCHALL "src/[A-Za-z0-9_]+\\.(S|s|c)" port_files "${port_cmake}")
    list(REMOVE_DUPLICATES port_files)
    foreach(file IN LISTS port_files)
      if(NOT EXISTS "${port_dir}/${file}")
        message(FATAL_ERROR "${context}: ${port_dir}/CMakeLists.txt lists missing ${file}")
      endif()
      list(APPEND port_sources "${port_dir}/${file}")
    endforeach()
  endif()
  if(NOT port_sources)
    message(FATAL_ERROR "${context}: no sources found for port ${arg_PORT} in ${port_dir}/CMakeLists.txt")
  endif()

  if(arg_CONFIG)
    _threadx_require_header("${context}" ${arg_CONFIG} tx_user.h
      "Start from ${kernel_dir}/common/inc/tx_user_sample.h")
  endif()

  file(GLOB common_sources "${kernel_dir}/common/src/*.c")

  mcu_add_named_library(${name} STATIC target ${common_sources} ${port_sources})
  # SYSTEM: kernel headers do not trigger the project's warning set.
  target_include_directories(${target} SYSTEM PUBLIC
    "${kernel_dir}/common/inc"
    "${port_dir}/inc"
  )
  target_link_libraries(${target} PUBLIC ${arg_CHIP})
  if(arg_CONFIG)
    target_compile_definitions(${target} PUBLIC TX_INCLUDE_USER_DEFINE_FILE)
    target_link_libraries(${target} PUBLIC ${arg_CONFIG})
  endif()
  # Read by the middleware modules as their default port.
  set_target_properties(${target} PROPERTIES THREADX_PORT ${arg_PORT})
endfunction()
