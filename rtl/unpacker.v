module unpacker (
	input clock,
	input reset_n,
	
	input [2:0] bpp,
	
	input start,
	input [31:0] din,
	output reg rd_req,	// rd_req will externally increment the dma_addr in madam.v.
	
	input next_pix,
	output reg eol,
	
	output [15:0] col_out
);

parameter PACK_EOL     = 2'b00;
parameter PACK_LITERAL = 2'b01;
parameter PACK_TRANSP  = 2'b10;
parameter PACK_REPEAT  = 2'b11;


wire pix1;
wire [1:0] pix2;
wire [3:0] pix4;
reg [5:0] pix6;
wire [7:0] pix8;
wire [15:0] pix16;

assign col_out = (bpp==3'd1) ? {15'b000000000000000, pix1} :
				 (bpp==3'd2) ? {14'b00000000000000, pix2} :
				 (bpp==3'd3) ? {12'h000, pix4} :
				 (bpp==3'd4) ? {10'b0000000000, pix6} :
				 (bpp==3'd5) ? {8'h00, pix8} :
				 (bpp==3'd6) ? pix16 :
							   16'haaaa;

reg [31:0] store0;
reg [31:0] store1;
reg [9:0] offset;
reg [1:0] pack_type;
reg [5:0] count;

reg [7:0] state;
reg [4:0] pix_sel;
reg word_sel;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 8'd0;
	rd_req <= 1'b0;
	pix_sel <= 5'd0;
	word_sel <= 1'b0;
	eol <= 1'b0;
	store0 <= 32'h00000000;
	store1 <= 32'h00000000;
end
else begin
	rd_req <= 1'b0;
	eol <= 1'b0;
	
	if (rd_req) begin
		if (!word_sel) store0[31:0] <= din;
		else store1[31:0] <= din;
	end

	case (state)
	0: if (start) begin
		state <= state + 8'd1;
	end
	
	1: begin		// Read the first 32-bit word into the store0 reg...
		word_sel <= 1'b0;
		rd_req <= 1'b1;
		state <= state + 8'd1;
	end
	
	2: begin		// Read the second 32-bit word into the store1 reg...
		word_sel <= 1'b1;
		rd_req <= 1'b1;
		state <= state + 8'd1;
	end
	
	3: begin
		if (bpp==3'd5 || bpp==3'd6) begin	// If 8BPP or 16BPP...
			offset <= store0[25:16];		// offset is 10 bits. (first byte of store0 is padded with six zeros).
			pack_type <= store0[15:14]; 	// Type is two bits.
			count <= store0[13:8];			// Count is six bits.
			pix_sel <= 5'd0; 				// ?? TODO: Calc this for 8BPP / 16BPP.
		end
		else begin							// If 1,2,4,6BPP...
			offset <= store0[31:24];		// offset is 8 bits (first byte).
			pack_type <= store0[23:22]; 	// Type is two bits.
			count <= store0[21:16];			// Count is six bits.
			if (bpp==3'd4) pix_sel <= 5'd24;// If 6BPP format, set the first pixel bitgroup. (because 6BPP is evil).
			else pix_sel <= 5'd0;			// For 1,2,4BPP, select the first bit group.
		end
		word_sel <= 1'b0;				// Clear for later.
		state <= state + 8'd1;
	end
	
	4: begin
		/*case (pack_type)
		PACK_EOL: begin eol <= 1'b1; state <= 8'd0; end
		PACK_LITERAL: state <= state + 8'd1;
		PACK_TRANSP: state <= 8'd10;	// Todo!
		PACK_REPEAT: state <= 8'd4;	// TESTING !!
		default: state <= 8'd0;
		endcase*/
		/*if (pack_type==PACK_EOL) begin eol <= 1'b1; state <= 8'd0; end
		else*/ state <= state + 8'd1;
	end
	
	5: begin	// PACK_LITERAL.
		if (next_pix) begin
			if (pack_type==PACK_LITERAL) pix_sel <= pix_sel + 1;	// Only increment pix_sel for LITERAL pixels, not transp nor repeat.
			count <= count - 1;										// Still decrement the count, for TRANSP and REPEAT pixels.
		end
		else if (count==6'd0) begin
			state <= 8'd1;
		end
		
		if (pack_type==PACK_LITERAL && pix_sel==5'd6  || pix_sel==5'd22 ) begin word_sel <= 1'b0; rd_req <= 1'b1; end
		if (pack_type==PACK_LITERAL && pix_sel==5'd11 || pix_sel==5'd27 ) begin word_sel <= 1'b1; rd_req <= 1'b1; end
	end
	
	default: ;
	endcase
end


/*
// 1BPP...
assign pix1  = store[63-pix_sel];

// 2BPP...
assign pix2  = store[63-(pix_sel<<1): 62-(pix_sel<<1)];

// 4BPP...
assign pix4  = store[63-(pix_sel<<2): 60-(pix_sel<<2)];

// 8BPP...
assign pix8  = store[63-(pix_sel<<3): 56-(pix_sel<<3)];

// 16BPP...
assign pix16 = store[63-(pix_sel<<4): 48-(pix_sel<<4)];
*/


// 6BPP...
always @(*) begin
	case (pix_sel[4:0])
		5'd0:  pix6 = store0[31:26];
		5'd1:  pix6 = store0[25:20];
		5'd2:  pix6 = store0[19:14];
		5'd3:  pix6 = store0[13:08];
		5'd4:  pix6 = store0[07:02];
		5'd5:  pix6 = {store0[01:00], store1[31:28]};
		5'd6:  pix6 = store1[27:22];
		5'd7:  pix6 = store1[21:16];
		5'd8:  pix6 = store1[15:10];
		5'd9:  pix6 = store1[09:04];
		5'd10: pix6 = {store1[03:00], store0[31:30]};
		5'd11: pix6 = store0[29:24];
		5'd12: pix6 = store0[23:18];
		5'd13: pix6 = store0[17:12];
		5'd14: pix6 = store0[11:06];
		5'd15: pix6 = store0[05:00];
		5'd16: pix6 = store1[31:26];
		5'd17: pix6 = store1[25:20];
		5'd18: pix6 = store1[19:14];
		5'd19: pix6 = store1[13:08];
		5'd20: pix6 = store1[07:02];
		5'd21: pix6 = {store1[01:00], store0[31:28]};
		5'd22: pix6 = store0[27:22];
		5'd23: pix6 = store0[21:16];
		5'd24: pix6 = store0[15:10];
		5'd25: pix6 = store0[09:04];
		5'd26: pix6 = {store0[03:00], store1[31:30]};
		5'd27: pix6 = store1[29:24];
		5'd28: pix6 = store1[23:18];
		5'd29: pix6 = store1[17:12];
		5'd30: pix6 = store1[11:06];
		5'd31: pix6 = store1[05:00];
		default: ;
	endcase
end

endmodule
