# sim_3do

Zap ARMv5T core by Revanth Kamaraj, from opencores.com

Verilator by Wilson Snyder.

Dear Imgui library by Omar (ocornut).


This is very early work on an FPGA core for the 3DO console.

The Zap CPU has started booting some BIOS code, but it's not getting very far yet before crashing.

Everything else (registers, DRAM, VRAM) is all emulated in C right now.

I was able to display the 3DO logo by parsing the CLUT (Color Look-Up Table), but only by using a VRAM dump from the MAME debugger (ie. "cheating")
But that confirmed that I was able to decode the logo image correctly.

The 3DO BIOS isn't booting far enough to copy the logo into VRAM yet.

Most of the registers for MADAM are in place already, but very little logic is written for them.

I've started putting the CLIO registers in Verilog.


ElectronAsh.
