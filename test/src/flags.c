// src/flags.c
#include <stdio.h>
#ifndef FROM_CLI
#error FROM_CLI not defined
#endif
#ifndef FROM_ENV
#error FROM_ENV not defined
#endif
int main(void) { puts("ok"); return 0; }