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


reg [31:0] store;
reg [23:0] dat;

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
reg shift_24;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 8'd0;
	rd_req <= 1'b0;
	pix_sel <= 5'd0;
	eol <= 1'b0;
	store <= 32'h00000000;
	dat <= 24'h000000;
	shift <= 6'd0;
	shift_1 <= 1'b0;
	shift_2 <= 1'b0;
	shift_4 <= 1'b0;
	shift_6 <= 1'b0;
	shift_8 <= 1'b0;
	shift_16 <= 1'b0;
	shift_24 <= 1'b0;
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
	shift_24 <= 1'b0;
	
	if (shift>=6'd32) begin shift <= 6'd0; rd_req <= 1'b1; end
	else begin
		if (shift_1)  begin {dat, store} <= {dat[22:0], store, 1'b0}; shift <= shift + 6'd1; end
		if (shift_2)  begin {dat, store} <= {dat[21:0], store, 2'b00}; shift <= shift + 6'd2; end
		if (shift_4)  begin {dat, store} <= {dat[20:0], store, 4'b0000}; shift <= shift + 6'd4; end
		if (shift_6)  begin {dat, store} <= {dat[17:0], store, 6'b000000}; shift <= shift + 6'd6; end
		if (shift_8)  begin {dat, store} <= {dat[15:0], store, 8'h00}; shift <= shift + 6'd8; end
		if (shift_16) begin {dat, store} <= {dat[7:0], store, 16'h0000}; shift <= shift + 6'd16; end
		if (shift_24) begin {dat, store} <= {store, 24'h000000}; shift <= shift + 6'd24; end
	end
	
	if (rd_req) store <= din;

	case (state)
	0: if (start) begin
		state <= state + 8'd1;
	end
	
	1: begin
		rd_req <= 1'b1;		// Read the first 32-bit word into the store reg...
		state <= state + 8'd1;
	end
	
	2: begin
		if (bpp==3'd5 || bpp==3'd6) shift_24 <= 1'b1;	// If 8BPP or 16BPP, shift 24 (three bytes. 6-bit pad, 10-bit offset, 2-bit type, 6-bit count).
		else shift_16 <= 1'b1; 							// Else (1,2,4,6 BPP), shift 16 (two bytes. 8-bit offset, 2-bit type, 6-bit count).
		state <= state + 8'd1;
	end
	
	3: begin
		if (bpp==3'd5 || bpp==3'd6) offset <= dat[17:08];	// For 8BPP and 16BPP, the offset is 10 bits.
		else offset <= dat[15:08];							// For 1,2,4,6BPP, the offset is 8 bits.
		
		pack_type <= dat[07:06]; 		// Type is two bits.
		count <= dat[05:00];			// Count is six bits.
		state <= state + 8'd1;
	end
	
	4: begin
		/*if (pack_type==PACK_EOL) begin eol <= 1'b1; state <= 8'd0; end
		else*/ if (pack_type==PACK_REPEAT || pack_type==PACK_LITERAL) begin
			if (bpp==3'd1) shift_1  <= 1'b1;	// 1BPP
			if (bpp==3'd2) shift_2  <= 1'b1;	// 2BPP
			if (bpp==3'd3) shift_4  <= 1'b1;	// 4BPP
			if (bpp==3'd4) shift_6  <= 1'b1;	// 6BPP
			if (bpp==3'd5) shift_8  <= 1'b1;	// 8BPP
			if (bpp==3'd6) shift_16 <= 1'b1;	// 16BPP
		end
		state <= state + 8'd1;
	end
	
	5: begin
		if (next_pix) begin
			if (pack_type==PACK_LITERAL) begin
				if (bpp==3'd1) shift_1  <= 1'b1;	// 1BPP
				if (bpp==3'd2) shift_2  <= 1'b1;	// 2BPP
				if (bpp==3'd3) shift_4  <= 1'b1;	// 4BPP
				if (bpp==3'd4) shift_6  <= 1'b1;	// 6BPP
				if (bpp==3'd5) shift_8  <= 1'b1;	// 8BPP
				if (bpp==3'd6) shift_16 <= 1'b1;	// 16BPP
			end
			pix_valid <= 1'b1;
			count <= count - 1;							// Still decrement the count, for TRANSP and REPEAT pixels.
			state <= state + 1;
		end
		
		if (count==6'd0) begin
			//shift <= 6'd0;
			state <= 8'd2;
		end
	end
	
	6: begin
		state <= 8'd5;
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
