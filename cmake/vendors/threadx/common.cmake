# Shared helpers for the Eclipse ThreadX modules (kernel, FileX, NetX Duo,
# USBX, LevelX, GUIX). Not meant to be included directly.

include_guard(GLOBAL)

if(NOT COMMAND mcu_fetch_package)
  message(FATAL_ERROR "vendors/threadx: include(mcu) first")
endif()

# _threadx_fetch(<package> <context> <repo name> <check file> <sparse paths>
#                [GIT_TAG ...] [GIT_REPOSITORY ...])
#
# Fetches eclipse-threadx/<repo name> (or GIT_REPOSITORY), only the
# directories in <sparse paths> (a ;-list), and checks that <check file>
# exists in it.
function(_threadx_fetch package context repo_name check_file sparse_paths)
  cmake_parse_arguments(PARSE_ARGV 5 arg "" "GIT_REPOSITORY;GIT_TAG" "")
  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. v6.5.2.202603_rel)")
  endif()
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/eclipse-threadx/${repo_name}.git)
  endif()

  mcu_fetch_package(${package}
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    SPARSE_PATHS ${sparse_paths}
    OUT_SOURCE_DIR source_dir
  )
  if(NOT EXISTS "${source_dir}/${check_file}")
    message(FATAL_ERROR "${context}: ${source_dir} is not ${repo_name} (${check_file} missing)")
  endif()
endfunction()

# _threadx_require_header(<context> <target> <header> <hint>)
#
# Fails unless the include directories of <target> contain <header>.
# Skipped when they use generator expressions.
function(_threadx_require_header context target header hint)
  if(NOT TARGET ${target})
    message(FATAL_ERROR "${context}: CONFIG '${target}' is not a target")
  endif()
  get_target_property(dirs ${target} INTERFACE_INCLUDE_DIRECTORIES)
  if(NOT dirs OR dirs MATCHES "\\$<")
    return()
  endif()
  foreach(dir IN LISTS dirs)
    if(EXISTS "${dir}/${header}")
      return()
    endif()
  endforeach()
  message(FATAL_ERROR "${context}: ${header} not found in the include directories of ${target} (${dirs}). ${hint}")
endfunction()

# _threadx_kernel_port(<context> <kernel target> <out_var>)
#
# Returns the port of a kernel created by threadx_add_kernel().
function(_threadx_kernel_port context kernel out_var)
  if(NOT TARGET ${kernel})
    message(FATAL_ERROR "${context}: KERNEL '${kernel}' is not a target")
  endif()
  get_target_property(port ${kernel} THREADX_PORT)
  if(NOT port)
    message(FATAL_ERROR "${context}: ${kernel} was not created by threadx_add_kernel()")
  endif()
  set(${out_var} ${port} PARENT_SCOPE)
endfunction()

# _threadx_port_include(<context> <package dir> <port> <port header> <out_var>)
#
# Returns <package dir>/ports/<port>/gnu/inc, or fails listing the ports
# that provide <port header>.
function(_threadx_port_include context package_dir port port_header out_var)
  set(include_dir "${package_dir}/ports/${port}/gnu/inc")
  if(NOT EXISTS "${include_dir}/${port_header}")
    file(GLOB candidates RELATIVE "${package_dir}/ports" "${package_dir}/ports/*/gnu/inc/${port_header}")
    list(TRANSFORM candidates REPLACE "/gnu/inc/${port_header}$" "")
    message(FATAL_ERROR
      "${context}: no GNU port '${port}' (${include_dir}/${port_header} missing). "
      "Available: ${candidates}")
  endif()
  set(${out_var} "${include_dir}" PARENT_SCOPE)
endfunction()

# _threadx_add_component(<name> <out_var>
#   CONTEXT <text>
#   KERNEL <kernel target>
#   [CONFIG <target>] USER_HEADER <file> USER_DEFINE <macro>
#   SOURCES <file>... INCLUDES <dir>...
#   [LINK <target>...])
#
# Creates the STATIC library <name> (namespaced names allowed), linked to the
# kernel (which carries the CPU flags and ThreadX headers).
function(_threadx_add_component name out_var)
  cmake_parse_arguments(PARSE_ARGV 2 arg ""
    "CONTEXT;KERNEL;CONFIG;USER_HEADER;USER_DEFINE" "SOURCES;INCLUDES;LINK")
  if(NOT arg_SOURCES)
    message(FATAL_ERROR "${arg_CONTEXT}: no sources")
  endif()

  if(arg_CONFIG)
    _threadx_require_header("${arg_CONTEXT}" ${arg_CONFIG} ${arg_USER_HEADER}
      "Start from the package's ${arg_USER_HEADER} sample.")
  endif()

  mcu_add_named_library(${name} STATIC target ${arg_SOURCES})
  # SYSTEM: vendor headers do not trigger the project's warning set.
  target_include_directories(${target} SYSTEM PUBLIC ${arg_INCLUDES})
  target_link_libraries(${target} PUBLIC ${arg_KERNEL} ${arg_LINK})
  if(arg_CONFIG)
    target_compile_definitions(${target} PUBLIC ${arg_USER_DEFINE})
    target_link_libraries(${target} PUBLIC ${arg_CONFIG})
  endif()
  set(${out_var} ${target} PARENT_SCOPE)
endfunction()
