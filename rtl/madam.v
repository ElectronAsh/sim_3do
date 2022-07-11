//
// 3DO MADAM chip implementation / notes. ElectronAsh, Jan 2022.
//
// MADAM contains: ARM CPU interface, DRAM/VRAM Address control, VRAM SPORT control (probably), DMA Engine, CEL Engine, Matrix Engine, Main timings for pixel/VDL/CCB access, P-Bus (joyport), "PD" bus (Slow bus??) for BIOS / SRAM / DAC access.
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
	
	output [22:0] ram_addr,	
	input [31:0] ram_din,
	
	output [31:0] ram_dout,
	output ram_wen,
	
	input pcsc,
	
	output reg lpsc_n, 	// Right-hand VRAM SAM strobe. (pixel or VDL data is on S-bus[31:16]).
	output reg rpsc_n 	// Left-hand VRAM SAM strobe.  (pixel or VDL data is on S-bus[15:00]).
);

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
reg [21:0] dma0_curaddr;	// 0x400. CPU RAM to DSP DMA Group 0x0: current address.
reg [21:0] dma0_curlen;		// 0x404. CPU RAM to DSP DMA Group 0x0: current length.
reg [21:0] dma0_nextaddr;	// 0x408. CPU RAM to DSP DMA Group 0x0: next address.
reg [21:0] dma0_nextlen;	// 0x40C. CPU RAM to DSP DMA Group 0x0: next length.

// TODO - There are actually around 128 DMA registers!
// This should all be put into its own Verilog module.
// Some specs say "36 Separate DMA Channels".

reg [21:0] dmac_curaddr;	// 0x4C0. CPU RAM to DSP DMA Group 0xC: current address.
reg [21:0] dmac_curlen;		// 0x4C4. CPU RAM to DSP DMA Group 0xC: current length.
reg [21:0] dmac_nextaddr;	// 0x4C8. CPU RAM to DSP DMA Group 0xC: next address.
reg [21:0] dmac_nextlen;	// 0x4CC. CPU RAM to DSP DMA Group 0xC: next length.

// 0x04D0 = FMV DMA Group 1?
// 0x04D3 = FMV DMA Group 1?
// 0x04E0 = FMV DMA Group 1?
// 0x04E4 = FMV DMA Group 1?

// 0x0540 = XBUS DMA: Source / Dest Address.
// 0x0544 = XBUX DMA: Length.

// 0x0550 = FMV DMA Group 2?
// 0x0554 = FMV DMA Group 2?
// 0x0560 = FMV DMA Group 2?
// 0x0564 = FMV DMA Group 2?

// 0x0570 = Player Bus DMA: Destination Address. See US patent WO09410641A1 page 61 line 25 for details.
// 0x0574 = Player Bus DMA: Length. Lower half word of 0xFFFC (-4) indicates end.
// 0x0578 = Player Bus DMA: Source Address.

reg [31:0] vdl_addr;// 0x580

// 0x0600 to 0x069C = Hardware Multiplier (Matrix Engine).
//

reg [31:0] vdl_addr_reg;


// MADAM register READ driver...
always @(*) begin
	case (cpu_addr[15:0])
		//reg [7:0] debug_print;		// 0x0000. Revision when read. BIOS Serial debug when written.
		//16'h0004: cpu_dout = msysbits;	// 0x0004. Memory Configuration. 0x29 = 2MB DRAM, 1MB VRAM.
		16'h0004: cpu_dout = 32'h00000029;	// 0x0004. Memory Configuration. 0x29 = 2MB DRAM, 1MB VRAM.
		16'h0008: cpu_dout = mctl;		// 0x0008. DMA channel enables. bit16 = Player Bus. bit20 = Spryte control.
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
		16'h0130: cpu_dout = regctl0;		// 0x0130. struct Bitmap→bm_REGCTL0.
		16'h0134: cpu_dout = regctl1;		// 0x0134. struct Bitmap→bm_REGCTL1.
		16'h0138: cpu_dout = regctl2;		// 0x0138. struct Bitmap→bm_REGCTL2.
		16'h013c: cpu_dout = regctl3;		// 0x013C. struct Bitmap→bm_REGCTL3.
		16'h0140: cpu_dout = xyposh;		// 0x0140.
		16'h0144: cpu_dout = xyposl;		// 0x0144.
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
		16'h0400: cpu_dout = dma0_curaddr;	// 0x400. CPU RAM to DSP DMA Group 0x0: current address.
		16'h0404: cpu_dout = dma0_curlen;	// 0x404. CPU RAM to DSP DMA Group 0x0: current length.
		16'h0408: cpu_dout = dma0_nextaddr;	// 0x408. CPU RAM to DSP DMA Group 0x0: next address.
		16'h040c: cpu_dout = dma0_nextlen;	// 0x40C. CPU RAM to DSP DMA Group 0x0: next length.

		// TODO - There are actually around 128 DMA registers!
		// This should all be put into its own Verilog module.
		// Some specs say "36 Separate DMA Channels".

		16'h04c0: cpu_dout = dmac_curaddr;	// 0x4C0. CPU RAM to DSP DMA Group 0xC: current address.
		16'h04c4: cpu_dout = dmac_curlen;	// 0x4C4. CPU RAM to DSP DMA Group 0xC: current length.
		16'h04c8: cpu_dout = dmac_nextaddr;	// 0x4C8. CPU RAM to DSP DMA Group 0xC: next address.
		16'h04cc: cpu_dout = dmac_nextlen;	// 0x4CC. CPU RAM to DSP DMA Group 0xC: next length.

		// 0x04D0 = FMV DMA Group 1?
		// 0x04D3 = FMV DMA Group 1?
		// 0x04E0 = FMV DMA Group 1?
		// 0x04E4 = FMV DMA Group 1?

		// 0x0540 = XBUS DMA: Source / Dest Address.
		// 0x0544 = XBUX DMA: Length.

		// 0x0550 = FMV DMA Group 2?
		// 0x0554 = FMV DMA Group 2?
		// 0x0560 = FMV DMA Group 2?
		// 0x0564 = FMV DMA Group 2?

		// 0x0570 = Player Bus DMA: Destination Address. See US patent WO09410641A1 page 61 line 25 for details.
		// 0x0574 = Player Bus DMA: Length. Lower half word of 0xFFFC (-4) indicates end.
		// 0x0578 = Player Bus DMA: Source Address.
		
		16'h0580: cpu_dout = vdl_addr;	// 0x580

		// 0x0600 to 0x069C = Hardware Multiplier (Matrix Engine).
		default: cpu_dout = 32'hBADACCE5;
	endcase
end

always @(posedge clk_25m or negedge reset_n)
if (!reset_n) begin

end
else begin
	// Handle MADAM register WRITES...
	if (cpu_wr) begin
		case (cpu_addr[15:0])
			//16'h0000: revision <= cpu_din;	// 0x00
			16'h0580: vdl_addr <= cpu_din;	// 0x580
			default: ;
		endcase
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

endmodule
