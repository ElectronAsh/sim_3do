//
// 3DO CLIO chip implementation / notes. ElectronAsh, Jan 2022.
//
// CLIO contains the CLUTs, VDL parsing, Pixel/line interpolation. DAC control/Pixel output. Audio DSP, Audio output, Expansion Bus (CDROM GA) control, FMV DMA signals?
//
//
module clio (			// IC140 on FZ1.
	input clk_25m,
	input reset_n,
	
	//input pon,			// Power ON Reset input. (not really needed).
							// Technically, RESET_N on CLIO is an OUTPUT to other stuff.
	
	output [23:0] ad,		// Pixel data to DAC/encoder. R/G/B order!
	output amyctl,			// Color Encoder (DAC) control signal.
	output tmuxsel,			// Pixel clock to DAC? 12.2727 MHz.
	output blank_n,			// Blanking FROM DAC?
	input vsync_n,			// FROM the DAC.
	input hsync_n,			// FROM the DAC.
	
	//input wdin,			// Watchdog Timer C/R input. (analog stuffs. Not needed).
	output wdres_n,			// Watchdog Timer Reset output.
	
	input [7:0] ed_in,		// Expansion Bus Data input. CD-ROM Gate Array access.
	output [7:0] ed_out,	// Expansion Bus Data output.
	output estr_n,			// Expansion Bus Strobe signal.
	output ewrt_n,			// Expansion Bus Write signal.
	output erst_n,			// Expansion Bus Reset signal.
	output ecmd_n,			// Expansion Bus Command signal.
	output esel_n,			// Expansion Bus Select signal.
	input erdy_n,			// Expansion Bus Ready input.
	input eint_n,			// Expansion Bus Interrupt input.
	
	output auddat,			// Audio Data output.
	output audws,			// Audio Word Sync (Left/Right sync).
	output audbck,			// Audio Bit Clock.
	output xaclk,			// Audio DAC Master Clock?
	
	inout serclk,			// Serial Audio INPUT port.
	inout serdat,			// All tied LOW on the FZ1 schematic!
	inout serr,
	inout serl,

	input extreq_r,			// Audio DMA Read request. FMV?
	input extreq_w,			// Audio DMA Write request. FMV?
	output extack_r,		// Audio DMA Read Acknowledge. FMV?
	output extack_w,		// Audio DMA Write Acknowledge. FMV?

	inout [3:0] adbio,	
	
	input lpsc,
	input rpsc,
	
	input [31:0] s_din,		// S-Bus from VRAM.
	output [31:0] s_dout,	// S-Bus to VRAM.
	
	input [31:0] cpu_din,
	output reg [31:0] cpu_dout,
	
	input [15:02] cpu_addr,	// CLIO does NOT have a full connection to the CPU Addr bus.
	
	input cpu_rd,			// In reality, the only mechanism I can see for CLIO reg access, are the three CLC[2:0] pins that come from MADAM.
	input cpu_wr,			// so there are no "direct" read/write pins from the CPU to the CLIO chip, it's all controlled via MADAM.
	
	output pcsc_n,			// To MADAM. (the main synchronizing signal). 
	
	output dmareq,			// To MADAM?
	
	input pdint_n,			// Labelled "UNCINT#" on the FZ1 schematic. Slow Bus Interrupt?
	output firq_n,			// To the ARM CPU.
	
	input [2:0] clc,		// CLIO Opera Device bits? Tech guide calls this "Control Code". Probably works like the RGA bus on the Amiga?
	inout cready_n,			// Tech guide calls this "Hand shake control for devices".
	
	inout uncreqw,			// Video DMA Write request. FMV? UN - Uncle Chip.
	inout uncreqr,			// Video DMA Read request. FMV? UN - Uncle Chip.
	inout uncackw,			// Video DMA Write Acknowledge. FMV? UN - Uncle Chip.
	inout uncackr,			// Video DMA Read Acknowledge. FMV? UN - Uncle Chip.
	
	//output [21:00] vram_addr,
	output vram_rd,
	output vram_wr,
	input [15:0] vram_l_din,
	input [15:0] vram_r_din,

	output [15:0] vram_l_dout,
	output [15:0] vram_r_dout,
	
	input vram_busy,
	
	input xbus_fiq_trig
);

wire [31:0] irq0_masked = irq0_pend & irq0_enable;	// Bit 31 of irq0_pend denotes one or more irq1_pend bits are set. (set in the clocked always block!)
wire irq0_trig = |irq0_masked;

wire [31:0] irq1_masked = irq1_pend & irq1_enable;
wire irq1_trig = |irq1_masked;		// bitwise OR, after masking irq1_pend with the irq1_enable bits.

assign firq_n = !(irq0_trig | irq1_trig);

// Timings taken from a 3DO patent, IIRC... ElectronAsh.
wire read_en  = hcnt>=11 && hcnt<=1292;
wire write_en = hcnt>=1293 && hcnt<=1339;
wire copy_en  = hcnt>=1340 && hcnt<=1399;
wire hsync_window = hcnt>=1400 && hcnt<=1799;

reg [23:0] clut_prev [0:32];
reg [23:0] clut_curr [0:32];

reg [31:0] revision;	// 0x00 - CLIO version if High byte. Feature flags in the rest. MAME returns 0x01020000. Opera return 0x02020000.
reg [31:0] csysbits;	// 0x04
reg [31:0] vint0;		// 0x08
reg [31:0] vint1;		// 0x0C
reg [31:0] audin;		// 0x20
reg [31:0] audout;		// 0x24
reg [31:0] cstatbits;	// 0x28
reg [31:0] wdog;		// 0x2c
reg [31:0] hcnt;		// 0x30 / hpos when read?
reg [31:0] vcnt;		// 0x34 / vpos when read?
reg [31:0] seed;		// 0x38
reg [31:0] random;		// 0x3c - read only?


// IRQs...
						// FIQ will be triggered if PENDING and corresponding MASK bits are both SET.
reg [31:0] irq0_pend;	// 0x40/0x44 - Writing to 0x40 SETs irq0_pend bits. Writing to 0x44 CLEARs irq0_pend bits. Reading = PENDING irq0_pend bits.
reg [31:0] irq0_enable;	// 0x48/0x4c - Writing to 0x48 SETs irq0 ENABLE mask bits. Writing to 0x4c CLEARSs irq0 ENABLE mask bits. Reading = irq0 ENABLE mask.

reg [31:0] mode;		// 0x50/0x54 - Writing to 0x50 SETs mode bits. Writing to 0x54 CLEARs mode bits. Reading = ?
reg [31:0] badbits;		// 0x58 - for reading things like DMA fail reasons?
reg [31:0] spare;		// 0x5c - ?

						// FIQ will be triggered if PENDING and corresponding MASK bits are both SET.
