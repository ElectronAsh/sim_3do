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
	
	output [21:00] vram_addr,
	output vram_rd,
	output vram_wr,
	output [31:0] vram_w_dat,
	input [31:0] vram_r_dat,
	
	input vram_busy
);


wire irq0_trig = |({any_irq1,irq0_pend[30:0]} & irq0_enable);	// Bit 31 of irq0_pend denotes one or more irq1_pend bits are set. I think irq0_enable[31] can also mask that bit?

wire irq1_trig = |(irq1_pend & irq1_enable); // bitwise OR, after masking irq1_pend with the irq1_enable bits.
wire any_irq1 = |irq1_pend;	// bitwise OR of irq1_pend, to see if ANY of the bits are set. 

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
reg [31:0] timer_count_0;	 // 0x100
reg [31:0] timer_backup_0;	 // 0x104
reg [31:0] timer_count_1;	 // 0x108
reg [31:0] timer_backup_1;	 // 0x10c
reg [31:0] timer_count_2;	 // 0x110
reg [31:0] timer_backup_2;	 // 0x114
reg [31:0] timer_count_3;	 // 0x118
reg [31:0] timer_backup_3;	 // 0x11c
reg [31:0] timer_count_4;	 // 0x120
reg [31:0] timer_backup_4;	 // 0x124
reg [31:0] timer_count_5;	 // 0x128
reg [31:0] timer_backup_5;	 // 0x12c
reg [31:0] timer_count_6;	 // 0x130
reg [31:0] timer_backup_6;	 // 0x134
reg [31:0] timer_count_7;	 // 0x138
reg [31:0] timer_backup_7;	 // 0x13c
reg [31:0] timer_count_8;	 // 0x140
reg [31:0] timer_backup_8;	 // 0x144
reg [31:0] timer_count_9;	 // 0x148
reg [31:0] timer_backup_9;	 // 0x14c
reg [31:0] timer_count_10;	 // 0x150
reg [31:0] timer_backup_10;	 // 0x154
reg [31:0] timer_count_11;	 // 0x158
reg [31:0] timer_backup_11;	 // 0x15c
reg [31:0] timer_count_12;	 // 0x160
reg [31:0] timer_backup_12;	 // 0x164
reg [31:0] timer_count_13;	 // 0x168
reg [31:0] timer_backup_13;	 // 0x16c
reg [31:0] timer_count_14;	 // 0x170
reg [31:0] timer_backup_14;	 // 0x174
reg [31:0] timer_count_15;	 // 0x178
reg [31:0] timer_backup_15;	 // 0x17c

// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.
// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
reg [63:0] timer_ctrl;		// 0x200,0x204,0x208,0x20c. 64-bits wide??

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

reg [31:0] sel_0;	// 0x500
reg [31:0] sel_1;	// 0x504
reg [31:0] sel_2;	// 0x508
reg [31:0] sel_3;	// 0x50c
reg [31:0] sel_4;	// 0x510
reg [31:0] sel_5;	// 0x514
reg [31:0] sel_6;	// 0x518
reg [31:0] sel_7;	// 0x51c
reg [31:0] sel_8;	// 0x520
reg [31:0] sel_9;	// 0x524
reg [31:0] sel_10;	// 0x528
reg [31:0] sel_11;	// 0x52c
reg [31:0] sel_12;	// 0x530
reg [31:0] sel_13;	// 0x534
reg [31:0] sel_14;	// 0x538
reg [31:0] sel_15;	// 0x53c

reg [31:0] poll_0;	// 0x540
reg [31:0] poll_1;	// 0x544
reg [31:0] poll_2;	// 0x548
reg [31:0] poll_3;	// 0x54c
reg [31:0] poll_4;	// 0x550
reg [31:0] poll_5;	// 0x554
reg [31:0] poll_6;	// 0x558
reg [31:0] poll_7;	// 0x55c
reg [31:0] poll_8;	// 0x560
reg [31:0] poll_9;	// 0x564
reg [31:0] poll_10;	// 0x568
reg [31:0] poll_11;	// 0x56c
reg [31:0] poll_12;	// 0x570
reg [31:0] poll_13;	// 0x574
reg [31:0] poll_14;	// 0x578
reg [31:0] poll_15;	// 0x57c

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
reg [31:0] unclerev;		// 0xc000. Opera returns 0x03800000.
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
	16'h0084: cpu_dout = adbio_reg;		// 0x84
	16'h0088: cpu_dout = adbctl;		// 0x88


