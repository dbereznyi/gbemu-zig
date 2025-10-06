#!/usr/bin/bash
rgbasm -o apu.o apu.sm83
rgblink -o ../apu.gb apu.o
rgbfix -v -p 0xFF ../apu.gb