reg [31:0] irq1_pend;	// 0x60/0x64 - Writing to 0x60 SETs irq1_pend bits. Writing to 0x64 CLEARs irq1_pend bits. Reading = PENDING irq1_pend bits.
reg [31:0] irq1_enable;	// 0x68/0x6c - Writing to 0x68 SETs irq1 ENABLE mask bits. Writing to 0x6c CLEARSs irq1 ENABLE mask bits. Reading = irq1 ENABLE mask.


// hdelay / adbio stuff...
reg [31:0] hdelay;		// 0x80
reg [31:0] adbio_reg;	// 0x84
reg [31:0] adbctl;		// 0x88


// Timers...
// (timers are handled by their own modules now.)
/*
reg [15:0] tmr_cnt_0;	 // 0x100
// ....
reg [15:0] tmr_bkp_15;	 // 0x17c
*/

// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.
// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
reg [31:0] tmr_ctrl_l;		// 0x200,0x204. Controls the lower timers 0 (lowermost nibble) through 7 (uppermost nibble).
reg [31:0] tmr_ctrl_u;		// 0x208,0x20c. Controls the lower timers 8 (lowermost nibble) through f (uppermost nibble).

reg [9:0] slack;			// 0x220. Only the lower 10 bits get written?

// 0x304 DMA starter thingy.

// 0x308 DMA stopper thingy.
reg [31:0] dmareqdis;		//

// Only bits 15,14,11,9 are written to in MAME? Opera calls this reg "XBUS Direction"...
reg [31:0] expctl;	// 0x400/0x404. Writing to 0x400 SETs bits of expctl. Writing to 0x404 CLEARs bits of expctl.
					// Opera starts with this -> 0x80; /* ARM has the expansion bus */

reg [31:0] type0_4;	// 0x408. ??? Opera doesn't seem to use this, but allows reg writes/reads.

reg [31:0] dipir1;	// 0x410. DIPIR (Disc Inserted Provide Interrupt Response) 1.
reg [31:0] dipir2;	// 0x414. DIPIR (Disc Inserted Provide Interrupt Response) 2.

parameter POLSTMASK = 8'h01;
parameter POLDTMASK = 8'h02;
parameter POLMAMASK = 8'h04;
parameter POLREMASK = 8'h08;
parameter POLST	    = 8'h10;
parameter POLDT	    = 8'h20;
parameter POLMA	    = 8'h40;
parameter POLRE	    = 8'h80;

parameter CDST_TRAY   = 8'h80;
parameter CDST_DISC   = 8'h40;
parameter CDST_SPIN   = 8'h20;
parameter CDST_ERRO   = 8'h10;
parameter CDST_2X     = 8'h02;
parameter CDST_RDY    = 8'h01;
parameter CDST_TRDISC = 8'hC0;
parameter CDST_OK     = CDST_RDY|CDST_TRAY|CDST_DISC|CDST_SPIN;


reg [7:0] sel_0;	// 0x500
reg [7:0] sel_1;	// 0x504
reg [7:0] sel_2;	// 0x508
reg [7:0] sel_3;	// 0x50c
reg [7:0] sel_4;	// 0x510
reg [7:0] sel_5;	// 0x514
reg [7:0] sel_6;	// 0x518
reg [7:0] sel_7;	// 0x51c
reg [7:0] sel_8;	// 0x520
reg [7:0] sel_9;	// 0x524
reg [7:0] sel_10;	// 0x528
reg [7:0] sel_11;	// 0x52c
reg [7:0] sel_12;	// 0x530
reg [7:0] sel_13;	// 0x534
reg [7:0] sel_14;	// 0x538
reg [7:0] sel_15;	// 0x53c

reg [7:0] poll_0;	// 0x540
reg [7:0] poll_1;	// 0x544
reg [7:0] poll_2;	// 0x548
reg [7:0] poll_3;	// 0x54c
reg [7:0] poll_4;	// 0x550
reg [7:0] poll_5;	// 0x554
reg [7:0] poll_6;	// 0x558
reg [7:0] poll_7;	// 0x55c
reg [7:0] poll_8;	// 0x560
reg [7:0] poll_9;	// 0x564
reg [7:0] poll_10;	// 0x568
reg [7:0] poll_11;	// 0x56c
reg [7:0] poll_12;	// 0x570
reg [7:0] poll_13;	// 0x574
reg [7:0] poll_14;	// 0x578
reg [7:0] poll_15;	// 0x57c

// 0x580 - 0x5bf. In Opera, on a write, this calls "opera_xbus_fifo_set_cmd(val_)".
// 0x5c0 - 0x5ff. In Opera, on a write, this calls "opera_xbus_fifo_set_data(val_)".


// DSP...
reg [31:0] sema;		// 0x17d0. DSP/ARM Semaphore. (can't call it "semaphore", because Verilog / Verilator).
reg [31:0] semaack;		// 0x17d4. Semaphore Acknowledge.
reg [31:0] dspdma;		// 0x17e0.
reg [31:0] dspprst0;	// 0x17e4. Write triggers DSP reset 0?
reg [31:0] dspprst1;	// 0x17e8. Write triggers DSP reset 1?
reg [31:0] dspppc;		// 0x17f4.
reg [31:0] dsppnr;		// 0x17f8.
reg [31:0] dsppgw;		// 0x17fc. Start / Stop the DSP.

// 0x1800 - 0x1fff. DSP Mem write.
// 0x2000 - 0x2fff. DSP Mem write.
// 0x3000 - 0x33ff. DSP Imem write.
// 0x3400 - 0x37ff. DSP Imem write.

reg [31:0] dsppclkreload;	// 0x39dc.


// UNCLE...
reg [31:0] unclerev;		// 0xc000. Opera returns 0x03800000. ??
reg [31:0] unc_soft_rev;	// 0xc004
reg [31:0] uncle_addr;		// 0xc008
reg [31:0] uncle_rom;		// 0xc00c

// TODO: Any other address needs to trigger an "unhandled" signal.


