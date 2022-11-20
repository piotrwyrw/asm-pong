#!/bin/bash

# Prepare the build directory
if [ -d build ]; then
	rm -rf build
fi

mkdir build

# Run the assembler
nasm -f elf64 pong.asm -o build/pong.o

# Link to external libraries using GCC
gcc -no-pie build/pong.o -o build/pong -lSDL2
