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
// --                                                                       --
// -- Implements a simple coprocessor interface for the ZAP core. The i/f   --
// -- is low bandwidth and thus is suited only for coprocessor that do not  --
// -- perform large data exchanges. Note that the translate function must be--
// -- present in the coprocessor to account for CPU modes.                  --
// --                                                                       --
// ---------------------------------------------------------------------------



module zap_predecode_coproc #(
        parameter [31:0] PHY_REGS = 32'd46
)
(
        input logic              i_clk,
        input logic              i_reset,

        // Instruction and valid qualifier.
        input logic [34:0]       i_instruction,
        input logic              i_valid,

        // CPSR Thumb Bit.
        input logic              i_cpsr_ff_t,
        input logic [4:0]        i_cpsr_ff_mode,

        // Interrupts.
        input logic              i_irq,
        input logic              i_fiq,

         // Clear and stall signals.
        input logic              i_clear_from_writeback, // | High Priority
        input logic              i_data_stall,           // |
        input logic              i_clear_from_alu,       // |
        input logic              i_stall_from_shifter,   // |
        input logic              i_stall_from_issue,     // V Low Priority
        input logic              i_clear_from_decode, 

        // Pipeline Valid. Must become 0 when every stage of the pipeline
        // is invalid.
        input logic              i_pipeline_dav,

        // Coprocessor done signal.
        input logic              i_copro_done,          

        // Interrupts output.
        output logic              o_irq,
        output logic              o_fiq,

        // Instruction and valid qualifier.
        output logic [34:0]       o_instruction,
        output logic              o_valid,

        // We can generate stall if coprocessor is slow. We also have
        // some minimal latency.
        output logic              o_stall_from_decode,      

        // Are we really asking for the coprocessor ?
        output logic              o_copro_dav_nxt,  

        // The entire instruction is passed to the coprocessor.
        output logic  [31:0]      o_copro_word_nxt  
);

///////////////////////////////////////////////////////////////////////////////

`include "zap_defines.svh"
`include "zap_localparams.svh"

///////////////////////////////////////////////////////////////////////////////

localparam IDLE = 0;
localparam BUSY = 1;

///////////////////////////////////////////////////////////////////////////////

// State register.
logic state_ff, state_nxt;

// Output registers.
logic        cp_dav_ff, cp_dav_nxt;
logic [31:0] cp_word_ff, cp_word_nxt;

logic unused;

///////////////////////////////////////////////////////////////////////////////

always_comb unused = |{PHY_REGS};

///////////////////////////////////////////////////////////////////////////////

// Connect next state to output.
always_comb
begin
        o_copro_word_nxt = cp_word_nxt;
        o_copro_dav_nxt  = cp_dav_nxt;
end

///////////////////////////////////////////////////////////////////////////////

// Next state logic.
always_comb
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

        case ( state_ff )
        IDLE:
                // Activate only if no thumb, not in USER mode and CP15 access is requested.
                casez ( (!i_cpsr_ff_t && (i_instruction[34:32] == 3'd0) && i_valid) ? i_instruction[31:0] : 32'd0 )
                MRC, MCR, LDC, STC, CDP, MRC2, MCR2, LDC2, STC2:
                begin
                        if ( i_instruction[11:8] == 4'b1111 && i_cpsr_ff_mode != USR )  // CP15 and root access -- perfectly fine.
                        begin
                                o_instruction = i_instruction; 
                                o_valid       = i_valid;
                                o_irq         = 1'd0;
                                o_fiq         = 1'd0;

                                // As long as there is an instruction to process...
                                if ( i_pipeline_dav )
                                begin
                                        // Do not impose any output. However, continue
                                        // to stall all before this unit in the 
                                        // pipeline.
                                        o_valid                 = i_valid;
                                        o_stall_from_decode     = 1'd1;
                                        cp_dav_nxt              = 1'd0;
                                        cp_word_nxt             = 32'd0;
                                end
                                else
                                begin
                                        // Prepare to move to BUSY. Continue holding
                                        // stall. Send out 0s.
                                        o_valid                 = i_valid;
                                        o_stall_from_decode     = 1'd1;
                                        cp_word_nxt             = i_instruction[31:0];
                                        cp_dav_nxt              = 1'd1;
                                        state_nxt               = BUSY;
                                end
                        end
                        else // Warning...
                        begin

                                // Remain transparent since this is not a coprocessor
                                // instruction.
                                o_valid                 = i_valid;
                                o_instruction           = i_instruction;
                                o_irq                   = i_irq;
                                o_fiq                   = i_fiq;
                                cp_dav_nxt              = 0;
                                o_stall_from_decode     = 0;
                                cp_word_nxt             = {32{1'dx}}; // Don't care. This is perfectly OK - synth will optimize.
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
                        cp_word_nxt             = {32{1'dx}}; // Don't care. This is perfectly OK - synth will optimize.
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
                o_valid                 = i_valid;
                o_instruction           = i_instruction;

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

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                cp_word_ff <= 0;
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
        else if ( i_clear_from_decode )
        begin
                clear;
        end
        else
        begin
                state_ff   <= state_nxt;
                cp_word_ff <= cp_word_nxt;
                cp_dav_ff  <= cp_dav_nxt;
        end
end

// Clear out the unit.
task automatic clear;
begin
                state_ff            <= IDLE;
                cp_dav_ff           <= 1'd0; 
end
endtask

endmodule



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
