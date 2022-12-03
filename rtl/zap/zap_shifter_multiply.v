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
// --  This unit handles 32x32=32/64 multiplication using an FSM using        --
// --  a 17x17 signed array multiplier.                                       -- 
// --                                                                         --
// -----------------------------------------------------------------------------


`default_nettype none

module zap_shifter_multiply
#(
        parameter PHY_REGS = 46,
        parameter ALU_OPS   = 32
)
(
        input wire                              i_clk,
        input wire                              i_reset,

        // Clear and stall signals.
        input wire                              i_clear_from_writeback,
        input wire                              i_data_stall,
        input wire                              i_clear_from_alu,

        // ALU operation to perform. Activate if this is multiplication.
        input wire   [$clog2(ALU_OPS)-1:0]      i_alu_operation_ff,

        // This is not used.
        input wire                              i_cc_satisfied,

        // rm.rs + {rh,rn}. For non accumulate versions, rn = 0x0 and rh = 0x0.
        input wire [31:0]                       i_rm,
        input wire [31:0]                       i_rn,
        input wire [31:0]                       i_rh,
        input wire [31:0]                       i_rs,        

        //
        // Outputs.
        //

        output reg  [31:0]                      o_rd,    // Result.
        output reg                              o_busy,  // Unit busy.
        output reg                              o_nozero // Don't set zero flag.
);

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

///////////////////////////////////////////////////////////////////////////////

// States
localparam IDLE = 0;
localparam S1   = 1;
localparam S2   = 2;
localparam S3   = 3;
localparam S4   = 4;
localparam S5   = 5;
localparam NUMBER_OF_STATES = 6;

///////////////////////////////////////////////////////////////////////////////

reg [31:0] buffer_nxt, buffer_ff;
wire higher = i_alu_operation_ff[0];
wire sign   = (i_alu_operation_ff == SMLALL || i_alu_operation_ff == SMLALH);
wire signed [16:0] a;
wire signed [16:0] b;
wire signed [16:0] c;
wire signed [16:0] d;
reg signed [63:0] x_ff, x_nxt;
reg signed [16:0] in1;
reg signed [16:0] in2;
wire signed [63:0] prod;

// State variable.
reg [$clog2(NUMBER_OF_STATES)-1:0] state_ff, state_nxt;

///////////////////////////////////////////////////////////////////////////////

assign prod = in1 * in2; // 17x17 hard macro model.

///////////////////////////////////////////////////////////////////////////////

assign a = sign ? {i_rm[31], i_rm[31:16]} : {1'd0, i_rm[31:16]};
assign b = sign ? {i_rs[31], i_rs[31:16]} : {1'd0, i_rs[31:16]};
assign c = {1'd0, i_rm[15:0]}; 
assign d = {1'd0, i_rs[15:0]};

///////////////////////////////////////////////////////////////////////////////

always @*
begin
        buffer_nxt = buffer_ff;
        o_nozero = 1'd0;
        o_busy = 1'd1;
        o_rd   = 32'd0;
        state_nxt = state_ff;
        x_nxt = x_ff;        
        in1 = 0;
        in2 = 0;

        case ( state_ff )
                IDLE:
                begin
                        o_busy = 1'd0;
                        x_nxt  = 32'd0;

                        // If we have the go signal.
                        if ( i_cc_satisfied && (i_alu_operation_ff == UMLALL || 
                                                i_alu_operation_ff == UMLALH || 
                                                i_alu_operation_ff == SMLALL || 
                                                i_alu_operation_ff == SMLALH) )
                        begin
                                o_busy = 1'd1;
                                state_nxt = S1;
                        end
                end
                S1:
                begin
                        in1 = c;
                        in2 = d;
                        x_nxt     = x_ff + (prod << 0);                        
                        state_nxt = S2;
                end
                S2:
                begin
                        in1 = b;
                        in2 = c;
                        state_nxt = S3;
                        x_nxt     = x_ff + (prod << 16);
                end
                S3:
                begin
                        in1 = a;
                        in2 = d;
                        state_nxt = S4;
                        x_nxt     = x_ff + (prod << 16);
                end
                S4:
                begin
                        in1 = a;
                        in2 = b;
                        state_nxt = S5;
                        x_nxt    = x_ff + (prod << 32);
                end
                S5:
                begin
                        state_nxt  = IDLE;
                        x_nxt      = x_ff + {i_rh, i_rn};
                        o_rd       = higher ? x_nxt[63:32] : x_nxt[31:0];

                        if ( !higher )
                        begin
                                buffer_nxt = x_nxt[31:0];
                        end

                        o_busy     = 1'd0;

                        if ( higher && (buffer_ff != 32'd0) )
                        begin
                                o_nozero = 1'd1;
                        end
                end
        endcase
end

///////////////////////////////////////////////////////////////////////////////

always @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                x_ff     <= 63'd0;
                state_ff <= IDLE;
                buffer_ff<= 32'd0;
        end
        else if ( i_clear_from_writeback )
        begin
                x_ff     <= 63'd0;
                state_ff <= IDLE; 
                buffer_ff <= 32'd0;
        end
        else if ( i_data_stall )
        begin
                // Hold values
        end
        else if ( i_clear_from_alu )
        begin
                x_ff     <= 63'd0;
                state_ff <= IDLE;
                buffer_ff <= 32'd0;
        end
        else
        begin
                x_ff <= x_nxt;
                state_ff <= state_nxt;
                buffer_ff <= buffer_nxt;
        end
end

///////////////////////////////////////////////////////////////////////////////

endmodule // zap_multiply.v
`default_nettype wire
