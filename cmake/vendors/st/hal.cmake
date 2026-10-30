# ST HAL / LL drivers.
#
#   include(vendors/st/hal)         # also includes vendors/st/cmsis_device
#
#   st_fetch_hal(
#     FAMILY <family>               # e.g. H7, F4, G4
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. v1.11.6
#     [GIT_REPOSITORY <url>])       # default: STMicroelectronics/stm32<family>xx-hal-driver
#
#   st_add_hal(<name>               # may be namespaced, e.g. board::hal_cm7
#     CHIP <chip target>            # chip with FAMILY set
#     CONFIG <target>               # provides stm32<family>xx_hal_conf.h
#     [MODULES <module>...]         # HAL modules, e.g. GPIO UART; CORTEX and
#                                   # RCC are always included, *_ex.c added
#     [LL_MODULES <module>...])     # LL modules, e.g. GPIO USART
#
# st_add_hal() creates the STATIC library <name>, built once with the chip's
# flags. Link the firmware (and any library that uses the HAL) to it; no HAL
# object is compiled twice. Needs st_fetch_cmsis_device() for the same family.

include_guard(GLOBAL)

include("${CMAKE_CURRENT_LIST_DIR}/cmsis_device.cmake")

function(st_fetch_hal)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "FAMILY;GIT_REPOSITORY;GIT_TAG" "")
  set(context "st_fetch_hal(${arg_FAMILY})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_FAMILY MATCHES "^[A-Z][A-Z0-9]+$")
    message(FATAL_ERROR "${context}: FAMILY is required, upper case (e.g. H7)")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. v1.11.6)")
  endif()

  string(TOLOWER ${arg_FAMILY} family_l)
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/STMicroelectronics/stm32${family_l}xx-hal-driver.git)
  endif()

  mcu_fetch_package(st_hal_${family_l}
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    SPARSE_PATHS Inc Src
    OUT_SOURCE_DIR source_dir
  )
  if(NOT EXISTS "${source_dir}/Src/stm32${family_l}xx_hal.c")
    message(FATAL_ERROR "${context}: ${source_dir} is not an ST HAL driver package "
      "(Src/stm32${family_l}xx_hal.c missing)")
  endif()
endfunction()

function(st_add_hal name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CHIP;CONFIG" "MODULES;LL_MODULES")
  set(context "st_add_hal(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_CHIP OR NOT arg_CONFIG)
    message(FATAL_ERROR "${context}: CHIP and CONFIG are required")
  endif()
  if(NOT TARGET ${arg_CONFIG})
    message(FATAL_ERROR "${context}: CONFIG '${arg_CONFIG}' is not a target")
  endif()

  _st_chip_family("${context}" ${arg_CHIP} family)
  string(TOLOWER ${family} family_l)
  set(prefix "stm32${family_l}xx")
  mcu_get_package_dir(st_hal_${family_l} hal_dir
    "Call st_fetch_hal(FAMILY ${family} GIT_TAG <tag>) first.")
  if(NOT TARGET st::cmsis_device::${family})
    message(FATAL_ERROR "${context}: call st_fetch_cmsis_device(FAMILY ${family} GIT_TAG <tag>) first")
  endif()

  # The config target must expose the HAL configuration header. Skipped when
  # its include directories use generator expressions.
  get_target_property(config_dirs ${arg_CONFIG} INTERFACE_INCLUDE_DIRECTORIES)
  if(config_dirs AND NOT config_dirs MATCHES "\\$<")
    set(found_config FALSE)
    foreach(dir IN LISTS config_dirs)
      if(EXISTS "${dir}/${prefix}_hal_conf.h")
        set(found_config TRUE)
      endif()
    endforeach()
    if(NOT found_config)
      message(FATAL_ERROR
        "${context}: ${prefix}_hal_conf.h not found in the include directories of "
        "${arg_CONFIG} (${config_dirs}). Start from ${hal_dir}/Inc/${prefix}_hal_conf_template.h")
    endif()
  endif()

  set(sources "${hal_dir}/Src/${prefix}_hal.c")
  set(modules CORTEX RCC ${arg_MODULES})
  list(REMOVE_DUPLICATES modules)
  foreach(module IN LISTS modules)
    string(TOLOWER ${module} module_l)
    set(source "${hal_dir}/Src/${prefix}_hal_${module_l}.c")
    if(NOT EXISTS "${source}")
      file(GLOB available RELATIVE "${hal_dir}/Src" "${hal_dir}/Src/${prefix}_hal_*.c")
      list(FILTER available EXCLUDE REGEX "(_ex|_template)\\.c$")
      list(TRANSFORM available REPLACE "^${prefix}_hal_(.*)\\.c$" "\\1")
      list(TRANSFORM available TOUPPER)
      message(FATAL_ERROR "${context}: unknown HAL module ${module}. Available: ${available}")
    endif()
    list(APPEND sources "${source}")
    if(EXISTS "${hal_dir}/Src/${prefix}_hal_${module_l}_ex.c")
      list(APPEND sources "${hal_dir}/Src/${prefix}_hal_${module_l}_ex.c")
    endif()
  endforeach()

  set(ll_modules ${arg_LL_MODULES})
  list(REMOVE_DUPLICATES ll_modules)
  foreach(module IN LISTS ll_modules)
    string(TOLOWER ${module} module_l)
    set(source "${hal_dir}/Src/${prefix}_ll_${module_l}.c")
    if(NOT EXISTS "${source}")
      file(GLOB available RELATIVE "${hal_dir}/Src" "${hal_dir}/Src/${prefix}_ll_*.c")
      list(TRANSFORM available REPLACE "^${prefix}_ll_(.*)\\.c$" "\\1")
      list(TRANSFORM available TOUPPER)
      message(FATAL_ERROR "${context}: unknown LL module ${module}. Available: ${available}")
    endif()
    list(APPEND sources "${source}")
  endforeach()

  mcu_add_named_library(${name} STATIC target ${sources})
  target_include_directories(${target} SYSTEM PUBLIC "${hal_dir}/Inc")
  target_compile_definitions(${target} PUBLIC USE_HAL_DRIVER)
  if(ll_modules)
    target_compile_definitions(${target} PUBLIC USE_FULL_LL_DRIVER)
  endif()
  target_link_libraries(${target} PUBLIC
    ${arg_CHIP}
    st::cmsis_device::${family}
    ${arg_CONFIG}
  )
endfunction()
