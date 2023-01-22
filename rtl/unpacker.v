module unpacker (
	input clock,
	input reset_n,
	
	input [2:0] bpp,
	input [3:0] skipx,
	
	input [31:0] sourceptr,
	output reg [31:0] up_addr,
	
	input start,
	input [31:0] din,
	output reg rd_req,	// rd_req will externally increment the dma_addr in madam.v.
	
	input next_pix,
	output reg eol,
	
	output reg [15:0] col_out,
	output reg pix_valid
);

parameter PACK_EOL     = 2'b00;
parameter PACK_LITERAL = 2'b01;
parameter PACK_TRANSP  = 2'b10;
parameter PACK_REPEAT  = 2'b11;


reg [47:0] store;
wire [15:0] store_u = store[47:32];
wire [31:0] store_l = store[31:00];

reg [9:0] offset;
reg [15:0] row_offset;

reg [1:0] pack_type;
reg [6:0] count;

reg [7:0] state;
reg [4:0] pix_sel;
reg [5:0] shift;

reg repeat_done;

reg shift_1;
reg shift_2;
reg shift_4;
reg shift_6;
reg shift_8;
reg shift_16;

wire [47:0] store_in = {store[47:32], din} << shift;

always @(posedge clock or negedge reset_n)
if (!reset_n) begin
	state <= 8'd0;
	rd_req <= 1'b0;
	pix_sel <= 5'd0;
	eol <= 1'b0;
	store <= 48'h000000000000;
	shift <= 6'd0;
	shift_1 <= 1'b0;
	shift_2 <= 1'b0;
	shift_4 <= 1'b0;
	shift_6 <= 1'b0;
	shift_8 <= 1'b0;
	shift_16 <= 1'b0;
	pix_valid <= 1'b0;
	offset <= 10'd0;
	count <= 7'd0;
	row_offset <= 16'd0;
	repeat_done <= 1'b0;
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
	
	if (shift>=32) begin
		store[(shift-32) +: 32] <= din;
		shift <= shift-32;
		rd_req <= 1'b1;
		up_addr <= up_addr + 4;
		$display("shift in!");
	end
	
	case (state)
	0: if (start) begin
		offset <= 10'd0;
		row_offset <= 16'd0;
		state <= state + 8'd1;
	end
	
	// Start of each ROW...
	1: begin
		shift <= 0;
		up_addr <= sourceptr + row_offset;
		rd_req <= 1'b1;			// Read the first 32-bit word into the store reg...
		state <= state + 8'd1;
	end
	
	2: begin
		store[31:00] <= din;
		$display("row_offset: 0x%08X  First Word: 0x%08X", row_offset, din);
		state <= state + 8'd1;
	end
	
	3: begin
		if (bpp==3'd5 || bpp==3'd6) begin store <= {store, 16'h0000}; shift <= shift + 6'd16; end	// If 8BPP or 16BPP, shift 16 (two bytes. 6-bit pad, 10-bit offset).
		else begin store <= {store, 8'h00}; shift <= shift + 6'd8; end 								// Else (1,2,4,6 BPP), shift 8 (one bytes. 8-bit offset).
		state <= state + 8'd1;
	end
	
	4: begin
		if (bpp==3'd5 || bpp==3'd6) offset <= store_u[09:00];	// For 8BPP and 16BPP, the offset is 10 bits. offset is in WORDS-2.
		else offset <= store_u[07:00];							// For 1,2,4,6BPP, the offset is 8 bits.
		rd_req <= 1'b1;					// Pre-request next 32-bit word!
		up_addr <= up_addr + 4;
		state <= state + 8'd1;
	end
	
	// Start of each PACKET...
	5: begin
		begin store <= {store, 8'h00}; shift <= shift + 6'd8; end	// Shift in Type/Count byte...
		repeat_done <= 1'b0;
		state <= state + 8'd1;
	end
	
	6: begin
		pack_type <= store_u[07:06]; 	// Type is two bits.
		count <= store_u[05:00] + 1;	// Count is six bits.
		//$display("row_offset: 0x%03X", row_offset);
		state <= state + 8'd1;
	end
	
	7: begin
		if (pack_type==PACK_EOL) begin
			$display("EOL"); eol <= 1'b1;
			row_offset <= row_offset + ((offset+2) << 2);
			rd_req <= 1'b1;
			up_addr <= up_addr + 4;
			state <= 8'd1;
		end
		else state <= state + 8'd1;
	end

	8: begin
		if (count>6'd0) state <= state + 1;
		else state <= 8'd5;		// Read in next PACKET.
	end
	
	9: begin
		if ( (pack_type==PACK_REPEAT && !repeat_done) || pack_type==PACK_LITERAL) begin
			if (bpp==1) begin store <= {store, 1'b0}; shift <= shift + 6'd1; end		// 1BPP
			if (bpp==2) begin store <= {store, 2'b00}; shift <= shift + 6'd2; end		// 2BPP
			if (bpp==3) begin store <= {store, 4'b0000}; shift <= shift + 6'd4; end		// 4BPP
			if (bpp==4) begin store <= {store, 6'b000000}; shift <= shift + 6'd6; end	// 6BPP
			if (bpp==5) begin store <= {store, 8'h00}; shift <= shift + 6'd8; end		// 8BPP
			if (bpp==6) begin store <= {store, 16'h0000}; shift <= shift + 6'd16; end	// 16BPP
		end
		state <= state + 8'd1;
	end
	
	10: begin	// Need time to allow the next new word to be loaded into "store", if necessary.
		state <= state + 8'd1;
	end
	
	11: begin
		if (pack_type==PACK_TRANSP && !repeat_done) $display("TRANSP  Count: %d", count);
		if (pack_type==PACK_REPEAT && !repeat_done) $display("REPEAT   0x%04X  Count: %d  store: 0x%02X%08X  ", col_out, count, store_u,store_l);
		if (pack_type==PACK_LITERAL) $display("LITERAL  0x%04X  Count: %d  store: 0x%02X%08X  ", col_out, count, store_u,store_l);
		pix_valid <= 1'b1;
		repeat_done <= 1'b1;
		count <= count - 1;
		state <= 8'd8;
	end
	
	default: ;
	endcase
end

assign col_out = (bpp==3'd1) ? store_u[0] :	// 1BPP
				 (bpp==3'd2) ? store_u[1:0] :	// 2BPP
				 (bpp==3'd3) ? store_u[3:0] :	// 4BPP
				 (bpp==3'd4) ? store_u[5:0] :	// 6BPP
				 (bpp==3'd5) ? store_u[7:0] :	// 8BPP
				 (bpp==3'd6) ? store_u[15:0] :	// 16BPP
									15'h0000;	// default (bpp==0 and bpp==7 are reserved).
									
/*
assign col_out = (bpp==3'd1) ? store_in[8] :	// 1BPP
				 (bpp==3'd2) ? store_in[9:8] :	// 2BPP
				 (bpp==3'd3) ? store_in[11:8] :	// 4BPP
				 (bpp==3'd4) ? store_in[13:8] :	// 6BPP
				 (bpp==3'd5) ? store_in[15:8] :	// 8BPP
				 (bpp==3'd6) ? store_in[23:8] :	// 16BPP
									15'hAA55;	// default (bpp==0 and bpp==7 are reserved).

*/

endmodule
