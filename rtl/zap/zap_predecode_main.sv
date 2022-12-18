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
// --                                                                         -- 
// --  The pre-decode block. Does partial instruction decoding and sequencing --
// --  before passing the instruction onto the next stage.                    --
// --                                                                         --
// -----------------------------------------------------------------------------


module zap_predecode_main #( parameter PHY_REGS = 46, parameter RAS_DEPTH = 8 )

(
        // Clock and reset.
        input   logic                            i_clk,
        input   logic                            i_reset,

        // UOP
        output logic                             o_uop_last,

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
logic                               dbg;
logic                               w_clear_from_decode;
logic [31:0]                        w_pc_from_decode;
logic [39:0]                        o_instruction_nxt;
logic                               o_instruction_valid_nxt;
logic                               o_uop_last_nxt;
logic                               mem_fetch_stall;
logic                               arm_irq;
logic                               arm_fiq;
logic                               irq_mask;
logic                               fiq_mask;
logic [34:0]                        arm_instruction;
logic                               arm_instruction_valid;
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

///////////////////////////////////////////////////////////////////////////////

// Flop the outputs to break the pipeline at this point.
always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                reset;
                clear;
                
                // Return address stack is RESET.
                ras_ff     <= '0;
                ras_ptr_ff <= '0;
        end
        else if ( i_clear_from_writeback )
        begin
                clear;
        end
        else if ( i_data_stall )
        begin
                // Preserve state.
        end
        else if ( i_clear_from_alu )
        begin
                clear;
        end
        else if ( i_stall_from_shifter )
        begin
                // Preserve state.
        end
        else if ( i_stall_from_issue )
        begin
                // Preserve state.
        end
        else if ( o_clear_from_decode )
        begin
                reset;
        end
        // If no stall, only then update...
        else
        begin
                // Do not pass IRQ and FIQ if mask is 1.
                o_irq_ff               <= skid_irq & irq_mask; 
                o_fiq_ff               <= skid_fiq & fiq_mask; 
                o_abt_ff               <= skid_abt;                    
                o_und_ff               <= skid_und && skid_instruction_valid;
                o_pc_plus_8_ff         <= skid_pc_plus_8_ff;
                o_pc_ff                <= skid_pc_ff;
                o_force32align_ff      <= skid_force32;
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

task automatic reset;
begin
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
end
endtask

task automatic clear;
begin
                o_irq_ff                                <= 0;
                o_fiq_ff                                <= 0;
                o_abt_ff                                <= 0; 
                o_und_ff                                <= 0;
                o_taken_ff                              <= 0;
                o_instruction_valid_ff                  <= 0;
                o_uop_last                              <= 0;
                o_clear_from_decode                     <= 0;
end
endtask

///////////////////////////////////////////////////////////////////////////////

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
        else if ( i_data_stall )
        begin
                // Stall from shifter.
        end
        else if ( i_clear_from_alu )
        begin
                o_stall_from_decode <= 1'd0;
        end
        else if ( i_stall_from_shifter )
        begin
                // Preserve state.
        end
        else if ( i_stall_from_issue )
        begin
                // Preserve state.
        end
        else 
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

///////////////////////////////////////////////////////////////////////////////

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



///////////////////////////////////////////////////////////////////////////////

// Alias.
always_comb arm_instruction          = cp_instruction;
always_comb arm_instruction_valid    = cp_instruction_valid;
always_comb arm_irq                  = cp_irq;
always_comb arm_fiq                  = cp_fiq;

///////////////////////////////////////////////////////////////////////////////

wire unused;
assign unused = |dbg;

always_comb
begin:bprblk1
        logic [31:0] addr;
        logic [31:0] addr_final;

        dbg = 1'd0;

        o_clear_btb             = 1'd0;
        w_clear_from_decode     = 1'd0;
        w_pc_from_decode        = 32'd0;
        taken_nxt               = skid_taken;
        ppc_nxt                 = o_ppc_ff;
        ras_nxt                 = ras_ff;
        ras_ptr_nxt             = ras_ptr_ff;
        addr                    = {{8{arm_instruction[23]}},arm_instruction[23:0]}; // Offset.
        
        if ( arm_instruction[34] )      // Indicates a left shift of 1 i.e., X = X * 2.
                addr_final = addr << 1;
        else                            // Indicates a left shift of 2 i.e., X = X * 4.
                addr_final = addr << 2;

        // Is it an instruction that we support ?
        // Proccessor recognizes:
        // 1. BL as a function call.
        // 2. MOV PC, LR as a function return.
        // 3. BX LR as a function return.

        // Bcc[L] <offset>. Function call.
        if ( arm_instruction[27:25] == 3'b101 && arm_instruction_valid )
        begin
                if ( skid_taken == ST || skid_taken == WT || arm_instruction[31:28] == AL ) 
                // Predicted as Taken or Predicted as Strongly Taken or Always taken.
                begin
                        // Predict new PC.
                        w_pc_from_decode    = skid_pc_plus_8_ff + addr_final;
                        ppc_nxt             = w_pc_from_decode;
        
                        if ( skid_pred[32] && skid_pred[31:0] != w_pc_from_decode )
                                w_clear_from_decode = 1'd1;
                        else if ( !skid_pred[32] )
                                w_clear_from_decode = 1'd1;
                        else
                                w_clear_from_decode = 1'd0;

                        // Force taken status to ST.
                        if ( arm_instruction[31:28] == AL )
                        begin 
                                taken_nxt = ST;  
                        end

                        // If Link=1, push next address onto RAS.
                        if ( arm_instruction[24] )
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
                  // BX LR is recognized as a fnction return.
                  (
                   arm_instruction[31:0] ==? BX_INST && 
                   arm_instruction[3:0]   ==   4'd14 && 
                   arm_instruction_valid) 
                  || 
                   // As is MOV PC, LR
                  (
                   ( arm_instruction[34:0] ==?  { 3'd0, 4'b????, 2'b00, 1'd0, MOV, 1'd0, 
                                                4'd0, ARCH_PC, 8'd0, 4'd15 } ) 
                   && 
                   arm_instruction_valid
                  ) ||
                  // As is load multiple with PC in register list.
                  (
                   arm_instruction[27:25] == 3'b100 && // LDM
                   arm_instruction[20]              && // Load
                   arm_instruction_valid            &&
                   arm_instruction[15]                 // PC in reglist.
                  ) ||
                  // As is load to PC from SP index.
                  (
                        (arm_instruction[31:0] ==? LS_INSTRUCTION_SPECIFIED_SHIFT ||
                         arm_instruction[31:0] ==? LS_IMMEDIATE)                  &&
                         arm_instruction[15:12] == ARCH_PC                        && 
                         arm_instruction[20]                                      &&
                         arm_instruction_valid                                    &&
                         arm_instruction[19:16] == ARCH_SP
                  )
                )
        begin
                dbg = 1'd1;

                // Predicted as taken.
                if ( skid_taken == WT || skid_taken == ST || arm_instruction[31:28] == AL )
                begin
                        ras_ptr_nxt--;
                        w_pc_from_decode    = ras_ff[ras_ptr_nxt];

                        if ( skid_pred[32] && skid_pred[31:0] != w_pc_from_decode )
                                w_clear_from_decode = 1'd1;
                        else if (!skid_pred[32])
                                w_clear_from_decode = 1'd1;
                        else
                                w_clear_from_decode = 1'd0;

                        if ( arm_instruction[31:28] == AL )
                                taken_nxt = ST;

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
                         arm_instruction_valid                                    && 
                        (arm_instruction[31:0] ==? LS_INSTRUCTION_SPECIFIED_SHIFT ||
                         arm_instruction[31:0] ==? LS_IMMEDIATE)                  &&
                         arm_instruction[15:12] == ARCH_PC                        && 
                         arm_instruction[20]                                
                )
        begin
                // Jump table. Do what the BTB says. Dont correct it.
        end
        else if (
                        // Data processing instructions for MOV/ADD with
                        // PC as destination. CPU predicts that with a jump.
                        arm_instruction_valid                                               &&
                        arm_instruction[27:26] == 2'b00                                     &&
                        arm_instruction[15:12] == ARCH_PC                                   &&
                        (arm_instruction[25] || !arm_instruction[4] || !arm_instruction[7]) &&
                        arm_instruction[24:21] inside {ADD, MOV}
                )
        begin
                // Jump table. Do what the BTB says. Dont correct it.
        end
        else if (arm_instruction_valid) // Predict non supported as strongly not taken.
        begin
                taken_nxt = SNT;

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

///////////////////////////////////////////////////////////////////////////////

// This FSM handles LDM/STM/SWAP/SWAPB/BL/LMULT
zap_predecode_uop_sequencer u_zap_uop_sequencer (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_cpsr_t(i_cpu_mode_t),

        .i_instruction(arm_instruction),                // Skid version
        .i_instruction_valid(arm_instruction_valid),    // Skid version
        .i_fiq(arm_fiq),                                // Skid version
        .i_irq(arm_irq),                                // Skid version

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
        .o_uop_last(o_uop_last_nxt),
        .o_stall_from_decode(mem_fetch_stall)
);

///////////////////////////////////////////////////////////////////////////////

endmodule

