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
// Implements a 16-bit instruction decoder. The 16-bit instruction set is
// not logically organized so as to save on encoding and thus the code
// seem a bit complex.
//



module zap_mode16_decoder_main (
        // Clock and reset.
        input logic              i_clk,
        input logic              i_reset,

        // Code stall.
        input logic              i_clear_from_writeback,
        input logic              i_data_stall,
        input logic              i_clear_from_alu,
        input logic              i_stall_from_shifter,
        input logic              i_stall_from_issue,
        input logic              i_stall_from_decode,
        input logic              i_clear_from_decode,

        // Predictor status.
        input logic  [1:0]       i_taken,
        input logic  [32:0]      i_pred,
        output logic [32:0]      o_pred,

        // Input from I-cache.
        // Instruction and valid qualifier.
        input logic [31:0]       i_instruction,
        input logic              i_instruction_valid,

        // Interrupts. Active high level sensitive signals.
        input logic              i_irq,
        input logic              i_fiq,

        // Aborts.
        input logic              i_iabort,
        output logic             o_iabort,

        // Ensure compressed mode is active (T bit).
        input logic              i_cpsr_ff_t,

        // Program counter.
        input logic      [31:0]  i_pc_ff,
        input logic      [31:0]  i_pc_plus_8_ff,

        //
        // Outputs to the 32=bit decoder.
        //

        // Instruction, valid, undefined by this decoder and force 32-bit
        // align signals (requires memory to keep lower 2 bits as 00).
        output logic [34:0]       o_instruction,
        output logic              o_instruction_valid,
        output logic              o_und,
        output logic              o_force32_align,

        // PCs.
        output  logic [31:0]      o_pc_ff,
        output  logic [31:0]      o_pc_plus_8_ff,

        // Interrupt status output.
        output logic              o_irq,
        output logic              o_fiq,

        // Taken
        output logic      [1:0]   o_taken_ff
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

logic [34:0] instruction_nxt;
logic instruction_valid_nxt;
logic und_nxt;
logic force32_nxt;
logic irq_nxt;
logic fiq_nxt;
logic stall;

zap_mode16_decoder u_zap_mode16_decoder (
        .i_instruction(i_instruction),
        .i_instruction_valid(i_instruction_valid),
        .i_irq(i_irq),
        .i_fiq(i_fiq),
        .i_offset(o_instruction[10:0]),
        .i_cpsr_ff_t(i_cpsr_ff_t),
        .o_instruction(instruction_nxt),
        .o_instruction_valid(instruction_valid_nxt),
        .o_und(und_nxt),
        .o_force32_align(force32_nxt),
        .o_irq(irq_nxt),
        .o_fiq(fiq_nxt)
);

assign stall = i_stall_from_shifter ||
               i_stall_from_issue   ||
               i_stall_from_decode  ||
               i_data_stall;

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                o_instruction           <= 0;
                o_force32_align         <= 0;
                o_pc_ff                 <= 0;
                o_taken_ff              <= 0;
                o_pred                  <= 33'd0;
                o_instruction_valid     <= 1'd0;
                o_irq                   <= 0;
                o_fiq                   <= 0;
                o_und                   <= 0;
                o_iabort                <= 0;
        end
        else if(( i_clear_from_writeback )
        ||      ( i_clear_from_alu && !i_data_stall )
        ||      ( i_clear_from_decode && !stall ))
        begin
                o_instruction_valid <= 1'd0;
                o_irq <= 0;
                o_fiq <= 0;
                o_und <= 0;
                o_iabort <= 0;
                o_force32_align <= 'x;
                o_pred <= 'x;
                o_pc_ff <= 'x;
                o_instruction <= 'x;
                o_taken_ff <= 'x;
        end
        else if ( !stall )
        begin
                o_iabort                <= i_iabort;
                o_instruction_valid     <= instruction_valid_nxt;
                o_instruction           <= instruction_valid_nxt ?
                                           instruction_nxt : o_instruction;
                o_und                   <= und_nxt;
                o_force32_align         <= force32_nxt;
                o_pc_ff                 <= i_pc_ff;
                o_pc_plus_8_ff          <= i_pc_plus_8_ff;
                o_irq                   <= irq_nxt;
                o_fiq                   <= fiq_nxt;
                o_taken_ff              <= i_taken;
                o_pred                  <= i_pred;
        end
end

// Helpful for debug.
zap_decompile u_zap_decompile (
        .i_instruction  ({1'd0, o_instruction}),
        .i_dav          (o_instruction_valid),

        /* verilator lint_off PINCONNECTEMPTY */
        .o_decompile    ()
        /* verilator lint_on PINCONNECTEMPTY */
);

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
