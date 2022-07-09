# sim_3do

:+1:Zap ARMv5T core by Revanth Kamaraj, from opencores.com

:+1:Verilator by Wilson Snyder.

:+1:Dear Imgui library by Omar (ocornut).


I run Verilator from within WSL2 / Ubuntu, to "compile" the Verilog into the C/C++ sim model.

You version of Verilator needs to be the same (or close) version to what I used.
I'm currently using v4.204, installed by compiling the Verilator source, then sudo make install, etc.

Every time a change is made to the Verilog, verilator needs to be run again, before running the sim from MSVC.
(I know it's possible to have MSVC run a WSL command, and that verilator can be compiled for Windows, but I find WSL good enough for most of this.)

I used Microsoft Visual Studio 2019, version 16.4.5 (the free version), to build and run the sim.


This is very early work on an FPGA core for the 3DO console.
The Zap CPU has started booting some BIOS code, but it's not getting very far yet before crashing.

:+1:'fixel' and 'trapexit' have been helping me a lot (on The 3DO Community Discord).

fixel helped patch the Zap core, to handle byte reads/writes properly.
(the ARM60 used on the 3DO is set to Big Endian mode, via a pin tied High on the motherboard. The Zap core originally only supported little endian, IIRC)

trapexit helped me get the Opera 3DO emulator compiling under MSVC, so I can compare trace logs to the Verilator sim version.
(I might make a new repo for the Opera MSVC project, but there are tons of files, and it will take some time to figure out.)


Everything else (registers, DRAM, VRAM, framebuffer) are all still emulated in C right now.
(I've started moving the registers from C to Verilog now. Still some logic done in C, plus the BIOS, DRAM, VRAM etc.)

I was able to display the 3DO logo by parsing the CLUT (Color Look-Up Table), but only by using a VRAM dump from the MAME debugger (ie. "cheating")
But that was enough to confirm that I could decode the logo image correctly...

![](png/3do_sim_logo.png)


The 3DO BIOS isn't booting far enough to copy the logo into VRAM yet.

Most of the registers for MADAM are in place already, but very little logic is written for them.
I've started putting the CLIO registers in Verilog.


ElectronAsh.
