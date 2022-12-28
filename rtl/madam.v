//
// 3DO MADAM chip implementation / notes. ElectronAsh, Jan 2022.
//
// MADAM contains: ARM CPU interface, DRAM/VRAM Address control, VRAM SPORT control (probably), DMA Engine, CEL Engine,
// Matrix Engine, Main timings for pixel/VDL/CCB access, P-Bus (joyport), "PD" bus (Slow bus??) for BIOS / SRAM / DAC access.
//
//
module madam (
	input clk_25m,
	input reset_n,
	
	input [31:0] cpu_addr,
	input [31:0] cpu_din,
	input cpu_rd,
	input cpu_wr,
	output reg [31:0] cpu_dout,
	
	output reg cpu_clk,
	
	output [21:0] mem_addr,	
	input [31:0] mem_din,
	output mem_rd,
	output mem_wr,
	output [31:0] mem_dout,
	
	output dram_cs,
	output vram_cs,
	output bios_cs,
	
	input pcsc,
	
	output reg lpsc_n, 		// Right-hand VRAM SAM strobe. (pixel or VDL data is on S-bus[31:16]).
	output reg rpsc_n, 		// Left-hand VRAM SAM strobe.  (pixel or VDL data is on S-bus[15:00]).
	
	input [4:0] dma_req,	// Parallel version of dmareq on the original MADAM chip.
	output reg dma_ack
);

