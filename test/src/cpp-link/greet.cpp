// src/greet.cpp
#include <string>
#include <cstdio>
extern "C" void greet(const char *name) {
	std::string s = std::string("hello ") + name;
	std::puts(s.c_str());
}