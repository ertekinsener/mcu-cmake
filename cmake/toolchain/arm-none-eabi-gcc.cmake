# Toolchain file for GNU Arm Embedded (arm-none-eabi-gcc).
#
# Only locates the compiler and binutils. CPU/FPU flags live on the chip
# targets created by mcu_add_chip(), so one build tree can hold firmware
# for several cores (e.g. a dual-core CM7 + CM4 part).
#
# Optional: ARM_TOOLCHAIN_PATH (CMake or environment variable) pointing to the
# toolchain root, i.e. the directory that contains bin/arm-none-eabi-gcc.

set(CMAKE_SYSTEM_NAME Generic)
set(CMAKE_SYSTEM_PROCESSOR arm)

if(NOT ARM_TOOLCHAIN_PATH AND DEFINED ENV{ARM_TOOLCHAIN_PATH})
  set(ARM_TOOLCHAIN_PATH "$ENV{ARM_TOOLCHAIN_PATH}")
endif()
# The toolchain file is re-read inside try_compile(); forward the path to it.
list(APPEND CMAKE_TRY_COMPILE_PLATFORM_VARIABLES ARM_TOOLCHAIN_PATH)

set(_arm_triplet arm-none-eabi)
set(_arm_hints "")
if(ARM_TOOLCHAIN_PATH)
  list(APPEND _arm_hints "${ARM_TOOLCHAIN_PATH}/bin")
endif()

find_program(CMAKE_C_COMPILER   NAMES ${_arm_triplet}-gcc     HINTS ${_arm_hints} REQUIRED)
find_program(CMAKE_CXX_COMPILER NAMES ${_arm_triplet}-g++     HINTS ${_arm_hints} REQUIRED)
find_program(CMAKE_ASM_COMPILER NAMES ${_arm_triplet}-gcc     HINTS ${_arm_hints} REQUIRED)
find_program(CMAKE_OBJCOPY      NAMES ${_arm_triplet}-objcopy HINTS ${_arm_hints} REQUIRED)
find_program(CMAKE_OBJDUMP      NAMES ${_arm_triplet}-objdump HINTS ${_arm_hints} REQUIRED)
find_program(CMAKE_SIZE         NAMES ${_arm_triplet}-size    HINTS ${_arm_hints} REQUIRED)

# Compiler checks cannot link without a linker script; compile a library instead.
set(CMAKE_TRY_COMPILE_TARGET_TYPE STATIC_LIBRARY)

set(CMAKE_EXECUTABLE_SUFFIX_C   .elf)
set(CMAKE_EXECUTABLE_SUFFIX_CXX .elf)
set(CMAKE_EXECUTABLE_SUFFIX_ASM .elf)

# Host programs (python, openocd, ...) must still be found on the host.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
