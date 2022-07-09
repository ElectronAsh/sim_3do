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
	
	input i_irq,
	input i_firq,

	// Zap...
	output o_wb_stb_nxt,
	output o_wb_cyc_nxt,
	output [31:0] o_wb_adr_nxt,
	output [2:0] o_wb_cti,
	output [1:0] o_wb_bte
);

/*
assign o_wb_sel = 4'hf;
assign o_wb_cyc = 1'b1;
assign o_wb_stb = 1'b1;

wire [4:0] mode;
arm7tdmis_top cpu (
	.CLK(sys_clk),		// input clock
	.nRESET(reset_n),	// input reset

	.ABORT(1'b0),		// input abort
	.PAUSE(1'b0),		// input pause
	.nIRQ(!i_irq),		// input nIRQ
	.nFIQ(!i_firq),		// input nFIQ

	.RDATA(i_wb_dat),	// input [31:0] rdata
	
	.ADDR(o_wb_adr),	// output [31:0] addr
	.WDATA(o_wb_dat),	// output [31:0] wdata
	.WRITE(o_wb_we), 	// output write
	
	.SIZE(o_wb_size),	// output [1:0] size
	.MODE(mode),		// output [4:0] mode
	.PREEMPTABLE(pre)	// output preemptable
);
*/

/*
assign o_wb_cyc = 1;
assign o_wb_stb = 1;

wire [31:0] ram_addr;
wire [31:0] rom_addr;
assign o_wb_adr = ram_cen ? ram_addr : rom_addr;

assign o_wb_we = !ram_wen;

arm9 arm9_inst(
	.clk(sys_clk),				// input clk.
	.cpu_en(1'b1),				// input cpu_en.
	.cpu_restart(1'b0),			// input cpu_restart
	.fiq(i_irq),				// input fiq
	.irq(i_firq),				// input irq
	.ram_abort(1'b0),			// input ram_abort
	.ram_rdata(i_wb_dat),		// input [31:0] ram_rdata.
	.rom_abort(1'b0),			// input rom_abort
	.rom_data(i_wb_dat),		// input [31:0] rom_data.
	.rst(!reset_n),				// input rst.

	.ram_addr(ram_addr),		// output [31:0] ram_addr.
	.ram_cen(ram_cen),			// output ram_cen.
	.ram_flag(o_wb_sel),		// output [3:0] ram_flag.
	.ram_wdata(o_wb_dat),		// output [31:0] ram_wdata.
	.ram_wen(ram_wen),			// output ram_wen
	.rom_addr(rom_addr),		// output [31:0] rom_addr.
	.rom_en(rom_en)				// output rom_en.
);
*/

/*
assign o_wb_cyc = mem_read || o_wb_we;
assign o_wb_stb = mem_read || o_wb_we;
assign o_wb_sel = 4'hf;

// NOTE: The multiplier blocks are currently commented out in this CPU core! ElectronAsh.
// (they are using the Altera/Intel multiplier IP blocks.)

cpu_armv4t cpu_armv4t_inst (
	.clk(sys_clk),				// input clk
	.rstn(reset_n),				// input rstn
	
	.mem_addr(o_wb_adr),		// output [31:0] mem_addr.
	.mem_width(mem_width),		// output [1:0] mem_width
	
	.mem_data_in(i_wb_dat),		// input [31:0] mem_data_in.
	.mem_read(mem_read),		// output mem_read	
	
	.mem_data_out(o_wb_dat),	// output [31:0] mem_data_out.
	.mem_write(o_wb_we),		// output mem_write
	
	.mem_ok(i_wb_ack),			// input mem_ok

	.mult_wait_time(5'd2)		// input [4:0] mult_wait_time
);
*/

// Note: The Verilator ifdef in sram_byte_en.v doesn't have Byte Enables yet, but a23_cache.v is the
// only place that uses sram_byte_en.v, and it sets the byte enables to {CACHE_LINE_WIDTH/8{1'd1}}
//
// CACHE_LINE_WIDTH is set to 128. So that will replicate the 1'd1 for 16 bits (all byte enables forced ON).
// Probably fine as-is for simulation. ElectronAsh.
//
/*
a23_core a23_core_inst (
	.i_clk(sys_clk),			// input  i_clk
	.i_reset(!reset_n),			// input  i_reset
	
	.i_irq(i_irq),				// input  Interrupt request, active high
	.i_firq(i_firq),			// input  Fast Interrupt request, active high
	
	.i_system_rdy(reset_n),		// input  Amber is stalled when this is low
	
	// Wishbone Master I/F
	.o_wb_adr(o_wb_adr),		// output [31:0] o_wb_adr
	.o_wb_sel(o_wb_sel),		// output [3:0]  
	.o_wb_we(o_wb_we),			// output  
	.i_wb_dat(i_wb_dat),		// input [31:0]  
	.o_wb_dat(o_wb_dat),		// output [31:0]  
	.o_wb_cyc(o_wb_cyc),		// output  
	.o_wb_stb(o_wb_stb),		// output  
	.i_wb_ack(i_wb_ack),		// input  
	//.o_wb_tga(o_wb_tga),		// output
	.i_wb_err(1'b0)				// input
);
*/

zap_top zap_top_inst (
	.i_clk(sys_clk),	// input
	.i_reset(!reset_n),	// input Active HIGH.

	.i_irq(1'b0),		// Active HIGH. (not used on 3DO).
	.i_fiq(i_firq),		// Active HIGH.

	.o_wb_cyc(o_wb_cyc),		// output
	.o_wb_stb(o_wb_stb),		// output
	.o_wb_stb_nxt(o_wb_stb_nxt),// output	not used atm.
	.o_wb_cyc_nxt(o_wb_cyc_nxt),// output	not used atm.
	.o_wb_adr_nxt(o_wb_adr_nxt),// output [31:0]  not used atm.
	.o_wb_adr(o_wb_adr),		// output [31:0]
	.o_wb_we(o_wb_we),			// output
	.o_wb_dat(o_wb_dat),		// output [31:0]
	.o_wb_sel(o_wb_sel),		// output [3:0]
	.o_wb_cti(o_wb_cti),		// output [2:0]	not used atm.
	.o_wb_bte(o_wb_bte),		// output [1:0]	not used atm.
	.i_wb_ack(i_wb_ack),		// input
	.i_wb_dat(i_wb_dat)			// input [31:0]
);


matrix_engine matrix_inst (
	.clock(sys_clk)
);


// Fixel code stuffs...
/*
always @(posedge clk)
  if (reset) cstatbits<=cstatbits|11'h1;
  else if (wdgrst) cstatbits<=cstatbits|11'h2;

  else if (dipir) cstatbits<=cstatbits|11'h40;
  else if (cstabits_wr) cstatbits<=(cstatbits&(top->i_wb_dat&11h63))|(top->i_wb_dat&11'h10);
*/
  

endmodule
