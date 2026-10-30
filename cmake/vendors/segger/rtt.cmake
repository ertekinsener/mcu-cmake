# SEGGER RTT (Real Time Transfer) target sources, vendor-neutral.
#
#   include(vendors/segger/rtt)
#
#   segger_fetch_rtt(
#     GIT_TAG <tag|commit>          # chosen by the project, e.g. V8.58.0
#     [GIT_REPOSITORY <url>])       # default: SEGGERMicro/RTT
#
#   segger_add_rtt(<name>           # may be namespaced, e.g. board::rtt_cm7
#     CHIP <chip target>            # provides the CPU flags
#     [CONFIG <target>]             # provides SEGGER_RTT_Conf.h; without it
#                                   # the package's default Config/ is used
#     [PRINTF]                      # SEGGER_RTT_printf() (no malloc, no stdio)
#     [SYSCALLS])                   # newlib _write() -> RTT channel 0, so
#                                   # printf()/puts() go to RTT
#
# Creates a STATIC library built with the chip's flags. The assembly
# implementation (SEGGER_RTT_ASM_ARMv7M.S) is added when ASM is enabled; RTT
# selects it itself for ARMv7-M / ARMv8-M cores. Without ASM, RTT_USE_ASM=0
# is defined and the C implementation is used.
#
# The control block (_SEGGER_RTT) and buffers live in .bss unless
# SEGGER_RTT_SECTION is set in SEGGER_RTT_Conf.h. On cores with a data cache
# they must be in non-cacheable memory (or set SEGGER_RTT_CPU_CACHE_LINE_SIZE /
# SEGGER_RTT_UNCACHED_OFF); the debug probe reads them behind the CPU's back.

include_guard(GLOBAL)

if(NOT COMMAND mcu_fetch_package)
  message(FATAL_ERROR "vendors/segger/rtt: include(mcu) first")
endif()

function(segger_fetch_rtt)
  cmake_parse_arguments(PARSE_ARGV 0 arg "" "GIT_REPOSITORY;GIT_TAG" "")
  set(context "segger_fetch_rtt()")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_GIT_TAG)
    message(FATAL_ERROR "${context}: GIT_TAG is required (e.g. V8.58.0)")
  endif()
  if(NOT arg_GIT_REPOSITORY)
    set(arg_GIT_REPOSITORY https://github.com/SEGGERMicro/RTT.git)
  endif()

  mcu_fetch_package(segger_rtt
    GIT_REPOSITORY ${arg_GIT_REPOSITORY}
    GIT_TAG ${arg_GIT_TAG}
    SPARSE_PATHS RTT Config Syscalls
    OUT_SOURCE_DIR source_dir
  )
  if(NOT EXISTS "${source_dir}/RTT/SEGGER_RTT.c")
    message(FATAL_ERROR "${context}: ${source_dir} is not SEGGER RTT (RTT/SEGGER_RTT.c missing)")
  endif()
endfunction()

function(segger_add_rtt name)
  cmake_parse_arguments(PARSE_ARGV 1 arg "PRINTF;SYSCALLS" "CHIP;CONFIG" "")
  set(context "segger_add_rtt(${name})")

  if(arg_UNPARSED_ARGUMENTS)
    message(FATAL_ERROR "${context}: unexpected arguments: ${arg_UNPARSED_ARGUMENTS}")
  endif()
  if(NOT arg_CHIP)
    message(FATAL_ERROR "${context}: CHIP is required")
  endif()
  if(NOT TARGET ${arg_CHIP})
    message(FATAL_ERROR "${context}: unknown chip '${arg_CHIP}'. Call mcu_add_chip() first.")
  endif()
  mcu_get_package_dir(segger_rtt dir "Call segger_fetch_rtt(GIT_TAG <tag>) first.")

  if(arg_CONFIG)
    if(NOT TARGET ${arg_CONFIG})
      message(FATAL_ERROR "${context}: CONFIG '${arg_CONFIG}' is not a target")
    endif()
    # The project's SEGGER_RTT_Conf.h replaces Config/; skipped when the
    # include directories use generator expressions.
    get_target_property(config_dirs ${arg_CONFIG} INTERFACE_INCLUDE_DIRECTORIES)
    if(config_dirs AND NOT config_dirs MATCHES "\\$<")
      set(found_config FALSE)
      foreach(config_dir IN LISTS config_dirs)
        if(EXISTS "${config_dir}/SEGGER_RTT_Conf.h")
          set(found_config TRUE)
        endif()
      endforeach()
      if(NOT found_config)
        message(FATAL_ERROR
          "${context}: SEGGER_RTT_Conf.h not found in the include directories of "
          "${arg_CONFIG} (${config_dirs}). Start from ${dir}/Config/SEGGER_RTT_Conf.h")
      endif()
    endif()
  endif()

  set(sources "${dir}/RTT/SEGGER_RTT.c")
  if(arg_PRINTF)
    list(APPEND sources "${dir}/RTT/SEGGER_RTT_printf.c")
  endif()
  if(arg_SYSCALLS)
    list(APPEND sources "${dir}/Syscalls/SEGGER_RTT_Syscalls_GCC.c")
  endif()
  get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  set(use_asm FALSE)
  if(ASM IN_LIST languages)
    list(APPEND sources "${dir}/RTT/SEGGER_RTT_ASM_ARMv7M.S")
    set(use_asm TRUE)
  endif()

  mcu_add_named_library(${name} STATIC target ${sources})
  # SYSTEM: vendor headers do not trigger the project's warning set.
  target_include_directories(${target} SYSTEM PUBLIC "${dir}/RTT")
  if(arg_CONFIG)
    target_link_libraries(${target} PUBLIC ${arg_CONFIG})
  else()
    target_include_directories(${target} SYSTEM PUBLIC "${dir}/Config")
  endif()
  target_link_libraries(${target} PUBLIC ${arg_CHIP})
  if(NOT use_asm)
    target_compile_definitions(${target} PUBLIC RTT_USE_ASM=0)
  endif()
  if(arg_SYSCALLS)
    # The firmware's own libraries are scanned before libc / libnosys. Without
    # this, nothing needs _write() yet when this archive is scanned, and the
    # linker later takes libnosys' stub instead.
    target_link_options(${target} INTERFACE "LINKER:--undefined=_write")
  endif()
endfunction()
