rm out/Vcore*.*

verilator --public --compiler msvc --converge-limit 2000 -Wno-PINMISSING -Wno-TIMESCALEMOD -Wno-LITENDIAN -Wno-CASEOVERLAP -Wno-WIDTH -Wno-IMPLICIT -Wno-MODDUP -Wno-UNSIGNED -Wno-CASEINCOMPLETE -Wno-CASEX -Wno-SYMRSVDWORD -Wno-COMBDLY -Wno-INITIALDLY -Wno-BLKANDNBLK -Wno-MULTIDRIVEN -Wno-UNOPT -Wno-LATCH -y -I. -Irtl -Irtl/amber23 -Irtl/amber25 -Irtl/armv4t -Irtl/armgba -Irtl/zap --top-module core_3do -Mdir out --cc core_3do.v --exe sim_main.cpp
