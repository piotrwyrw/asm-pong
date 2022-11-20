#!/bin/bash

# Prepare the build directory
if [ -d build ]; then
	rm -rf build
fi

mkdir build

# Run the assembler
nasm -f elf64 pong.asm -o build/pong.o

# Link to external libraries using GCC
gcc -c score.c -o build/score.o
gcc -c font.c -o build/font.o
gcc -no-pie build/pong.o build/score.o build/font.o -o build/pong -lSDL2
