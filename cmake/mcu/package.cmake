# mcu_fetch_package(): fetch a vendor package from git at a version chosen
# by the project. Nothing is pinned in this module.
#
#   mcu_fetch_package(<name>
#     GIT_REPOSITORY <url>
#     GIT_TAG <tag|commit>
#     [OUT_SOURCE_DIR <var>])
#
# - Tags and branches are cloned shallow; a full 40-character commit hash
#   needs a full clone (git cannot shallow-fetch an arbitrary commit).
# - The package is only downloaded, never added with add_subdirectory(), so
#   repositories with their own CMakeLists.txt do not inject targets.
# - Fetching the same <name> again with the same repository and tag is a
#   no-op; a different repository or tag is a FATAL_ERROR, so two parts of a
#   project cannot silently use different versions.
# - Local checkout instead of a download (offline work, patched drivers):
#     -DFETCHCONTENT_SOURCE_DIR_<NAME>=/path   (<NAME> in upper case)
#
# The source directory is also stored in the global property
# MCU_PACKAGE_<name>_DIR.

include_guard(GLOBAL)
include(FetchContent)

function(mcu_fetch_package name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "GIT_REPOSITORY;GIT_TAG;OUT_SOURCE_DIR" "")
  set(context "mcu_fetch_package(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT name MATCHES "^[a-z0-9_]+$")
    message(FATAL_ERROR "${context}: name must be lower case [a-z0-9_]")
  endif()
  foreach(required GIT_REPOSITORY GIT_TAG)
    if(NOT arg_${required})
      message(FATAL_ERROR "${context}: ${required} is required")
    endif()
  endforeach()

  get_property(fetched GLOBAL PROPERTY MCU_PACKAGE_${name}_DIR SET)
  if(fetched)
    get_property(prev_repo GLOBAL PROPERTY MCU_PACKAGE_${name}_REPOSITORY)
    get_property(prev_tag GLOBAL PROPERTY MCU_PACKAGE_${name}_TAG)
    if(NOT prev_repo STREQUAL arg_GIT_REPOSITORY OR NOT prev_tag STREQUAL arg_GIT_TAG)
      message(FATAL_ERROR
        "${context}: already fetched as ${prev_repo} @ ${prev_tag}, "
        "now requested as ${arg_GIT_REPOSITORY} @ ${arg_GIT_TAG}")
    endif()
  else()
    if(arg_GIT_TAG MATCHES "^[0-9a-f]{40}$")
      set(shallow FALSE)
    else()
      set(shallow TRUE)
    endif()

    FetchContent_Declare(${name}
      GIT_REPOSITORY "${arg_GIT_REPOSITORY}"
      GIT_TAG "${arg_GIT_TAG}"
      GIT_SHALLOW ${shallow}
      GIT_SUBMODULES ""
      GIT_PROGRESS TRUE
      # Points at a directory without CMakeLists.txt, so MakeAvailable only
      # populates the sources.
      SOURCE_SUBDIR mcu-cmake-populate-only
    )
    message(STATUS "mcu: fetching ${name} (${arg_GIT_TAG})")
    FetchContent_MakeAvailable(${name})
    FetchContent_GetProperties(${name} SOURCE_DIR source_dir)

    set_property(GLOBAL PROPERTY MCU_PACKAGE_${name}_DIR "${source_dir}")
    set_property(GLOBAL PROPERTY MCU_PACKAGE_${name}_REPOSITORY "${arg_GIT_REPOSITORY}")
    set_property(GLOBAL PROPERTY MCU_PACKAGE_${name}_TAG "${arg_GIT_TAG}")
  endif()

  if(arg_OUT_SOURCE_DIR)
    get_property(source_dir GLOBAL PROPERTY MCU_PACKAGE_${name}_DIR)
    set(${arg_OUT_SOURCE_DIR} "${source_dir}" PARENT_SCOPE)
  endif()
endfunction()

# Returns the source directory of a fetched package, or fails with <hint>.
function(mcu_get_package_dir name out_var hint)
  get_property(fetched GLOBAL PROPERTY MCU_PACKAGE_${name}_DIR SET)
  if(NOT fetched)
    message(FATAL_ERROR "mcu: package ${name} has not been fetched. ${hint}")
  endif()
  get_property(source_dir GLOBAL PROPERTY MCU_PACKAGE_${name}_DIR)
  set(${out_var} "${source_dir}" PARENT_SCOPE)
endfunction()
