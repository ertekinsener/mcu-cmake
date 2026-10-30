# Eclipse ThreadX NetX Duo (TCP/IP stack).
#
#   include(vendors/threadx/netxduo)
#
#   threadx_fetch_netxduo(
#     GIT_TAG <tag|commit>          # chosen by the project
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/netxduo
#
#   threadx_add_netxduo(<name>      # may be namespaced, e.g. board::netx_cm7
#     KERNEL <threadx kernel target>
#     [PORT <port>]                 # default: the kernel's port
#     [CONFIG <target>]             # provides nx_user.h
#     [ADDONS <addon>...]           # directories under addons/, e.g. dhcp dns
#                                   # mqtt sntp
#     [SECURE])                     # NetX Secure (TLS/DTLS) + crypto library
#
# Creates a STATIC library built with the kernel's chip flags. The network
# driver is the application's; the RAM/loopback driver
# (_nx_ram_network_driver) is part of the library. The azure_iot addon (needs
# the Azure SDK for C), TSN and utilities are not covered.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/kernel.cmake")

function(threadx_fetch_netxduo)
  _threadx_fetch(threadx_netxduo "threadx_fetch_netxduo()" netxduo common/inc/nx_api.h
    "common;ports;addons;nx_secure;crypto_libraries" ${ARGN})
endfunction()

function(threadx_add_netxduo name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "SECURE" "KERNEL;PORT;CONFIG" "ADDONS")
  set(context "threadx_add_netxduo(${name})")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()

  _threadx_kernel_port("${context}" "${arg_KERNEL}" kernel_port)
  if(NOT arg_PORT)
    set(arg_PORT ${kernel_port})
  endif()
  mcu_get_package_dir(threadx_netxduo dir "Call threadx_fetch_netxduo(GIT_TAG <tag>) first.")
  _threadx_port_include("${context}" "${dir}" ${arg_PORT} nx_port.h port_include)

  file(GLOB sources "${dir}/common/src/*.c")
  set(includes "${dir}/common/inc" "${port_include}")

  list(REMOVE_DUPLICATES arg_ADDONS)
  foreach(addon IN LISTS arg_ADDONS)
    set(addon_dir "${dir}/addons/${addon}")
    file(GLOB addon_sources "${addon_dir}/*.c")
    if(addon STREQUAL "azure_iot" OR NOT addon_sources)
      file(GLOB available LIST_DIRECTORIES true RELATIVE "${dir}/addons" "${dir}/addons/*")
      list(FILTER available EXCLUDE REGEX "(\\.txt|azure_iot)$")
      message(FATAL_ERROR "${context}: unsupported addon '${addon}'. Available: ${available}")
    endif()
    list(APPEND sources ${addon_sources})
    list(APPEND includes "${addon_dir}")
  endforeach()

  if(arg_SECURE)
    _threadx_port_include("${context}" "${dir}/crypto_libraries" ${arg_PORT} nx_crypto_port.h crypto_port_include)
    file(GLOB secure_sources "${dir}/nx_secure/src/*.c" "${dir}/crypto_libraries/src/*.c")
    list(APPEND sources ${secure_sources})
    list(APPEND includes
      "${dir}/nx_secure/inc"
      "${dir}/nx_secure/ports"
      "${dir}/crypto_libraries/inc"
      "${crypto_port_include}"
    )
  endif()

  set(optional_args "")
  if(arg_CONFIG)
    list(APPEND optional_args CONFIG ${arg_CONFIG})
  endif()
  _threadx_add_component(${name} target
    CONTEXT "${context}"
    KERNEL ${arg_KERNEL}
    ${optional_args}
    USER_HEADER nx_user.h
    USER_DEFINE NX_INCLUDE_USER_DEFINE_FILE
    SOURCES ${sources}
    INCLUDES ${includes}
  )
endfunction()
