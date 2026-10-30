# Opt-in INTERFACE targets shared by all chips. Link the ones you want:
#
#   mcu::cxx_bare_metal  C++ without exceptions, RTTI, guarded statics
#   mcu::newlib_nano     newlib-nano + nosys syscall stubs
#   mcu::warnings        warning set for own code (not for vendor code)

include_guard(GLOBAL)

add_library(mcu_cxx_bare_metal INTERFACE)
add_library(mcu::cxx_bare_metal ALIAS mcu_cxx_bare_metal)
target_compile_options(mcu_cxx_bare_metal INTERFACE
  $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit>
)

add_library(mcu_newlib_nano INTERFACE)
add_library(mcu::newlib_nano ALIAS mcu_newlib_nano)
target_link_options(mcu_newlib_nano INTERFACE
  --specs=nano.specs
  --specs=nosys.specs
)

add_library(mcu_warnings INTERFACE)
add_library(mcu::warnings ALIAS mcu_warnings)
target_compile_options(mcu_warnings INTERFACE
  -Wall
  -Wextra
  -Wshadow
  -Wdouble-promotion
  $<$<COMPILE_LANGUAGE:CXX>:-Wold-style-cast -Wnon-virtual-dtor>
)
