# stm32_add_chip(): describe one chip (or one core of a multi-core chip).
#
# There is no built-in device database. The caller passes the values from the
# datasheet / reference manual, and every value is validated.
#
#   stm32_add_chip(<chip>
#     [CORE <core>]                      # e.g. CM7, CM4 for dual-core parts
#     CPU <cpu>                          # -mcpu value, e.g. cortex-m7
#     [FPU <fpu>]                        # -mfpu value, e.g. fpv5-d16
#     [FLOAT_ABI <soft|softfp|hard>]     # default: hard with FPU, soft without
#     [DEFINITIONS <define>...]          # e.g. STM32H755xx CORE_CM7
#     MEMORY <name> <attributes> <origin> <length>
#            [<name> <attributes> <origin> <length>...])
#
# Creates the INTERFACE target stm32::<chip> or stm32::<chip>::<core> that
# carries the CPU flags, definitions and memory map. Link firmware to it and
# call stm32_add_linker_script() with the same target.
#
# Memory entries: <attributes> as in a GNU ld MEMORY block (rx, xrw, ...),
# <origin> in hex (0x08000000), <length> as 64K / 1M / hex / decimal bytes.

include_guard(GLOBAL)

# Converts a length (64K, 1M, 0x10000, 65536) to bytes.
function(_stm32_length_to_bytes length out_var)
  if(length MATCHES "^([0-9]+)K$")
    math(EXPR bytes "${CMAKE_MATCH_1} * 1024")
  elseif(length MATCHES "^([0-9]+)M$")
    math(EXPR bytes "${CMAKE_MATCH_1} * 1024 * 1024")
  elseif(length MATCHES "^(0x[0-9A-Fa-f]+|[0-9]+)$")
    math(EXPR bytes "${length}")
  else()
    message(FATAL_ERROR "stm32: invalid memory length '${length}'")
  endif()
  set(${out_var} ${bytes} PARENT_SCOPE)
endfunction()

# Validates a flat MEMORY list: names, attributes, origins, lengths,
# duplicates and overlapping regions.
function(_stm32_validate_memory context memory)
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
    _stm32_length_to_bytes(${length} size)
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

function(stm32_add_chip chip)
  cmake_parse_arguments(PARSE_ARGV 1 arg "" "CORE;CPU;FPU;FLOAT_ABI" "DEFINITIONS;MEMORY")

  if(arg_CORE)
    set(alias_name "stm32::${chip}::${arg_CORE}")
    set(target_name "stm32_${chip}_${arg_CORE}")
  else()
    set(alias_name "stm32::${chip}")
    set(target_name "stm32_${chip}")
  endif()
  set(context "stm32_add_chip(${alias_name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT chip MATCHES "^[A-Za-z0-9]+$")
    message(FATAL_ERROR "${context}: chip name must be alphanumeric, e.g. H755ZI")
  endif()
  if(arg_CORE AND NOT arg_CORE MATCHES "^[A-Za-z0-9]+$")
    message(FATAL_ERROR "${context}: core name must be alphanumeric, e.g. CM7")
  endif()
  if(TARGET ${target_name})
    message(FATAL_ERROR "${context}: already defined")
  endif()
  if(NOT arg_CPU)
    message(FATAL_ERROR "${context}: CPU is required (e.g. cortex-m7)")
  endif()

  if(NOT arg_FLOAT_ABI)
    if(arg_FPU)
      set(arg_FLOAT_ABI hard)
    else()
      set(arg_FLOAT_ABI soft)
    endif()
  endif()
  if(NOT arg_FLOAT_ABI MATCHES "^(soft|softfp|hard)$")
    message(FATAL_ERROR "${context}: FLOAT_ABI must be soft, softfp or hard")
  endif()
  if(NOT arg_FPU AND NOT arg_FLOAT_ABI STREQUAL "soft")
    message(FATAL_ERROR "${context}: FLOAT_ABI ${arg_FLOAT_ABI} needs an FPU")
  endif()

  _stm32_validate_memory("${context}" "${arg_MEMORY}")

  set(cpu_flags -mcpu=${arg_CPU} -mthumb -mfloat-abi=${arg_FLOAT_ABI})
  if(arg_FPU)
    list(APPEND cpu_flags -mfpu=${arg_FPU})
  endif()

  add_library(${target_name} INTERFACE)
  add_library(${alias_name} ALIAS ${target_name})

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
    STM32_CHIP "${chip}"
    STM32_CORE "${arg_CORE}"
    STM32_MEMORY "${arg_MEMORY}"
  )
endfunction()