always @(*) begin
	// CLIO Register READ output driver...
	case ({cpu_addr,2'b00})
	16'h0000: cpu_dout = revision;	// 0x00 - CLIO version if High byte. Feature flags in the rest. MAME returns 0x01020000. Opera return 0x02020000.
	16'h0004: cpu_dout = csysbits;	// 0x04
	16'h0008: cpu_dout = vint0;		// 0x08
	16'h000c: cpu_dout = vint1;		// 0x0C
	16'h0020: cpu_dout = audin;		// 0x20
	16'h0024: cpu_dout = audout;	// 0x24
	16'h0028: cpu_dout = cstatbits;	// 0x28
	16'h002c: cpu_dout = wdog;		// 0x2c
	16'h0030: cpu_dout = hcnt;		// 0x30 / hpos when read?
	16'h0034: cpu_dout = (field<<11) | vcnt;	// 0x34 / vpos when read?
	16'h0038: cpu_dout = seed;		// 0x38
	16'h003c: cpu_dout = random;	// 0x3c - read only?

// IRQs...
												// FIQ will be triggered if PENDING and corresponding ENABLE bits are both SET.
	16'h0040,16'h0044: cpu_dout = irq0_pend;	// 0x40/0x44 - Writing to 0x40 SETs irq0_pend bits. Writing to 0x44 CLEARs irq0_pend bits. Reading = PENDING irq0_pend bits.
	16'h0048,16'h004c: cpu_dout = irq0_enable;	// 0x48/0x4c - Writing to 0x48 SETs irq0_enable bits. Writing to 0x4c CLEARSs irq0_enable bits.

	16'h0050,16'h0054: cpu_dout = mode;			// 0x50/0x54 - Writing to 0x50 SETs mode bits. Writing to 0x54 CLEARs mode bits. Reading = ?
	16'h0058: cpu_dout = badbits;				// 0x58 - for reading things like DMA fail reasons?
	16'h005c: cpu_dout = spare;					// 0x5c - ?

												// FIQ will be triggered if PENDING and corresponding ENABLE bits are both SET.
	16'h0060,16'h0064: cpu_dout = irq1_pend;	// 0x60/0x64 - Writing to 0x60 SETs irq1_pend bits. Writing to 0x64 CLEARs irq1_pend bits. Reading = PENDING irq1_pend bits.
	16'h0068,16'h006c: cpu_dout = irq1_enable;	// 0x68/0x6c - Writing to 0x68 SETs irq1_enable bits. Writing to 0x6c CLEARSs irq1_enable bits.


// hdelay / adbio stuff...
	16'h0080: cpu_dout = hdelay;		// 0x80
	16'h0084: /*cpu_dout = {28'h0000000, adbio_reg[7:4]};*/ cpu_dout = 32'h00000000;	// 0x84
	16'h0088: cpu_dout = adbctl;		// 0x88


// Timers... (16-bit wide?)
	16'h0100: cpu_dout = {16'h0000, tmr_read_mux};	// 0x100
	16'h0104: cpu_dout = {16'h0000, tmr_read_mux};	// 0x104
	16'h0108: cpu_dout = {16'h0000, tmr_read_mux};	// 0x108
	16'h010c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x10c
	16'h0110: cpu_dout = {16'h0000, tmr_read_mux};	// 0x110
	16'h0114: cpu_dout = {16'h0000, tmr_read_mux};	// 0x114
	16'h0118: cpu_dout = {16'h0000, tmr_read_mux};	// 0x118
	16'h011c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x11c
	16'h0120: cpu_dout = {16'h0000, tmr_read_mux};	// 0x120
	16'h0124: cpu_dout = {16'h0000, tmr_read_mux};	// 0x124
	16'h0128: cpu_dout = {16'h0000, tmr_read_mux};	// 0x128
	16'h012c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x12c
	16'h0130: cpu_dout = {16'h0000, tmr_read_mux};	// 0x130
	16'h0134: cpu_dout = {16'h0000, tmr_read_mux};	// 0x134
	16'h0138: cpu_dout = {16'h0000, tmr_read_mux};	// 0x138
	16'h013c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x13c
	16'h0140: cpu_dout = {16'h0000, tmr_read_mux};	// 0x140
	16'h0144: cpu_dout = {16'h0000, tmr_read_mux};	// 0x144
	16'h0148: cpu_dout = {16'h0000, tmr_read_mux};	// 0x148
	16'h014c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x14c
	16'h0150: cpu_dout = {16'h0000, tmr_read_mux};	// 0x150
	16'h0154: cpu_dout = {16'h0000, tmr_read_mux};	// 0x154
	16'h0158: cpu_dout = {16'h0000, tmr_read_mux};	// 0x158
	16'h015c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x15c
	16'h0160: cpu_dout = {16'h0000, tmr_read_mux};	// 0x160
	16'h0164: cpu_dout = {16'h0000, tmr_read_mux};	// 0x164
	16'h0168: cpu_dout = {16'h0000, tmr_read_mux};	// 0x168
	16'h016c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x16c
	16'h0170: cpu_dout = {16'h0000, tmr_read_mux};	// 0x170
	16'h0174: cpu_dout = {16'h0000, tmr_read_mux};	// 0x174
	16'h0178: cpu_dout = {16'h0000, tmr_read_mux};	// 0x178
	16'h017c: cpu_dout = {16'h0000, tmr_read_mux};	// 0x17c

// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.
// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
	16'h0200: cpu_dout = tmr_ctrl_l;	// TODO. Not 100% sure what should get read back for these? ElectronAsh.
	16'h0204: cpu_dout = tmr_ctrl_l;
	16'h0208: cpu_dout = tmr_ctrl_u;
	16'h020c: cpu_dout = tmr_ctrl_u;

	16'h0220: cpu_dout = slack;				// 0x220. Only the lower 10 bits get written?

// 0x304 DMA starter thingy.
	//16'h0304: TODO

	16'h0308: cpu_dout = dmareqdis;	// 0x308 DMA stopper thingy.

