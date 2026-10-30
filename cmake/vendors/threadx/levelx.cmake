# Eclipse ThreadX LevelX (NOR / NAND flash wear leveling).
#
#   include(vendors/threadx/levelx)
#
#   threadx_fetch_levelx(
#     GIT_TAG <tag|commit>          # chosen by the project
#     [GIT_REPOSITORY <url>])       # default: eclipse-threadx/levelx
#
#   threadx_add_levelx(<name>       # may be namespaced, e.g. board::levelx_cm7
#     KERNEL <threadx kernel target>
#     [FILEX <filex target>]        # also build the FileX media drivers
#                                   # (fx_*_flash_simulat*_driver.c)
#     [CONFIG <target>])            # provides lx_user.h
#
# Creates a STATIC library built with the kernel's chip flags. LevelX has no
# port layer. The NOR / NAND simulators (RAM-backed) are part of the library;
# real flash drivers are the application's.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/kernel.cmake")

function(threadx_fetch_levelx)
  _threadx_fetch(threadx_levelx "threadx_fetch_levelx()" levelx common/inc/lx_api.h "common" ${ARGN})
endfunction()

function(threadx_add_levelx name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "KERNEL;FILEX;CONFIG" "")
  set(context "threadx_add_levelx(${name})")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()

  _threadx_kernel_port("${context}" "${arg_KERNEL}" kernel_port)
  if(arg_FILEX AND NOT TARGET ${arg_FILEX})
    message(FATAL_ERROR "${context}: FILEX '${arg_FILEX}' is not a target")
  endif()
  mcu_get_package_dir(threadx_levelx dir "Call threadx_fetch_levelx(GIT_TAG <tag>) first.")

  file(GLOB sources "${dir}/common/src/lx_*.c")
  if(arg_FILEX)
    # FileX media drivers on top of the LevelX simulators.
    file(GLOB fx_drivers "${dir}/common/src/fx_*.c")
    list(APPEND sources ${fx_drivers})
  endif()

  set(optional_args "")
  if(arg_CONFIG)
    list(APPEND optional_args CONFIG ${arg_CONFIG})
  endif()
  _threadx_add_component(${name} target
    CONTEXT "${context}"
    KERNEL ${arg_KERNEL}
    ${optional_args}
    USER_HEADER lx_user.h
    USER_DEFINE LX_INCLUDE_USER_DEFINE_FILE
    SOURCES ${sources}
    INCLUDES "${dir}/common/inc"
  )
  if(arg_FILEX)
    target_link_libraries(${target} PUBLIC ${arg_FILEX})
  endif()
endfunction()
