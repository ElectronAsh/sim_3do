//
//  (C) 2016-2022 Revanth Kamaraj (krevanth)
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
// This is a classic synchronous FIFO.
//

module zap_sync_fifo #(
        parameter logic [31:0] WIDTH = 32'd32,
        parameter logic [31:0] DEPTH = 32'd32
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
        output  logic [WIDTH-1:0] o_data,

        // Controls.
        input   logic             i_clear,

        // Flags
        output logic              o_empty,
        output logic              o_empty_n,
        output logic              o_full,
        output logic              o_full_n
);

localparam [31:0] PTR_WDT = $clog2(DEPTH) + 32'd1;

// Variables
logic [PTR_WDT-1:0] rptr_ff, rptr_nxt;
logic [PTR_WDT-1:0] wptr_ff,wptr_nxt;
logic               empty_ff, empty_nxt;
logic               full_ff, full_nxt;
logic [WIDTH-1:0]   mem [DEPTH-1:0];
logic               write_ok;
logic               read_ok;

// Drive outputs.
assign o_empty   = empty_ff;
assign o_empty_n = ~o_empty;
assign o_full_n  = ~o_full;
assign o_full    = full_ff;
assign  o_data   = mem[rptr_ff[PTR_WDT-2:0]];

// Flags
assign empty_nxt =   i_clear ? 1'd1 : (wptr_nxt == rptr_nxt);
assign full_nxt  =   i_clear ? 1'd0 :
                     (( wptr_nxt[PTR_WDT-2:0] == rptr_nxt[PTR_WDT-2:0] ) &
                      ( wptr_nxt[PTR_WDT-1]   != rptr_nxt[PTR_WDT-1]   ));

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                empty_ff <= 1'd1;
                full_ff  <= 1'd0;
        end
        else
        begin
                empty_ff <= empty_nxt;
                full_ff  <= full_nxt;
        end
end

// Guard conditions for IO operations.
assign write_ok = i_wr_en & ~o_full;
assign read_ok  = i_ack   & ~o_empty;

// FIFO write.
always_ff @ (posedge i_clk)
begin
        if ( write_ok )
        begin
                mem[wptr_ff[PTR_WDT-2:0]] <= i_data;
        end
end

// Pointer updates.
assign  wptr_nxt = i_clear ? 'd0 : (wptr_ff + (write_ok ? 'd1 : 'd0));
assign  rptr_nxt = i_clear ? 'd0 : (rptr_ff + (read_ok  ? 'd1 : 'd0));

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                rptr_ff   <= '0;
                wptr_ff   <= '0;
        end
        else
        begin
                rptr_ff  <= rptr_nxt;
                wptr_ff  <= wptr_nxt;
        end
end

endmodule // zap_sync_fifo

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