// Only bits 15,14,11,9 are written to in MAME? Opera calls this reg "XBUS Direction"...
	16'h0400: cpu_dout = expctl;	// 0x400/0x404. Writing to 0x400 SETs bits of expctl. Writing to 0x404 CLEARs bits of expctl.
									// Opera starts with this -> 0x80; /* ARM has the expansion bus */

	16'h0408: cpu_dout = type0_4;	// 0x408. ??? Opera doesn't seem to use this, but allows reg writes/reads.

	16'h0410: cpu_dout = dipir1;	// 0x410. DIPIR (Disc Inserted Provide Interrupt Response) 1.
	16'h0414: cpu_dout = dipir2;	// 0x414. DIPIR (Disc Inserted Provide Interrupt Response) 2.

	16'h0500: cpu_dout = {24'h000000, sel_0};	// 0x500
	16'h0504: cpu_dout = {24'h000000, sel_1};	// 0x504
	16'h0508: cpu_dout = {24'h000000, sel_2};	// 0x508
	16'h050c: cpu_dout = {24'h000000, sel_3};	// 0x50c
	16'h0510: cpu_dout = {24'h000000, sel_4};	// 0x510
	16'h0514: cpu_dout = {24'h000000, sel_5};	// 0x514
	16'h0518: cpu_dout = {24'h000000, sel_6};	// 0x518
	16'h051c: cpu_dout = {24'h000000, sel_7};	// 0x51c
	16'h0520: cpu_dout = {24'h000000, sel_8};	// 0x520
	16'h0524: cpu_dout = {24'h000000, sel_9};	// 0x524
	16'h0528: cpu_dout = {24'h000000, sel_10};	// 0x528
	16'h052c: cpu_dout = {24'h000000, sel_11};	// 0x52c
	16'h0530: cpu_dout = {24'h000000, sel_12};	// 0x530
	16'h0534: cpu_dout = {24'h000000, sel_13};	// 0x534
	16'h0538: cpu_dout = {24'h000000, sel_14};	// 0x538
	16'h053c: cpu_dout = {24'h000000, sel_15};	// 0x53c

	16'h0540: cpu_dout = {24'h000000, poll_0};	// 0x540
	16'h0544: cpu_dout = {24'h000000, poll_1};	// 0x544
	16'h0548: cpu_dout = {24'h000000, poll_2};	// 0x548
	16'h054c: cpu_dout = {24'h000000, poll_3};	// 0x54c
	16'h0550: cpu_dout = {24'h000000, poll_4};	// 0x550
	16'h0554: cpu_dout = {24'h000000, poll_5};	// 0x554
	16'h0558: cpu_dout = {24'h000000, poll_6};	// 0x558
	16'h055c: cpu_dout = {24'h000000, poll_7};	// 0x55c
	16'h0560: cpu_dout = {24'h000000, poll_8};	// 0x560
	16'h0564: cpu_dout = {24'h000000, poll_9};	// 0x564
	16'h0568: cpu_dout = {24'h000000, poll_10};	// 0x568
	16'h056c: cpu_dout = {24'h000000, poll_11};	// 0x56c
	16'h0570: cpu_dout = {24'h000000, poll_12};	// 0x570
	16'h0574: cpu_dout = {24'h000000, poll_13};	// 0x574
	16'h0578: cpu_dout = {24'h000000, poll_14};	// 0x578
	16'h057c: cpu_dout = {24'h000000, poll_15};	// 0x57c

	16'h0580: cpu_dout = {24'h000000, fifo_spoof};	// 0x580. CmdStFIFO for Xbus access.

// 0x580 - 0x5bf. In Opera, on a write, this calls "opera_xbus_fifo_set_cmd(val_)".
// 0x5c0 - 0x5ff. In Opera, on a write, this calls "opera_xbus_fifo_set_data(val_)".

// DSP...
	16'h17d0: cpu_dout = sema;		// 0x17d0. DSP/ARM Semaphore. (can't call it "semaphore", because Verilog / Verilator).
	16'h17d4: cpu_dout = semaack;	// 0x17d4. Semaphore Acknowledge.
	16'h17e0: cpu_dout = dspdma;	// 0x17e0.
	16'h17e4: cpu_dout = dspprst0;	// 0x17e4. Write triggers DSP reset 0?
	16'h17e8: cpu_dout = dspprst1;	// 0x17e8. Write triggers DSP reset 1?
	16'h17f4: cpu_dout = dspppc;	// 0x17f4.
	16'h17f8: cpu_dout = dsppnr;	// 0x17f8.
	16'h17fc: cpu_dout = dsppgw;	// 0x17fc. Start / Stop the DSP.

// 0x1800 - 0x1fff. DSP Mem write.
// 0x2000 - 0x2fff. DSP Mem write.
// 0x3000 - 0x33ff. DSP Imem write.
// 0x3400 - 0x37ff. DSP Imem write.

	16'h39dc: cpu_dout = dsppclkreload;	// 0x39dc. ?


// UNCLE...
	16'hc000: cpu_dout = unclerev;		// 0xc000
	16'hc004: cpu_dout = unc_soft_rev;	// 0xc004
	16'hc008: cpu_dout = uncle_addr;	// 0xc008
	16'hc00c: cpu_dout = uncle_rom;		// 0xc00c
	
	default: cpu_dout = 32'hBADACCE5;	// default case.
	endcase
end

wire wdgrst = 0;
wire dipir = 0;

wire [31:0] hcnt_max = 32'd1590;
wire [31:0] vcnt_max = 32'd262;
reg field;

reg [3:0] fifo_idx;