// Timers...
	16'h0100: cpu_dout = timer_count_0;		// 0x100
	16'h0104: cpu_dout = timer_backup_0;	// 0x104
	16'h0108: cpu_dout = timer_count_1;		// 0x108
	16'h010c: cpu_dout = timer_backup_1;	// 0x10c
	16'h0110: cpu_dout = timer_count_2;		// 0x110
	16'h0114: cpu_dout = timer_backup_2;	// 0x114
	16'h0118: cpu_dout = timer_count_3;		// 0x118
	16'h011c: cpu_dout = timer_backup_3;	// 0x11c
	16'h0120: cpu_dout = timer_count_4;		// 0x120
	16'h0124: cpu_dout = timer_backup_4;	// 0x124
	16'h0128: cpu_dout = timer_count_5;		// 0x128
	16'h012c: cpu_dout = timer_backup_5;	// 0x12c
	16'h0130: cpu_dout = timer_count_6;		// 0x130
	16'h0134: cpu_dout = timer_backup_6;	// 0x134
	16'h0138: cpu_dout = timer_count_7;		// 0x138
	16'h013c: cpu_dout = timer_backup_7;	// 0x13c
	16'h0140: cpu_dout = timer_count_8;		// 0x140
	16'h0144: cpu_dout = timer_backup_8;	// 0x144
	16'h0148: cpu_dout = timer_count_9;		// 0x148
	16'h014c: cpu_dout = timer_backup_9;	// 0x14c
	16'h0150: cpu_dout = timer_count_10;	// 0x150
	16'h0154: cpu_dout = timer_backup_10;	// 0x154
	16'h0158: cpu_dout = timer_count_11;	// 0x158
	16'h015c: cpu_dout = timer_backup_11;	// 0x15c
	16'h0160: cpu_dout = timer_count_12;	// 0x160
	16'h0164: cpu_dout = timer_backup_12;	// 0x164
	16'h0168: cpu_dout = timer_count_13;	// 0x168
	16'h016c: cpu_dout = timer_backup_13;	// 0x16c
	16'h0170: cpu_dout = timer_count_14;	// 0x170
	16'h0174: cpu_dout = timer_backup_14;	// 0x174
	16'h0178: cpu_dout = timer_count_15;	// 0x178
	16'h017c: cpu_dout = timer_backup_15;	// 0x17c

// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.
// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
	16'h0200: cpu_dout = timer_ctrl;		// 0x200,0x204,0x208,0x20c. 64-bits wide?? TODO: How to handle READS of the 64-bit reg?

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

	// opera_xbus_get_res(); ...
	16'h0500: cpu_dout = sel_0;		// 0x500
	16'h0504: cpu_dout = sel_1;		// 0x504
	16'h0508: cpu_dout = sel_2;		// 0x508
	16'h050c: cpu_dout = sel_3;		// 0x50c
	16'h0510: cpu_dout = sel_4;		// 0x510
	16'h0514: cpu_dout = sel_5;		// 0x514
	16'h0518: cpu_dout = sel_6;		// 0x518
	16'h051c: cpu_dout = sel_7;		// 0x51c
	16'h0520: cpu_dout = sel_8;		// 0x520
	16'h0524: cpu_dout = sel_9;		// 0x524
	16'h0528: cpu_dout = sel_10;	// 0x528
	16'h052c: cpu_dout = sel_11;	// 0x52c
	16'h0530: cpu_dout = sel_12;	// 0x530
	16'h0534: cpu_dout = sel_13;	// 0x534
	16'h0538: cpu_dout = sel_14;	// 0x538
	16'h053c: cpu_dout = sel_15;	// 0x53c

	// opera_xbus_get_poll(); ...
	16'h0540: cpu_dout = poll_0;	// 0x540
	16'h0544: cpu_dout = poll_1;	// 0x544
	16'h0548: cpu_dout = poll_2;	// 0x548
	16'h054c: cpu_dout = poll_3;	// 0x54c
	16'h0550: cpu_dout = poll_4;	// 0x550
	16'h0554: cpu_dout = poll_5;	// 0x554
	16'h0558: cpu_dout = poll_6;	// 0x558
	16'h055c: cpu_dout = poll_7;	// 0x55c
	16'h0560: cpu_dout = poll_8;	// 0x560
	16'h0564: cpu_dout = poll_9;	// 0x564
	16'h0568: cpu_dout = poll_10;	// 0x568
	16'h056c: cpu_dout = poll_11;	// 0x56c
	16'h0570: cpu_dout = poll_12;	// 0x570
	16'h0574: cpu_dout = poll_13;	// 0x574
	16'h0578: cpu_dout = poll_14;	// 0x578
	16'h057c: cpu_dout = poll_15;	// 0x57c

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
	16'hc000: cpu_dout = unclerev;		// 0xc000. Opera returns 0x03800000.
	16'hc004: cpu_dout = unc_soft_rev;	// 0xc004
	16'hc008: cpu_dout = uncle_addr;	// 0xc008
	16'hc00c: cpu_dout = uncle_rom;		// 0xc00c
	
	default: cpu_dout = 32'hBADACCE5;	// default case.
	endcase
