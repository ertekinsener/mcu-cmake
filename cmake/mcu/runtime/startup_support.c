// Added by mcu_target_add_runtime(), e.g. through st_add_cmsis_startup().
//
// The image is linked with -nostartfiles (crt0.o would pull exit/atexit and
// the nosys stubs). ST's startup code still calls __libc_init_array(), which
// calls _init(); that symbol normally comes from crti.o.

void _init(void) {}
void _fini(void) {}
