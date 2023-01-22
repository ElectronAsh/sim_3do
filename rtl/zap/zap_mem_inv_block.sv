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
// This RTL describes RAM with single cycle invalidate via flip-flops. The
// valid bits per memory row are maintained using flip-flops. This avoids
// having to do an actual memory write to invalidate the memory. This allows
// bulk invalidation to happen in a single cycle.
//

module zap_mem_inv_block #(
        parameter [31:0] DEPTH = 32,
        parameter [31:0] WIDTH = 32   // Not including valid bit.
)(


        input logic                           i_clk,
        input logic                           i_reset,

        // Read enable/Clock enable.
        input logic                           i_clken,

        // Write data.
        input logic   [WIDTH-1:0]             i_wdata,

        // Write enable. Also required i_clken.
        input logic                           i_wen,

        // Invalidate entries in 1 cycle.
        input logic                           i_inv,

        // Read and write address.
        input logic   [$clog2(DEPTH)-1:0]     i_raddr,
        input logic   [$clog2(DEPTH)-1:0]     i_waddr,

        // Read data and valid.
        output logic [WIDTH-1:0]              o_rdata_pre,
        output logic                          o_rdav_pre,

        // Read data and valid.
        output logic [WIDTH-1:0]              o_rdata,
        output logic                          o_rdav
);

// These are valid bits corresponding to each memory location.
logic [DEPTH-1:0]         dav_ff;

logic                     rdav_st1;

logic [$clog2(DEPTH)-1:0] raddr_del;
logic [$clog2(DEPTH)-1:0] raddr_del2;

//
// Detect conflicts at each pipeline stage. When a conflict happens, make
// the dav=1. This is intended to reflect the write data on the read
// side.
//
logic conflict_st1, conflict_st2, conflict_st3;

// Block RAM.
zap_ram_simple #(.WIDTH(WIDTH), .DEPTH(DEPTH)) u_ram_simple (
        .i_clk     ( i_clk ),
        .i_clken   ( i_clken ),

        .i_wr_en   ( i_wen ),
        .i_wr_data ( i_wdata ),

        .o_rd_data_pre ( o_rdata_pre ),
        .o_rd_data     ( o_rdata ),

        .i_wr_addr ( i_waddr ),
        .i_rd_addr ( i_raddr )
);

////////////////////////////
// Write logic.
////////////////////////////

// Set valid bit on write. Clear valid bits on invalidate.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
               dav_ff <= '0;
        end
        else if ( i_inv )
        begin
               dav_ff <= {DEPTH{1'd0}};
        end
        else if ( i_wen && i_clken )
        begin
              dav_ff [ i_waddr ] <= 1'd1;
        end
end

////////////////////////////
// Read logic.
////////////////////////////

// ----------------------------------------------------------------------------
// Stage 1
// ----------------------------------------------------------------------------

// If write and read target the same address, there is a conflict.
assign conflict_st1 = i_raddr == i_waddr && i_wen;

always @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                rdav_st1 <= '0;
        end
        else if ( i_inv )
        begin
                rdav_st1 <= 1'd0;
        end
        else if ( i_clken )
        begin
                rdav_st1 <= conflict_st1 ? 1'd1 : dav_ff [ i_raddr ];
        end
end

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                raddr_del <= '0;
        end
        else if ( i_inv )
        begin
                raddr_del <= '0;
        end
        else if ( i_clken )
        begin
                raddr_del <= i_raddr;
        end
end

// ----------------------------------------------------------------------------
// Stage 2
// ----------------------------------------------------------------------------

// If write address and read delay target are same, there is a conflict.
assign conflict_st2 = raddr_del == i_waddr && i_wen;

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                o_rdav_pre <= 1'd0;
        end
        else if ( i_inv )
        begin
                o_rdav_pre <= 1'd0;
        end
        else if  ( i_clken )
        begin
                o_rdav_pre <= conflict_st2 ? 1'd1 : rdav_st1;
        end
end

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                raddr_del2 <= '0;
        end
        else if ( i_inv )
        begin
                raddr_del2 <= '0;
        end
        else if ( i_clken )
        begin
                raddr_del2 <= raddr_del;
        end
end

// ----------------------------------------------------------------------------
// Stage 3
// ----------------------------------------------------------------------------

// If write address and read delay-delay are same, there is a conflict.
assign conflict_st3 = raddr_del2 == i_waddr && i_wen;

always_ff @  (posedge i_clk )
begin
        if ( i_reset )
        begin
                o_rdav <= '0;
        end
        else if ( i_inv )
        begin
                o_rdav <= 1'd0;
        end
        else if ( i_clken )
        begin
                o_rdav <= conflict_st3 ? 1'd1 : o_rdav_pre;
        end
end

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
