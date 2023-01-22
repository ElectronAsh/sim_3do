//
//  (C) 2016-2022 Revanth Kamaraj (krevanth)
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
//  02110-1301, USA.
//
//  This is the simple I-cache frontend to the processor. This stage
//  serves as a buffer for instructions. Data aborts are handled by adding
//  an extra signal down the pipeline. Data aborts piggyback off
//  AND R0, R0, R0.
//

module zap_fetch_main
(
// Clock and reset.
input logic i_clk,          // ZAP clock.
input logic i_reset,        // Active high synchronous reset.

//
// From other parts of the pipeline. These
// signals either tell the unit to invalidate
// its outputs or freeze in place.
//
input logic i_code_stall,           // | High Priority.
input logic i_clear_from_writeback, // |
input logic i_clear_from_alu,       // |
input logic i_clear_from_decode,    // V

// Comes from WB unit.
input logic [31:0]   i_pc_ff,         // Program counter.

// Comes from active CPSR
input logic          i_cpsr_ff_t,     // CPSR T bit.

// From I-cache.
input logic [31:0] i_instruction,     // A 32-bit ZAP instruction.

input logic          i_valid,         // Instruction valid indicator.
input logic          i_instr_abort,   // Instruction abort fault.

// To decode.
output logic [31:0]  o_instruction,  // The 32-bit instruction.
output logic         o_valid,        // Instruction valid.
output logic         o_instr_abort,  // Indication of an abort.
output logic [31:0]  o_pc_plus_8_ff, // PC +8 ouput.
output logic [31:0]  o_pc_ff,        // PC output.

// For BP.
input logic  [1:0]   i_taken,        // Predicted status in.
output logic [1:0]   o_taken,        // Predicted status out.

// Pred. The MSB indicates if the BTB made a prediction, the rest is the address.
input logic  [32:0]  i_pred,
output logic [32:0]  o_pred

);

`include "zap_defines.svh"
`include "zap_localparams.svh"
`include "zap_functions.svh"

logic sleep_ff;

//
// NOTE: If an instruction is invalid, only then can it be tagged with any
// kind of interrupt. Thus, the MMU must make instruction valid as 1 before
// attaching an abort interrupt to it even though the instruction generated
// might be invalid. Such an instruction is not actually executed.
//

//
// This stage simply forwards data from the
// I-cache downwards.
//
always_ff @ ( posedge i_clk )
begin
        if (  i_reset )
        begin
                o_pc_plus_8_ff  <= 'x;
                o_pc_ff         <= 'x;
                o_instruction   <= 'x;
                o_valid         <= 1'd0;
                o_instr_abort   <= 1'd0;
                sleep_ff        <= 1'd0;
                o_pred          <= 'x;
        end
        else if(( i_clear_from_writeback )
        ||      ( i_clear_from_alu )
        ||      ( i_clear_from_decode ))
        begin
                o_valid         <= 1'd0;
                o_instr_abort   <= 1'd0;
                sleep_ff        <= 1'd0;
        end
        // If unit is sleeping.
        else if ( sleep_ff && !i_code_stall )
        begin
                // Nothing valid to be sent.
                o_valid         <= 1'd0;

                // No aborts.
                o_instr_abort   <= 1'd0;

                // Keep sleeping.
                sleep_ff        <= 1'd1;
        end
        // Data from memory is valid. This could also be used to signal
        // an instruction access abort.
        else if ( i_valid && !i_code_stall )
        begin
                // Instruction aborts occur with i_valid as 1. See NOTE.
                o_valid         <= 1'd1;
                o_instr_abort   <= i_instr_abort;

                // Taken
                o_taken         <= i_taken;

                // Detect breakpoint. These are unconditional.
                if ( (~i_cpsr_ff_t) & (i_instruction ==? BKPT) )
                begin
                        o_instr_abort <= 1'd1;
                end
                else if ( i_cpsr_ff_t )
                begin
                        if ( i_pc_ff[1] && i_instruction[31:16] ==? T_BKPT )
                        begin
                                o_instr_abort <= 1'd1;
                        end
                        else if ( !i_pc_ff[1] && i_instruction[15:0] ==? T_BKPT )
                        begin
                                o_instr_abort <= 1'd1;
                        end
                end

                // Put unit to sleep on an abort.
                sleep_ff        <= i_instr_abort;

                // Pump PC + 4/8 down the pipeline.
                o_pc_plus_8_ff <= i_cpsr_ff_t ? ( i_pc_ff + 32'd4 ) :
                                                ( i_pc_ff + 32'd8 );

                // Actual PC is pumped down the pipeline.
                o_pc_ff <= i_pc_ff;

                //
                // Instruction. If 16-bit aligned address, move data from
                // cache by 16-bit to focus on the instruction.
                //
                o_instruction <= i_pc_ff[1] ? i_instruction >> 16 : i_instruction;

                // Prediction state and address.
                o_pred <= i_pred;
        end
        else if ( !i_code_stall )
        begin
                // Invalidate the output.
                o_valid        <= 1'd0;
        end
end

zap_decompile u_zap_decompile (
        .i_instruction  ({4'd0, o_instruction}),
        .i_dav          (o_valid),
        /* verilator lint_off PINCONNECTEMPTY */
        .o_decompile    ()
        /* verilator lint_on PINCONNECTEMPTY */

);

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
