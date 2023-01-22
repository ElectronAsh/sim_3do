//
// (C) 2016-2022 Revanth Kamaraj (krevanth)
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 3
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
// 02110-1301, USA.
//
//  Synthesizes to standard 1R + 1W block RAM. The read and write addresses
//  may be specified separately. This synthesizes as a single cycle
//  memory, which behaves as a write first memory, even though the macro
//  is a standard read first memory. This memory provides a read latency
//  of 1 cycle.
//

module zap_ram_simple_nopipe #(
        parameter logic [31:0] WIDTH = 32'd32,
        parameter logic [31:0] DEPTH = 32'd32
)
(
        // Clock
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

/////////////////////////////////
// SRAM (Read First)
/////////////////////////////////

// Memory array.
logic [WIDTH-1:0] mem [DEPTH-1:0];
logic [WIDTH-1:0] mem_rd_data;

always_ff @ (posedge i_clk) if ( i_rd_en ) mem_rd_data <= mem [ i_rd_addr ];
always_ff @ (posedge i_clk) if ( i_wr_en ) mem [ i_wr_addr ] <= i_wr_data;

/////////////////////////////////
// Steering logic.
/////////////////////////////////

logic [WIDTH-1:0] buffer_ff, buffer_nxt;
logic             hazard_ff, hazard_nxt;
logic             addr_conflict;
logic             concurrent_access;

assign addr_conflict     = i_wr_addr == i_rd_addr ? 1'd1 : 1'd0;
assign concurrent_access = i_wr_en & i_rd_en;

// If a read to address X happens on the same cycle as write to address X,
// it is a hazard.
assign hazard_nxt = addr_conflict & concurrent_access;

always_ff @ ( posedge i_clk)
begin
        hazard_ff <= hazard_nxt;
end

// Buffer the write data in case of hazard.
assign buffer_nxt = hazard_nxt ? i_wr_data : {WIDTH{1'dx}};

always_ff @ ( posedge i_clk )
begin
        buffer_ff <= buffer_nxt;
end

// And forward it to the output in case of hazard.
assign o_rd_data = hazard_ff ? buffer_ff : mem_rd_data;

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
