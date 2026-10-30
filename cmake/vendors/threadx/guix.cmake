# Eclipse ThreadX GUIX (embedded GUI).
#
#   include(vendors/threadx/guix)
#
#   threadx_fetch_guix(
#     GIT_TAG <tag|commit>          # chosen by the project
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/guix
#
#   threadx_add_guix(<name>         # may be namespaced, e.g. board::guix_cm7
#     KERNEL <threadx kernel target>
#     [PORT <port>]                 # default: the kernel's port
#     [CONFIG <target>])            # provides gx_user.h
#
# Creates a STATIC library built with the kernel's chip flags. The display
# driver and the generated GUIX Studio resources are the application's.
# Only common/ and ports/ are fetched: the full repository (GUIX Studio,
# tests) is several hundred MB.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/kernel.cmake")

function(threadx_fetch_guix)
  _threadx_fetch(threadx_guix "threadx_fetch_guix()" guix common/inc/gx_api.h "common;ports" ${ARGN})
endfunction()

function(threadx_add_guix name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "KERNEL;PORT;CONFIG" "")
  set(context "threadx_add_guix(${name})")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()

  _threadx_kernel_port("${context}" "${arg_KERNEL}" kernel_port)
  if(NOT arg_PORT)
    set(arg_PORT ${kernel_port})
  endif()
  mcu_get_package_dir(threadx_guix dir "Call threadx_fetch_guix(GIT_TAG <tag>) first.")
  _threadx_port_include("${context}" "${dir}" ${arg_PORT} gx_port.h port_include)

  file(GLOB sources "${dir}/common/src/*.c")
  set(optional_args "")
  if(arg_CONFIG)
    list(APPEND optional_args CONFIG ${arg_CONFIG})
  endif()
  _threadx_add_component(${name} target
    CONTEXT "${context}"
    KERNEL ${arg_KERNEL}
    ${optional_args}
    USER_HEADER gx_user.h
    USER_DEFINE GX_INCLUDE_USER_DEFINE_FILE
    SOURCES ${sources}
    INCLUDES "${dir}/common/inc" "${port_include}"
  )
endfunction()