wire [7:0] fifo_spoof = (fifo_idx==4'd0)  ? 8'h83 : // CDROM_CMD_READ_ID
						(fifo_idx==4'd1)  ? 8'h00 : // manufacture id
						(fifo_idx==4'd2)  ? 8'h10 : // 0x10
						(fifo_idx==4'd3)  ? 8'h00 : // manufacture number
						(fifo_idx==4'd4)  ? 8'h01 : // 0x01
						(fifo_idx==4'd5)  ? 8'h00 :
						(fifo_idx==4'd6)  ? 8'h00 :
						(fifo_idx==4'd7)  ? 8'h00 : // revision number
						(fifo_idx==4'd8)  ? 8'h00 :
						(fifo_idx==4'd9)  ? 8'h00 : // flag bytes
						(fifo_idx==4'd10) ? 8'h00 :
						//(fifo_idx==4'd11) ? 8'hE1 : // CDST_RDY|CDST_TRAY|CDST_DISC|CDST_SPIN (CD drive's actual status)
						(fifo_idx==4'd11) ? 8'h01 : // CDST_RDY (CD drive's actual status)
						(fifo_idx==4'd12) ? 8'h01 :	// device driver size. ??
											8'h00;	// default value.

always @(posedge clk_25m or negedge reset_n)
if (!reset_n) begin
	revision <= 32'h02020000;		// Opera returns 0x02020000.
	cstatbits[0] <= 1'b1;			// Set bit 0 (POR). fixel said to start with this bit set only.
	//cstatbits[6] <= 1'b1;			// Set bit 0 (DIPIR). TESTING !!
	expctl <= 32'h00000080;			// Opera starts with this -> 0x80; // ARM has the expansion bus.
	field <= 1'b0;
	hcnt <= 32'd0;
	vcnt <= 32'd0;
	
	unclerev <= 32'h03800000;		//  Opera returns 0x03800000. ?
	unc_soft_rev <= 32'h00000000;
	
	slack <= 10'd64;
	adbio_reg <= 32'h00000000;
	
	poll_0 <= 8'h00;
	
	fifo_idx <= 4'd0;
	
	irq0_pend <= 32'h00000000;
	irq0_enable <= 32'h00000000;
	irq1_pend <= 32'h00000000;
	irq1_enable <= 32'h00000000;
end
else begin
	// Setting an upper nibble bit of the adbio reg will set the corresponding lower bit.
	// (opera source code). The upper nibble is not kept, AFAIK. ElectronAsh.
	// The ADBIO pins on CLIO are all unconnected, aside from bit 3 being routed via a diode to the WatchDog Reset pin (also on CLIO).
	/*
	uint32_t adbio_temp = top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg;
	if (adbio_temp & 0x10) top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg |= 0x01;
	if (adbio_temp & 0x20) top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg |= 0x02;
	if (adbio_temp & 0x40) top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg |= 0x04;
	if (adbio_temp & 0x80) top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg |= 0x08;
	top->rootp->core_3do__DOT__clio_inst__DOT__adbio_reg &= 0x0F;
	*/
	
	//adbio_reg <= {28'h0000000, adbio_reg[7:4]};
	
//
// POLSTMASK = 8'h01;	// BIOS sets this, if it wants the device to generate an Interrupt when POLST is High.
// POLDTMASK = 8'h02;	// BIOS sets this, if it wants the device to generate an Interrupt when POLDT is High.
// POLMAMASK = 8'h04;	// Ditto for POLMA.
// POLREMASK = 8'h08;	// ??
// POLST	 = 8'h10;	// DEVICE sets this, if it has Status bytes waiting to be read from the Status FIFO.
// POLDT	 = 8'h20;	// DEVICE sets this, if it has Data bytes waiting to be read from the Data FIFO.
// POLMA	 = 8'h40;	// Media Access bit. Set when a new disk is inserted, probably??
// POLRE	 = 8'h80;	// Erm, Reset device? (the Device's ID does not get cleared by this, only by the physical RESET_N pin).
//
	
	/*
	// Writes to sel0 reg...
	if (cpu_wr && {cpu_addr,2'b00}==16'h0500) begin
		if (cpu_din[7] && cpu_din[3:0]==4'hf) begin
			poll_0   <= 8'h0F;		// Discard the upper nibble if sel[7] set?? Return the device ID in the lower nibble.
		end
		else poll_0[7:0] <= 8'h30;	// Else, (sel[7] is low) clear the lower nibble, for all other devices.
	end
	
	// COMMAND Writes to CmdStFIFO...
	if (cpu_wr && {cpu_addr,2'b00}==16'h0580) begin
		fifo_idx <= 4'd0;		// Reset our fake CmdStFIFO index.
		poll_0[4] <= 1'b1;				// Set the Status bit (should really do this after all command bytes received, but meh.)
	end
	
	// STATUS Reads from CmdStFIFO...
	if (cpu_rd && {cpu_addr,2'b00}==16'h0580) begin
		fifo_idx <= fifo_idx + 4'd1;	// Increment our fake CmdStFIFO index on each Read..
	end
	if (fifo_idx==4'd12 && poll_0[3:0]==4'hf) begin
		poll_0[4] <= 1'b0;				// All STATUS bytes read, clear the poll status bit immediately.
	end
	
	// Set XBUS IRQ pending bit, if the corresponding STATUS / DATA mask bits are set.
	irq0_pend[2] <= ((poll_0&POLST) && (poll_0&POLSTMASK)) || ((poll_0&POLDT) && (poll_0&POLDTMASK));
	*/
	
	if (xbus_fiq_trig) irq0_pend[2] <= 1'b1;
	
	
	if ( hcnt==32'd0 && vcnt==(vint0&11'h7FF)) irq0_pend[0] <= 1'b1;	// vint0 is on irq0, bit 0.
	if ( hcnt==32'd0 && vcnt==(vint1&11'h7FF)) irq0_pend[1] <= 1'b1;	// vint1 is on irq0, bit 1.

	irq0_pend[31] <= |irq1_pend;	// If ANY irq1_pend bits are set, use that to set (or clear) bit 31 of irq0_pend.

	if (hcnt==hcnt_max) begin
		hcnt <= 32'd0;
		
		if (vcnt==vcnt_max) begin
			vcnt <= 32'd0;
			field <= !field;
		end
		else begin
			vcnt <= vcnt + 1'd1;
		end
	end
	else begin
		hcnt <= hcnt + 1'd1;
	end

	if (wdgrst) cstatbits[1] <= 1'b1;		// Set bit 1 (WDT).
	else if (dipir) cstatbits[6] <= 1'b1;	// Set bit 6 (DIPIR).
	
	// Handle CLIO register WRITES...
	if (cpu_wr) begin
		case ({cpu_addr,2'b00})
		//16'h0000: revision <= cpu_din;	// 0x00 - READ ONLY? CLIO version in High byte. Feature flags in the rest. Opera return 0x02020000. MAME returns 0x01020000.
		16'h0004: csysbits <= cpu_din;	// 0x04
		16'h0008: vint0 <= cpu_din;		// 0x08
		16'h000c: vint1 <= cpu_din;		// 0x0C
		16'h0020: audin <= cpu_din;		// 0x20
		16'h0024: audout <= cpu_din;	// 0x24
		16'h0028: cstatbits <= cpu_din;	// 0x28
		16'h002c: wdog <= cpu_din;		// 0x2c
		16'h0030: hcnt <= cpu_din;		// 0x30 / hpos when read?
		16'h0034: vcnt <= cpu_din;		// 0x34 / vpos when read?
		16'h0038: seed <= cpu_din;		// 0x38
		16'h003c: random <= cpu_din;	// 0x3c - read only?

		// IRQs. (FIQ on ARM will be triggered if PENDING and corresponding MASK bits are both SET.)
															
		16'h0040: begin irq0_pend <= irq0_pend |  cpu_din; $display("Write to irq0_pend SET."); end			// 0x40. Writing to 0x40 SETs irq0_pend bits. 
		16'h0044: begin irq0_pend <= irq0_pend & ~cpu_din; $display("Write to irq0_pend CLR."); end			// 0x44. Writing to 0x44 CLEARs irq0_pend bits.
		
		16'h0048: begin irq0_enable <= irq0_enable |  cpu_din; $display("Write to irq0_enable SET."); end	// 0x48. Writing to 0x48 SETs irq0_enable bits.
		16'h004c: begin irq0_enable <= irq0_enable & ~cpu_din; $display("Write to irq0_enable CLR."); end	// 0x4c. Writing to 0x4c CLEARSs irq0_enable bits.

		16'h0050: mode <= mode |  cpu_din;		// 0x50. Writing to 0x50 SETs mode bits.
		16'h0054: mode <= mode & ~cpu_din;		// 0x54. Writing to 0x54 CLEARs mode bits.
		
		16'h0058: badbits <= cpu_din;				// 0x58. for reading things like DMA fail reasons?
		
		16'h005c: spare <= cpu_din;					// 0x5c. ?

															// FIQ will be triggered if PENDING and corresponding ENABLE bits are both SET.
		16'h0060: begin irq1_pend <= irq1_pend |  cpu_din; $display("Write to irq1_pend SET."); end		// 0x60. Writing to 0x60 SETs irq1_pend bits.
		16'h0064: begin irq1_pend <= irq1_pend & ~cpu_din; $display("Write to irq1_pend CLR."); end		// 0x64. Writing to 0x64 CLEARs irq1_pend bits.
		
		16'h0068: begin irq1_enable <= irq1_enable |  cpu_din; $display("Write to irq1_enable SET."); end	// 0x68. Writing to 0x68 SETs irq1_enable bits.
		16'h006c: begin irq1_enable <= irq1_enable & ~cpu_din; $display("Write to irq1_enable CLR."); end	// 0x6c. Writing to 0x6c CLEARSs irq1_enable bits.

		// hdelay / adbio stuff...
		16'h0080: hdelay <= cpu_din;		// 0x80
		16'h0084: adbio_reg <= cpu_din;		// 0x84
		16'h0088: adbctl <= cpu_din;		// 0x88

		// Timers... (timers are handled in each timer module now).
		/*
		16'h0100: tmr_cnt_0  <= cpu_din[15:0];	// 0x100
		// ....
		16'h017c: tmr_bkp_15 <= cpu_din[15:0];	// 0x17c
		*/
		
		16'h0200: tmr_ctrl_l <= (tmr_ctrl_l | cpu_din);		// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
		16'h0204: tmr_ctrl_l <= (tmr_ctrl_l & ~cpu_din);	// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.

		16'h0208: tmr_ctrl_u <= (tmr_ctrl_u | cpu_din);		// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
		16'h020c: tmr_ctrl_u <= (tmr_ctrl_u & ~cpu_din);	// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
		
		16'h0220: slack <= cpu_din;				// 0x220. Only the lower 10 bits get written?

		// 0x304 DMA starter thingy.
		//16'h0304: TODO

		16'h0308: dmareqdis <= cpu_din;	// 0x308 DMA stopper thingy.

		// Only bits 15,14,11,9 are written to in MAME? Opera calls this reg "XBUS Direction"...
		// Opera starts with this -> 0x80; // ARM has the expansion bus.
		16'h0400: /*expctl <= (expctl |  cpu_din)*/;	// 0x400. Writing to 0x400 SETs bits of expctl.
		16'h0404: /*expctl <= (expctl & ~cpu_din)*/;	// 0x404. Writing to 0x404 CLEARs bits of expctl.

		16'h0408: type0_4 <= cpu_din;	// 0x408. ??? Opera doesn't seem to use this, but allows reg writes/reads.

		16'h0410: dipir1 <= cpu_din;	// 0x410. DIPIR (Disc Inserted Provide Interrupt Response) 1?
		16'h0414: dipir2 <= cpu_din;	// 0x414. DIPIR (Disc Inserted Provide Interrupt Response) 2?

		16'h0500: sel_0  <= cpu_din[7:0];	// 0x500
		16'h0504: sel_1  <= cpu_din[7:0];	// 0x504
		16'h0508: sel_2  <= cpu_din[7:0];	// 0x508
		16'h050c: sel_3  <= cpu_din[7:0];	// 0x50c
		16'h0510: sel_4  <= cpu_din[7:0];	// 0x510
		16'h0514: sel_5  <= cpu_din[7:0];	// 0x514
		16'h0518: sel_6  <= cpu_din[7:0];	// 0x518
		16'h051c: sel_7  <= cpu_din[7:0];	// 0x51c
		16'h0520: sel_8  <= cpu_din[7:0];	// 0x520
		16'h0524: sel_9  <= cpu_din[7:0];	// 0x524
		16'h0528: sel_10 <= cpu_din[7:0];	// 0x528
		16'h052c: sel_11 <= cpu_din[7:0];	// 0x52c
		16'h0530: sel_12 <= cpu_din[7:0];	// 0x530
		16'h0534: sel_13 <= cpu_din[7:0];	// 0x534
		16'h0538: sel_14 <= cpu_din[7:0];	// 0x538
		16'h053c: sel_15 <= cpu_din[7:0];	// 0x53c

		16'h0540: /*poll_0  <= cpu_din[7:0]*/;	// 0x540. Assert Poll Status bit after BIOS writes 0x01 to poll..
		16'h0544: poll_1  <= cpu_din[7:0];	// 0x544
		16'h0548: poll_2  <= cpu_din[7:0];	// 0x548
		16'h054c: poll_3  <= cpu_din[7:0];	// 0x54c
		16'h0550: poll_4  <= cpu_din[7:0];	// 0x550
		16'h0554: poll_5  <= cpu_din[7:0];	// 0x554
		16'h0558: poll_6  <= cpu_din[7:0];	// 0x558
		16'h055c: poll_7  <= cpu_din[7:0];	// 0x55c
		16'h0560: poll_8  <= cpu_din[7:0];	// 0x560
		16'h0564: poll_9  <= cpu_din[7:0];	// 0x564
		16'h0568: poll_10 <= cpu_din[7:0];	// 0x568
		16'h056c: poll_11 <= cpu_din[7:0];	// 0x56c
		16'h0570: poll_12 <= cpu_din[7:0];	// 0x570
		16'h0574: poll_13 <= cpu_din[7:0];	// 0x574
		16'h0578: poll_14 <= cpu_din[7:0];	// 0x578
		16'h057c: poll_15 <= cpu_din[7:0];	// 0x57c
		
		// 0x580 - 0x5bf. In Opera, on a write, this calls "opera_xbus_fifo_set_cmd(val_)".
		// 0x5c0 - 0x5ff. In Opera, on a write, this calls "opera_xbus_fifo_set_data(val_)".

		// DSP...
		16'h17d0: sema <= cpu_din;		// 0x17d0. DSP/ARM Semaphore. (can't call it "semaphore", because Verilog / Verilator).
		16'h17d4: semaack <= cpu_din;	// 0x17d4. Semaphore Acknowledge.
		16'h17e0: dspdma <= cpu_din;	// 0x17e0.
		16'h17e4: dspprst0 <= cpu_din;	// 0x17e4. Write triggers DSP reset 0?
		16'h17e8: dspprst1 <= cpu_din;	// 0x17e8. Write triggers DSP reset 1?
		16'h17f4: dspppc <= cpu_din;	// 0x17f4.
		16'h17f8: dsppnr <= cpu_din;	// 0x17f8.
		16'h17fc: dsppgw <= cpu_din;	// 0x17fc. Start / Stop the DSP.

		// 0x1800 - 0x1fff. DSP Mem write.
		// 0x2000 - 0x2fff. DSP Mem write.
		// 0x3000 - 0x33ff. DSP Imem write.
		// 0x3400 - 0x37ff. DSP Imem write.

		16'h39dc: dsppclkreload <= cpu_din;	// 0x39dc. ?

		// UNCLE...
		16'hc000: /*unclerev <= cpu_din*/;		// 0xc000. Opera returns 0x03800000.
		16'hc004: /*unc_soft_rev <= cpu_din*/;	// 0xc004
		16'hc008: uncle_addr <= cpu_din;	// 0xc008
		16'hc00c: uncle_rom <= cpu_din;		// 0xc00c
		
		default: ;
		endcase
	end


	// Timer stuff...	
	if (tmr0_ena_clr)  tmr_ctrl_l[0]  <= 1'b0;
	if (tmr1_ena_clr)  tmr_ctrl_l[4]  <= 1'b0;
	if (tmr2_ena_clr)  tmr_ctrl_l[8]  <= 1'b0;
	if (tmr3_ena_clr)  tmr_ctrl_l[12] <= 1'b0;
	if (tmr4_ena_clr)  tmr_ctrl_l[16] <= 1'b0;
	if (tmr5_ena_clr)  tmr_ctrl_l[20] <= 1'b0;
	if (tmr6_ena_clr)  tmr_ctrl_l[24] <= 1'b0;
	if (tmr7_ena_clr)  tmr_ctrl_l[28] <= 1'b0;
	
	if (tmr8_ena_clr)  tmr_ctrl_u[0]  <= 1'b0;
	if (tmr9_ena_clr)  tmr_ctrl_u[4]  <= 1'b0;
	if (tmr10_ena_clr) tmr_ctrl_u[8]  <= 1'b0;
	if (tmr11_ena_clr) tmr_ctrl_u[12] <= 1'b0;
	if (tmr12_ena_clr) tmr_ctrl_u[16] <= 1'b0;
	if (tmr13_ena_clr) tmr_ctrl_u[20] <= 1'b0;
	if (tmr14_ena_clr) tmr_ctrl_u[24] <= 1'b0;
	if (tmr15_ena_clr) tmr_ctrl_u[28] <= 1'b0;
	

	// irq0_pend bits...
	// Interrupts from timers, only possible from odd (highest in pairs)	
	//
	// bit 10: Timer.1
	// bit 09: Timer.3
	// bit 08: Timer.5
	// bit 07: Timer.7
	// bit 06: Timer.9
	// bit 05: Timer.11
	// bit 04: Timer.13
	// bit 03: Timer.15

	if (tmr1_wrap)  irq0_pend[10] <= 1'b1;
	if (tmr3_wrap)  irq0_pend[09] <= 1'b1;
	if (tmr5_wrap)  irq0_pend[08] <= 1'b1;
	if (tmr7_wrap)  irq0_pend[07] <= 1'b1;
	if (tmr9_wrap)  irq0_pend[06] <= 1'b1;
	if (tmr11_wrap) irq0_pend[05] <= 1'b1;
	if (tmr13_wrap) irq0_pend[04] <= 1'b1;
	if (tmr15_wrap) irq0_pend[03] <= 1'b1;
end

// reg [31:0] tmr_ctrl_l;        // 0x200,0x204. Controls the lower timers 7  (uppermost nibble) through 0 (lowermost nibble).
// reg [31:0] tmr_ctrl_u;        // 0x208,0x20c. Controls the lower timers 15 (uppermost nibble) through 8 (lowermost nibble).

// Bits of each nibble...
//bit 0: decrement / enable
//bit 1: reload - When timer counter reaches zero reload count with “reload” value. If not set then set counter to 0xFFFF and clear decrement / enable bit.
//bit 2: cascade - decremented when the previous timer underflows
//bit 3: flabcode - ?? unknown

wire [3:0] tmr0_ctrl  = tmr_ctrl_l[3:0];
wire [3:0] tmr1_ctrl  = tmr_ctrl_l[7:4];
wire [3:0] tmr2_ctrl  = tmr_ctrl_l[11:8];
wire [3:0] tmr3_ctrl  = tmr_ctrl_l[15:12];
wire [3:0] tmr4_ctrl  = tmr_ctrl_l[19:16];
wire [3:0] tmr5_ctrl  = tmr_ctrl_l[23:20];
wire [3:0] tmr6_ctrl  = tmr_ctrl_l[27:24];
wire [3:0] tmr7_ctrl  = tmr_ctrl_l[31:28];

wire [3:0] tmr8_ctrl  = tmr_ctrl_u[3:0];
wire [3:0] tmr9_ctrl  = tmr_ctrl_u[7:4];
wire [3:0] tmr10_ctrl = tmr_ctrl_u[11:8];
wire [3:0] tmr11_ctrl = tmr_ctrl_u[15:12];
wire [3:0] tmr12_ctrl = tmr_ctrl_u[19:16];
wire [3:0] tmr13_ctrl = tmr_ctrl_u[23:20];
wire [3:0] tmr14_ctrl = tmr_ctrl_u[27:24];
wire [3:0] tmr15_ctrl = tmr_ctrl_u[31:28];

wire timer_cs = {cpu_addr,2'b00}>=16'h0100 && {cpu_addr,2'b00}<=16'h017c;

// cpu_addr[2] goes to all timer blocks, to select either tmr_cnt, or tmr_bkp.
wire tmr0_cs  = timer_cs && (cpu_addr[6:3]==4'd0);		// 0x100, 0x104
wire tmr1_cs  = timer_cs && (cpu_addr[6:3]==4'd1);		// 0x108, 0x10c
wire tmr2_cs  = timer_cs && (cpu_addr[6:3]==4'd2);		// 0x110, 0x114
wire tmr3_cs  = timer_cs && (cpu_addr[6:3]==4'd3);		// 0x118, 0x11c
wire tmr4_cs  = timer_cs && (cpu_addr[6:3]==4'd4);		// 0x120, 0x124
wire tmr5_cs  = timer_cs && (cpu_addr[6:3]==4'd5);		// 0x128, 0x12c
wire tmr6_cs  = timer_cs && (cpu_addr[6:3]==4'd6);		// 0x130, 0x134
wire tmr7_cs  = timer_cs && (cpu_addr[6:3]==4'd7);		// 0x138, 0x13c
wire tmr8_cs  = timer_cs && (cpu_addr[6:3]==4'd8);		// 0x140, 0x144
wire tmr9_cs  = timer_cs && (cpu_addr[6:3]==4'd9);		// 0x148, 0x14c
wire tmr10_cs = timer_cs && (cpu_addr[6:3]==4'd10);		// 0x150, 0x154
wire tmr11_cs = timer_cs && (cpu_addr[6:3]==4'd11);		// 0x158, 0x15c
wire tmr12_cs = timer_cs && (cpu_addr[6:3]==4'd12);		// 0x160, 0x164
wire tmr13_cs = timer_cs && (cpu_addr[6:3]==4'd13);		// 0x168, 0x16c
wire tmr14_cs = timer_cs && (cpu_addr[6:3]==4'd14);		// 0x170, 0x174
wire tmr15_cs = timer_cs && (cpu_addr[6:3]==4'd15);		// 0x178, 0x17c

wire tmr0_ena_clr;
wire tmr1_ena_clr;
wire tmr2_ena_clr;
wire tmr3_ena_clr;
wire tmr4_ena_clr;
wire tmr5_ena_clr;
wire tmr6_ena_clr;
wire tmr7_ena_clr;
wire tmr8_ena_clr;
wire tmr9_ena_clr;
wire tmr10_ena_clr;
wire tmr11_ena_clr;
wire tmr12_ena_clr;
wire tmr13_ena_clr;
wire tmr14_ena_clr;
wire tmr15_ena_clr;

wire tmr0_wrap;
wire tmr1_wrap;
wire tmr2_wrap;
wire tmr3_wrap;
wire tmr4_wrap;
wire tmr5_wrap;
wire tmr6_wrap;
wire tmr7_wrap;
wire tmr8_wrap;
wire tmr9_wrap;
wire tmr10_wrap;
wire tmr11_wrap;
wire tmr12_wrap;
wire tmr13_wrap;
wire tmr14_wrap;
wire tmr15_wrap;


wire [15:0] tmr0_dout;
wire [15:0] tmr1_dout;
wire [15:0] tmr2_dout;
wire [15:0] tmr3_dout;
wire [15:0] tmr4_dout;
wire [15:0] tmr5_dout;
wire [15:0] tmr6_dout;
wire [15:0] tmr7_dout;
wire [15:0] tmr8_dout;
wire [15:0] tmr9_dout;
wire [15:0] tmr10_dout;
wire [15:0] tmr11_dout;
wire [15:0] tmr12_dout;
wire [15:0] tmr13_dout;
wire [15:0] tmr14_dout;
wire [15:0] tmr15_dout;

wire [15:0] tmr_read_mux = (tmr0_cs)  ? tmr0_dout :
						   (tmr1_cs)  ? tmr1_dout :
						   (tmr2_cs)  ? tmr2_dout :
						   (tmr3_cs)  ? tmr3_dout :
						   (tmr4_cs)  ? tmr4_dout :
						   (tmr5_cs)  ? tmr5_dout :
						   (tmr6_cs)  ? tmr6_dout :
						   (tmr7_cs)  ? tmr7_dout :
						   (tmr8_cs)  ? tmr8_dout :
						   (tmr9_cs)  ? tmr9_dout :
						   (tmr10_cs) ? tmr10_dout :
						   (tmr11_cs) ? tmr11_dout :
						   (tmr12_cs) ? tmr12_dout :
						   (tmr13_cs) ? tmr13_dout :
						   (tmr14_cs) ? tmr14_dout :
										tmr15_dout;



clio_timer  tmr0_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr0_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr0_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr0_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr0_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr0_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr0_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr0_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr0_cas )		// input  tmr_cas_clk
);
clio_timer  tmr1_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr1_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr1_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr1_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr1_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr1_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr1_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr1_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr0_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr2_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr2_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr2_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr2_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr2_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr2_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr2_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr2_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr1_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr3_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr3_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr3_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr3_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr3_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr3_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr3_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr3_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr2_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr4_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr4_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr4_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr4_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr4_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr4_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr4_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr4_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr3_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr5_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr5_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr5_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr5_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr5_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr5_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr5_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr5_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr4_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr6_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr6_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr6_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr6_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr6_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr6_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr6_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr6_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr5_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr7_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr7_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr7_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr7_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr7_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr7_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr7_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr7_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr6_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr8_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr8_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr8_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr8_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr8_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr8_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr8_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr8_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr7_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr9_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr9_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr9_dout ),			// output [15:0] tmr_dout
	.tmr_ena( tmr9_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr9_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr9_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr9_wrap ),			// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr9_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr8_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr10_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr10_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr10_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr10_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr10_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr10_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr10_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr10_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr9_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr11_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr11_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr11_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr11_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr11_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr11_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr11_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr11_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr10_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr12_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr12_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr12_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr12_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr12_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr12_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr12_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr12_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr11_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr13_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr13_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr13_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr13_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr13_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr13_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr13_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr13_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr12_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr14_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr14_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr14_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr14_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr14_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr14_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr14_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr14_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr13_wrap )		// input  tmr_cas_clk
);
clio_timer  tmr15_inst (
	.reset_n( reset_n ),			// input  reset_n
	.clock( clk_25m ),				// input  clock
	.tmr_din( cpu_din[15:0] ),		// input  [15:0] tmr_din
	.tmr_a2( cpu_addr[2] ),			// input  tmr_a2
	.tmr_we( tmr15_cs & cpu_wr ),	// input  tmr_we
	.tmr_dout( tmr15_dout ),		// output [15:0] tmr_dout
	.tmr_ena( tmr15_ctrl[0] ),		// input  tmr_ena
	.tmr_reload( tmr15_ctrl[1] ),	// input  tmr_reload
	.tmr_cas_bit( tmr15_ctrl[2] ),	// input  tmr_cas_bit
	.tmr_wrap( tmr15_wrap ),		// output tmr_wrap (pulse)
	.tmr_ena_clr( tmr15_ena_clr ),	// output tmr_ena_clr (pulse)
	.tmr_cas_clk( tmr14_wrap )		// input  tmr_cas_clk
);

endmodule



module clio_timer (
	input reset_n,
	input clock,

	input [15:0] tmr_din,
	input tmr_we,
	
	input tmr_a2,
	output [15:0] tmr_dout,
	
	input tmr_ena,
	input tmr_reload,
	input tmr_cas_bit,
	output reg tmr_wrap,
	output reg tmr_ena_clr,
	
	input tmr_cas_clk
);

// Handle reg reads...
assign tmr_dout = (!tmr_a2) ? tmr_cnt : tmr_bkp;

reg [3:0] tmr_ctrl;
reg [15:0] tmr_cnt;
reg [15:0] tmr_bkp;

// If tmr_cas_bit (from tmr_ctrl) is Low, then just decrement using "clock".
// Else, if tmr_cas_bit is High, then decrement using "tmr_cas_clk".
wire tmr_dec = !tmr_cas_bit || (tmr_cas_bit&&tmr_cas_clk);

always @(posedge clock)
if (!reset_n) begin
	tmr_wrap <= 1'b0;
	tmr_ena_clr <= 1'b0;
	tmr_cnt <= 16'h0000;
	tmr_bkp <= 16'h0000;
end
else begin
	tmr_wrap <= 1'b0;
	tmr_ena_clr <= 1'b0;

	// Handle reg writes.
	if (tmr_we) begin
		if (!tmr_a2) tmr_cnt <= tmr_din;
		else tmr_bkp <= tmr_din;
	end

	if (tmr_ena) begin
		if (tmr_cnt==16'hFFFF) begin			// Timer has wrapped...
			tmr_wrap <= 1'b1;					// PULSE the tmr_wrap bit. (to optionally clock the next timer, via the cascade input).
			if (tmr_reload) tmr_cnt <= tmr_bkp;	// If Reload bit is set, reload the "backup" count value.
			else tmr_ena_clr <= 1'b1;			// If Reload bit is NOT set, PULSE, to clear the Enable bit.
		end
		else if (tmr_dec) tmr_cnt <= tmr_cnt - 1'b1;	// Decrement.
	end
end


endmodule
