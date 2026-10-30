# Opt-in INTERFACE targets shared by all chips. Link the ones you want:
#
#   stm32::cxx_bare_metal  C++ without exceptions, RTTI, guarded statics
#   stm32::newlib_nano     newlib-nano + nosys syscall stubs
#   stm32::warnings        warning set for own code (not for vendor code)

include_guard(GLOBAL)

add_library(stm32_cxx_bare_metal INTERFACE)
add_library(stm32::cxx_bare_metal ALIAS stm32_cxx_bare_metal)
target_compile_options(stm32_cxx_bare_metal INTERFACE
  $<$<COMPILE_LANGUAGE:CXX>:-fno-exceptions -fno-rtti -fno-threadsafe-statics -fno-use-cxa-atexit>
)

add_library(stm32_newlib_nano INTERFACE)
add_library(stm32::newlib_nano ALIAS stm32_newlib_nano)
target_link_options(stm32_newlib_nano INTERFACE
  --specs=nano.specs
  --specs=nosys.specs
)

add_library(stm32_warnings INTERFACE)
add_library(stm32::warnings ALIAS stm32_warnings)
target_compile_options(stm32_warnings INTERFACE
  -Wall
  -Wextra
  -Wshadow
  -Wdouble-promotion
  $<$<COMPILE_LANGUAGE:CXX>:-Wold-style-cast -Wnon-virtual-dtor>
)
