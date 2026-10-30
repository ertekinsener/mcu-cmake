# Eclipse ThreadX FileX (FAT file system).
#
#   include(vendors/threadx/filex)
#
#   threadx_fetch_filex(
#     GIT_TAG <tag|commit>          # chosen by the project
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/filex
#
#   threadx_add_filex(<name>        # may be namespaced, e.g. board::filex_cm7
#     KERNEL <threadx kernel target>
#     [PORT <port>]                 # default: the kernel's port
#     [CONFIG <target>])            # provides fx_user.h
#
# Creates a STATIC library built with the kernel's chip flags. The media
# driver is the application's; FileX's RAM driver (_fx_ram_driver) is part of
# the library.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/kernel.cmake")

function(threadx_fetch_filex)
  _threadx_fetch(threadx_filex "threadx_fetch_filex()" filex common/inc/fx_api.h "common;ports" ${ARGN})
endfunction()

function(threadx_add_filex name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "KERNEL;PORT;CONFIG" "")
  set(context "threadx_add_filex(${name})")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()

  _threadx_kernel_port("${context}" "${arg_KERNEL}" kernel_port)
  if(NOT arg_PORT)
    set(arg_PORT ${kernel_port})
  endif()
  mcu_get_package_dir(threadx_filex dir "Call threadx_fetch_filex(GIT_TAG <tag>) first.")
  _threadx_port_include("${context}" "${dir}" ${arg_PORT} fx_port.h port_include)

  file(GLOB sources "${dir}/common/src/*.c")
  set(optional_args "")
  if(arg_CONFIG)
    list(APPEND optional_args CONFIG ${arg_CONFIG})
  endif()
  _threadx_add_component(${name} target
    CONTEXT "${context}"
    KERNEL ${arg_KERNEL}
    ${optional_args}
    USER_HEADER fx_user.h
    USER_DEFINE FX_INCLUDE_USER_DEFINE_FILE
    SOURCES ${sources}
    INCLUDES "${dir}/common/inc" "${port_include}"
  )
endfunction()
