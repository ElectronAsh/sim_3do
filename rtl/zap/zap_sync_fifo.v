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
// -- This is a simple synchronous FIFO.                                      --
// -----------------------------------------------------------------------------

`default_nettype none

// FWFT means "First Word Fall Through".
module zap_sync_fifo #(
        parameter WIDTH            = 32, 
        parameter DEPTH            = 32, 
        parameter FWFT             = 1,
        parameter PROVIDE_NXT_DATA = 0
)
(
        // Clock and reset
        input   wire             i_clk,
        input   wire             i_reset,

        // Flow control
        input   wire             i_ack,
        input   wire             i_wr_en,

        // Data busses
        input   wire [WIDTH-1:0] i_data,
        output  reg [WIDTH-1:0]  o_data,
        output  reg [WIDTH-1:0]  o_data_nxt,

        // Flags
        output wire              o_empty,
        output wire              o_full,
        output wire              o_empty_n,
        output wire              o_full_n,
        output wire              o_full_n_nxt
);

// Xilinx ISE does not allow $CLOG2 in localparams.
parameter PTR_WDT = $clog2(DEPTH) + 32'd1;
parameter [PTR_WDT-1:0] DEFAULT = {PTR_WDT{1'd0}}; 

// Variables
reg [PTR_WDT-1:0] rptr_ff;
reg [PTR_WDT-1:0] rptr_nxt;
reg [PTR_WDT-1:0] wptr_ff;
reg               empty, nempty;
reg               full, nfull;
reg [PTR_WDT-1:0] wptr_nxt;
reg [WIDTH-1:0]   mem [DEPTH-1:0]; 
wire [WIDTH-1:0]  dt;
reg [WIDTH-1:0]   dt1;
reg               sel_ff;
reg [WIDTH-1:0]   bram_ff;         
reg [WIDTH-1:0]   dt_ff;

// Assigns
assign o_empty = empty;
assign o_full  = full;
assign o_empty_n = nempty;
assign o_full_n = nfull;
assign o_full_n_nxt = i_reset ? 1 :
                      !( ( wptr_nxt[PTR_WDT-2:0] == rptr_nxt[PTR_WDT-2:0] ) &&
                       ( wptr_nxt != rptr_nxt ) );


// FIFO write logic.
always @ (posedge i_clk)
        if ( i_wr_en && !o_full )
                mem[wptr_ff[PTR_WDT-2:0]] <= i_data;

// FIFO read logic
generate
begin:gb1
        if ( FWFT == 1 )
        begin:f1
                // Retimed output data compared to normal FIFO.
                always @ (posedge i_clk) 
                begin
                         dt_ff <= i_data;
                        sel_ff <= ( i_wr_en && (wptr_ff == rptr_nxt) );
                       bram_ff <= mem[rptr_nxt[PTR_WDT-2:0]];
                end
        
                // Output signal steering MUX.
                always @*
                begin
                        o_data = sel_ff ? dt_ff : bram_ff;
                        o_data_nxt = 0; // Tied off.
                end
        end
        else
        begin:f0
                always @ (posedge i_clk)
                begin
                        if ( i_ack && nempty ) // Read request and not empty.
                        begin
                                o_data <= mem [ rptr_ff[PTR_WDT-2:0] ];
                        end
                end

                if ( PROVIDE_NXT_DATA ) 
                begin: f11
                        always @ (*)
                        begin 
                                if ( i_ack && nempty ) 
                                        o_data_nxt = mem [ rptr_ff[PTR_WDT-2:0] ];
                                else
                                        o_data_nxt = o_data;
                        end
                end
                else
                begin: f22
                        always @* o_data_nxt = 0;
                end
        end
end
endgenerate

// Flip-flop update.
always @ (posedge i_clk)
begin
        dt1     <= i_reset ? 0 : i_data;
        rptr_ff <= i_reset ? 0 : rptr_nxt;
        wptr_ff <= i_reset ? 0 : wptr_nxt;
        empty   <= i_reset ? 1 : ( wptr_nxt == rptr_nxt );
        nempty  <= i_reset ? 0 : ( wptr_nxt != rptr_nxt );
        nfull   <= o_full_n_nxt;
        full    <= !o_full_n_nxt;
end

// Pointer updates.
always @*
begin
        wptr_nxt = wptr_ff + (i_wr_en && !o_full);
        rptr_nxt = rptr_ff + (i_ack && !o_empty);
end

endmodule // zap_sync_fifo

`default_nettype wire
