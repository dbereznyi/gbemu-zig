#!/usr/bin/bash
rgbasm -o timer.o timer.rgbds
rgblink -o ../timer.gb timer.o
rgbfix -v -p 0xFF ../timer.gb

