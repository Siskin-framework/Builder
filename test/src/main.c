#include <stdio.h>

#ifdef HAS_HELLO
# include "hello.h"
#endif

#if defined(OPT_INCLUDE)
#include OPT_INCLUDE
#endif

#ifdef HAS_MESSAGE
extern char* message;
#endif
extern int meaning; // in file global.c

int main( void ) {
	#ifdef HAS_HELLO
	hello();
	#endif
	printf("The meaning of life is: %u\n", meaning);
	#ifdef HAS_MESSAGE
	puts(message);
	#endif
	#if defined(STR_VALUE)
	printf("Has STR_VALUE = %s\n", STR_VALUE);
	#endif
	#if defined(OPT_STR_VALUE)
	printf("Has OPT_STR_VALUE = %s\n", OPT_STR_VALUE);
	#endif
}
