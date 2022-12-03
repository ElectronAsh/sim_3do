// -----------------------------------------------------------------------------
// --                                                                         --
// --                   (C) 2016-2018 Revanth Kamaraj.                        --
// --                                                                         -- 
// -- --------------------------------------------------------------------------
// --                                                                         --
// -- This program is free software; you can redistribute it and/or           --
// -- modify it under the terms of the GNU General Public License             --
// -- as published by the Free Software Foundation; either version 2          --
// -- of the License, or (at your option) any later version.                  --
// --                                                                         --
// -- This program is distributed in the hope that it will be useful,         --
// -- but WITHOUT ANY WARRANTY; without even the implied warranty of          --
// -- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the           --
// -- GNU General Public License for more details.                            --
// --                                                                         --
// -- You should have received a copy of the GNU General Public License       --
// -- along with this program; if not, write to the Free Software             --
// -- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA           --
// -- 02110-1301, USA.                                                        --
// --                                                                         --
// -----------------------------------------------------------------------------
// --                                                                         -- 
// --  ZAP register file implemented using flip-flops which makes sense for an--
// --  FPGA implementation where flip-flops are plentiful.                    --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

module zap_register_file
(
        input wire              i_clk,

        input wire              i_reset,

        input wire              i_wen,

        input wire  [5:0]       i_wr_addr_a, 
                                i_wr_addr_b,       // 2 write addresses.

        input wire  [31:0]      i_wr_data_a, 
                                i_wr_data_b,       // 2 write data.

        input wire  [5:0]       i_rd_addr_a, 
                                i_rd_addr_b, 
                                i_rd_addr_c, 
                                i_rd_addr_d,

        output reg  [31:0]      o_rd_data_a,
                                o_rd_data_b, 
                                o_rd_data_c, 
                                o_rd_data_d
);

// Dual distributed RAM setup.
reg [31:0] mem [39:0];
reg [31:0] MEM [39:0];

initial
begin: blk1
        integer i;
        
        for(i=0;i<40;i=i+1)
	begin
                mem[i] = 0;
                MEM[i] = 0;
	end
end

reg [39:0] sel;

// assertions_start
        wire [31:0] r0;  assign r0 =  sel[0]  ? MEM[0] : mem[0]; 
        wire [31:0] r1;  assign r1 =  sel[1]  ? MEM[1] : mem[1];
        wire [31:0] r2;  assign r2 =  sel[2]  ? MEM[2] : mem[2];
        wire [31:0] r3;  assign r3 =  sel[3]  ? MEM[3] : mem[3];
        wire [31:0] r4;  assign r4 =  sel[4]  ? MEM[4] : mem[4];
        wire [31:0] r5;  assign r5 =  sel[5]  ? MEM[5] : mem[5];
        wire [31:0] r6;  assign r6 =  sel[6]  ? MEM[6] : mem[6];
        wire [31:0] r7;  assign r7 =  sel[7]  ? MEM[7] : mem[7];
        wire [31:0] r8;  assign r8 =  sel[8]  ? MEM[8] : mem[8];
        wire [31:0] r9;  assign r9 =  sel[9]  ? MEM[9] : mem[9];
        wire [31:0] r10; assign r10 = sel[10] ? MEM[10] : mem[10];
        wire [31:0] r11; assign r11 = sel[11] ? MEM[11] : mem[11];
        wire [31:0] r12; assign r12 = sel[12] ? MEM[12] : mem[12];
        wire [31:0] r13; assign r13 = sel[13] ? MEM[13] : mem[13];
        wire [31:0] r14; assign r14 = sel[14] ? MEM[14] : mem[14];
        wire [31:0] r15; assign r15 = sel[15] ? MEM[15] : mem[15];
        wire [31:0] r16; assign r16 = sel[16] ? MEM[16] : mem[16];
        wire [31:0] r17; assign r17 = sel[17] ? MEM[17] : mem[17];
        wire [31:0] r18; assign r18 = sel[18] ? MEM[18] : mem[18];
        wire [31:0] r19; assign r19 = sel[19] ? MEM[19] : mem[19];
        wire [31:0] r20; assign r20 = sel[20] ? MEM[20] : mem[20];
        wire [31:0] r21; assign r21 = sel[21] ? MEM[21] : mem[21];
        wire [31:0] r22; assign r22 = sel[22] ? MEM[22] : mem[22];
        wire [31:0] r23; assign r23 = sel[23] ? MEM[23] : mem[23];
        wire [31:0] r24; assign r24 = sel[24] ? MEM[24] : mem[24];
        wire [31:0] r25; assign r25 = sel[25] ? MEM[25] : mem[25];
        wire [31:0] r26; assign r26 = sel[26] ? MEM[26] : mem[26];
        wire [31:0] r27; assign r27 = sel[27] ? MEM[27] : mem[27];
        wire [31:0] r28; assign r28 = sel[28] ? MEM[28] : mem[28];
        wire [31:0] r29; assign r29 = sel[29] ? MEM[29] : mem[29];
        wire [31:0] r30; assign r30 = sel[30] ? MEM[30] : mem[30];
        wire [31:0] r31; assign r31 = sel[31] ? MEM[31] : mem[31];
        wire [31:0] r32; assign r32 = sel[32] ? MEM[32] : mem[32];
        wire [31:0] r33; assign r33 = sel[33] ? MEM[33] : mem[33];
        wire [31:0] r34; assign r34 = sel[34] ? MEM[34] : mem[34];
        wire [31:0] r35; assign r35 = sel[35] ? MEM[35] : mem[35];
        wire [31:0] r36; assign r36 = sel[36] ? MEM[36] : mem[36];
        wire [31:0] r37; assign r37 = sel[37] ? MEM[37] : mem[37];
        wire [31:0] r38; assign r38 = sel[38] ? MEM[38] : mem[38];
        wire [31:0] r39; assign r39 = sel[39] ? MEM[39] : mem[39];
// assertions_end

always @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                sel <= 40'd0;
        end
        else
        begin
                sel [ i_wr_addr_a ] <= 1'd0;
                sel [ i_wr_addr_b ] <= 1'd1;
        end
end

always @ (posedge i_clk)
begin
        if ( i_wen )
        begin
                mem [ i_wr_addr_a ] <= i_wr_data_a;
                MEM [ i_wr_addr_b ] <= i_wr_data_b;
        end
end

always @*
begin
        o_rd_data_a = sel[i_rd_addr_a] ? MEM [ i_rd_addr_a ] : mem [ i_rd_addr_a ];
        o_rd_data_b = sel[i_rd_addr_b] ? MEM [ i_rd_addr_b ] : mem [ i_rd_addr_b ];
        o_rd_data_c = sel[i_rd_addr_c] ? MEM [ i_rd_addr_c ] : mem [ i_rd_addr_c ];
        o_rd_data_d = sel[i_rd_addr_d] ? MEM [ i_rd_addr_d ] : mem [ i_rd_addr_d ];
end

endmodule // bram_wrapper.v
`default_nettype wire
