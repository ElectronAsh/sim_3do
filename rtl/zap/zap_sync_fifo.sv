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
// -- This is a simple synchronous FIFO.                                      --
// -----------------------------------------------------------------------------



// FWFT means "First Word Fall Through".
module zap_sync_fifo #(
        parameter [31:0] WIDTH            = 32'd32, 
        parameter [31:0] DEPTH            = 32'd32, 
        parameter [31:0] FWFT             = 32'd1
)
(
        // Clock and reset
        input   logic             i_clk,
        input   logic             i_reset,

        // Flow control
        input   logic             i_ack,
        input   logic             i_wr_en,

        // Data busses
        input   logic [WIDTH-1:0] i_data,
        output  logic [WIDTH-1:0]  o_data,

        // Flags
        output logic              o_empty,
        output logic              o_full,
        output logic              o_empty_n,
        output logic              o_full_n,
        output logic              o_full_n_nxt
);

localparam PTR_WDT = $clog2(DEPTH) + 32'd1;

// Variables
logic [PTR_WDT-1:0] rptr_ff;
logic [PTR_WDT-1:0] rptr_nxt;
logic [PTR_WDT-1:0] wptr_ff;
logic               empty, nempty;
logic               full, nfull;
logic [PTR_WDT-1:0] wptr_nxt;
logic [WIDTH-1:0]   mem [DEPTH-1:0]; 
logic               unused;

// Assigns
always_comb unused  = |{FWFT, 1'd1};

always_comb o_empty = empty;
always_comb o_full  = full;
always_comb o_empty_n = nempty;
always_comb o_full_n = nfull;
always_comb o_full_n_nxt = i_reset ? 1 :
                      !( ( wptr_nxt[PTR_WDT-2:0] == rptr_nxt[PTR_WDT-2:0] ) &&
                       ( wptr_nxt != rptr_nxt ) );

// FIFO write logic.
always_ff @ (posedge i_clk)
        if ( i_wr_en && !o_full )
                mem[wptr_ff[PTR_WDT-2:0]] <= i_data;

// Read data output.
always_comb
        o_data = mem[rptr_ff[PTR_WDT-2:0]];

// Flip-flop update.
always_ff @ (posedge i_clk)
begin
        rptr_ff <= i_reset ? 0 : rptr_nxt;
        wptr_ff <= i_reset ? 0 : wptr_nxt;
        empty   <= i_reset ? 1 : ( wptr_nxt == rptr_nxt );
        nempty  <= i_reset ? 0 : ( wptr_nxt != rptr_nxt );
        nfull   <= i_reset ? 1 :  o_full_n_nxt;
        full    <= i_reset ? 0 : !o_full_n_nxt;
end

// Pointer updates.
always_comb
begin
        wptr_nxt = wptr_ff + (i_wr_en && !o_full ? {{(PTR_WDT-1){1'd0}}, 1'd1} : {PTR_WDT{1'd0}});
        rptr_nxt = rptr_ff + (i_ack && !o_empty  ? {{(PTR_WDT-1){1'd0}}, 1'd1} : {PTR_WDT{1'd0}});
end

endmodule // zap_sync_fifo

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
