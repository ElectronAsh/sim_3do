`timescale 1 ns / 1 ns

module core_3do (
	input reset_n,
	input sys_clk,
	
	output [31:0] o_wb_adr,
	output [31:0] o_wb_dat,
	output [3:0] o_wb_sel,
	output o_wb_we,
	output o_wb_cyc,
	output o_wb_stb,
	output o_wb_tga,
	
	input [31:0] i_wb_dat,
	input i_wb_ack,

	// Zap...
	output o_wb_stb_nxt,
	output o_wb_cyc_nxt,
	output [31:0] o_wb_adr_nxt,
	output [2:0] o_wb_cti,
	output [1:0] o_wb_bte,
	
	output [23:0] rgb_out
);

`define DEBUG_EN 1


zap_top zap_top_inst (
	.i_clk( sys_clk ),				// input. Should probably be 12.5 MHz, but using sys_clk, for faster simulation.
	
	.i_reset( !reset_n ),			// input Active HIGH.

	.i_irq( 1'b0 ),					// Active HIGH. (not used on 3DO).
	.i_fiq( !firq_n ),				// Active HIGH.

	.o_wb_cyc( o_wb_cyc ),			// output
	.o_wb_stb( o_wb_stb ),			// output
	//.o_wb_stb_nxt( o_wb_stb_nxt ),	// output	not used atm.
	//.o_wb_cyc_nxt( o_wb_cyc_nxt ),	// output	not used atm.
	//.o_wb_adr_nxt( o_wb_adr_nxt ),	// output [31:0]  not used atm.
	.o_wb_adr( o_wb_adr ),			// output [31:0]
	.o_wb_we( o_wb_we ),			// output
	.o_wb_dat( o_wb_dat ),			// output [31:0]
	.o_wb_sel( o_wb_sel ),			// output [3:0]
	.o_wb_cti( o_wb_cti ),			// output [2:0]	not used atm.
	.o_wb_bte( o_wb_bte ),			// output [1:0]	not used atm.
	.i_wb_ack( i_wb_ack ),			// input
	.i_wb_dat( zap_din )			// input [31:0]
	//.i_wb_dat( i_wb_dat )			// input [31:0]
);

wire [31:0] zap_din;


clio clio_inst (
	.clk_25m( sys_clk ),	// input. 
	.reset_n( reset_n ),	// input. Active-LOW! Technically, RESET_N on CLIO is an OUTPUT to other stuff.
	
	//.pon( !reset_n ),		// input. Power ON Reset input. (not really needed).
	
	.ad( rgb_out ),			// output [23:0]. Pixel data to DAC/encoder. R/G/B order!
	
	//.amyctl( amyctl ),	// output. Color Encoder (DAC) control signal.
	//.tmuxsel( tmuxsel ),	// output. Pixel clock to DAC? 12.2727 MHz.
	//.blank_n( blank_n ),	// input. Blanking FROM DAC?
	//.vsync_n( vsync_n ),	// input. FROM the DAC.
	//.hsync_n( hsync_n ),	// input. FROM the DAC.
	
	//.wdin( wdin ),		// input. Watchdog Timer C/R input. (analog stuffs. Not needed).
	//.wdres_n( wdres_n ),	// output. Watchdog Timer Reset output.
	
	//.ed_in( ed_in ),		// input [7:0] Expansion Bus Data input. CD-ROM Gate Array access.
	//.ed_out( ed_out ),	// output [7:0] Expansion Bus Data output.
	//.estr_n( estr_n ),	// output. Expansion Bus Strobe signal.
	//.ewrt_n( ewrt_n ),	// output. Expansion Bus Write signal.
	//.erst_n( erst_n ),	// output. Expansion Bus Reset signal.
	//.ecmd_n( ecmd_n ),	// output. Expansion Bus Command signal.
	//.esel_n( esel_n ),	// output. Expansion Bus Select signal.
	//.erdy_n( erdy_n ),	// input. Expansion Bus Ready input.
	//.eint_n( eint_n ),	// input. Expansion Bus Interrupt input.
	
	//.auddat( auddat ),	// output. Audio Data output.
	//.audws( audws ),		// output. Audio Word Sync (Left/Right sync).
	//.audbck( audbck ),	// output. Audio Bit Clock.
	//.xaclk( xaclk ),		// output. Audio DAC Master Clock?
	
	//.serclk( serclk ),	// inout. Serial Audio INPUT port.
	//.serdat( serdat ),	// inout. All tied LOW on the FZ1 schematic!
	//.serr( serr ),		// inout. 
	//.serl( serl ),		// inout. 

	//.extreq_r( extreq_r ),	// Audio DMA Read request. FMV?
	//.extreq_w( extreq_w ),	// Audio DMA Write request. FMV?
	//.extack_r( extack_r ),	// Audio DMA Read Acknowledge. FMV?
	//.extack_w( extack_w ),	// Audio DMA Write Acknowledge. FMV?

	//.adbio( adbio ),		// inout [3:0]. adbio bus.	
	
	//.lpsc( lpsc ),		// Left-hand VRAM SC clock.
	//.rpsc( rpsc ),		// Right-hand VRAM SC clock.
	
	.s_din(  ),				// input [31:00]. S-Bus from VRAM.
	.s_dout(  ),			// output [31:00]. S-Bus to VRAM.
	
	.cpu_addr( o_wb_adr[15:02] ),	// input [15:02]. CLIO does NOT have a full connection to the CPU Addr bus.
	
	.cpu_din( o_wb_dat ),		// input [31:00] FROM the ARM CPU.
	.cpu_dout( clio_dout ),		// output [31:00] TO the ARM CPU.
	
	.cpu_rd( clio_cs & o_wb_stb & !o_wb_we ),	// In reality, the only mechanism I can see for CLIO reg access, are the three CLC[2:0] pins that come from MADAM.
	.cpu_wr( clio_cs & o_wb_stb &  o_wb_we ),	// so there are no "direct" read/write pins from the CPU to the CLIO chip, it's all controlled via MADAM.
	
	//.pcsc_n(  ),			// To MADAM. (the main synchronizing signal).
	//.dmareq(  ),			// To MADAM?
	
	//.pdint_n(  ),			// Labelled "UNCINT#" on the FZ1 schematic. Slow Bus Interrupt?
	.firq_n( firq_n ),		// To the ARM CPU.
	
	//.clc( clc ),			// output [2:0] CLIO Opera Device bits? Tech guide calls this "Control Code". Probably works like the RGA bus on the Amiga?
	//.cready_n( cready_n ),// inout. Tech guide calls this "Hand shake control for devices".
	
	//.uncreqw( uncreqw ),	// inout. Video DMA Write request. FMV? UN - Uncle Chip.
	//.uncreqr( uncreqr ),	// inout. Video DMA Read request. FMV? UN - Uncle Chip.
	//.uncackw( uncackw ),	// inout. Video DMA Write Acknowledge. FMV? UN - Uncle Chip.
	//.uncackr( uncackr )	// inout. Video DMA Read Acknowledge. FMV? UN - Uncle Chip.
);

madam madam_inst (
	.clk_25m( sys_clk ),
	.reset_n( reset_n ),
	
	.cpu_addr( o_wb_adr ),	// input [31:00].
	
	.cpu_din( o_wb_dat ),			// input [31:00] FROM the ARM CPU.
	.cpu_dout( madam_dout ),		// output [31:00] TO the ARM CPU.
	
	.cpu_rd( madam_cs & o_wb_stb & !o_wb_we ),
	.cpu_wr( madam_cs & o_wb_stb &  o_wb_we ),

	//.ram_addr( ram_addr ),	// output [22:0].
	//.ram_din( ram_din ),	// input [31:0].
	//.ram_dout( ram_dout ),	// output [31:0].
	//.ram_wen( ram_wen ),	// output.
	
	//.pcsc( pcsc ),		// input.
	
	.lpsc_n( lpsc_n ), 	// output. Right-hand VRAM SAM strobe. (pixel or VDL data is on S-bus[31:16]).
	.rpsc_n( rpsc_n ) 	// output. Left-hand VRAM SAM strobe.  (pixel or VDL data is on S-bus[15:00]).
);

wire [31:0] madam_dout;
wire [31:0] clio_dout;

wire svf_cs   = (o_wb_adr>=32'h03200000 && o_wb_adr<=32'h0320FFFF);
wire madam_cs = (o_wb_adr>=32'h03300000 && o_wb_adr<=32'h0330FFFF);
wire unc_cs   = (o_wb_adr>=32'h0340c000 && o_wb_adr<=32'h0340c00f);
wire clio_cs  = (o_wb_adr>=32'h03400000 && o_wb_adr<=32'h0340FFFF);

assign zap_din = (madam_cs) ? madam_dout :
				 (unc_cs) ? 32'h00000000 :
				 (clio_cs)  ? clio_dout :
								i_wb_dat;	// Else, take input from the C code in the sim. (TESTING, for BIOS, DRAM, VRAM, NVRAM, SVF etc.)


/*
matrix_engine matrix_inst (
	.clock(sys_clk)
);
*/

endmodule
