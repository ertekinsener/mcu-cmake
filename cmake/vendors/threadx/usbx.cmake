# Eclipse ThreadX USBX (USB host / device stack).
#
#   include(vendors/threadx/usbx)
#
#   threadx_fetch_usbx(
#     GIT_TAG <tag|commit>          # chosen by the project
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/usbx
#
#   threadx_add_usbx(<name>         # may be namespaced, e.g. board::usbx_cm7
#     KERNEL <threadx kernel target>
#     [PORT <port>]                 # default: the kernel's port
#     [CONFIG <target>]             # provides ux_user.h
#     [NETX <netxduo target>]       # enables the classes that need NetX Duo
#                                   # and adds the network part (USBX <-> NetX)
#     [FILEX <filex target>]        # enables the classes that need FileX
#     [PARTS <part>...])            # default: all; core is always included.
#                                   # device_classes host_classes
#                                   # host_controllers network pictbridge
#
# Classes whose header includes nx_api.h (CDC-ECM, RNDIS, ASIX, the network
# part) are built only with NETX, classes whose header includes fx_api.h (host
# storage) only with FILEX; otherwise they are left out. Requesting PARTS
# network without NETX is an error. For host storage without FileX, define
# UX_HOST_CLASS_STORAGE_NO_FILEX in ux_user.h and pass FILEX anyway, or build
# that class yourself.
# Creates a STATIC library built with the kernel's chip flags. The USB
# controller driver (DCD / HCD) is the application's: recent USBX releases no
# longer ship the STM32 controller drivers, ST provides them separately.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/kernel.cmake")

function(threadx_fetch_usbx)
  _threadx_fetch(threadx_usbx "threadx_fetch_usbx()" usbx common/core/inc/ux_api.h "common;ports" ${ARGN})
endfunction()

function(threadx_add_usbx name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "KERNEL;PORT;CONFIG;NETX;FILEX" "PARTS")
  set(context "threadx_add_usbx(${name})")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()

  _threadx_kernel_port("${context}" "${arg_KERNEL}" kernel_port)
  foreach(dependency NETX FILEX)
    if(arg_${dependency} AND NOT TARGET ${arg_${dependency}})
      message(FATAL_ERROR "${context}: ${dependency} '${arg_${dependency}}' is not a target")
    endif()
  endforeach()
  if(NOT arg_PORT)
    set(arg_PORT ${kernel_port})
  endif()
  mcu_get_package_dir(threadx_usbx dir "Call threadx_fetch_usbx(GIT_TAG <tag>) first.")
  _threadx_port_include("${context}" "${dir}" ${arg_PORT} ux_port.h port_include)

  # Parts are the common/usbx_<part> directories.
  file(GLOB available LIST_DIRECTORIES true RELATIVE "${dir}/common" "${dir}/common/usbx_*")
  list(TRANSFORM available REPLACE "^usbx_" "")
  set(parts_explicit FALSE)
  if(arg_PARTS)
    set(parts_explicit TRUE)
  else()
    set(arg_PARTS ${available})
  endif()

  set(part_dirs "${dir}/common/core")
  foreach(part IN LISTS arg_PARTS)
    if(part STREQUAL "core")
      continue()
    endif()
    if(NOT part IN_LIST available)
      message(FATAL_ERROR "${context}: unknown part '${part}'. Available: core ${available}")
    endif()
    list(APPEND part_dirs "${dir}/common/usbx_${part}")
  endforeach()
  if(arg_NETX AND EXISTS "${dir}/common/usbx_network")
    # The NetX-based classes include ux_network_driver.h.
    list(APPEND part_dirs "${dir}/common/usbx_network")
  endif()
  list(REMOVE_DUPLICATES part_dirs)

  set(sources "")
  set(includes "${port_include}")
  foreach(part_dir IN LISTS part_dirs)
    file(GLOB part_sources "${part_dir}/src/*.c")
    # Leave out every class whose header pulls in a middleware that was not
    # given: a header ux_<class>.h excludes ux_<class>.c and ux_<class>_*.c.
    file(GLOB part_headers "${part_dir}/inc/*.h")
    foreach(header IN LISTS part_headers)
      foreach(dependency NETX FILEX)
        if(arg_${dependency})
          continue()
        endif()
        if(dependency STREQUAL "NETX")
          set(api_header "nx_api\\.h")
        else()
          set(api_header "fx_api\\.h")
        endif()
        file(STRINGS "${header}" api_include REGEX "#include[ \t]+\"${api_header}\"")
        if(api_include)
          get_filename_component(class "${header}" NAME_WE)
          if(parts_explicit AND part_dir MATCHES "/usbx_network$")
            message(FATAL_ERROR "${context}: PARTS network needs NETX <netxduo target>")
          endif()
          list(FILTER part_sources EXCLUDE REGEX "/${class}(_[^/]*)?\\.c$")
        endif()
      endforeach()
    endforeach()
    list(APPEND sources ${part_sources})
    list(APPEND includes "${part_dir}/inc")
  endforeach()

  set(optional_args "")
  if(arg_CONFIG)
    list(APPEND optional_args CONFIG ${arg_CONFIG})
  endif()
  _threadx_add_component(${name} target
    CONTEXT "${context}"
    KERNEL ${arg_KERNEL}
    ${optional_args}
    USER_HEADER ux_user.h
    USER_DEFINE UX_INCLUDE_USER_DEFINE_FILE
    SOURCES ${sources}
    INCLUDES ${includes}
  )
  foreach(dependency NETX FILEX)
    if(arg_${dependency})
      target_link_libraries(${target} PUBLIC ${arg_${dependency}})
    endif()
  endforeach()
endfunction()
