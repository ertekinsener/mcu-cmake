# mcu_add_chip(): describe one chip (or one core of a multi-core chip).
#
# There is no built-in device database. The caller passes the values from the
# datasheet / reference manual, and every value is validated.
#
#   mcu_add_chip(<name>                  # chosen by the project, may be
#                                        # namespaced, e.g. stm32::H755ZI::CM7
#     [ARCH <arch>]                      # CPU architecture, default: arm
#     [FAMILY <family>]                  # vendor family, e.g. H7; used by
#                                        # vendor modules (st_add_hal(), ...)
#     [CORE <core>]                      # informational, e.g. CM7 (shown in
#                                        # the generated linker script)
#     CPU <cpu>                          # arm: -mcpu value, e.g. cortex-m7
#     [FPU <fpu>]                        # arm: -mfpu value, e.g. fpv5-d16
#     [FLOAT_ABI <soft|softfp|hard>]     # arm: default hard with FPU
#     [DEFINITIONS <define>...]          # e.g. STM32H755xx CORE_CM7
#     MEMORY <name> <attributes> <origin> <length>
#            [<name> <attributes> <origin> <length>...])
#
# Creates the INTERFACE target <name> (an ALIAS of a real target when
# namespaced, see naming.cmake) that carries the CPU flags, definitions and
# memory map. Link firmware to it and call mcu_add_linker_script() with the
# same target. A dual-core part gets one chip target per core. Functions that
# take a CHIP check its properties, not its name.
#
# CPU, FPU and FLOAT_ABI are interpreted by the architecture handler
# _mcu_arch_<arch>_flags() (see arch/). Supporting another architecture
# means adding a handler and a matching toolchain file.
#
# Memory entries: <attributes> as in a GNU ld MEMORY block (rx, xrw, ...),
# <origin> in hex (0x08000000), <length> as 64K / 1M / hex / decimal bytes.

include_guard(GLOBAL)

# Converts a length (64K, 1M, 0x10000, 65536) to bytes.
function(_mcu_length_to_bytes length out_var)
  if(length MATCHES "^([0-9]+)K$")
    math(EXPR bytes "${CMAKE_MATCH_1} * 1024")
  elseif(length MATCHES "^([0-9]+)M$")
    math(EXPR bytes "${CMAKE_MATCH_1} * 1024 * 1024")
  elseif(length MATCHES "^(0x[0-9A-Fa-f]+|[0-9]+)$")
    math(EXPR bytes "${length}")
  else()
    message(FATAL_ERROR "mcu: invalid memory length '${length}'")
  endif()
  set(${out_var} ${bytes} PARENT_SCOPE)
endfunction()

# Validates a flat MEMORY list: names, attributes, origins, lengths,
# duplicates and overlapping regions.
function(_mcu_validate_memory context memory)
  list(LENGTH memory count)
  if(count EQUAL 0)
    message(FATAL_ERROR "${context}: MEMORY is required")
  endif()
  math(EXPR remainder "${count} % 4")
  if(NOT remainder EQUAL 0)
    message(FATAL_ERROR
      "${context}: MEMORY needs groups of 4 values "
      "(<name> <attributes> <origin> <length>), got ${count} values")
  endif()

  set(names "")
  set(starts "")
  set(ends "")
  math(EXPR last "${count} - 1")
  foreach(i RANGE 0 ${last} 4)
    math(EXPR i_attr "${i} + 1")
    math(EXPR i_origin "${i} + 2")
    math(EXPR i_length "${i} + 3")
    list(GET memory ${i} name)
    list(GET memory ${i_attr} attr)
    list(GET memory ${i_origin} origin)
    list(GET memory ${i_length} length)

    if(NOT name MATCHES "^[A-Za-z_][A-Za-z0-9_]*$")
      message(FATAL_ERROR "${context}: invalid memory region name '${name}'")
    endif()
    if(name IN_LIST names)
      message(FATAL_ERROR "${context}: duplicate memory region '${name}'")
    endif()
    if(NOT attr MATCHES "^!?[rwxailRWXAIL]+$")
      message(FATAL_ERROR "${context}: invalid attributes '${attr}' for region ${name}")
    endif()
    if(NOT origin MATCHES "^0x[0-9A-Fa-f]+$")
      message(FATAL_ERROR "${context}: origin of ${name} must be hex (0x...), got '${origin}'")
    endif()
    _mcu_length_to_bytes(${length} size)
    if(size EQUAL 0)
      message(FATAL_ERROR "${context}: region ${name} has zero length")
    endif()
    math(EXPR start "${origin}")
    math(EXPR end "${start} + ${size}")

    # Overlap check against the regions seen so far.
    set(j 0)
    foreach(other IN LISTS names)
      list(GET starts ${j} other_start)
      list(GET ends ${j} other_end)
      if(start LESS other_end AND other_start LESS end)
        message(FATAL_ERROR "${context}: memory regions ${name} and ${other} overlap")
      endif()
      math(EXPR j "${j} + 1")
    endforeach()

    list(APPEND names ${name})
    list(APPEND starts ${start})
    list(APPEND ends ${end})
  endforeach()
endfunction()

function(mcu_add_chip name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "ARCH;FAMILY;CORE;CPU;FPU;FLOAT_ABI" "DEFINITIONS;MEMORY")
  set(context "mcu_add_chip(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(arg_FAMILY AND NOT arg_FAMILY MATCHES "^[A-Z][A-Z0-9]+$")
    message(FATAL_ERROR "${context}: FAMILY must be upper case, e.g. H7")
  endif()
  if(arg_CORE AND NOT arg_CORE MATCHES "^[A-Za-z0-9]+$")
    message(FATAL_ERROR "${context}: core name must be alphanumeric, e.g. CM7")
  endif()
  if(NOT arg_ARCH)
    set(arg_ARCH arm)
  endif()
  if(NOT COMMAND _mcu_arch_${arg_ARCH}_flags)
    message(FATAL_ERROR "${context}: unsupported ARCH '${arg_ARCH}'")
  endif()
  cmake_language(CALL _mcu_arch_${arg_ARCH}_flags
    "${context}" "${arg_CPU}" "${arg_FPU}" "${arg_FLOAT_ABI}" cpu_flags)

  _mcu_validate_memory("${context}" "${arg_MEMORY}")

  mcu_add_named_library(${name} INTERFACE target_name)

  # CPU flags must reach the linker too, so it picks the matching multilib.
  target_compile_options(${target_name} INTERFACE
    ${cpu_flags}
    -ffunction-sections
    -fdata-sections
  )
  target_link_options(${target_name} INTERFACE
    ${cpu_flags}
    LINKER:--gc-sections
  )
  target_compile_definitions(${target_name} INTERFACE ${arg_DEFINITIONS})

  set_target_properties(${target_name} PROPERTIES
    MCU_CHIP "${name}"
    MCU_ARCH "${arg_ARCH}"
    MCU_FAMILY "${arg_FAMILY}"
    MCU_CORE "${arg_CORE}"
    MCU_MEMORY "${arg_MEMORY}"
  )
endfunction()
