# mcu_add_firmware_outputs(): post-build artifacts for a firmware ELF.
#
#   mcu_add_firmware_outputs(<target>
#     [BIN]           # <name>.bin next to the ELF
#     [HEX]           # <name>.hex next to the ELF
#     [MAP]           # <name>.map linker map file
#     [MEMORY_USAGE]  # per-region usage printed by the linker
#     [SIZE])         # arm-none-eabi-size after each link

include_guard(GLOBAL)

function(mcu_add_firmware_outputs target)
  cmake_parse_arguments(PARSE_ARGV 1 arg "BIN;HEX;MAP;MEMORY_USAGE;SIZE" "" "")
  set(context "mcu_add_firmware_outputs(${target})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT TARGET ${target})
    message(FATAL_ERROR "${context}: ${target} is not a target")
  endif()

  set(elf "$<TARGET_FILE:${target}>")
  set(base "$<TARGET_FILE_DIR:${target}>/$<TARGET_FILE_BASE_NAME:${target}>")

  if(arg_MAP)
    target_link_options(${target} PRIVATE "LINKER:-Map=${base}.map")
  endif()
  if(arg_MEMORY_USAGE)
    target_link_options(${target} PRIVATE "LINKER:--print-memory-usage")
  endif()
  if(arg_BIN)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_OBJCOPY} -O binary "${elf}" "${base}.bin"
      COMMENT "Generating ${target}.bin"
      VERBATIM)
  endif()
  if(arg_HEX)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_OBJCOPY} -O ihex "${elf}" "${base}.hex"
      COMMENT "Generating ${target}.hex"
      VERBATIM)
  endif()
  if(arg_SIZE)
    add_custom_command(TARGET ${target} POST_BUILD
      COMMAND ${CMAKE_SIZE} "${elf}"
      VERBATIM)
  endif()
endfunction()
