// src/undef.c
#ifdef FROM_NEST
#error FROM_NEST should be undefined
#endif
int main(void) { return 0; }