# Target naming helpers used by all *_add_*() functions.
#
# The project chooses library names, optionally with a namespace:
#   st_add_hal(board::hal_cm7 ...)
# A namespaced name becomes an ALIAS of a real target with "::" replaced by
# "_" (board::hal_cm7 -> board_hal_cm7). Linking against the namespaced name
# is recommended: CMake treats names containing "::" as targets and fails at
# configure time on a typo, while a plain unknown name silently becomes a
# -l<name> linker flag.

include_guard(GLOBAL)

# mcu_add_named_library(<name> <type> <out_var> [<source>...])
#
# Creates the library and stores the real target name in <out_var>; use the
# real name for target_*() calls (they do not accept ALIAS targets).
function(mcu_add_named_library name type out_var)
  set(context "mcu_add_named_library(${name})")
  if(NOT name MATCHES "^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$")
    message(FATAL_ERROR "${context}: invalid target name, use [A-Za-z0-9_] with optional :: separators")
  endif()
  if(NOT type MATCHES "^(STATIC|OBJECT|INTERFACE)$")
    message(FATAL_ERROR "${context}: type must be STATIC, OBJECT or INTERFACE")
  endif()

  string(REPLACE "::" "_" real "${name}")
  if(TARGET ${name} OR TARGET ${real})
    message(FATAL_ERROR "${context}: target ${name} (real name ${real}) already exists")
  endif()

  add_library(${real} ${type} ${ARGN})
  if(NOT real STREQUAL name)
    add_library(${name} ALIAS ${real})
  endif()
  set(${out_var} ${real} PARENT_SCOPE)
endfunction()

# mcu_resolve_target(<name> <out_var>)
#
# Returns the real target behind an ALIAS (or <name> itself). Fails if <name>
# is not a target.
function(mcu_resolve_target name out_var)
  if(NOT TARGET ${name})
    message(FATAL_ERROR "mcu: ${name} is not a target")
  endif()
  get_target_property(aliased ${name} ALIASED_TARGET)
  if(aliased)
    set(${out_var} ${aliased} PARENT_SCOPE)
  else()
    set(${out_var} ${name} PARENT_SCOPE)
  endif()
endfunction()