end

reg [5:0] clk_div;
always @(posedge clk_25m) clk_div <= clk_div + 1;

wire timer_tick = (clk_div==0);


wire wdgrst = 0;
wire dipir = 0;

wire [31:0] hcnt_max = 32'd1590;
wire [31:0] vcnt_max = 32'd262;
reg field;

always @(posedge clk_25m or negedge reset_n)
if (!reset_n) begin
	revision <= 32'h02020000;		// Opera returns 0x02020000.
	//revision <= 32'h02022000;		// Latest MAME returns 0x02022000 with panafz10 BIOS.
	//cstatbits[0] <= 1'b1;			// Set bit 0 (POR). fixel said to start with this bit set only.
	//cstatbits[6] <= 1'b1;			// Set bit 6 (DIPIR). TESTING !!
	cstatbits <= 32'h00000040;		// This is the first value read from cstatbits by the Opera emulator!
	expctl <= 32'h00000080;
	field <= 1'b1;
	hcnt <= 32'd0;
	vcnt <= 32'd0;
	
	dipir2 <= 32'h00004000;			// This is the first value read from dipir2 by the Opera emulator!
	poll_0 <= 32'h0000000F;			// Spoofing value from Opera log atm.
	
	adbio_reg <= 32'h00000062;
	//adbio_reg <= 32'h00000000;
	
	irq0_pend <= 32'h00000000;
	irq0_enable <= 32'h00000000;
	irq1_pend <= 32'h00000000;
	irq1_enable <= 32'h00000000;
end
else begin
	if ( hcnt==32'd0 && vcnt==(vint0&11'h7FF) ) irq0_pend[0] <= 1'b1;	// vint0 is on irq0, bit 0.
	if ( hcnt==32'd0 && vcnt==(vint1&11'h7FF) ) irq0_pend[1] <= 1'b1;	// vint1 is on irq0, bit 1.

	if (hcnt==hcnt_max) begin
		hcnt <= 32'd0;
		
		//if ( irq0_enable[0] && vcnt==(vint0&32'h000007FF) ) irq0_pend[0] <= 1'b1;	// vint0 is on irq0, bit 0.
		//if ( irq0_enable[1] && vcnt==(vint1&32'h000007FF) ) irq0_pend[1] <= 1'b1;	// vint1 is on irq0, bit 1.

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
	
	if (timer_count_0>0  && timer_tick) timer_count_0 <= timer_count_0 - 1;
	if (timer_count_1>0  && timer_tick) timer_count_1 <= timer_count_1 - 1;
	if (timer_count_2>0  && timer_tick) timer_count_2 <= timer_count_2 - 1;
	if (timer_count_3>0  && timer_tick) timer_count_3 <= timer_count_3 - 1;
	if (timer_count_4>0  && timer_tick) timer_count_4 <= timer_count_4 - 1;
	if (timer_count_5>0  && timer_tick) timer_count_5 <= timer_count_5 - 1;
	if (timer_count_6>0  && timer_tick) timer_count_6 <= timer_count_6 - 1;
	if (timer_count_7>0  && timer_tick) timer_count_7 <= timer_count_7 - 1;
	if (timer_count_8>0  && timer_tick) timer_count_8 <= timer_count_8 - 1;
	if (timer_count_9>0  && timer_tick) timer_count_9 <= timer_count_9 - 1;
	if (timer_count_10>0 && timer_tick) timer_count_10 <= timer_count_10 - 1;
	if (timer_count_11>0 && timer_tick) timer_count_11 <= timer_count_11 - 1;
	if (timer_count_12>0 && timer_tick) timer_count_12 <= timer_count_12 - 1;
	if (timer_count_13>0 && timer_tick) timer_count_13 <= timer_count_13 - 1;
	if (timer_count_14>0 && timer_tick) timer_count_14 <= timer_count_14 - 1;
	if (timer_count_15>0 && timer_tick) timer_count_15 <= timer_count_15 - 1;
	
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
													
