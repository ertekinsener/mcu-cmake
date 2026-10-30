# Flash targets driven by probe-rs (vendor-neutral: probe-rs knows the chips
# of many vendors and works with CMSIS-DAP, ST-LINK, J-Link, ... probes).
#
#   mcu_add_flash_target(<name>     # custom target: cmake --build . --target <name>
#     FIRMWARE <target>...          # executables, flashed in this order
#     PROBE_RS_CHIP <chip>          # probe-rs chip name, e.g. STM32H755ZITx
#     [PROBE <VID:PID[:SERIAL]>]    # needed when several probes are connected
#     [VERIFY]                      # read back and compare after flashing
#     [NO_RESET])                   # do not reset the chip afterwards
#
# Builds the images if needed, downloads each one with `probe-rs download`
# and then resets the chip once, so that all cores of a multi-core part start
# together. Several FIRMWARE entries cover multi-core parts (one image per
# core) and bootloader + application.
#
# probe-rs is looked up when the target is created (cache variable
# MCU_PROBE_RS_EXECUTABLE). Without it, configuring still works and the
# target fails with a message when it is run, so build machines without
# probe-rs are not affected.

include_guard(GLOBAL)

function(mcu_add_flash_target name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "VERIFY;NO_RESET" "PROBE_RS_CHIP;PROBE" "FIRMWARE")
  set(context "mcu_add_flash_target(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_FIRMWARE)
    message(FATAL_ERROR "${context}: FIRMWARE is required")
  endif()
  if(NOT arg_PROBE_RS_CHIP)
    message(FATAL_ERROR "${context}: PROBE_RS_CHIP is required (see `probe-rs chip list`)")
  endif()
  if(TARGET ${name})
    message(FATAL_ERROR "${context}: target ${name} already exists")
  endif()
  foreach(firmware IN LISTS arg_FIRMWARE)
    if(NOT TARGET ${firmware})
      message(FATAL_ERROR "${context}: ${firmware} is not a target")
    endif()
    get_target_property(type ${firmware} TYPE)
    if(NOT type STREQUAL "EXECUTABLE")
      message(FATAL_ERROR "${context}: ${firmware} is not an executable (${type})")
    endif()
  endforeach()

  find_program(MCU_PROBE_RS_EXECUTABLE probe-rs
    DOC "probe-rs, used by mcu_add_flash_target()")

  if(NOT MCU_PROBE_RS_EXECUTABLE)
    add_custom_target(${name}
      COMMAND ${CMAKE_COMMAND} -E echo
        "${name}: probe-rs not found. Install it (cargo install probe-rs-tools --locked) or set MCU_PROBE_RS_EXECUTABLE."
      COMMAND ${CMAKE_COMMAND} -E false
      VERBATIM
    )
    return()
  endif()

  set(common_args --chip ${arg_PROBE_RS_CHIP} --non-interactive)
  if(arg_PROBE)
    list(APPEND common_args --probe ${arg_PROBE})
  endif()
  set(download_args --disable-progressbars)
  if(arg_VERIFY)
    list(APPEND download_args --verify)
  endif()

  set(commands "")
  foreach(firmware IN LISTS arg_FIRMWARE)
    list(APPEND commands
      COMMAND ${MCU_PROBE_RS_EXECUTABLE} download ${common_args} ${download_args}
              $<TARGET_FILE:${firmware}>)
  endforeach()
  if(NOT arg_NO_RESET)
    list(APPEND commands COMMAND ${MCU_PROBE_RS_EXECUTABLE} reset ${common_args})
  endif()

  list(JOIN arg_FIRMWARE ", " firmware_list)
  add_custom_target(${name}
    ${commands}
    DEPENDS ${arg_FIRMWARE}
    COMMENT "Flashing ${firmware_list} (${arg_PROBE_RS_CHIP})"
    USES_TERMINAL
    VERBATIM
  )
endfunction()
