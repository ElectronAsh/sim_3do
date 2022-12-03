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
// --  Synthesizes to standard 1R + 1W block RAM. The read and write addresses--
// --  may be specified separately.                                           --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

module zap_ram_simple #(
        parameter WIDTH = 32,
        parameter DEPTH = 32
)
(
        input wire                          i_clk,

        // Write and read enable.
        input wire                          i_wr_en,
        input wire                          i_rd_en,

        // Write data and address.
        input wire [WIDTH-1:0]              i_wr_data,
        input wire[$clog2(DEPTH)-1:0]       i_wr_addr,

        // Read address and data.
        input wire [$clog2(DEPTH)-1:0]      i_rd_addr,
        output reg [WIDTH-1:0]              o_rd_data
);

// Memory array.
reg [WIDTH-1:0] mem [DEPTH-1:0];

// Initialize block RAM to 0.
initial
begin: blk1
        integer i;

        for(i=0;i<DEPTH;i=i+1)
                mem[i] = {WIDTH{1'd0}};
end

// Read logic.
always @ (posedge i_clk)
begin
        if ( i_rd_en )
                o_rd_data <= mem [ i_rd_addr ];
end

// Write logic.
always @ (posedge i_clk)
begin
        if ( i_wr_en )  
                mem [ i_wr_addr ] <= i_wr_data;
end

endmodule // ram_simple.v
`default_nettype wire
