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
// --                                                                         -- 
// --  Synthesizes to standard 1R + 1W block RAM. The read and write addresses--
// --  may be specified separately. Only for FPGA.                            --
// --                                                                         --
// -----------------------------------------------------------------------------

module zap_ram_simple_nopipe #(
        parameter WIDTH = 32,
        parameter DEPTH = 32
)
(
        input logic                          i_clk,

        // Write and read enable.
        input logic                          i_wr_en,
        input logic                          i_rd_en,

        // Write data and address.
        input logic [WIDTH-1:0]              i_wr_data,
        input logic[$clog2(DEPTH)-1:0]       i_wr_addr,

        // Read address and data.
        input logic [$clog2(DEPTH)-1:0]      i_rd_addr,
        output logic [WIDTH-1:0]             o_rd_data
);

// Memory array.
logic [WIDTH-1:0] mem [DEPTH-1:0];

// Hazard detection.
logic [WIDTH-1:0] mem_data;
logic [WIDTH-1:0] buffer;
logic             sel;

// Hazard Detection Logic
always_ff @ ( posedge i_clk )
begin
        if ( i_wr_addr == i_rd_addr && i_wr_en && i_rd_en )
                sel <= 1'd1;
        else
                sel <= 1'd0;                
end

// Buffer update logic.
always_ff @ ( posedge i_clk )
begin
        if ( i_wr_addr == i_rd_addr && i_wr_en && i_rd_en )
                buffer <= i_wr_data;
end

// Read logic.
always_ff @ (posedge i_clk)
begin
        if ( i_rd_en )
                mem_data <= mem [ i_rd_addr ];
end

// Output logic.
always_comb
begin
        if ( sel )
                o_rd_data = buffer;
        else
                o_rd_data = mem_data;
end

// Write logic.
always_ff @ (posedge i_clk)
begin
        if ( i_wr_en )  
                mem [ i_wr_addr ] <= i_wr_data;
end

endmodule // zap_ram_simple.v


// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
