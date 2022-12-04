// -----------------------------------------------------------------------------
// --                                                                         --
// --    (C) 2016-2022 Revanth Kamaraj (krevanth)                             --
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
// Flip flop based register files. Good for FPGA where flip-flops are         --
// plentiful.                                                                 --
// -----------------------------------------------------------------------------

module zap_register_file
(
        input logic              i_clk,
        input logic              i_reset,

        input logic              i_wen,
        input logic  [5:0]       i_wr_addr_a, 
        input logic  [5:0]       i_wr_addr_b,       // 3 write addresses.
        input logic  [39:0]      i_wr_addr_c,

        input logic  [31:0]      i_wr_data_a, 
        input logic  [31:0]      i_wr_data_b,       // 3 write data.
        input logic  [31:0]      i_wr_data_c,

        input logic  [5:0]       i_rd_addr_a, 
        input logic  [5:0]       i_rd_addr_b, 
        input logic  [5:0]       i_rd_addr_c, 
        input logic  [5:0]       i_rd_addr_d,

        output logic  [31:0]      o_rd_data_a,
        output logic  [31:0]      o_rd_data_b, 
        output logic  [31:0]      o_rd_data_c, 
        output logic  [31:0]      o_rd_data_d
);

logic [39:0][31:0] mem; // Flip-flop array.

// 2 write ports. Synchronous reset for the register file.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                mem <= {32'd40{32'd0}};
        end
        else
        begin
                if ( i_wen )
                begin
                        mem [ i_wr_addr_a ] <= i_wr_data_a;
                        mem [ i_wr_addr_b ] <= i_wr_data_b;
                end

                if ( |i_wr_addr_c )
                begin
                        for(int i=0;i<40;i++)
                        begin
                                if(i_wr_addr_c[i])
                                begin
                                        mem [i] <= i_wr_data_c;
                                end
                        end
                end
        end
end

// 4 read ports.
always_comb
begin
        o_rd_data_a = mem [ i_rd_addr_a ];
        o_rd_data_b = mem [ i_rd_addr_b ];
        o_rd_data_c = mem [ i_rd_addr_c ];
        o_rd_data_d = mem [ i_rd_addr_d ];
end

endmodule



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