16'h0040: begin irq0_pend <= irq0_pend |  cpu_din; $display("Write to irq0_pend SET."); end				// 0x40. Writing to 0x40 SETs irq0_pend bits. 
16'h0044: begin irq0_pend <= irq0_pend & ~cpu_din; $display("Write to irq0_pend CLR."); end				// 0x44. Writing to 0x44 CLEARs irq0_pend bits.

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
		16'h0084: adbio_reg  <= cpu_din;	// 0x84
		16'h0088: adbctl <= cpu_din;		// 0x88

		// Timers...
		16'h0100: timer_count_0   <= cpu_din;	// 0x100
		16'h0104: timer_backup_0  <= cpu_din;	// 0x104
		16'h0108: timer_count_1   <= cpu_din;	// 0x108
		16'h010c: timer_backup_1  <= cpu_din;	// 0x10c
		16'h0110: timer_count_2   <= cpu_din;	// 0x110
		16'h0114: timer_backup_2  <= cpu_din;	// 0x114
		16'h0118: timer_count_3   <= cpu_din;	// 0x118
		16'h011c: timer_backup_3  <= cpu_din;	// 0x11c
		16'h0120: timer_count_4   <= cpu_din;	// 0x120
		16'h0124: timer_backup_4  <= cpu_din;	// 0x124
		16'h0128: timer_count_5   <= cpu_din;	// 0x128
		16'h012c: timer_backup_5  <= cpu_din;	// 0x12c
		16'h0130: timer_count_6   <= cpu_din;	// 0x130
		16'h0134: timer_backup_6  <= cpu_din;	// 0x134
		16'h0138: timer_count_7   <= cpu_din;	// 0x138
		16'h013c: timer_backup_7  <= cpu_din;	// 0x13c
		16'h0140: timer_count_8   <= cpu_din;	// 0x140
		16'h0144: timer_backup_8  <= cpu_din;	// 0x144
		16'h0148: timer_count_9   <= cpu_din;	// 0x148
		16'h014c: timer_backup_9  <= cpu_din;	// 0x14c
		16'h0150: timer_count_10  <= cpu_din;	// 0x150
		16'h0154: timer_backup_10 <= cpu_din;	// 0x154
		16'h0158: timer_count_11  <= cpu_din;	// 0x158
		16'h015c: timer_backup_11 <= cpu_din;	// 0x15c
		16'h0160: timer_count_12  <= cpu_din;	// 0x160
		16'h0164: timer_backup_12 <= cpu_din;	// 0x164
		16'h0168: timer_count_13  <= cpu_din;	// 0x168
		16'h016c: timer_backup_13 <= cpu_din;	// 0x16c
		16'h0170: timer_count_14  <= cpu_din;	// 0x170
		16'h0174: timer_backup_14 <= cpu_din;	// 0x174
		16'h0178: timer_count_15  <= cpu_din;	// 0x178
		16'h017c: timer_backup_15 <= cpu_din;	// 0x17c

		16'h0200: timer_ctrl[31:00] <= (timer_ctrl[31:00] | cpu_din);	// Writing to 0x200 SETs the LOWER 32-bits of timer_ctrl.
		16'h0204: timer_ctrl[31:00] <= (timer_ctrl[31:00] & ~cpu_din);	// Writing to 0x204 CLEARs the LOWER 32-bits of timer_ctrl.

		16'h0208: timer_ctrl[63:32] <= (timer_ctrl[63:32] | cpu_din);	// Writing to 0x208 SETs the UPPER 32-bits of timer_ctrl.
		16'h020c: timer_ctrl[63:32] <= (timer_ctrl[63:32] & ~cpu_din);	// Writing to 0x20c CLEARs the UPPER 32-bits of timer_ctrl.
		
		16'h0220: slack <= cpu_din;				// 0x220. Only the lower 10 bits get written?

		// 0x304 DMA starter thingy.
		//16'h0304: TODO

		16'h0308: dmareqdis <= cpu_din;	// 0x308 DMA stopper thingy.

		// Only bits 15,14,11,9 are written to in MAME? Opera calls this reg "XBUS Direction"...
		// Opera starts with this -> 0x80; /* ARM has the expansion bus */
		16'h0400: expctl <= (expctl |  cpu_din);	// 0x400. Writing to 0x400 SETs bits of expctl.
		16'h0404: expctl <= (expctl & ~cpu_din);	// 0x404. Writing to 0x404 CLEARs bits of expctl.

		16'h0408: type0_4 <= cpu_din;	// 0x408. ??? Opera doesn't seem to use this, but allows reg writes/reads.

		16'h0410: dipir1 <= cpu_din;	// 0x410. DIPIR (Disc Inserted Provide Interrupt Response) 1?
		16'h0414: dipir2 <= cpu_din;	// 0x414. DIPIR (Disc Inserted Provide Interrupt Response) 2?

		16'h0500: sel_0 <= cpu_din;		// 0x500
		16'h0504: sel_1 <= cpu_din;		// 0x504
		16'h0508: sel_2 <= cpu_din;		// 0x508
		16'h050c: sel_3 <= cpu_din;		// 0x50c
		16'h0510: sel_4 <= cpu_din;		// 0x510
		16'h0514: sel_5 <= cpu_din;		// 0x514
		16'h0518: sel_6 <= cpu_din;		// 0x518
		16'h051c: sel_7 <= cpu_din;		// 0x51c
		16'h0520: sel_8 <= cpu_din;		// 0x520
		16'h0524: sel_9 <= cpu_din;		// 0x524
		16'h0528: sel_10 <= cpu_din;	// 0x528
		16'h052c: sel_11 <= cpu_din;	// 0x52c
		16'h0530: sel_12 <= cpu_din;	// 0x530
		16'h0534: sel_13 <= cpu_din;	// 0x534
		16'h0538: sel_14 <= cpu_din;	// 0x538
		16'h053c: sel_15 <= cpu_din;	// 0x53c

		16'h0540: poll_0 <= cpu_din;	// 0x540
		16'h0544: poll_1 <= cpu_din;	// 0x544
		16'h0548: poll_2 <= cpu_din;	// 0x548
		16'h054c: poll_3 <= cpu_din;	// 0x54c
		16'h0550: poll_4 <= cpu_din;	// 0x550
		16'h0554: poll_5 <= cpu_din;	// 0x554
		16'h0558: poll_6 <= cpu_din;	// 0x558
		16'h055c: poll_7 <= cpu_din;	// 0x55c
		16'h0560: poll_8 <= cpu_din;	// 0x560
		16'h0564: poll_9 <= cpu_din;	// 0x564
		16'h0568: poll_10 <= cpu_din;	// 0x568
		16'h056c: poll_11 <= cpu_din;	// 0x56c
		16'h0570: poll_12 <= cpu_din;	// 0x570
		16'h0574: poll_13 <= cpu_din;	// 0x574
		16'h0578: poll_14 <= cpu_din;	// 0x578
		16'h057c: poll_15 <= cpu_din;	// 0x57c
		
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
		16'hc000: unclerev <= cpu_din;		// 0xc000. Opera returns 0x03800000.
		16'hc004: unc_soft_rev <= cpu_din;// 0xc004
		16'hc008: uncle_addr <= cpu_din;	// 0xc008
		16'hc00c: uncle_rom <= cpu_din;		// 0xc00c
		
		default: ;
		endcase
	end
end

endmodule
