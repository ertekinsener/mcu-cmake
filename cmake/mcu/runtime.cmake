# mcu_target_add_runtime(): small runtime pieces for images that bring their
# own Reset_Handler (vendor startup files or hand-written ones).
#
#   mcu_target_add_runtime(<target>)
#
# <target> is the OBJECT library holding the startup code, or the executable
# itself. It gets:
#   - runtime/startup_support.c: empty _init() / _fini() for
#     __libc_init_array(), since crti.o is not linked,
#   - runtime/cxx_support.cc (if C++ is enabled): trapping
#     std::__glibcxx_assert_fail instead of the stdio-based libstdc++ one,
#   - -nostartfiles on the final link: crt0.o would pull exit/atexit, stdio
#     and the nosys stubs.

include_guard(GLOBAL)

function(mcu_target_add_runtime target)
  set(context "mcu_target_add_runtime(${target})")
  if(NOT TARGET ${target})
    message(FATAL_ERROR "${context}: ${target} is not a target")
  endif()

  get_target_property(type ${target} TYPE)
  if(type STREQUAL "OBJECT_LIBRARY")
    set(link_scope INTERFACE)
  elseif(type STREQUAL "EXECUTABLE")
    set(link_scope PRIVATE)
  else()
    message(FATAL_ERROR "${context}: needs an OBJECT library or an executable, got ${type}")
  endif()

  get_property(module_dir GLOBAL PROPERTY MCU_MODULE_DIR)
  get_property(languages GLOBAL PROPERTY ENABLED_LANGUAGES)
  target_sources(${target} PRIVATE "${module_dir}/runtime/startup_support.c")
  if(CXX IN_LIST languages)
    target_sources(${target} PRIVATE "${module_dir}/runtime/cxx_support.cc")
  endif()
  target_link_options(${target} ${link_scope} -nostartfiles)
endfunction()
