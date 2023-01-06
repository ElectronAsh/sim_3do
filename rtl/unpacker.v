module unpacker (
	input clock,
	input reset_n,
	
	input [2:0] bpp,
	
	input start,
	input [31:0] din,
	output reg rd_req,	// rd_req will externally increment the dma_addr in madam.v.
	
	input next_pix,
	output reg eol,
	
	output [15:0] col_out,
	output reg pix_valid
);

parameter PACK_EOL     = 2'b00;
parameter PACK_LITERAL = 2'b01;
parameter PACK_TRANSP  = 2'b10;
parameter PACK_REPEAT  = 2'b11;


reg [15:0] dat;
reg [63:0] store;
wire [31:0] store_u = store[63:32];
wire [31:0] store_l = store[31:00];

reg [9:0] offset;
reg [1:0] pack_type;
reg [5:0] count;

reg [7:0] state;
reg [4:0] pix_sel;
reg [5:0] shift;

reg shift_1;
reg shift_2;
reg shift_4;
reg shift_6;
reg shift_8;
reg shift_16;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 8'd0;
	rd_req <= 1'b0;
	pix_sel <= 5'd0;
	eol <= 1'b0;
	dat <= 16'h0000;
	store <= 64'h0000000000000000;
	shift <= 6'd0;
	shift_1 <= 1'b0;
	shift_2 <= 1'b0;
	shift_4 <= 1'b0;
	shift_6 <= 1'b0;
	shift_8 <= 1'b0;
	shift_16 <= 1'b0;
	pix_valid <= 1'b0;
end
else begin
	rd_req <= 1'b0;
	eol <= 1'b0;
	pix_valid <= 1'b0;
	
	shift_1 <= 1'b0;
	shift_2 <= 1'b0;
	shift_4 <= 1'b0;
	shift_6 <= 1'b0;
	shift_8 <= 1'b0;
	shift_16 <= 1'b0;
	
	if (shift>=32) begin store[32+(shift-32) +: 32] <= din; shift <= shift-32; rd_req <= 1'b1; end
	
	case (state)
	0: if (start) begin
		state <= state + 8'd1;
	end
	
	// Start of each ROW...
	1: begin
		shift <= 0;
		rd_req <= 1'b1;		// Read the first 32-bit word into the store reg...
		state <= state + 8'd1;
	end
	
	2: begin
		store[63:32] <= din;
		state <= state + 8'd1;
	end
	
	3: begin
		if (bpp==3'd5 || bpp==3'd6) begin {dat, store} <= {store, 16'h0000}; shift <= shift + 6'd16; end	// If 8BPP or 16BPP, shift 16 (two bytes. 6-bit pad, 10-bit offset).
		else begin {dat, store} <= {store, 8'h00}; shift <= shift + 6'd8; end 								// Else (1,2,4,6 BPP), shift 8 (one bytes. 8-bit offset).
		state <= state + 8'd1;
	end
	
	4: begin
		if (bpp==3'd5 || bpp==3'd6) offset <= dat[09:00];	// For 8BPP and 16BPP, the offset is 10 bits.
		else offset <= dat[07:00];							// For 1,2,4,6BPP, the offset is 8 bits.
		rd_req <= 1'b1;					// Pre-request next 32-bit word!
		state <= state + 8'd1;
	end
	
	// Start of each PACKET...
	5: begin
		begin {dat, store} <= {store, 8'h00}; shift <= shift + 6'd8; end	// Shift in Type/Count byte...
		state <= state + 8'd1;
	end
	
	6: begin
		pack_type <= dat[07:06]; 	// Type is two bits.
		count <= dat[05:00];		// Count is six bits.
		state <= state + 8'd1;
	end
	
	7: begin
		if (pack_type==PACK_EOL) begin eol <= 1'b1; state <= 8'd1; end
		else if (pack_type==PACK_REPEAT || pack_type==PACK_LITERAL) begin
			// Shift in REPEAT or first LITERAL pixel from this packet.
			if (bpp==1) begin {dat, store} <= {store, 1'b0}; shift <= shift + 6'd1; end			// 1BPP
			if (bpp==2) begin {dat, store} <= {store, 2'b00}; shift <= shift + 6'd2; end		// 2BPP
			if (bpp==3) begin {dat, store} <= {store, 4'b0000}; shift <= shift + 6'd4; end		// 4BPP
			if (bpp==4) begin {dat, store} <= {store, 6'b000000}; shift <= shift + 6'd6; end	// 6BPP
			if (bpp==5) begin {dat, store} <= {store, 8'h00}; shift <= shift + 6'd8; end		// 8BPP
			if (bpp==6) begin {dat, store} <= {store, 16'h0000}; shift <= shift + 6'd16; end	// 16BPP
			state <= state + 8'd1;
		end
		else state <= state + 8'd1;	// "Transparent" pixel. (will decrement count, but will not do a write to the framebuffer).
	end
	
	8: begin
		if (next_pix) begin
			if (pack_type==PACK_LITERAL) state <= state + 1;	// Only shift in the next pixel(s) if pack_type is LITERAL.
			pix_valid <= 1'b1;
			count <= count - 1;		// Still decrement the count, for TRANSP and REPEAT pixels.
		end
		
		if (count==6'd0) state <= 8'd5;		// Read in next PACKET.
	end
	
	9: begin
		if (bpp==1) begin {dat, store} <= {store, 1'b0}; shift <= shift + 6'd1; end			// 1BPP
		if (bpp==2) begin {dat, store} <= {store, 2'b00}; shift <= shift + 6'd2; end		// 2BPP
		if (bpp==3) begin {dat, store} <= {store, 4'b0000}; shift <= shift + 6'd4; end		// 4BPP
		if (bpp==4) begin {dat, store} <= {store, 6'b000000}; shift <= shift + 6'd6; end	// 6BPP
		if (bpp==5) begin {dat, store} <= {store, 8'h00}; shift <= shift + 6'd8; end		// 8BPP
		if (bpp==6) begin {dat, store} <= {store, 16'h0000}; shift <= shift + 6'd16; end	// 16BPP
		state <= 8'd8;
	end
	
	default: ;
	endcase
end

assign col_out = (bpp==3'd1) ? dat[0] :		// 1BPP
				 (bpp==3'd2) ? dat[1:0] :	// 2BPP
				 (bpp==3'd3) ? dat[3:0] :	// 4BPP
				 (bpp==3'd4) ? dat[5:0] :	// 6BPP
				 (bpp==3'd5) ? dat[7:0] :	// 8BPP
				 (bpp==3'd6) ? dat[15:0] :	// 16BPP
								15'hAA55;		// default (bpp==0 and bpp==7 are reserved).


endmodule
