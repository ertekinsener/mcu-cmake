# Architecture handler for Arm Cortex-M (arm-none-eabi-gcc).
#
# Called by mcu_add_chip() through cmake_language(CALL). Validates the
# arm-specific arguments and returns the compile/link flags.

include_guard(GLOBAL)

function(_mcu_arch_arm_flags context cpu fpu float_abi out_var)
  if(NOT cpu)
    message(FATAL_ERROR "${context}: CPU is required (e.g. cortex-m7)")
  endif()
  if(NOT cpu MATCHES "^cortex-m[0-9a-z.+-]*$")
    message(FATAL_ERROR "${context}: CPU '${cpu}' is not a Cortex-M core")
  endif()

  if(NOT float_abi)
    if(fpu)
      set(float_abi hard)
    else()
      set(float_abi soft)
    endif()
  endif()
  if(NOT float_abi MATCHES "^(soft|softfp|hard)$")
    message(FATAL_ERROR "${context}: FLOAT_ABI must be soft, softfp or hard")
  endif()
  if(NOT fpu AND NOT float_abi STREQUAL "soft")
    message(FATAL_ERROR "${context}: FLOAT_ABI ${float_abi} needs an FPU")
  endif()

  set(flags -mcpu=${cpu} -mthumb -mfloat-abi=${float_abi})
  if(fpu)
    list(APPEND flags -mfpu=${fpu})
  endif()
  set(${out_var} ${flags} PARENT_SCOPE)
endfunction()
