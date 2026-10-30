# Configures and builds one example with warnings as errors (cmake -P).
#
#   -DSOURCE_DIR=<example> -DBINARY_DIR=<tree> -DBUILD_TYPE=<config>
#   -DTOOLCHAIN=<file> -DGENERATOR=<name>
#   [-DDEPS_FROM=<dir with *-src>] [-DDEPS_FROM_TREE=<configured build tree>]
#
# CMAKE_COMPILE_WARNING_AS_ERROR covers the compiler. CMake's
# CMAKE_LINK_WARNING_AS_ERROR has no effect here: the toolchain file detects
# the compiler without linking, so CMake does not know the linker. The test
# trees therefore link with -Wl,--fatal-warnings (test only; the examples
# themselves set no global flags), and the build output is scanned for
# "warning:" as well.
#
# DEPS_FROM_TREE reuses every package of another tree: its _deps/*-src and the
# FETCHCONTENT_SOURCE_DIR_* entries of its cache.

foreach(var SOURCE_DIR BINARY_DIR BUILD_TYPE TOOLCHAIN GENERATOR)
  if(NOT DEFINED ${var})
    message(FATAL_ERROR "build_example: ${var} is required")
  endif()
endforeach()

set(configure_args
  -S "${SOURCE_DIR}" -B "${BINARY_DIR}" -G "${GENERATOR}"
  --toolchain "${TOOLCHAIN}"
  -DCMAKE_BUILD_TYPE=${BUILD_TYPE}
  -DCMAKE_COMPILE_WARNING_AS_ERROR=ON
  "-DCMAKE_EXE_LINKER_FLAGS=-Wl,--fatal-warnings"
)

# Reuse fetched packages: FETCHCONTENT_SOURCE_DIR_<NAME> per *-src tree.
if(DEPS_FROM AND IS_DIRECTORY "${DEPS_FROM}")
  file(GLOB package_dirs LIST_DIRECTORIES true "${DEPS_FROM}/*-src")
  foreach(package_dir IN LISTS package_dirs)
    get_filename_component(package "${package_dir}" NAME)
    string(REGEX REPLACE "-src$" "" package "${package}")
    string(TOUPPER "${package}" package)
    list(APPEND configure_args "-DFETCHCONTENT_SOURCE_DIR_${package}=${package_dir}")
  endforeach()
endif()

if(DEPS_FROM_TREE AND EXISTS "${DEPS_FROM_TREE}/CMakeCache.txt")
  file(GLOB package_dirs LIST_DIRECTORIES true "${DEPS_FROM_TREE}/_deps/*-src")
  foreach(package_dir IN LISTS package_dirs)
    get_filename_component(package "${package_dir}" NAME)
    string(REGEX REPLACE "-src$" "" package "${package}")
    string(TOUPPER "${package}" package)
    list(APPEND configure_args "-DFETCHCONTENT_SOURCE_DIR_${package}=${package_dir}")
  endforeach()
  file(STRINGS "${DEPS_FROM_TREE}/CMakeCache.txt" overrides
    REGEX "^FETCHCONTENT_SOURCE_DIR_[A-Z0-9_]+:PATH=.+$")
  foreach(override IN LISTS overrides)
    string(REGEX REPLACE ":PATH=" "=" override "${override}")
    list(APPEND configure_args "-D${override}")
  endforeach()
endif()

execute_process(
  COMMAND ${CMAKE_COMMAND} ${configure_args}
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "configure failed:\n${output}")
endif()

execute_process(
  COMMAND ${CMAKE_COMMAND} --build "${BINARY_DIR}"
  RESULT_VARIABLE result
  OUTPUT_VARIABLE output
  ERROR_VARIABLE output
)
if(NOT result EQUAL 0)
  message(FATAL_ERROR "build failed:\n${output}")
endif()
string(REGEX MATCHALL "[^\n]*warning:[^\n]*" warnings "${output}")
if(warnings)
  list(JOIN warnings "\n" warnings)
  message(FATAL_ERROR "build produced warnings:\n${warnings}")
endif()
message(STATUS "${SOURCE_DIR} (${BUILD_TYPE}): built without warnings")
