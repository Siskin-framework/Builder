#include <stdio.h>

#define EXPORT __attribute__((visibility("default")))
 
// Initializer.
__attribute__((constructor))
static void initializer(void) {
    printf("[%s] initializer()\n", __FILE__);
}
 
// Finalizer.
__attribute__((destructor))
static void finalizer(void) {
    printf("[%s] finalizer()\n", __FILE__);
}

EXPORT void hello(void){
	puts("Hello everybody!");
}