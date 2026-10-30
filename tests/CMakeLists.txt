# mcu-cmake test suite (host project, no cross toolchain of its own).
#
#   cmake -S tests -B build/tests -G Ninja
#   ctest --test-dir build/tests -j2 --output-on-failure
#
# Test groups (ctest -L <label>):
#   errors    configure-only checks of the FATAL_ERROR paths, offline
#   build     every example in Debug and MinSizeRel, warnings are errors
#             (compiler and linker); fetches the vendor packages
#   hardware  flash and check the examples on a board (MCU_HARDWARE_TESTS=ON,
#             needs probe-rs, a NUCLEO-H755ZI-Q and the build tests' trees)
#
# MCU_TEST_DEPS_FROM=<dir with *-src package trees> lets the Debug builds use
# already fetched packages instead of cloning, e.g.
# examples/h755zi-threadx/build/debug/_deps. Release builds always reuse the
# packages of their Debug build.

cmake_minimum_required(VERSION 3.25)
project(mcu_cmake_tests NONE)
enable_testing()

get_filename_component(MCU_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(MCU_TEST_TOOLCHAIN "${MCU_ROOT}/cmake/toolchain/arm-none-eabi-gcc.cmake")

set(MCU_TEST_EXAMPLES h755zi-freertos h755zi-threadx h755zi-systemview
  CACHE STRING "Examples built by the build tests")
set(MCU_TEST_DEPS_FROM "" CACHE PATH
  "Directory with fetched *-src package trees to reuse in the Debug builds")
option(MCU_HARDWARE_TESTS "Register the on-board tests (needs probe-rs and the board)" OFF)

find_program(MCU_TEST_NINJA ninja)
if(MCU_TEST_NINJA)
  set(generator Ninja)
else()
  set(generator "${CMAKE_GENERATOR}")
endif()

# --- errors -------------------------------------------------------------------

# <case> <regular expression the FATAL_ERROR output must match>. CMake wraps
# long messages, so each pattern is a short piece that stays on one line.
set(error_cases
  chip_no_memory               "MEMORY is required"
  chip_memory_groups           "MEMORY needs groups of 4 values"
  chip_overlap                 "memory regions RAM and RAM2 overlap|memory regions RAM2 and RAM overlap"
  chip_decimal_origin          "origin of FLASH must be hex"
  chip_duplicate_region        "duplicate memory region 'RAM'"
  chip_not_cortex_m            "'cortex-a7' is not a Cortex-M core"
  chip_hard_float_without_fpu  "FLOAT_ABI hard needs an FPU"
  name_invalid                 "invalid target name"
  name_collision               "already exists"
  linker_unknown_region        "RAM_REGION 'DTCM' is not in the memory map"
  linker_unknown_chip          "unknown chip 'test::missing'"
  package_version_conflict     "now requested as"
  package_not_fetched          "package demo has not been fetched"
  flash_no_chip                "PROBE_RS_CHIP is required"
  flash_not_executable         "interface_lib is not an executable"
  rtt_no_tag                   "GIT_TAG is required"
  rtt_before_fetch             "package segger_rtt has not been fetched"
  rtt_config_without_header    "SEGGER_RTT_Conf.h not found"
  sysview_before_fetch         "package segger_systemview has not been fetched"
  sysview_no_rtt               "RTT is required"
  sysview_os_without_target    "OS ThreadX needs OS_TARGET"
  sysview_target_without_os    "OS_TARGET needs OS"
  sysview_unknown_os           "Sample/Zephyr"
  sysview_os_target_not_static "STATIC library \\(is INTERFACE_LIBRARY\\)"
  sysview_config_without_header "SEGGER_SYSVIEW_Conf.h not found"
)

function(add_configure_test name case)
  add_test(NAME ${name}
    COMMAND ${CMAKE_COMMAND}
      -S "${CMAKE_CURRENT_SOURCE_DIR}/errors"
      -B "${CMAKE_CURRENT_BINARY_DIR}/errors/${case}"
      -G "${generator}"
      --toolchain "${MCU_TEST_TOOLCHAIN}"
      -DCASE=${case}
  )
  set_tests_properties(${name} PROPERTIES LABELS errors ${ARGN})
endfunction()

add_configure_test(errors.ok ok)
while(error_cases)
  list(POP_FRONT error_cases case regex)
  add_configure_test(errors.${case} ${case})
  # FATAL_ERROR makes cmake exit non-zero; WILL_FAIL alone would also accept
  # an unrelated failure, so the message is matched instead.
  set_tests_properties(errors.${case} PROPERTIES PASS_REGULAR_EXPRESSION "${regex}")
endwhile()

# --- build --------------------------------------------------------------------

foreach(example IN LISTS MCU_TEST_EXAMPLES)
  foreach(config Debug MinSizeRel)
    string(TOLOWER ${config} preset)
    set(tree "${CMAKE_CURRENT_BINARY_DIR}/build/${example}-${preset}")
    set(deps_from "")
    set(deps_from_tree "")
    if(config STREQUAL "Debug")
      set(deps_from "${MCU_TEST_DEPS_FROM}")
    else()
      set(deps_from_tree "${CMAKE_CURRENT_BINARY_DIR}/build/${example}-debug")
    endif()
    add_test(NAME build.${example}.${preset}
      COMMAND ${CMAKE_COMMAND}
        -DSOURCE_DIR=${MCU_ROOT}/examples/${example}
        -DBINARY_DIR=${tree}
        -DBUILD_TYPE=${config}
        -DTOOLCHAIN=${MCU_TEST_TOOLCHAIN}
        -DGENERATOR=${generator}
        -DDEPS_FROM=${deps_from}
        -DDEPS_FROM_TREE=${deps_from_tree}
        -P "${CMAKE_CURRENT_SOURCE_DIR}/cmake/build_example.cmake"
    )
    set_tests_properties(build.${example}.${preset} PROPERTIES
      LABELS build
      FIXTURES_SETUP build.${example}.${preset}
      # Large builds (ThreadX middleware) and package clones.
      TIMEOUT 3600
    )
    if(config STREQUAL "MinSizeRel")
      set_tests_properties(build.${example}.${preset} PROPERTIES
        FIXTURES_REQUIRED build.${example}.debug)
    endif()
  endforeach()
endforeach()

# --- hardware -----------------------------------------------------------------

if(MCU_HARDWARE_TESTS)
  find_package(Python3 3.9 REQUIRED COMPONENTS Interpreter)
  # The examples' flash targets need it at their configure time; fail early.
  find_program(MCU_TEST_PROBE_RS probe-rs REQUIRED)
  set(bridge "${MCU_ROOT}/tools/sysview-bridge/target/release/sysview-bridge")
  add_test(NAME hardware.bridge
    COMMAND cargo build --release --manifest-path "${MCU_ROOT}/tools/sysview-bridge/Cargo.toml")
  set_tests_properties(hardware.bridge PROPERTIES
    LABELS hardware FIXTURES_SETUP hardware.bridge)
  set(previous "")
  foreach(example IN LISTS MCU_TEST_EXAMPLES)
    add_test(NAME hardware.${example}
      COMMAND Python3::Interpreter -I "${CMAKE_CURRENT_SOURCE_DIR}/hardware/smoke.py"
        --example ${example}
        --build-dir "${CMAKE_CURRENT_BINARY_DIR}/build/${example}-debug"
        --cmake "${CMAKE_COMMAND}"
        --bridge "${bridge}"
        --work-dir "${CMAKE_CURRENT_BINARY_DIR}/hardware/${example}"
    )
    # One board: the hardware tests must not run in parallel.
    set_tests_properties(hardware.${example} PROPERTIES
      LABELS hardware
      RESOURCE_LOCK board
      FIXTURES_REQUIRED "hardware.bridge;build.${example}.debug"
      TIMEOUT 300
    )
  endforeach()
endif()
