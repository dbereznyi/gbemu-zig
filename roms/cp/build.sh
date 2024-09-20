#!/usr/bin/bash
rgbasm -o a.o cp.rgbds
rgblink -o ../cp.gb a.o
rgbfix -v -p 0xFF ../cp.gb

