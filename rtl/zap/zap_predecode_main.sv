//
//    (C) 2016-2022 Revanth Kamaraj (krevanth)
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
// The pre-decode block. Does partial instruction decoding and sequencing
// before passing the instruction onto the next stage.
//

module zap_predecode_main #(
        parameter logic [31:0] PHY_REGS  = 32'd64,
        parameter logic [31:0] RAS_DEPTH = 32'd8
)
(
        // Clock and reset.
        input   logic                            i_clk,
        input   logic                            i_reset,

        // UOP
        output logic                             o_uop_last,

        // L4
        input   logic                            i_l4_enable,

        // Predict. MSB is valid bit.
        input logic   [32:0]                     i_pred,
        output logic                             o_clear_btb,

        // Branch state.
        input   logic     [1:0]                  i_taken,
        input   logic                            i_force32,
        input   logic                            i_und,

        // Clear and stall signals. From high to low priority.
        input logic                              i_clear_from_writeback, // |Pri
        input logic                              i_data_stall,           // |
        input logic                              i_clear_from_alu,       // |
        input logic                              i_stall_from_shifter,   // |
        input logic                              i_stall_from_issue,     // V

        // Interrupt events.
        input   logic                            i_irq,
        input   logic                            i_fiq,
        input   logic                            i_abt,

        // Is 0 if all pipeline is invalid. Used for coprocessor.
        input   logic                            i_pipeline_dav,

        // Coprocessor done.
        input   logic                            i_copro_done,

        // PC input.
        input logic  [31:0]                      i_pc_ff,
        input logic  [31:0]                      i_pc_plus_8_ff,

        // CPU mode. Taken from CPSR in the ALU.
        input   logic                            i_cpu_mode_t, // T mode.
        input   logic [4:0]                      i_cpu_mode_mode, // CPU mode.

        // Instruction input.
        input     logic  [34:0]                  i_instruction,
        input     logic                          i_instruction_valid,

        // Instruction output
        output logic [39:0]                       o_instruction_ff,
        output logic                              o_instruction_valid_ff,

        // Stall of PC and fetch.
        output  logic                             o_stall_from_decode,

        // Switch.
        output  logic                             o_switch_ff,

        // PC output.
        output  logic  [31:0]                     o_pc_plus_8_ff,
        output  logic  [31:0]                     o_pc_ff,
        output  logic  [31:0]                     o_ppc_ff,

        // Interrupts.
        output  logic                             o_irq_ff,
        output  logic                             o_fiq_ff,
        output  logic                             o_abt_ff,
        output  logic                             o_und_ff,

        // Force 32-bit alignment on memory accesses.
        output logic                              o_force32align_ff,

        // Coprocessor interface.
        output logic                             o_copro_dav_ff,
        output logic  [31:0]                     o_copro_word_ff,

        // Branch.
        output logic   [1:0]                      o_taken_ff,

        // Clear from decode.
        output logic                              o_clear_from_decode,
        output logic [31:0]                       o_pc_from_decode
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

logic                               copro_dav_nxt;
logic [31:0]                        copro_word_nxt;
logic                               w_clear_from_decode;
logic [31:0]                        w_pc_from_decode;
logic [39:0]                        o_instruction_nxt;
logic                               o_instruction_valid_nxt;
logic                               o_uop_last_nxt;
logic                               mem_fetch_stall;
logic                               mode32_irq;
logic                               mode32_fiq;
logic                               irq_mask;
logic                               fiq_mask;
logic [34:0]                        mode32_instruction;
logic                               mode32_instruction_valid;
logic                               cp_stall;
logic [34:0]                        cp_instruction;
logic                               cp_instruction_valid;
logic                               cp_irq;
logic                               cp_fiq;
logic [1:0]                         taken_nxt;
logic [31:0]                        ppc_nxt; // Predicted PC.
logic [34:0]                        skid_instruction;
logic                               skid_instruction_valid;
logic [139:0]                       skid;
logic [1:0]                         skid_taken;
logic [32:0]                        skid_pred;
logic                               skid_force32;
logic                               skid_und;
logic                               skid_irq;
logic                               skid_fiq;
logic                               skid_abt;
logic [31:0]                        skid_pc_ff;
logic [31:0]                        skid_pc_plus_8_ff;
logic [RAS_DEPTH-1:0][31:0]         ras_ff, ras_nxt;
logic [$clog2(RAS_DEPTH)-1:0]       ras_ptr_ff, ras_ptr_nxt;
logic                               align_nxt;
logic                               switch_nxt;
logic                               stall;

assign stall = i_data_stall || i_stall_from_shifter || i_stall_from_issue;

// Flop the outputs to break the pipeline at this point.
always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                ras_ff                 <= '0;
                ras_ptr_ff             <= '0;
                o_irq_ff               <= 0;
                o_fiq_ff               <= 0;
                o_abt_ff               <= 0;
                o_und_ff               <= 0;
                o_pc_plus_8_ff         <= 0;
                o_pc_ff                <= 0;
                o_force32align_ff      <= 0;
                o_taken_ff             <= 0;
                o_instruction_ff       <= 0;
                o_instruction_valid_ff <= 0;
                o_uop_last             <= 0;
                o_ppc_ff               <= 0;
                o_clear_from_decode    <= 0;
                o_pc_from_decode       <= 0;
                o_copro_word_ff        <= 0;
                o_copro_dav_ff         <= 0;
                o_switch_ff            <= 0;
        end
        else if(( i_clear_from_writeback )
        ||      ( i_clear_from_alu && !i_data_stall )
        ||      ( o_clear_from_decode && !stall ))
        begin
                o_irq_ff                <= 0;
                o_fiq_ff                <= 0;
                o_abt_ff                <= 0;
                o_und_ff                <= 0;
                o_taken_ff              <= 0;
                o_instruction_valid_ff  <= 0;
                o_uop_last              <= 0;
                o_clear_from_decode     <= 0;
                o_force32align_ff       <= 0;
                o_switch_ff             <= 0;
        end
        // If no stall, only then update...
        else if ( !stall )
        begin
                // Do not pass IRQ and FIQ if mask is 1.
                o_irq_ff               <= skid_irq & irq_mask;
                o_fiq_ff               <= skid_fiq & fiq_mask;
                o_abt_ff               <= skid_abt;
                o_und_ff               <= skid_und && skid_instruction_valid;
                o_pc_plus_8_ff         <= skid_pc_plus_8_ff;
                o_pc_ff                <= skid_pc_ff;
                o_force32align_ff      <= skid_force32 | align_nxt;
                o_switch_ff            <= switch_nxt;
                o_taken_ff             <= taken_nxt;
                o_instruction_ff       <= o_instruction_nxt;
                o_instruction_valid_ff <= o_instruction_valid_nxt;
                o_uop_last             <= o_uop_last_nxt;
                o_copro_dav_ff         <= copro_dav_nxt;
                o_copro_word_ff        <= copro_word_nxt;

                if ( mem_fetch_stall == 1'd0 )
                begin
                        o_clear_from_decode    <= w_clear_from_decode;
                        o_pc_from_decode       <= w_pc_from_decode;
                        o_ppc_ff               <= ppc_nxt;
                        ras_ff                 <= ras_nxt;
                        ras_ptr_ff             <= ras_ptr_nxt;
                end
        end
end

always_ff @ ( posedge i_clk)
begin
        if ( i_reset )
        begin
                o_stall_from_decode <= 1'd0;
        end
        else if ( i_clear_from_writeback )
        begin
                o_stall_from_decode <= 1'd0;
        end
        else if ( i_clear_from_alu && !i_data_stall )
        begin
                o_stall_from_decode <= 1'd0;
        end
        else if ( !stall )
        begin
                case(o_stall_from_decode)

                1'd0:
                begin
                        if ( mem_fetch_stall || cp_stall )
                        begin
                                o_stall_from_decode <= 1'd1;
                                skid                <= {i_pred,
                                                        i_taken,
                                                        i_force32,
                                                        i_und,
                                                        i_irq,
                                                        i_fiq,
                                                        i_abt,
                                                        i_pc_ff,
                                                        i_pc_plus_8_ff,
                                                        i_instruction,
                                                        i_instruction_valid};
                        end
                end

                1'd1:
                begin
                        if ( !(mem_fetch_stall || cp_stall) )
                        begin
                                o_stall_from_decode <= 1'd0;

                        end
                end

                endcase

                if ( o_clear_from_decode )
                begin
                        o_stall_from_decode <= 1'd0;
                end
        end
end

always_comb
begin
        if ( o_stall_from_decode )
        begin
                skid_pred              = skid[139:107];
                skid_taken             = skid[106:105];
                skid_force32           = skid[104];
                skid_und               = skid[103];
                skid_irq               = skid[102];
                skid_fiq               = skid[101];
                skid_abt               = skid[100];
                skid_pc_ff             = skid[99:68];
                skid_pc_plus_8_ff      = skid[67:36];
                skid_instruction       = skid[35:1];
                skid_instruction_valid = skid[0];
        end
        else
        begin
                skid_pred               = i_pred;
                skid_taken              = i_taken;
                skid_force32            = i_force32;
                skid_und                = i_und;
                skid_irq                = i_irq;
                skid_fiq                = i_fiq;
                skid_abt                = i_abt;
                skid_pc_ff              = i_pc_ff;
                skid_pc_plus_8_ff       = i_pc_plus_8_ff;
                skid_instruction        = i_instruction;
                skid_instruction_valid  = i_instruction_valid;
        end
end

// This unit handles coprocessor stuff.
zap_predecode_coproc
#(
        .PHY_REGS(PHY_REGS)
)
u_zap_decode_coproc
(
        // Inputs from outside world.
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_irq(skid_irq),
        .i_fiq(skid_fiq),
        .i_instruction(skid_instruction_valid ? skid_instruction : 35'd0),
        .i_valid(skid_instruction_valid),
        .i_cpsr_ff_t(i_cpu_mode_t),
        .i_cpsr_ff_mode(i_cpu_mode_mode),

        // Clear and stall signals.
        .i_clear_from_writeback(i_clear_from_writeback),
        .i_data_stall(i_data_stall),
        .i_clear_from_alu(i_clear_from_alu),
        .i_stall_from_issue(i_stall_from_issue),
        .i_stall_from_shifter(i_stall_from_shifter),
        .i_clear_from_decode(o_clear_from_decode),

        // Valid signals.
        .i_pipeline_dav (i_pipeline_dav),

        // Coprocessor
        .i_copro_done(i_copro_done),

        // Output to next block.
        .o_instruction(cp_instruction),
        .o_valid(cp_instruction_valid),
        .o_irq(cp_irq),
        .o_fiq(cp_fiq),

        // Stall.
        .o_stall_from_decode(cp_stall),

        // Coprocessor interface.
        .o_copro_dav_nxt(copro_dav_nxt),
        .o_copro_word_nxt(copro_word_nxt)
);

assign mode32_instruction          = cp_instruction;
assign mode32_instruction_valid    = cp_instruction_valid;
assign mode32_irq                  = cp_irq;
assign mode32_fiq                  = cp_fiq;

always_comb
begin:bprblk1
        logic [31:0] addr;
        logic [31:0] addr_final;

        o_clear_btb             = 1'd0;
        w_clear_from_decode     = 1'd0;
        w_pc_from_decode        = 32'd0;
        taken_nxt               = skid_taken;
        ppc_nxt                 = o_ppc_ff;
        ras_nxt                 = ras_ff;
        ras_ptr_nxt             = ras_ptr_ff;
        addr                    = {{8{mode32_instruction[23]}},mode32_instruction[23:0]}; // Offset.

        // Indicates a left shift of 1 i.e., X = X * 2.
        if ( mode32_instruction[34] )
        begin
                addr_final = addr << 1;
        end
        // Indicates a left shift of 2 i.e., X = X * 4.
        else
        begin
                addr_final = addr << 2;
        end

        //
        // Is it an instruction that we support ?
        // Proccessor recognizes:
        // 1. BL as a function call.
        // 2. MOV PC, LR as a function return.
        // 3. BX LR as a function return.
        //

        // Bcc[L] <offset>. Function call.
        if ( mode32_instruction[27:25] == 3'b101 && mode32_instruction_valid )
        begin
                if ( skid_taken == ST || skid_taken == WT || mode32_instruction[31:28] == AL )
                // Predicted as Taken or Predicted as Strongly Taken or Always taken.
                begin
                        // Predict new PC.
                        w_pc_from_decode    = skid_pc_plus_8_ff + addr_final;
                        ppc_nxt             = w_pc_from_decode;

                        if ( skid_pred[32] && skid_pred[31:0] != w_pc_from_decode )
                        begin
                                w_clear_from_decode = 1'd1;
                        end
                        else if ( !skid_pred[32] )
                        begin
                                w_clear_from_decode = 1'd1;
                        end
                        else
                        begin
                                w_clear_from_decode = 1'd0;
                        end

                        // Force taken status to ST.
                        if ( mode32_instruction[31:28] == AL )
                        begin
                                taken_nxt = ST;
                        end

                        // If Link=1, push next address onto RAS.
                        if ( mode32_instruction[24] )
                        begin
                               ras_nxt[ras_ptr_ff] = skid_pc_ff +
                                                     (i_cpu_mode_t ? 32'd2 : 32'd4);
                               ras_ptr_nxt++;
                        end
                end
                else // Predicted as Not Taken or Weakly Not Taken.
                begin
                        w_clear_from_decode = 1'd0;
                        w_pc_from_decode    = 32'd0;
                        ppc_nxt             = skid_pc_ff + (i_cpu_mode_t ? 32'd2 : 32'd4);
                end
        end
        else if (
                  // BX LR is recognized as a function return.
                  (
                   mode32_instruction[31:0] ==? BX_INST &&
                   mode32_instruction[3:0]   ==   4'd14 &&
                   mode32_instruction_valid
                  )
                  ||
                  // As is MOV PC, LR
                  (
                    (
                        mode32_instruction[34:0] ==?  { 3'd0, 4'b????, 2'b00, 1'd0, MOV, 1'd0,
                                                     4'd0, ARCH_PC, 8'd0, 4'd15 }
                    )
                    &&
                    mode32_instruction_valid
                  )
                  ||
                  // As is load multiple with PC in register list.
                  (
                   mode32_instruction[27:25] == 3'b100 && // LDM
                   mode32_instruction[20]              && // Load
                   mode32_instruction_valid            &&
                   mode32_instruction[15]                 // PC in reglist.
                  )
                  ||
                  // As is load to PC from SP index.
                  (
                        (mode32_instruction[31:0] ==? LS_INSTRUCTION_SPECIFIED_SHIFT ||
                         mode32_instruction[31:0] ==? LS_IMMEDIATE)                  &&
                         mode32_instruction[15:12] == ARCH_PC                        &&
                         mode32_instruction[20]                                      &&
                         mode32_instruction_valid                                    &&
                         mode32_instruction[19:16] == ARCH_SP
                  )
                )
        begin

                // Predicted as taken.
                if ( skid_taken == WT || skid_taken == ST || mode32_instruction[31:28] == AL )
                begin
                        ras_ptr_nxt--;
                        w_pc_from_decode    = ras_ff[ras_ptr_nxt];

                        if ( skid_pred[32] && skid_pred[31:0] != w_pc_from_decode )
                        begin
                                w_clear_from_decode = 1'd1;
                        end
                        else if (!skid_pred[32])
                        begin
                                w_clear_from_decode = 1'd1;
                        end
                        else
                        begin
                                w_clear_from_decode = 1'd0;
                        end

                        if ( mode32_instruction[31:28] == AL )
                        begin
                                taken_nxt = ST;
                        end

                        // Helps ALU verify that the RAS is correct.
                        ppc_nxt             = w_pc_from_decode;
                end
                else // Predicted as not taken.
                begin
                        w_clear_from_decode = 1'd0;
                        w_pc_from_decode    = 32'd0;
                        ppc_nxt             = skid_pc_ff + (i_cpu_mode_t ? 32'd2 : 32'd4);
                end
        end
        else if (
                         mode32_instruction_valid                                    &&
                        (mode32_instruction[31:0] ==? LS_INSTRUCTION_SPECIFIED_SHIFT ||
                         mode32_instruction[31:0] ==? LS_IMMEDIATE)                  &&
                         mode32_instruction[15:12] == ARCH_PC                        &&
                         mode32_instruction[20]
                )
        begin
                // Jump table. Do what the BTB says. Dont correct it.
        end
        else if (
                        // Data processing instructions for MOV/ADD with
                        // PC as destination. CPU predicts that with a jump.
                        mode32_instruction_valid                                               &&
                        mode32_instruction[27:26] == 2'b00                                     &&
                        mode32_instruction[15:12] == ARCH_PC                                   &&
                        (mode32_instruction[25] || !mode32_instruction[4] || !mode32_instruction[7]) &&
                        ( (mode32_instruction[24:21] == ADD) || (mode32_instruction[24:21] == MOV) )
                        // mode32_instruction inside {ADD, MOV}
                )
        begin
                // Jump table. Do what the BTB says. Dont correct it.
        end
        else if (mode32_instruction_valid)
        // Predict non supported instructions as strongly not taken.
        begin
                taken_nxt = SNT;

                // Clear out the BTB.
                if ( skid_pred[32] )
                begin
                        w_clear_from_decode = 1'd1;
                        w_pc_from_decode    = skid_pc_ff + (i_cpu_mode_t ? 32'd2 : 32'd4);
                        ppc_nxt             = w_pc_from_decode;
                        o_clear_btb         = 1'd1;
                end
        end
        else
        begin
                taken_nxt = SNT;
        end
end

// This FSM handles LDM/STM/SWAP/SWAPB/BL/LMULT
zap_predecode_uop_sequencer u_zap_uop_sequencer (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_cpsr_t(i_cpu_mode_t),

        .i_instruction(mode32_instruction),                // Skid version
        .i_instruction_valid(mode32_instruction_valid),    // Skid version
        .i_fiq(mode32_fiq),                                // Skid version
        .i_irq(mode32_irq),                                // Skid version
        .i_l4_enable(i_l4_enable),

        .i_clear_from_writeback(i_clear_from_writeback),
        .i_data_stall(i_data_stall),
        .i_clear_from_alu(i_clear_from_alu),
        .i_issue_stall(i_stall_from_issue),
        .i_stall_from_shifter(i_stall_from_shifter),
        .i_clear_from_decode(o_clear_from_decode),

        .o_irq(irq_mask),
        .o_fiq(fiq_mask),

        .o_instruction(o_instruction_nxt), // 40-bit, upper 4 bits RESERVED.
        .o_instruction_valid(o_instruction_valid_nxt),
        .o_align(align_nxt),
        .o_switch(switch_nxt), // Provided when load to PC in LDM.
        .o_uop_last(o_uop_last_nxt),
        .o_stall_from_decode(mem_fetch_stall)
);

endmodule

