#!/usr/bin/bash
rgbasm -o a.o instr.rgbds
rgblink -o ../instr.gb a.o
rgbfix -v -p 0xFF ../instr.gb

