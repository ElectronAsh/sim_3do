// ---------------------------------------------------------------------------
// --                                                                       --
// --                   (C) 2016-2018 Revanth Kamaraj.                      --
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
// Implements a simple coprocessor interface for the ZAP core. The interface
// is low bandwidth and thus is suited only for coprocessor that do not
// perform large data exchanges. Note that the translate function must be
// present in the coprocessor to account for CPU modes.
// ----------------------------------------------------------------------------

`default_nettype none
module zap_predecode_coproc #(
        parameter PHY_REGS = 46
)
(
        input wire              i_clk,
        input wire              i_reset,

        // Instruction and valid qualifier.
        input wire [34:0]       i_instruction,
        input wire              i_valid,

        // CPSR Thumb Bit.
        input wire              i_cpsr_ff_t,
        input wire [4:0]        i_cpsr_ff_mode,

        // Interrupts.
        input wire              i_irq,
        input wire              i_fiq,

         // Clear and stall signals.
        input wire              i_clear_from_writeback, // | High Priority
        input wire              i_data_stall,           // |
        input wire              i_clear_from_alu,       // |
        input wire              i_stall_from_shifter,   // |
        input wire              i_stall_from_issue,     // V Low Priority

        // Pipeline Valid. Must become 0 when every stage of the pipeline
        // is invalid.
        input wire              i_pipeline_dav,

        // Coprocessor done signal.
        input wire              i_copro_done,          

        // Interrupts output.
        output reg              o_irq,
        output reg              o_fiq,

        // Instruction and valid qualifier.
        output reg [34:0]       o_instruction,
        output reg              o_valid,

        // We can generate stall if coprocessor is slow. We also have
        // some minimal latency.
        output reg              o_stall_from_decode,      

        // Are we really asking for the coprocessor ?
        output reg              o_copro_dav_ff,  

        // The entire instruction is passed to the coprocessor.
        output reg  [31:0]      o_copro_word_ff  
);

///////////////////////////////////////////////////////////////////////////////

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

///////////////////////////////////////////////////////////////////////////////

localparam IDLE = 0;
localparam BUSY = 1;

///////////////////////////////////////////////////////////////////////////////

// State register.
reg state_ff, state_nxt;

// Output registers.
reg        cp_dav_ff, cp_dav_nxt;
reg [31:0] cp_word_ff, cp_word_nxt;

///////////////////////////////////////////////////////////////////////////////

// Connect output registers to output.
always @*
begin
        o_copro_word_ff = cp_word_ff;
        o_copro_dav_ff  = cp_dav_ff;
end

///////////////////////////////////////////////////////////////////////////////

wire c1 = !i_cpsr_ff_t;
wire c2 = i_cpsr_ff_mode != USR;
wire c3 = i_instruction[11:8] == 4'b1111;
wire c4 = i_instruction[34:32] == 3'd0;
wire c5 = c1 & c2 & c3 & c4;
reg eclass;

// Next state logic.
always @*
begin
        // Default values.
        cp_dav_nxt              = cp_dav_ff;
        cp_word_nxt             = cp_word_ff;
        o_stall_from_decode     = 1'd0;
        o_instruction           = i_instruction;
        o_valid                 = i_valid;
        state_nxt               = state_ff;
        o_irq                   = i_irq;
        o_fiq                   = i_fiq;

        eclass = 0;

        case ( state_ff )
        IDLE:
                // Activate only if no thumb, not in USER mode and CP15 access is requested.
                casez ( (!i_cpsr_ff_t && (i_instruction[34:32] == 3'd0) && i_valid) ? i_instruction[31:0] : 35'd0 )
                MRC, MCR, LDC, STC, CDP:
                begin
                        if ( i_instruction[11:8] == 4'b1111 && i_cpsr_ff_mode != USR )  // CP15 and root access -- perfectly fine.
                        begin
                                // Send ANDNV R0, R0, R0 instruction.
                                o_instruction = {4'b1111, 28'd0}; 
                                o_valid       = 1'd0;
                                o_irq         = 1'd0;
                                o_fiq         = 1'd0;

                                // As long as there is an instruction to process...
                                if ( i_pipeline_dav )
                                begin
                                        // Do not impose any output. However, continue
                                        // to stall all before this unit in the 
                                        // pipeline.
                                        o_valid                 = 1'd0;
                                        o_stall_from_decode     = 1'd1;
                                        cp_dav_nxt              = 1'd0;
                                        cp_word_nxt             = 32'd0;
                                end
                                else
                                begin
                                        // Prepare to move to BUSY. Continue holding
                                        // stall. Send out 0s.
                                        o_valid                 = 1'd0;
                                        o_stall_from_decode     = 1'd1;
                                        cp_word_nxt             = i_instruction;
                                        cp_dav_nxt              = 1'd1;
                                        state_nxt               = BUSY;
                                end
                        end
                        else // Warning...
                        begin

                                if ( i_instruction[11:8] != 4'b1111 ) 
                                        eclass = 1;
                                else
                                        eclass = 2;
            

                                // Remain transparent since this is not a coprocessor
                                // instruction.
                                o_valid                 = i_valid;
                                o_instruction           = i_instruction;
                                o_irq                   = i_irq;
                                o_fiq                   = i_fiq;
                                cp_dav_nxt              = 0;
                                o_stall_from_decode     = 0;
                                cp_word_nxt             = {32{1'dx}}; // Don't care.
                        end
                end
                default:
                begin
                        // Remain transparent since this is not a coprocessor
                        // instruction.
                        o_valid                 = i_valid;
                        o_instruction           = i_instruction;
                        o_irq                   = i_irq;
                        o_fiq                   = i_fiq;
                        cp_dav_nxt              = 0;
                        o_stall_from_decode     = 0;
                        cp_word_nxt             = {32{1'dx}}; // Don't care.
                end
                endcase

        BUSY:
        begin
                // Provide coprocessor word and valid to the coprocessor.
                cp_word_nxt             = cp_word_ff;
                cp_dav_nxt              = cp_dav_ff;

                // Continue holding stall.
                o_stall_from_decode     = 1'd1;

                // Send out nothing.
                o_valid                 = 1'd0;
                o_instruction           = 32'd0;

                // Block interrupts.
                o_irq = 1'd0;
                o_fiq = 1'd0;

                // If we get a response, we can move back to IDLE. Release
                // the stall so that processor can continue.
                if ( i_copro_done )
                begin
                        cp_dav_nxt              = 1'd0;
                        cp_word_nxt             = 32'd0;
                        state_nxt               = IDLE;
                        o_stall_from_decode     = 1'd0;
                end
        end
        endcase
end

always @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                clear;
        end
        else if ( i_clear_from_writeback )
        begin
                clear;
        end
        else if ( i_data_stall )
        begin
                // Preserve values.
        end
        else if ( i_clear_from_alu )
        begin
                clear;
        end
        else if ( i_stall_from_shifter )
        begin
                // Preserve values.
        end
        else if ( i_stall_from_issue )
        begin
                // Preserve values.
        end
        else
        begin
                state_ff   <= state_nxt;
                cp_word_ff <= cp_word_nxt;
                cp_dav_ff  <= cp_dav_nxt;
        end
end

// Clear out the unit.
task clear;
begin
                state_ff            <= IDLE;
                cp_dav_ff           <= 1'd0; 
end
endtask

endmodule
`default_nettype wire
