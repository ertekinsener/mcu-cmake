// Added by mcu_target_add_runtime() when C++ is enabled in the project.

// GCC 15 enables _GLIBCXX_ASSERTIONS at -O0. The libstdc++ handler prints via
// fprintf and calls abort, which pulls stdio, malloc and the nosys stubs.
// Overriding it keeps the checks but just traps into the debugger.
namespace std {
[[noreturn]] void __glibcxx_assert_fail(const char* /*file*/, int /*line*/,
                                        const char* /*function*/,
                                        const char* /*condition*/) noexcept {
  __builtin_trap();
}
}  // namespace std
