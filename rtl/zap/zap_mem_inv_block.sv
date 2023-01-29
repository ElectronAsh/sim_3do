// ---------------------------------------------------------------------------
// --                                                                       --
// --    (C) 2016-2022 Revanth Kamaraj (krevanth)                           --
// --                                                                       -- 
// -- ------------------------------------------------------------------------
// --                                                                       --
// -- This program is free software; you can redistribute it and/or         --
// -- modify it under the terms of the GNU General Public License           --
// -- as published by the Free Software Foundation; either version 2        --
// -- of the License, or (at your option) any later version.                --
// --                                                                       --
// -- This program is distributed in the hope that it will be useful,       --
// -- but WITHOUT ANY WARRANTY; without even the implied warranty of        --
// -- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the         --
// -- GNU General Public License for more details.                          --
// --                                                                       --
// -- You should have received a copy of the GNU General Public License     --
// -- along with this program; if not, write to the Free Software           --
// -- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA         --
// -- 02110-1301, USA.                                                      --
// --                                                                       --
// ---------------------------------------------------------------------------

// RAMs with single cycle invalidate via flip-flops.
module zap_mem_inv_block #(
        parameter DEPTH = 32,
        parameter WIDTH = 32   // Not including valid bit.
)(  


        input logic                           i_clk,
        input logic                           i_reset,
        input logic                           i_clken,

        // Write data.
        input logic   [WIDTH-1:0]             i_wdata,

        // Write and read enable.
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


logic [DEPTH-1:0]         dav_ff;
logic                     rdav_st1;
logic [$clog2(DEPTH)-1:0] raddr_del, raddr_del2;

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

// ----------------------------------------------------------------------------
// Stage 1
// ----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
               dav_ff <= '0;
        else if ( i_inv )
               dav_ff <= {DEPTH{1'd0}};
        else if ( i_wen && i_clken )
              dav_ff [ i_waddr ] <= 1'd1;
end

always @ ( posedge i_clk )
begin
        if ( i_reset )
                rdav_st1 <= '0;
        else if ( i_inv )
                rdav_st1 <= 1'd0;
        else if ( i_clken )
                rdav_st1 <= i_raddr == i_waddr && i_wen ? 1'd1 : dav_ff [ i_raddr ];
end

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
                raddr_del <= '0;
        else if ( i_inv )
                raddr_del <= '0;
        else if ( i_clken )
                raddr_del <= i_raddr;
end

// ----------------------------------------------------------------------------
// Stage 2
// ----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
                o_rdav_pre <= 1'd0;
        else if ( i_inv )
                o_rdav_pre <= 1'd0;
        else if  ( i_clken )
                o_rdav_pre <= i_waddr == raddr_del && i_wen ? 1'd1 : rdav_st1;
end

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
                raddr_del2 <= '0;
        else if ( i_inv )
                raddr_del2 <= '0;
        else if ( i_clken )
                raddr_del2 <= raddr_del;
end

// ----------------------------------------------------------------------------
// Stage 3
// ----------------------------------------------------------------------------

always_ff @  (posedge i_clk )
begin   
        if ( i_reset )
                o_rdav <= '0;
        else if ( i_inv )
                o_rdav <= 1'd0;
        else if ( i_clken )
                o_rdav <= i_waddr == raddr_del2 && i_wen ? 1'd1 : o_rdav_pre;
end

endmodule // mem_inv_block.v