assign mem_addr = (dma_req>5'd0 && dma_ack) ? dma_addr : cpu_addr[21:0];
assign mem_dout = (dma_req>5'd0 && dma_ack) ? dma_dout : cpu_dout;
assign mem_rd   = (dma_req>5'd0 && dma_ack) ? dma_rd : cpu_rd;
assign mem_wr   = (dma_req>5'd0 && dma_ack) ? dma_wr : cpu_wr;

reg [21:0] dma_addr;
wire [31:0] dma_dout;
reg dma_rd;
reg dma_wr;


assign dram_cs = (cpu_addr>=32'h00000000 && cpu_addr<=32'h001fffff);	// 2MB main DRAM.
assign vram_cs = (cpu_addr>=32'h00200000 && cpu_addr<=32'h002fffff);	// 1MB VRAM.

// BIOS is mapped to the (2MB) DRAM range at start-up / reset. Any write to that range will Clear map_bios.
// BIOS is always mapped at 0x00300000-0x003fffff.
// TODO: Is the 1MB BIOS only mapped to the lower 1MB of DRAM range, or is it mirrored to the upper 1MB of DRAM as well?
reg map_bios;
assign bios_cs = (dram_cs && map_bios) || (cpu_addr>=32'h00300000 && cpu_addr<=32'h003fffff);



reg [2:0] pcsc_index;
reg [7:0] pcsc_reg;
// pcsc_reg should end up with the bits shifted in like this...
//
// b0 = ignore!
// b1 = VZ (CLIO VCNT==0).
// b2 = V# (CLIO VCNT[0]). (even or odd line)
// b3 = F# (CLIO field 0 or field 1).
// b4 = FC (Forced CLUT).
// b5 = VR (Generate VIRS test pattern??)
// b6 = VD (NTSC or PAL).
// b7 = VL (CLIO VCNT==last line).
//

reg pcsc_dly;
wire pcsc_rising = pcsc && !pcsc_dly;

reg [11:0] hcount;

always @(posedge clk_25m)
if (!reset_n) begin
	hcount <= 12'd0;
	pcsc_reg <= 8'd0;
	pcsc_index <= 3'd0;
end
else begin
	pcsc_dly <= pcsc;
	
	if (pcsc_rising && pcsc_index==0) begin	// pcsc_index==0 is to stop this re-triggering when pcsc toggles during each flag bit. (first 7-8 cycles of hcount).
		hcount <= 12'd0;
		pcsc_index <= 3'd1;
	end
	else hcount <= hcount + 12'd1;
	
	if (pcsc_index > 3'd0) begin	// This should evaluate for pcsc_index 1 through 7, then stops when it wraps to zero.
		pcsc_reg[pcsc_index] <= pcsc;		// Shift in the bits from the pcsc signal.
		pcsc_index <= pcsc_index + 3'd1;	// Increment the bit index.
	end
end

// MADAM registers...
// 0x0330xxxx
//
reg [7:0] debug_print;	// 0x0000. Revision when read. BIOS Serial debug when written.
reg [31:0] msysbits;	// 0x0004. Memory Configuration. 0x29 = 2MB DRAM, 1MB VRAM.
reg [31:0] mctl;		// 0x0008. DMA channel enables. bit16 = Player Bus. bit20 = Spryte control.
reg [31:0] sltime;		// 0x000C ? Unsure. “testbin” sets it to 0x00178906.
// 0x000D to 0x001C ??
reg [31:0] abortbits;	// 0x0020 ? Contains a bitmask of reasons for an abort signal MADAM sent to the CPU.
reg [31:0] privbits;	// 0x0024 ? DMA privilage violation bits.
reg [31:0] statbits;	// 0x0028 ? Spryte rendering engine status register. Details found in US patent 5,572,235. See Table 1.8. bit4 = SPRON “spryte engine enabled”. bit5 = SPRPAU “spryte engine paused”.

reg [31:0] msb_check;	// 0x002C. (arbitrary name). Write a value and when read it will return the number of the most significantly set bit.
						// example: Write 0x8400_0000 and a read will return 31. Write 0x0000_0000 and the return will be 0xFFFF_FFFF;

reg [31:0] diag;		// 0x0040 ? MAME forces this to 1 when written to?

// CEL control regs...
// 03300100 - SPRSTRT - Start the CEL engine (W)
// 03300104 - SPRSTOP - Stop the CEL engine (W)
// 03300108 - SPRCNTU - Continue the CEL engine (W)
// 0330010c - SPRPAUS - Pause the CEL engine (W)
reg [31:0] ccobctl0;	// 03300110 - CCOBCTL0 - CCoB control (RW). struct Bitmap→bm_CEControl. General spryte rendering engine control word
reg [31:0] ppmpc;		// 03300129 - PPMPC (RW) (note: comment in MAME said 0x0120, case was 0x0129 ?!

// More MADAM regs...
reg [31:0] regctl0;		// 0x0130. struct Bitmap→bm_REGCTL0. Controls the modulo for 
						// reading source frame buffer data into the primary and/or secondary imput port of the 
						// spryte engine and for writing spryte image result data from the spryte engine into a 
						// destination frame buffer in VRAM. The modulo effectively indicates the number of pixels 
						// per scan line as represented in the respective frame buffer in VRAM.

reg [31:0] regctl1;		// 0x0134. struct Bitmap→bm_REGCTL1
						// X and Y clip values, effecively indicating the number of pixels 
						// in the X and Y dimensions which make up the frame buffer. Bits 
						// 26:16 indicate the last writable row (counting from row 0) in 
						// the Y dimension and the bits 10:0 indicate the last writable 
						// column (counting from col 0) in the X dimension. All other bits 
						// must be zero. As an example, a value of 0x00EF_013F indicates 
						// that the frame buffer data is represented in 320×240 format.

reg [31:0] regctl2;		// 0x0138. struct Bitmap→bm_REGCTL2
						// Read base address. Indicates the address in VRAM of the upper left corner pixel of the source frame buffer data.

reg [31:0] regctl3;		// 0x013C. struct Bitmap→bm_REGCTL3
						// Write base address. Indicates the addres in VRAM of the upper left corner pixel of the destination frame buffer.

reg [31:0] xyposh;		// 0x0140.
reg [31:0] xyposl;		// 0x0144.
reg [31:0] linedxyh;	// 0x0148.
reg [31:0] linedxyl;	// 0x014C.
reg [31:0] dxyh;		// 0x0150.
reg [31:0] dxyl;		// 0x0154.
reg [31:0] ddxyh;		// 0x0158.
reg [31:0] ddxyl;		// 0x015C.

// 0x0180 to 0x01F8 = PIP! MAME has 0x0180-0x01BC for writes, but 0x0180-0x01F8 for reads?
// MAME splits each 32-bit reg into separate 16-bit reads?

// 0x0200 to 0x023C = Fence! MAME has 0x0200-0x023C for writes, but 0x0200-0x0278 for reads?
// MAME splits each 32-bit reg into separate 16-bit reads?
reg [31:0] fence_0l;
reg [31:0] fence_0r;
reg [31:0] fence_1l;
reg [31:0] fence_1r;
reg [31:0] fence_2l;
reg [31:0] fence_2r;
reg [31:0] fence_3l;
reg [31:0] fence_3r;

// 0x0300 to 0x03FC = MMU! ?? 

// 0x0400 to 0x05FC = DMA. See US patent WO09410641A1 page 46 line 25 for details.
// Most of the DMA addr regs are probably 22-bits wide, as suggested in the patent.
// (ie. each can address a 4MB memory range.)


reg [31:0] vdl_addr;// 0x580

// 0x0600 to 0x069C = Hardware Multiplier (Matrix Engine).
//

reg [31:0] vdl_addr_reg;

reg [31:0] pbus_dst;
reg [31:0] pbus_len;
reg [31:0] pbus_src;
reg trig_pbus_dma;

// MADAM register READ driver...
always @(*) begin
	casez (cpu_addr[15:0])
		16'h0000: cpu_dout = 32'h01020000;	// 0x0000. Revision when read. BIOS Serial debug when written.
		//16'h0004: cpu_dout = msysbits;	// 0x0004. Memory Configuration.
		16'h0004: cpu_dout = 32'h00000029;	// 0x0004. Memory Configuration. 0x29 = 2MB DRAM, 1MB VRAM.
		16'h0008: cpu_dout = mctl;			// 0x0008. DMA channel enables. bit16 (typo I thinK. Should be "bit 15"?) = Player Bus. bit20 = Spryte control.
		16'h000c: cpu_dout = sltime;	// 0x000C ? Unsure. “testbin” sets it to 0x00178906.
										// 0x000D to 0x001C ??
		16'h0020: cpu_dout = abortbits;	// 0x0020 ? Contains a bitmask of reasons for an abort signal MADAM sent to the CPU.
		16'h0024: cpu_dout = privbits;	// 0x0024 ? DMA privilage violation bits.
		16'h0028: cpu_dout = statbits;	// 0x0028 ? Spryte rendering engine status register. Details found in US patent 5,572,235. See Table 1.8.
		16'h002c: cpu_dout = msb_check;	// 0x002C. (arbitrary name). Write a value and when read it will return the number of the most significantly set bit.
										// example: Write 0x8400_0000 and a read will return 31. Write 0x0000_0000 and the return will be 0xFFFF_FFFF;

		16'h0040: cpu_dout = diag;		// 0x0040 ? MAME forces this to 1 when written to?

		// CEL control regs...
		// 03300100 - SPRSTRT - Start the CEL engine (W)
		// 03300104 - SPRSTOP - Stop the CEL engine (W)
		// 03300108 - SPRCNTU - Continue the CEL engine (W)
		// 0330010c - SPRPAUS - Pause the CEL engine (W)
		16'h0110: cpu_dout = ccobctl0;	// 03300110 - CCOBCTL0 - CCoB control (RW). struct Bitmap→bm_CEControl. General spryte rendering engine control word
		16'h0129: cpu_dout = ppmpc;		// 03300129?? - PPMPC (RW) (note: comment in MAME said 0x0120, case was 0x0129 ?!

		// More MADAM regs...
		16'h0130: cpu_dout = regctl0;	// 0x0130. struct Bitmap→bm_REGCTL0.
		16'h0134: cpu_dout = regctl1;	// 0x0134. struct Bitmap→bm_REGCTL1.
		16'h0138: cpu_dout = regctl2;	// 0x0138. struct Bitmap→bm_REGCTL2.
		16'h013c: cpu_dout = regctl3;	// 0x013C. struct Bitmap→bm_REGCTL3.
		16'h0140: cpu_dout = xyposh;	// 0x0140.
		16'h0144: cpu_dout = xyposl;	// 0x0144.
		16'h0148: cpu_dout = linedxyh;	// 0x0148.
		16'h014c: cpu_dout = linedxyl;	// 0x014C.
		16'h0150: cpu_dout = dxyh;		// 0x0150.
		16'h0154: cpu_dout = dxyl;		// 0x0154.
		16'h0158: cpu_dout = ddxyh;		// 0x0158.
		16'h015c: cpu_dout = ddxyl;		// 0x015C.

		// 0x0180 to 0x01F8 = PIP! MAME has 0x0180-0x01BC for writes, but 0x0180-0x01F8 for reads?
		// MAME splits each 32-bit reg into separate 16-bit reads?

		// 0x0230 to 0x023C = Fence! MAME has 0x0200-0x023C for writes, but 0x0200-0x0278 for reads?
		// MAME splits each 32-bit reg into separate 16-bit reads?
		16'h0230: cpu_dout = fence_0l;	// 0x230.
		16'h0234: cpu_dout = fence_0r;	// 0x234.
		16'h0238: cpu_dout = fence_1l;	// 0x238.
		16'h023c: cpu_dout = fence_1r;	// 0x23c.
		
		16'h0270: cpu_dout = fence_2l;	// 0x270.
		16'h0274: cpu_dout = fence_2r;	// 0x274.
		16'h0278: cpu_dout = fence_3l;	// 0x278.
		16'h027c: cpu_dout = fence_3r;	// 0x27c.

		// 0x0300 to 0x03FC = MMU! ?? 

		// 0x0400 to 0x05FC = DMA. See US patent WO09410641A1 page 46 line 25 for details.
		// Most of the DMA addr regs are probably 22-bits wide, as suggested in the patent.
		// (ie. each can address a 4MB memory range.)
		
		16'h04??, 16'h05??: cpu_dout = dma_regout;	// 0x0400 - 0x05ff.

		// 0x0600 to 0x069C = Hardware Multiplier (Matrix Engine).
		default: cpu_dout = 32'hBADACCE5;
	endcase
end

always @(posedge clk_25m or negedge reset_n)
if (!reset_n) begin
	mctl <= 32'h00000000;
	trig_pbus_dma <= 1'b0;
	
	pbus_len <= 32'hfffffffc;      // Set PBUS length reg to -4 ?

	map_bios <= 1'b1;
	
	cpu_clk <= 1'b0;
end
else begin
	trig_pbus_dma <= 1'b0;
	
	cpu_clk <= ~cpu_clk;

	if (cpu_addr>=32'h00000000 && cpu_addr<=32'h001fffff && cpu_wr) map_bios <= 1'b0;	// Any write to the 2MB DRAM range will unmap the BIOS.

	// Handle MADAM register WRITES...
	if (cpu_wr) begin
		case (cpu_addr[15:0])
			//16'h0000: m_print <= 32'h01020000;	// 0x0000. Revision when read. BIOS Serial debug when written.
			//16'h0004: msysbits <= cpu_din;	// 0x0004. Memory Configuration. When read, 0x29 = 2MB DRAM, 1MB VRAM.
			16'h0008: mctl <= cpu_din; 		// 0x0008. DMA channel enables. bit16 (surely bit 15?) = Player Bus. bit20 = Spryte control.
			16'h000c: sltime <= cpu_din;	// 0x000C ? Unsure. “testbin” sets it to 0x00178906.
											// 0x000D to 0x001C ??
			16'h0020: abortbits <= cpu_din;	// 0x0020 ? Contains a bitmask of reasons for an abort signal MADAM sent to the CPU.
			16'h0024: privbits <= cpu_din;	// 0x0024 ? DMA privilage violation bits.
			16'h0028: statbits <= cpu_din;	// 0x0028 ? Spryte rendering engine status register. Details found in US patent 5,572,235. See Table 1.8.
			16'h002c: msb_check <= cpu_din;	// 0x002C. (arbitrary name). Write a value and when read it will return the number of the most significantly set bit.
											// example: Write 0x8400_0000 and a read will return 31. Write 0x0000_0000 and the return will be 0xFFFF_FFFF;

			16'h0040: diag <= cpu_din;		// 0x0040 ? MAME forces this to 1 when written to?

			// CEL control regs...
			// 03300100 - SPRSTRT - Start the CEL engine (W)
			// 03300104 - SPRSTOP - Stop the CEL engine (W)
			// 03300108 - SPRCNTU - Continue the CEL engine (W)
			// 0330010c - SPRPAUS - Pause the CEL engine (W)
			16'h0110: ccobctl0 <= cpu_din;	// 03300110 - CCOBCTL0 - CCoB control (RW). struct Bitmap→bm_CEControl. General spryte rendering engine control word
			16'h0129: ppmpc <= cpu_din;		// 03300129?? - PPMPC (RW) (note: comment in MAME said 0x0120, case was 0x0129 ?!

			// More MADAM regs...
			16'h0130: regctl0 <= cpu_din;	// 0x0130. struct Bitmap→bm_REGCTL0.
			16'h0134: regctl1 <= cpu_din;	// 0x0134. struct Bitmap→bm_REGCTL1.
			16'h0138: regctl2 <= cpu_din;	// 0x0138. struct Bitmap→bm_REGCTL2.
			16'h013c: regctl3 <= cpu_din;	// 0x013C. struct Bitmap→bm_REGCTL3.
			16'h0140: xyposh <= cpu_din;	// 0x0140.
			16'h0144: xyposl <= cpu_din;	// 0x0144.
			16'h0148: linedxyh <= cpu_din;	// 0x0148.
			16'h014c: linedxyl <= cpu_din;	// 0x014C.
			16'h0150: dxyh <= cpu_din;		// 0x0150.
			16'h0154: dxyl <= cpu_din;		// 0x0154.
			16'h0158: ddxyh <= cpu_din;		// 0x0158.
			16'h015c: ddxyl <= cpu_din;		// 0x015C.

			// 0x0180 to 0x01F8 <= PIP! MAME has 0x0180-0x01BC for writes, but 0x0180-0x01F8 for reads?
			// MAME splits each 32-bit reg into separate 16-bit reads?

			// 0x0230 to 0x023C <= Fence! MAME has 0x0200-0x023C for writes, but 0x0200-0x0278 for reads?
			// MAME splits each 32-bit reg into separate 16-bit reads?
			16'h0230: fence_0l <= cpu_din;	// 0x230.
			16'h0234: fence_0r <= cpu_din;	// 0x234.
			16'h0238: fence_1l <= cpu_din;	// 0x238.
			16'h023c: fence_1r <= cpu_din;	// 0x23c.
			
			16'h0270: fence_2l <= cpu_din;	// 0x270.
			16'h0274: fence_2r <= cpu_din;	// 0x274.
			16'h0278: fence_3l <= cpu_din;	// 0x278.
			16'h027c: fence_3r <= cpu_din;	// 0x27c.

			// 0x0300 to 0x03FC <= MMU! ?? 

			// 0x0400 to 0x05FC <= DMA. See US patent WO09410641A1 page 46 line 25 for details.
			// Most of the DMA addr regs are probably 22-bits wide, as suggested in the patent.
			// (ie. each can address a 4MB memory range.)

			16'h0580: vdl_addr <= cpu_din;	// 0x580. Actually a DMA register!
			
			default: ;
		endcase
	end
	
	if (cpu_wr && cpu_addr[15:0]==16'h0008 && cpu_din[15]) begin	// Bit 15 of a mctl triggers a PBUS DMA.
		trig_pbus_dma <= 1'b1;
	end
end
		
	
	
// MAME has varius regs for this, but not sure if MAME has the actual Matrix engine FSM?
//
// 4DO has this Matrix engine code...

// M00 through to V3 are accessed like this in 4DO...
// ((double)(signed int)mregs[0x600])

reg [31:0] m00;		// 0x0600.
reg [31:0] m01;		// 0x0604.
reg [31:0] m02;		// 0x0608.
reg [31:0] m03;		// 0x060C.
reg [31:0] m11;		// 0x0610.
reg [31:0] m12;		// 0x0614.
reg [31:0] m13;		// 0x0618.
reg [31:0] m14;		// 0x061C.
reg [31:0] m20;		// 0x0620.
reg [31:0] m21;		// 0x0624.
reg [31:0] m22;		// 0x0628.
reg [31:0] m23;		// 0x062C.
reg [31:0] m30;		// 0x0630.
reg [31:0] m31;		// 0x0634.
reg [31:0] m32;		// 0x0638.
reg [31:0] m33;		// 0x063C.

reg [31:0] v0;		// 0x0640.
reg [31:0] v1;		// 0x0644.
reg [31:0] v2;		// 0x0648.
reg [31:0] v3;		// 0x064C.

reg [31:0] rez0;	// 0x0660.
reg [31:0] rez1;	// 0x0664.
reg [31:0] rez2;	// 0x0668.
reg [31:0] rez3;	// 0x066C.

reg [63:0] nfrac16;	// {0x0680, 0x0684}.

reg [31:0] mult_ctl;// 0x07F0 = set bits. 0x07F4 = clear bits.

//Matrix engine macros
/*
// Looks like these basically cast the 32-bit (signed) reg values to 64-bit (doubles),
// with sign-extension, so it can do the matrix calcs using doubles. ElectronAsh.

#define M00  ((double)(signed int)mregs[0x600])
#define M01  ((double)(signed int)mregs[0x604])
#define M02  ((double)(signed int)mregs[0x608])
#define M03  ((double)(signed int)mregs[0x60C])
#define M10  ((double)(signed int)mregs[0x610])
#define M11  ((double)(signed int)mregs[0x614])
#define M12  ((double)(signed int)mregs[0x618])
#define M13  ((double)(signed int)mregs[0x61C])
#define M20  ((double)(signed int)mregs[0x620])
#define M21  ((double)(signed int)mregs[0x624])
#define M22  ((double)(signed int)mregs[0x628])
#define M23  ((double)(signed int)mregs[0x62C])
#define M30  ((double)(signed int)mregs[0x630])
#define M31  ((double)(signed int)mregs[0x634])
#define M32  ((double)(signed int)mregs[0x638])
#define M33  ((double)(signed int)mregs[0x63C])

#define  V0  ((double)(signed int)mregs[0x640])
#define  V1  ((double)(signed int)mregs[0x644])
#define  V2  ((double)(signed int)mregs[0x648])
#define  V3  ((double)(signed int)mregs[0x64C])

#define Rez0 mregs[0x660]
#define Rez1 mregs[0x664]
#define Rez2 mregs[0x668]
#define Rez3 mregs[0x66C]

#define Nfrac16 (((__int64)mregs[0x680]<<32)|(unsigned int)mregs[0x684])
*/

reg [63:0] rez0t;	// Result reg?
reg [63:0] rez1t;	// Result reg?
reg [63:0] rez2t;	// Result reg?
reg [63:0] rez3t;	// Result reg?

// Matix engine from 4DO...
/*
	case 0x7fc:
		mregs[0x7fc]=0; // Ours matrix engine already ready

		static double Rez0T,Rez1T,Rez2T,Rez3T;
			   // io_interface(EXT_DEBUG_PRINT,(void*)str.print("MADAM Write madam[0x%X] = 0x%8.8X\n",addr,val).CStr());

		switch(val) // Cmd
		{
			case 0: //printf("#Matrix = NOP\n");
				Rez0=Rez0T;
				Rez1=Rez1T;
				Rez2=Rez2T;
				Rez3=Rez3T;
				// Verilog...
				//rez0 <= rez0t;
				//rez1 <= rez1t;
				//rez2 <= rez2t;
				//rez3 <= rez3t;
				return;   // NOP

			case 1: //multiply a 4x4 matrix of 16.16 values by a vector of 16.16 values
				Rez0=Rez0T;
				Rez1=Rez1T;
				Rez2=Rez2T;
				Rez3=Rez3T;
				// Verilog...
				//rez0 <= rez0t;
				//rez1 <= rez1t;
				//rez2 <= rez2t;
				//rez3 <= rez3t;

				Rez0T=(int)((M00*V0+M01*V1+M02*V2+M03*V3)/65536.0);
				Rez1T=(int)((M10*V0+M11*V1+M12*V2+M13*V3)/65536.0);
				Rez2T=(int)((M20*V0+M21*V1+M22*V2+M23*V3)/65536.0);
				Rez3T=(int)((M30*V0+M31*V1+M32*V2+M33*V3)/65536.0);

				return;
			case 2: //multiply a 3x3 matrix of 16.16 values by a vector of 16.16 values
				Rez0=Rez0T;
				Rez1=Rez1T;
				Rez2=Rez2T;
				Rez3=Rez3T;
				// Verilog...
				//rez0 <= rez0t;
				//rez1 <= rez1t;
				//rez2 <= rez2t;
				//rez3 <= rez3t;

				Rez0T=(int)((M00*V0+M01*V1+M02*V2)/65536.0);
				Rez1T=(int)((M10*V0+M11*V1+M12*V2)/65536.0);
				Rez2T=(int)((M20*V0+M21*V1+M22*V2)/65536.0);
				//printf("#Matrix CMD2, R0=0x%8.8X, R1=0x%8.8X, R2=0x%8.8X\n",Rez0,Rez1,Rez2);
				return;

			case 3: // Multiply a 3x3 matrix of 16.16 values by multiple vectors, then multiply x and y by n/z
				{   // Return the result vectors {x*n/z, y*n/z, z}
					Rez0=Rez0T;
					Rez1=Rez1T;
					Rez2=Rez2T;
					Rez3=Rez3T;
					// Verilog...
					//rez0 <= rez0t;
					//rez1 <= rez1t;
					//rez2 <= rez2t;
					//rez3 <= rez3t;

					double M;

					Rez2T=(signed int)((M20*V0+M21*V1+M22*V2)/65536.0); // z
					if(Rez2T!=0) M=Nfrac16/(double)Rez2T;          // n/z
					else {
						M=Nfrac16;
						//	io_interface(EXT_DEBUG_PRINT,(void*)"!!!Division by zero!!!\n");
					}

					Rez0T=(signed int)((M00*V0+M01*V1+M02*V2)/65536.0);
					Rez1T=(signed int)((M10*V0+M11*V1+M12*V2)/65536.0);

					Rez0T=(double)((Rez0T*M)/65536.0/65536.0); // x * n/z
					Rez1T=(double)((Rez1T*M)/65536.0/65536.0); // y * n/z
				}
				return;
				default:
					//io_interface(EXT_DEBUG_PRINT,(void*)str.print("??? Unknown cmd MADAM[0x7FC]==0x%x\n", val).CStr());
					return;
		}
		break;
	case 0x130:
		mregs[addr]=val;	//modulo variables :)
		RMOD = ((val&1)<<7) + ((val&12)<<8) + ((val&0x70)<<4);
		val >>= 8;		
		WMOD = ((val&1)<<7) + ((val&12)<<8) + ((val&0x70)<<4);
		// Verilog equiv...
		// regctl0 <= val;
		// RMOD <= (val[0]<<7) + (val[3:2]<<8) + (val[6:4]<<4);
		// No val shift required...
		// WMOD <= (val[8]<<7) + (val[11:10]<<8) + (val[14:12]<<4);
		break;
	default:
		mregs[addr]=val;
		break;
	}
}
*/

wire dma_reg_cs = (cpu_addr>=32'h03300400 && cpu_addr<=32'h033005fc);
wire [31:0] dma_regout;

dma_stack dma_stack_inst (
	.clk_25m( clk_25m ),	// input clk_25m,
	.reset_n( reset_n ),	// input reset_n,

	.cpu_addr( cpu_addr ),	// input [31:0] cpu_addr,
	.cpu_din( cpu_din ),	// input [31:0] cpu_din,
	.cpu_rd( cpu_rd ),		// input cpu_rd,
	.cpu_wr( cpu_wr ),		// input cpu_wr,
	
	.dma_reg_cs( dma_reg_cs ),	// input dma_reg_cs,
	.dma_regout( dma_regout ),	// output [31:0] dma_regout,
	
	.dma_req( dma_req ),	// input [4:0] dma_req,
	.dma_ack( dma_ack ),	// output reg dma_ack,
	.dma_addr( dma_addr ),	// output [21:0] dma_addr,
	.dma_dir( dma_dir )		// output dma_dir
);

endmodule


module dma_stack (
	input clk_25m,
	input reset_n,

	input [31:0] cpu_addr,
	input [31:0] cpu_din,
	input cpu_rd,
	input cpu_wr,
	
	input dma_reg_cs,
	output reg [31:0] dma_regout,
	
	input [4:0] dma_req,
	output reg dma_ack,
	output [21:0] dma_addr,
	output dma_dir
);


// 0x0400 to 0x05FC = DMA reg. See US patent WO09410641A1 page 46 line 25 for details.
// Most of the DMA address regs are probably 22-bits wide, as suggested in the patent.
// (ie. each can address a 4MB memory range.)

reg [21:0] dma0_curaddr;	// 0x400. RamToDSPP0
reg [23:0] dma0_curlen;		// 0x404
reg [21:0] dma0_nextaddr;	// 0x408
reg [23:0] dma0_nextlen;	// 0x40c

reg [21:0] dma1_curaddr;	// 0x410. RamToDSPP1
reg [23:0] dma1_curlen;		// 0x414
reg [21:0] dma1_nextaddr;	// 0x418
reg [23:0] dma1_nextlen;	// 0x41c

reg [21:0] dma2_curaddr;	// 0x420. RamToDSPP2
reg [23:0] dma2_curlen;		// 0x424
reg [21:0] dma2_nextaddr;	// 0x428
reg [23:0] dma2_nextlen;	// 0x42c

reg [21:0] dma3_curaddr;	// 0x430. RamToDSPP3
reg [23:0] dma3_curlen;		// 0x434
reg [21:0] dma3_nextaddr;	// 0x438
reg [23:0] dma3_nextlen;	// 0x43c

reg [21:0] dma4_curaddr;	// 0x440. RamToDSPP4
reg [23:0] dma4_curlen;		// 0x444
reg [21:0] dma4_nextaddr;	// 0x448
reg [23:0] dma4_nextlen;	// 0x44c

reg [21:0] dma5_curaddr;	// 0x450. RamToDSPP5
reg [23:0] dma5_curlen;		// 0x454
reg [21:0] dma5_nextaddr;	// 0x458
reg [23:0] dma5_nextlen;	// 0x45c

reg [21:0] dma6_curaddr;	// 0x460. RamToDSPP6
reg [23:0] dma6_curlen;		// 0x464
reg [21:0] dma6_nextaddr;	// 0x468
reg [23:0] dma6_nextlen;	// 0x46c

reg [21:0] dma7_curaddr;	// 0x470. RamToDSPP7
reg [23:0] dma7_curlen;		// 0x474
reg [21:0] dma7_nextaddr;	// 0x478
reg [23:0] dma7_nextlen;	// 0x47c

reg [21:0] dma8_curaddr;	// 0x480. RamToDSPP8
reg [23:0] dma8_curlen;		// 0x484
reg [21:0] dma8_nextaddr;	// 0x488
reg [23:0] dma8_nextlen;	// 0x48c

reg [21:0] dma9_curaddr;	// 0x490. RamToDSPP9
reg [23:0] dma9_curlen;		// 0x494
reg [21:0] dma9_nextaddr;	// 0x498
reg [23:0] dma9_nextlen;	// 0x49c

reg [21:0] dma10_curaddr;	// 0x4a0. RamToDSPP10
reg [23:0] dma10_curlen;	// 0x4a4
reg [21:0] dma10_nextaddr;	// 0x4a8
reg [23:0] dma10_nextlen;	// 0x4ac

reg [21:0] dma11_curaddr;	// 0x4b0. RamToDSPP11
reg [23:0] dma11_curlen;	// 0x4b4
reg [21:0] dma11_nextaddr;	// 0x4b8
reg [23:0] dma11_nextlen;	// 0x4bc

reg [21:0] dma12_curaddr;	// 0x4c0. RamToDSPP12
reg [23:0] dma12_curlen;	// 0x4c4
reg [21:0] dma12_nextaddr;	// 0x4c8
reg [23:0] dma12_nextlen;	// 0x4cc

reg [21:0] dma13_curaddr;	// 0x4d0. RamToUncle
reg [23:0] dma13_curlen;	// 0x4d4
reg [21:0] dma13_nextaddr;	// 0x4d8
reg [23:0] dma13_nextlen;	// 0x4dc

reg [21:0] dma14_curaddr;	// 0x4e0. RamToExternal
reg [23:0] dma14_curlen;	// 0x4e4
reg [21:0] dma14_nextaddr;	// 0x4e8
reg [23:0] dma14_nextlen;	// 0x4ec

reg [21:0] dma15_curaddr;	// 0x4f0. RamToDSPPNStack
reg [23:0] dma15_curlen;	// 0x4f4
reg [21:0] dma15_nextaddr;	// 0x4f8
reg [23:0] dma15_nextlen;	// 0x4fc

reg [21:0] dma16_curaddr;	// 0x500. DSPPToRam0
reg [23:0] dma16_curlen;	// 0x504
reg [21:0] dma16_nextaddr;	// 0x508
reg [23:0] dma16_nextlen;	// 0x50c

reg [21:0] dma17_curaddr;	// 0x510. DSPPToRam1
reg [23:0] dma17_curlen;	// 0x514
reg [21:0] dma17_nextaddr;	// 0x518
reg [23:0] dma17_nextlen;	// 0x51c

reg [21:0] dma18_curaddr;	// 0x520. DSPPToRam2
reg [23:0] dma18_curlen;	// 0x524
reg [21:0] dma18_nextaddr;	// 0x528
reg [23:0] dma18_nextlen;	// 0x52c

reg [21:0] dma19_curaddr;	// 0x530. DSPPToRam3
reg [23:0] dma19_curlen;	// 0x534
reg [21:0] dma19_nextaddr;	// 0x538
reg [23:0] dma19_nextlen;	// 0x53c

reg [21:0] dma20_curaddr;	// 0x540. XBUS DMA (CDROM drive / Expansion Bus etc.)
reg [23:0] dma20_curlen;	// 0x544
reg [21:0] dma20_nextaddr;	// 0x548
reg [23:0] dma20_nextlen;	// 0x54c

reg [21:0] dma21_curaddr;	// 0x550. UncleToRam
reg [23:0] dma21_curlen;	// 0x554
reg [21:0] dma21_nextaddr;	// 0x558
reg [23:0] dma21_nextlen;	// 0x55c

reg [21:0] dma22_curaddr;	// 0x560. ExternalToRam
reg [23:0] dma22_curlen;	// 0x564
reg [21:0] dma22_nextaddr;	// 0x568
reg [23:0] dma22_nextlen;	// 0x56c

reg [21:0] dma23_curaddr;	// 0x570. PlayerBus (ControlPort).
reg [23:0] dma23_curlen;	// 0x574
reg [21:0] dma23_nextaddr;	// 0x578
reg [23:0] dma23_nextlen;	// 0x57c

reg [21:0] dma24_curaddr;	// 0x580. CLUT_MID (CLUT Ctrl) vdl_addr!
reg [23:0] dma24_curlen;	// 0x584
reg [21:0] dma24_nextaddr;	// 0x588
reg [23:0] dma24_nextlen;	// 0x58c

reg [21:0] dma25_curaddr;	// 0x590. Video_MID
reg [23:0] dma25_curlen;	// 0x594
reg [21:0] dma25_nextaddr;	// 0x598
reg [23:0] dma25_nextlen;	// 0x59c

reg [21:0] dma26_curaddr;	// 0x5a0. CELControl
reg [23:0] dma26_curlen;	// 0x5a4
reg [21:0] dma26_nextaddr;	// 0x5a8
reg [23:0] dma26_nextlen;	// 0x5ac

reg [21:0] dma27_curaddr;	// 0x5b0. CELData
reg [23:0] dma27_curlen;	// 0x5b4
reg [21:0] dma27_nextaddr;	// 0x5b8
reg [23:0] dma27_nextlen;	// 0x5bc

reg [21:0] dma28_curaddr;	// 0x5c0. Commandgrabber
reg [23:0] dma28_curlen;	// 0x5c4
reg [21:0] dma28_nextaddr;	// 0x5c8
reg [23:0] dma28_nextlen;	// 0x5cc

reg [21:0] dma29_curaddr;	// 0x5d0. Framegrabber
reg [23:0] dma29_curlen;	// 0x5d4
reg [21:0] dma29_nextaddr;	// 0x5d8
reg [23:0] dma29_nextlen;	// 0x5dc

reg [21:0] dma30_curaddr;	// 0x5e0. Not sure if these regs exist, but having 32 sets of DMA regs might make sense?
reg [23:0] dma30_curlen;	// 0x5e4
reg [21:0] dma30_nextaddr;	// 0x5e8
reg [23:0] dma30_nextlen;	// 0x5ec

reg [21:0] dma31_curaddr;	// 0x5f0. Not sure if these regs exist, but having 32 sets of DMA regs might make sense?
reg [23:0] dma31_curlen;	// 0x5f4
reg [21:0] dma31_nextaddr;	// 0x5f8
reg [23:0] dma31_nextlen;	// 0x5fc


// Handle DMA Register Reads...
always @(*) begin
case (cpu_addr[15:0])
	16'h0400: dma_regout = dma0_curaddr;	// RamToDSPP0
	16'h0404: dma_regout = dma0_curlen;
	16'h0408: dma_regout = dma0_nextaddr;
	16'h040c: dma_regout = dma0_nextlen;

	16'h0410: dma_regout = dma1_curaddr;	// RamToDSPP1
	16'h0414: dma_regout = dma1_curlen;
	16'h0418: dma_regout = dma1_nextaddr;
	16'h041c: dma_regout = dma1_nextlen;

	16'h0420: dma_regout = dma2_curaddr;	// RamToDSPP2
	16'h0424: dma_regout = dma2_curlen;
	16'h0428: dma_regout = dma2_nextaddr;
	16'h042c: dma_regout = dma2_nextlen;

	16'h0430: dma_regout = dma3_curaddr;	// RamToDSPP3
	16'h0434: dma_regout = dma3_curlen;
	16'h0438: dma_regout = dma3_nextaddr;
	16'h043c: dma_regout = dma3_nextlen;

	16'h0440: dma_regout = dma4_curaddr;	// RamToDSPP4
	16'h0444: dma_regout = dma4_curlen;
	16'h0448: dma_regout = dma4_nextaddr;
	16'h044c: dma_regout = dma4_nextlen;

	16'h0450: dma_regout = dma5_curaddr;	// RamToDSPP5
	16'h0454: dma_regout = dma5_curlen;
	16'h0458: dma_regout = dma5_nextaddr;
	16'h045c: dma_regout = dma5_nextlen;

	16'h0460: dma_regout = dma6_curaddr;	// RamToDSPP6
	16'h0464: dma_regout = dma6_curlen;
	16'h0468: dma_regout = dma6_nextaddr;
	16'h046c: dma_regout = dma6_nextlen;

	16'h0470: dma_regout = dma7_curaddr;	// RamToDSPP7
	16'h0474: dma_regout = dma7_curlen;
	16'h0478: dma_regout = dma7_nextaddr;
	16'h047c: dma_regout = dma7_nextlen;

	16'h0480: dma_regout = dma8_curaddr;	// RamToDSPP8
	16'h0484: dma_regout = dma8_curlen;
	16'h0488: dma_regout = dma8_nextaddr;	
	16'h048c: dma_regout = dma8_nextlen;	

	16'h0490: dma_regout = dma9_curaddr;	// RamToDSPP9
	16'h0494: dma_regout = dma9_curlen;
	16'h0498: dma_regout = dma9_nextaddr;	
	16'h049c: dma_regout = dma9_nextlen;	

	16'h04a0: dma_regout = dma10_curaddr;	// RamToDSPP10
	16'h04a4: dma_regout = dma10_curlen;
	16'h04a8: dma_regout = dma10_nextaddr;
	16'h04ac: dma_regout = dma10_nextlen;	

	16'h04b0: dma_regout = dma11_curaddr;	// RamToDSPP11
	16'h04b4: dma_regout = dma11_curlen;
	16'h04b8: dma_regout = dma11_nextaddr;
	16'h04bc: dma_regout = dma11_nextlen;	
	
	16'h04c0: dma_regout = dma12_curaddr;	// RamToDSPP12
	16'h04c4: dma_regout = dma12_curlen;
	16'h04c8: dma_regout = dma12_nextaddr;
	16'h04cc: dma_regout = dma12_nextlen;	
	
	16'h04d0: dma_regout = dma13_curaddr;	// RamToUncle.
	16'h04d4: dma_regout = dma13_curlen;
	16'h04d8: dma_regout = dma13_nextaddr;
	16'h04dc: dma_regout = dma13_nextlen;	

	16'h04e0: dma_regout = dma14_curaddr;	// RamToExternal
	16'h04e4: dma_regout = dma14_curlen;
	16'h04e8: dma_regout = dma14_nextaddr;
	16'h04ec: dma_regout = dma14_nextlen;	

	16'h04f0: dma_regout = dma15_curaddr;	// RamToDSPPNStack
	16'h04f4: dma_regout = dma15_curlen;
	16'h04f8: dma_regout = dma15_nextaddr;
	16'h04fc: dma_regout = dma15_nextlen;	

	16'h0500: dma_regout = dma16_curaddr;	// DSPPToRam0
	16'h0504: dma_regout = dma16_curlen;
	16'h0508: dma_regout = dma16_nextaddr;
	16'h050c: dma_regout = dma16_nextlen;	

	16'h0510: dma_regout = dma17_curaddr;	// DSPPToRam1
	16'h0514: dma_regout = dma17_curlen;
	16'h0518: dma_regout = dma17_nextaddr;
	16'h051c: dma_regout = dma17_nextlen;	

	16'h0520: dma_regout = dma18_curaddr;	// DSPPToRam2
	16'h0524: dma_regout = dma18_curlen;
	16'h0528: dma_regout = dma18_nextaddr;
	16'h052c: dma_regout = dma18_nextlen;	

	16'h0530: dma_regout = dma19_curaddr;	// DSPPToRam3
	16'h0534: dma_regout = dma19_curlen;
	16'h0538: dma_regout = dma19_nextaddr;
	16'h053c: dma_regout = dma19_nextlen;	

	16'h0540: dma_regout = dma20_curaddr;	// XBUS DMA.
	16'h0544: dma_regout = dma20_curlen;
	16'h0548: dma_regout = dma20_nextaddr;
	16'h054c: dma_regout = dma20_nextlen;	

	16'h0550: dma_regout = dma21_curaddr;	// UncleToRam.
	16'h0554: dma_regout = dma21_curlen;
	16'h0558: dma_regout = dma21_nextaddr;
	16'h055c: dma_regout = dma21_nextlen;	

	16'h0560: dma_regout = dma22_curaddr;	// ExternalToRam
	16'h0564: dma_regout = dma22_curlen;
	16'h0568: dma_regout = dma22_nextaddr;
	16'h056c: dma_regout = dma22_nextlen;			

	16'h0570: dma_regout = dma23_curaddr;	// Player Bus DMA: Destination Address. See US patent WO09410641A1 page 61 line 25 for details.
	16'h0574: dma_regout = dma23_curlen;	// Player Bus DMA: Length. Lower half word of 0xFFFC (-4) indicates end.
	16'h0578: dma_regout = dma23_nextaddr;	// Player Bus DMA:
	16'h057c: dma_regout = dma23_nextlen;	// Player Bus DMA: Next Address.
	
	16'h0580: dma_regout = dma24_curaddr;	// 0x580 vdl_addr
	16'h0584: dma_regout = dma24_curlen;
	16'h0588: dma_regout = dma24_nextaddr;
	16'h058c: dma_regout = dma24_nextlen;		
	
	16'h0590: dma_regout = dma25_curaddr;	// Video_MID
	16'h0594: dma_regout = dma25_curlen;
	16'h0598: dma_regout = dma25_nextaddr;
	16'h059c: dma_regout = dma25_nextlen;	

	16'h05a0: dma_regout = dma26_curaddr;	// CELControl
	16'h05a4: dma_regout = dma26_curlen;
	16'h05a8: dma_regout = dma26_nextaddr;
	16'h05ac: dma_regout = dma26_nextlen;	

	16'h05b0: dma_regout = dma27_curaddr;	// CELData
	16'h05b4: dma_regout = dma27_curlen;
	16'h05b8: dma_regout = dma27_nextaddr;
	16'h05bc: dma_regout = dma27_nextlen;	

	16'h05c0: dma_regout = dma28_curaddr;	// Commandgrabber
	16'h05c4: dma_regout = dma28_curlen;
	16'h05c8: dma_regout = dma28_nextaddr;
	16'h05cc: dma_regout = dma28_nextlen;	

	16'h05d0: dma_regout = dma29_curaddr;	// Framegrabber
	16'h05d4: dma_regout = dma29_curlen;
	16'h05d8: dma_regout = dma29_nextaddr;
	16'h05dc: dma_regout = dma29_nextlen;			
	
	16'h05e0: dma_regout = dma30_curaddr;	// Not sure if this exists, but having 32 sets of DMA regs would make sense?
	16'h05e4: dma_regout = dma30_curlen;
	16'h05e8: dma_regout = dma30_nextaddr;
	16'h05ec: dma_regout = dma30_nextlen;	
	
	16'h05f0: dma_regout = dma31_curaddr;	// Not sure if this exists, but having 32 sets of DMA regs would make sense?
	16'h05f4: dma_regout = dma31_curlen;
	16'h05f8: dma_regout = dma31_nextaddr;
	16'h05fc: dma_regout = dma31_nextlen;	
	
	default: dma_regout = 32'hBADACCE5;
	endcase
end


always @(posedge clk_25m or negedge reset_n)
if (!reset_n) begin

end
else begin

	// Handle DMA Register Writes...
	if (dma_reg_cs && cpu_wr) begin
		case (cpu_addr[15:0])
			16'h0400: dma0_curaddr <= cpu_din;		// RamToDSPP0
			16'h0404: dma0_curlen <= cpu_din;
			16'h0408: dma0_nextaddr <= cpu_din;
			16'h040c: dma0_nextlen <= cpu_din;

			16'h0410: dma1_curaddr <= cpu_din;		// RamToDSPP1
			16'h0414: dma1_curlen <= cpu_din;
			16'h0418: dma1_nextaddr <= cpu_din;
			16'h041c: dma1_nextlen <= cpu_din;

			16'h0420: dma2_curaddr <= cpu_din;		// RamToDSPP2
			16'h0424: dma2_curlen <= cpu_din;
			16'h0428: dma2_nextaddr <= cpu_din;
			16'h042c: dma2_nextlen <= cpu_din;

			16'h0430: dma3_curaddr <= cpu_din;		// RamToDSPP3
			16'h0434: dma3_curlen <= cpu_din;
			16'h0438: dma3_nextaddr <= cpu_din;
			16'h043c: dma3_nextlen <= cpu_din;

			16'h0440: dma4_curaddr <= cpu_din;		// RamToDSPP4
			16'h0444: dma4_curlen <= cpu_din;
			16'h0448: dma4_nextaddr <= cpu_din;
			16'h044c: dma4_nextlen <= cpu_din;

			16'h0450: dma5_curaddr <= cpu_din;		// RamToDSPP5
			16'h0454: dma5_curlen <= cpu_din;
			16'h0458: dma5_nextaddr <= cpu_din;
			16'h045c: dma5_nextlen <= cpu_din;

			16'h0460: dma6_curaddr <= cpu_din;		// RamToDSPP6
			16'h0464: dma6_curlen <= cpu_din;
			16'h0468: dma6_nextaddr <= cpu_din;
			16'h046c: dma6_nextlen <= cpu_din;

			16'h0470: dma7_curaddr <= cpu_din;		// RamToDSPP7
			16'h0474: dma7_curlen <= cpu_din;
			16'h0478: dma7_nextaddr <= cpu_din;
			16'h047c: dma7_nextlen <= cpu_din;

			16'h0480: dma8_curaddr <= cpu_din;		// RamToDSPP8
			16'h0484: dma8_curlen <= cpu_din;
			16'h0488: dma8_nextaddr <= cpu_din;	
			16'h048c: dma8_nextlen <= cpu_din;	

			16'h0490: dma9_curaddr <= cpu_din;		// RamToDSPP9
			16'h0494: dma9_curlen <= cpu_din;
			16'h0498: dma9_nextaddr <= cpu_din;	
			16'h049c: dma9_nextlen <= cpu_din;	

			16'h04a0: dma10_curaddr <= cpu_din;		// RamToDSPP10
			16'h04a4: dma10_curlen <= cpu_din;
			16'h04a8: dma10_nextaddr <= cpu_din;
			16'h04ac: dma10_nextlen <= cpu_din;	

			16'h04b0: dma11_curaddr <= cpu_din;		// RamToDSPP11
			16'h04b4: dma11_curlen <= cpu_din;
			16'h04b8: dma11_nextaddr <= cpu_din;
			16'h04bc: dma11_nextlen <= cpu_din;	
			
			16'h04c0: dma12_curaddr <= cpu_din;		// RamToDSPP12
			16'h04c4: dma12_curlen <= cpu_din;
			16'h04c8: dma12_nextaddr <= cpu_din;
			16'h04cc: dma12_nextlen <= cpu_din;	
			
			16'h04d0: dma13_curaddr <= cpu_din;		// RamToUncle.
			16'h04d4: dma13_curlen <= cpu_din;
			16'h04d8: dma13_nextaddr <= cpu_din;
			16'h04dc: dma13_nextlen <= cpu_din;	

			16'h04e0: dma14_curaddr <= cpu_din;		// RamToExternal
			16'h04e4: dma14_curlen <= cpu_din;
			16'h04e8: dma14_nextaddr <= cpu_din;
			16'h04ec: dma14_nextlen <= cpu_din;	

			16'h04f0: dma15_curaddr <= cpu_din;		// RamToDSPPNStack
			16'h04f4: dma15_curlen <= cpu_din;
			16'h04f8: dma15_nextaddr <= cpu_din;
			16'h04fc: dma15_nextlen <= cpu_din;	

			16'h0500: dma16_curaddr <= cpu_din;		// DSPPToRam0
			16'h0504: dma16_curlen <= cpu_din;
			16'h0508: dma16_nextaddr <= cpu_din;
			16'h050c: dma16_nextlen <= cpu_din;	

			16'h0510: dma17_curaddr <= cpu_din;		// DSPPToRam1
			16'h0514: dma17_curlen <= cpu_din;
			16'h0518: dma17_nextaddr <= cpu_din;
			16'h051c: dma17_nextlen <= cpu_din;	

			16'h0520: dma18_curaddr <= cpu_din;		// DSPPToRam2
			16'h0524: dma18_curlen <= cpu_din;
			16'h0528: dma18_nextaddr <= cpu_din;
			16'h052c: dma18_nextlen <= cpu_din;	

			16'h0530: dma19_curaddr <= cpu_din;		// DSPPToRam3
			16'h0534: dma19_curlen <= cpu_din;
			16'h0538: dma19_nextaddr <= cpu_din;
			16'h053c: dma19_nextlen <= cpu_din;	

			16'h0540: dma20_curaddr <= cpu_din;		// XBUS DMA.
			16'h0544: dma20_curlen <= cpu_din;
			16'h0548: dma20_nextaddr <= cpu_din;
			16'h054c: dma20_nextlen <= cpu_din;	

			16'h0550: dma21_curaddr <= cpu_din;		// UncleToRam.
			16'h0554: dma21_curlen <= cpu_din;
			16'h0558: dma21_nextaddr <= cpu_din;
			16'h055c: dma21_nextlen <= cpu_din;	

			16'h0560: dma22_curaddr <= cpu_din;		// ExternalToRam
			16'h0564: dma22_curlen <= cpu_din;
			16'h0568: dma22_nextaddr <= cpu_din;
			16'h056c: dma22_nextlen <= cpu_din;			

			16'h0570: dma23_curaddr <= cpu_din;		// Player Bus DMA: Destination Address. See US patent WO09410641A1 page 61 line 25 for details.
			16'h0574: dma23_curlen <= cpu_din;		// Player Bus DMA: Length. Lower half word of 0xFFFC (-4) indicates end.
			16'h0578: dma23_nextaddr <= cpu_din;	// Player Bus DMA:
			16'h057c: dma23_nextlen <= cpu_din;		// Player Bus DMA: Next Address.
			
			16'h0580: dma24_curaddr <= cpu_din;		// 0x580 vdl_addr
			16'h0584: dma24_curlen <= cpu_din;
			16'h0588: dma24_nextaddr <= cpu_din;
			16'h058c: dma24_nextlen <= cpu_din;		
			
			16'h0590: dma25_curaddr <= cpu_din;		// Video_MID
			16'h0594: dma25_curlen <= cpu_din;
			16'h0598: dma25_nextaddr <= cpu_din;
			16'h059c: dma25_nextlen <= cpu_din;	

			16'h05a0: dma26_curaddr <= cpu_din;		// CELControl
			16'h05a4: dma26_curlen <= cpu_din;
			16'h05a8: dma26_nextaddr <= cpu_din;
			16'h05ac: dma26_nextlen <= cpu_din;	

			16'h05b0: dma27_curaddr <= cpu_din;		// CELData
			16'h05b4: dma27_curlen <= cpu_din;
			16'h05b8: dma27_nextaddr <= cpu_din;
			16'h05bc: dma27_nextlen <= cpu_din;	

			16'h05c0: dma28_curaddr <= cpu_din;		// Commandgrabber
			16'h05c4: dma28_curlen <= cpu_din;
			16'h05c8: dma28_nextaddr <= cpu_din;
			16'h05cc: dma28_nextlen <= cpu_din;	

			16'h05d0: dma29_curaddr <= cpu_din;		// Framegrabber
			16'h05d4: dma29_curlen <= cpu_din;
			16'h05d8: dma29_nextaddr <= cpu_din;
			16'h05dc: dma29_nextlen <= cpu_din;			
			
			16'h05e0: dma30_curaddr <= cpu_din;		// Not sure if this exists, but having 32 sets of DMA regs would make sense?
			16'h05e4: dma30_curlen <= cpu_din;
			16'h05e8: dma30_nextaddr <= cpu_din;
			16'h05ec: dma30_nextlen <= cpu_din;	
			
			16'h05f0: dma31_curaddr <= cpu_din;		// Not sure if this exists, but having 32 sets of DMA regs would make sense?
			16'h05f4: dma31_curlen <= cpu_din;
			16'h05f8: dma31_nextaddr <= cpu_din;
			16'h05fc: dma31_nextlen <= cpu_din;	
			
			default: ;
		endcase
	end
	

end

endmodule