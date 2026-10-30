# mcu_add_linker_script(): generate a linker script from a chip's memory map.
#
#   mcu_add_linker_script(<target>
#     CHIP <chip target>        # e.g. stm32::H755ZI::CM7
#     FLASH_REGION <region>     # code, read-only data, .data load image
#     RAM_REGION <region>       # .data, .bss, heap and stack
#     STACK_SIZE <bytes>        # minimum stack, e.g. 0x2000
#     HEAP_SIZE <bytes>         # minimum heap, 0 if malloc is not used
#     [TEMPLATE <file>])        # own template, same @VARIABLES@ as default.ld.in
#
# Every other writable region gets a NOLOAD output section named after it in
# lower case (RAM_D2 -> .ram_d2). Use it with [[gnu::section(".ram_d2")]].
# These sections are not initialized by the startup code.
#
# The script is generated at configure time into the target's binary dir.

include_guard(GLOBAL)

function(mcu_add_linker_script target)
  cmake_parse_arguments(PARSE_ARGV 1 arg ""
    "CHIP;FLASH_REGION;RAM_REGION;STACK_SIZE;HEAP_SIZE;TEMPLATE" "")
  set(context "mcu_add_linker_script(${target})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT TARGET ${target})
    message(FATAL_ERROR "${context}: ${target} is not a target")
  endif()
  mcu_resolve_target(${target} target)
  foreach(required CHIP FLASH_REGION RAM_REGION STACK_SIZE HEAP_SIZE)
    if(NOT DEFINED arg_${required} OR arg_${required} STREQUAL "")
      message(FATAL_ERROR "${context}: ${required} is required")
    endif()
  endforeach()
  foreach(size_arg STACK_SIZE HEAP_SIZE)
    if(NOT arg_${size_arg} MATCHES "^(0x[0-9A-Fa-f]+|[0-9]+)$")
      message(FATAL_ERROR "${context}: ${size_arg} must be a byte count, got '${arg_${size_arg}}'")
    endif()
  endforeach()

  if(NOT TARGET ${arg_CHIP})
    message(FATAL_ERROR
      "${context}: unknown chip '${arg_CHIP}'. Call mcu_add_chip() first.")
  endif()
  get_target_property(memory ${arg_CHIP} MCU_MEMORY)
  if(NOT memory)
    message(FATAL_ERROR "${context}: ${arg_CHIP} was not created by mcu_add_chip()")
  endif()
  get_target_property(chip ${arg_CHIP} MCU_CHIP)
  get_target_property(core ${arg_CHIP} MCU_CORE)

  # Build the MEMORY block and the NOLOAD sections for the extra regions.
  set(memory_block "")
  set(extra_sections "")
  set(names "")
  list(LENGTH memory count)
  math(EXPR last "${count} - 1")
  foreach(i RANGE 0 ${last} 4)
    math(EXPR i_attr "${i} + 1")
    math(EXPR i_origin "${i} + 2")
    math(EXPR i_length "${i} + 3")
    list(GET memory ${i} name)
    list(GET memory ${i_attr} attr)
    list(GET memory ${i_origin} origin)
    list(GET memory ${i_length} length)
    list(APPEND names ${name})

    string(APPEND memory_block
      "  ${name} (${attr}) : ORIGIN = ${origin}, LENGTH = ${length}\n")

    if(name STREQUAL arg_FLASH_REGION OR name STREQUAL arg_RAM_REGION)
      continue()
    endif()
    if(attr MATCHES "^!" OR NOT attr MATCHES "[wW]")
      continue()
    endif()
    string(TOLOWER ${name} section)
    string(APPEND extra_sections
      "  .${section} (NOLOAD) :\n"
      "  {\n"
      "    . = ALIGN(4);\n"
      "    *(.${section})\n"
      "    *(.${section}.*)\n"
      "    . = ALIGN(4);\n"
      "  } >${name}\n\n")
  endforeach()

  foreach(region_arg FLASH_REGION RAM_REGION)
    if(NOT arg_${region_arg} IN_LIST names)
      message(FATAL_ERROR
        "${context}: ${region_arg} '${arg_${region_arg}}' is not in the memory map "
        "of ${arg_CHIP} (${names})")
    endif()
  endforeach()

  if(arg_TEMPLATE)
    get_filename_component(template "${arg_TEMPLATE}" ABSOLUTE)
  else()
    get_property(module_dir GLOBAL PROPERTY MCU_MODULE_DIR)
    set(template "${module_dir}/linker/default.ld.in")
  endif()
  if(NOT EXISTS "${template}")
    message(FATAL_ERROR "${context}: template not found: ${template}")
  endif()

  # Variables consumed by the template.
  set(MCU_LD_TARGET "${target}")
  if(core)
    set(MCU_LD_CHIP "${chip}, core ${core}")
  else()
    set(MCU_LD_CHIP "${chip}")
  endif()
  set(MCU_LD_MEMORY "${memory_block}")
  set(MCU_LD_EXTRA_SECTIONS "${extra_sections}")
  set(MCU_LD_FLASH "${arg_FLASH_REGION}")
  set(MCU_LD_RAM "${arg_RAM_REGION}")
  set(MCU_LD_STACK_SIZE "${arg_STACK_SIZE}")
  set(MCU_LD_HEAP_SIZE "${arg_HEAP_SIZE}")

  get_target_property(binary_dir ${target} BINARY_DIR)
  set(script "${binary_dir}/${target}.ld")
  configure_file("${template}" "${script}" @ONLY)

  target_link_options(${target} PRIVATE "-T${script}")
  set_property(TARGET ${target} APPEND PROPERTY LINK_DEPENDS "${script}")
endfunction()
