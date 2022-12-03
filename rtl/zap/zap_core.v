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
// -- This is the ZAP core which contains the bare processor core without any --
// -- cache or MMU. In other words, this is the bare pipeline.                --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

module zap_core #(
        // Number of branch predictor entries.
        parameter [31:0] BP_ENTRIES = 1024,

        // Depth of FIFO.
        parameter [31:0] FIFO_DEPTH = 4
) 
(

// ------------------------------------------------
// Clock and reset. Reset is synchronous.
// ------------------------------------------------

input wire                              i_clk,                  
input wire                              i_reset,                

// -------------------------------------------------
// Wishbone memory access for data.
// -------------------------------------------------

output wire                             o_data_wb_we,
output wire                             o_data_wb_cyc,
output wire                             o_data_wb_stb,
output wire[31:0]                       o_data_wb_adr,              
input wire                              i_data_wb_ack,
input wire                              i_data_wb_err,
input wire  [31:0]                      i_data_wb_dat,
output wire [31:0]                      o_data_wb_dat,
output wire  [3:0]                      o_data_wb_sel,                  

// Next state stuff for Wishbone data.
output wire                             o_data_wb_we_nxt,
output wire                             o_data_wb_cyc_nxt,
output wire                             o_data_wb_stb_nxt,
output wire [31:0]                      o_data_wb_dat_nxt,
output wire  [3:0]                      o_data_wb_sel_nxt,    
output wire [31:0]                      o_data_wb_adr_nxt,

// Force user view.
output wire                             o_mem_translate,

// --------------------------------------------------
// Interrupts. Active high.
// --------------------------------------------------

input wire                              i_fiq,                  // FIQ signal.
input wire                              i_irq,                  // IRQ signal.

// ---------------------------------------------------
// Wishbone instruction access ports.
// ---------------------------------------------------

output wire     [31:0]                  o_instr_wb_adr, // Code address.                  
output wire                             o_instr_wb_cyc, // Always 1.
output wire                             o_instr_wb_stb, // Always 1.
output wire                             o_instr_wb_we,  // Always 0.
input wire [31:0]                       i_instr_wb_dat, // A 32-bit ZAP instruction.
input wire                              i_instr_wb_ack, // Instruction available.
input wire                              i_instr_wb_err, // Instruction abort fault. Given with ack = 1.
output wire [3:0]                       o_instr_wb_sel, // wishbone byte select.

// Instruction wishbone nxt ports.
output wire     [31:0]                  o_instr_wb_adr_nxt,               
output wire                             o_instr_wb_stb_nxt,

// Determines user or supervisory mode. Cache must use this for VM.
output wire      [31:0]                 o_cpsr,                 

// -----------------------------------------------------
// For MMU/cache connectivity.
// -----------------------------------------------------

input wire      [31:0]                  i_fsr,
input wire      [31:0]                  i_far,
output wire      [31:0]                 o_dac,
output wire      [31:0]                 o_baddr,
output wire                             o_mmu_en,
output wire      [1:0]                  o_sr,
output wire                             o_dcache_inv,
output wire                             o_icache_inv,
output wire                             o_dcache_clean,
output wire                             o_icache_clean,
output wire                             o_dtlb_inv,
output wire                             o_itlb_inv,
output wire                             o_dcache_en,
output wire                             o_icache_en,
input   wire                            i_dcache_inv_done,
input   wire                            i_icache_inv_done,
input   wire                            i_dcache_clean_done,
input   wire                            i_icache_clean_done
);

// ----------------------------------------------------------------------------

`include "zap_localparams.vh"
`include "zap_defines.vh"
`include "zap_functions.vh"

localparam ARCH_REGS = 32;
localparam ALU_OPS   = 32;
localparam SHIFT_OPS = 7;
localparam PHY_REGS  = TOTAL_PHY_REGS;
localparam FLAG_WDT  = 32;

// ----------------------------------------------------------------------------

// Low Bandwidth Coprocessor (COP) I/F to CP15 control block.
wire                             copro_done;        // COP done.
wire                             copro_dav;         // COP command valid.
wire  [31:0]                     copro_word;        // COP command.
wire                             copro_reg_en;      // COP controls registers.
wire      [$clog2(PHY_REGS)-1:0] copro_reg_wr_index;// Reg. file write index.
wire      [$clog2(PHY_REGS)-1:0] copro_reg_rd_index;// Reg. file read index.
wire      [31:0]                 copro_reg_wr_data; // Reg. file write data.
wire     [31:0]                  copro_reg_rd_data; // Reg. file read data.

wire                            reset;               // Tied to i_reset.
wire                            shelve;              // From writeback.
wire                            fiq;                 // Tied to FIQ.
wire                            irq;                 // Tied to IRQ.

// Clear and stall signals.
wire                            stall_from_decode;
wire                            clear_from_alu;
wire                            stall_from_issue;
wire                            clear_from_writeback;
wire                            data_stall;
wire                            code_stall;
wire                            instr_valid;
wire                            pipeline_is_not_empty;

// Fetch
wire [31:0]                     fetch_instruction;  // Instruction from the fetch unit.
wire                            fetch_valid;        // Instruction valid from the fetch unit.
wire                            fetch_instr_abort;  // abort indicator.
wire [31:0]                     fetch_pc_plus_8_ff; // PC + 8 generated from the fetch unit.
wire [31:0]                     fetch_pc_ff;        // PC generated from fetch unit.
wire [1:0]                      fetch_bp_state;

// FIFO.
wire [31:0]                     fifo_pc_plus_8;
wire                            fifo_valid;
wire                            fifo_instr_abort;
wire [31:0]                     fifo_instruction;
wire [1:0]                      fifo_bp_state;

// Predecode
wire [31:0]                     predecode_pc_plus_8;
wire [31:0]                     predecode_pc;
wire                            predecode_irq;
wire                            predecode_fiq;
wire                            predecode_abt; 
wire [35:0]                     predecode_inst;
wire                            predecode_val;
wire                            predecode_force32;
wire                            predecode_und;
wire [1:0]                      predecode_taken;

// Compressed decoder.
wire                            thumb_irq;
wire                            thumb_fiq;
wire                            thumb_iabort;
wire [34:0]                     thumb_instruction;
wire                            thumb_valid;
wire                            thumb_und;
wire                            thumb_force32;
wire [1:0]                      thumb_bp_state;
wire [31:0]                     thumb_pc_ff;
wire [31:0]                     thumb_pc_plus_8_ff;

// Decode
wire [3:0]                      decode_condition_code;
wire [$clog2(PHY_REGS)-1:0]     decode_destination_index;
wire [32:0]                     decode_alu_source_ff;
wire [$clog2(ALU_OPS)-1:0]      decode_alu_operation_ff;             
wire [32:0]                     decode_shift_source_ff;
wire [$clog2(SHIFT_OPS)-1:0]    decode_shift_operation_ff;
wire [32:0]                     decode_shift_length_ff;
wire                            decode_flag_update_ff;
wire [$clog2(PHY_REGS)-1:0]     decode_mem_srcdest_index_ff;
wire                            decode_mem_load_ff;
wire                            decode_mem_store_ff;
wire                            decode_mem_pre_index_ff;
wire                            decode_mem_unsigned_byte_enable_ff;
wire                            decode_mem_signed_byte_enable_ff;
wire                            decode_mem_signed_halfword_enable_ff;
wire                            decode_mem_unsigned_halfword_enable_ff;
wire                            decode_mem_translate_ff;
wire                            decode_irq_ff;
wire                            decode_fiq_ff;
wire                            decode_abt_ff;
wire                            decode_swi_ff;
wire [31:0]                     decode_pc_plus_8_ff;
wire [31:0]                     decode_pc_ff;
wire                            decode_switch_ff;
wire                            decode_force32_ff;
wire                            decode_und_ff;
wire                            clear_from_decode;
wire [31:0]                     pc_from_decode;
wire [1:0]                      decode_taken_ff;

// Issue
wire [$clog2(PHY_REGS)-1:0]     issue_rd_index_0, 
                                issue_rd_index_1, 
                                issue_rd_index_2, 
                                issue_rd_index_3;

wire [3:0]                      issue_condition_code_ff;  
wire [$clog2(PHY_REGS)-1:0]     issue_destination_index_ff;
wire [$clog2(ALU_OPS)-1:0]      issue_alu_operation_ff;
wire [$clog2(SHIFT_OPS)-1:0]    issue_shift_operation_ff;
wire                            issue_flag_update_ff;
wire [$clog2(PHY_REGS)-1:0]     issue_mem_srcdest_index_ff;
wire                            issue_mem_load_ff;
wire                            issue_mem_store_ff;
wire                            issue_mem_pre_index_ff;
wire                            issue_mem_unsigned_byte_enable_ff;
wire                            issue_mem_signed_byte_enable_ff;
wire                            issue_mem_signed_halfword_enable_ff;
wire                            issue_mem_unsigned_halfword_enable_ff;
wire                            issue_mem_translate_ff;
wire                            issue_irq_ff;
wire                            issue_fiq_ff;
wire                            issue_abt_ff;
wire                            issue_swi_ff;
wire [31:0]                     issue_alu_source_value_ff;
wire [31:0]                     issue_shift_source_value_ff;
wire [31:0]                     issue_shift_length_value_ff;
wire [31:0]                     issue_mem_srcdest_value_ff;
wire [32:0]                     issue_alu_source_ff;
wire [32:0]                     issue_shift_source_ff;
wire [31:0]                     issue_pc_plus_8_ff;
wire [31:0]                     issue_pc_ff;
wire                            issue_shifter_disable_ff;
wire                            issue_switch_ff;
wire                            issue_force32_ff;
wire                            issue_und_ff;
wire  [1:0]                     issue_taken_ff;

wire [$clog2(PHY_REGS)-1:0]     rd_index_0;
wire [$clog2(PHY_REGS)-1:0]     rd_index_1;
wire [$clog2(PHY_REGS)-1:0]     rd_index_2;
wire [$clog2(PHY_REGS)-1:0]     rd_index_3;

// Shift
wire [$clog2(PHY_REGS)-1:0]     shifter_mem_srcdest_index_ff;
wire                            shifter_mem_load_ff;
wire                            shifter_mem_store_ff;
wire                            shifter_mem_pre_index_ff;
wire                            shifter_mem_unsigned_byte_enable_ff;
wire                            shifter_mem_signed_byte_enable_ff;
wire                            shifter_mem_signed_halfword_enable_ff;
wire                            shifter_mem_unsigned_halfword_enable_ff;
wire                            shifter_mem_translate_ff;
wire [3:0]                      shifter_condition_code_ff;
wire [$clog2(PHY_REGS)-1:0]     shifter_destination_index_ff;
wire [$clog2(ALU_OPS)-1:0]      shifter_alu_operation_ff;
wire                            shifter_nozero_ff;
wire                            shifter_flag_update_ff;
wire [31:0]                     shifter_mem_srcdest_value_ff;
wire [31:0]                     shifter_alu_source_value_ff;
wire [31:0]                     shifter_shifted_source_value_ff;
wire                            shifter_shift_carry_ff;
wire [31:0]                     shifter_pc_plus_8_ff;
wire [31:0]                     shifter_pc_ff;
wire                            shifter_irq_ff;
wire                            shifter_fiq_ff;
wire                            shifter_abt_ff;
wire                            shifter_swi_ff;
wire                            shifter_switch_ff;
wire                            shifter_force32_ff;
wire                            shifter_und_ff;
wire                            stall_from_shifter;
wire [1:0]                      shifter_taken_ff;

// ALU
wire [$clog2(SHIFT_OPS)-1:0]    alu_shift_operation_ff;
wire [31:0]                     alu_alu_result_nxt;
wire [31:0]                     alu_alu_result_ff;
wire                            alu_abt_ff;
wire                            alu_irq_ff;
wire                            alu_fiq_ff;
wire                            alu_swi_ff;
wire                            alu_dav_ff;
wire                            alu_dav_nxt;
wire [31:0]                     alu_pc_plus_8_ff;
wire [31:0]                     pc_from_alu;
wire [$clog2(PHY_REGS)-1:0]     alu_destination_index_ff;
wire [FLAG_WDT-1:0]             alu_flags_ff;
wire [$clog2(PHY_REGS)-1:0]     alu_mem_srcdest_index_ff;
wire                            alu_mem_load_ff;
wire                            alu_und_ff;
wire [31:0]                     alu_cpsr_nxt; 
wire                            confirm_from_alu;
wire                            alu_sbyte_ff;
wire                            alu_ubyte_ff;
wire                            alu_shalf_ff;
wire                            alu_uhalf_ff;
wire [31:0]                     alu_address_ff;
wire [31:0]                     alu_address_nxt;

// Memory
wire [31:0]                     memory_alu_result_ff;
wire [$clog2(PHY_REGS)-1:0]     memory_destination_index_ff;
wire [$clog2(PHY_REGS)-1:0]     memory_mem_srcdest_index_ff;
wire                            memory_dav_ff;
wire [31:0]                     memory_pc_plus_8_ff;
wire                            memory_irq_ff;
wire                            memory_fiq_ff;
wire                            memory_swi_ff;
wire                            memory_instr_abort_ff;
wire                            memory_mem_load_ff;
wire  [FLAG_WDT-1:0]            memory_flags_ff;
wire  [31:0]                    memory_mem_rd_data;
wire                            memory_und_ff;
wire                            memory_data_abt_ff;

// Writeback
wire [31:0]                     rd_data_0;
wire [31:0]                     rd_data_1;
wire [31:0]                     rd_data_2;
wire [31:0]                     rd_data_3;
wire [31:0]                     cpsr_nxt, cpsr;

// Hijack interface - related to Writeback - ALU interaction.
wire                            wb_hijack;
wire [31:0]                     wb_hijack_op1;
wire [31:0]                     wb_hijack_op2;
wire                            wb_hijack_cin;
wire [31:0]                     alu_hijack_sum;

// Decompile chain for debugging.
wire [64*8-1:0]                 decode_decompile;
wire [64*8-1:0]                 issue_decompile;
wire [64*8-1:0]                 shifter_decompile;
wire [64*8-1:0]                 alu_decompile;
wire [64*8-1:0]                 memory_decompile; 
wire [64*8-1:0]                 rb_decompile;

// ----------------------------------------------------------------------------

assign o_cpsr                   = alu_flags_ff;
assign o_data_wb_adr            = {alu_address_ff[31:2], 2'd0};
assign o_data_wb_adr_nxt        = {alu_address_nxt[31:2], 2'd0};
assign o_instr_wb_we            = 1'd0;
assign o_instr_wb_sel           = 4'b1111;
assign reset                    = i_reset; 
assign irq                      = i_irq;   
assign fiq                      = i_fiq;   
assign data_stall               = o_data_wb_stb && o_data_wb_cyc && !i_data_wb_ack;
assign code_stall               = (!o_instr_wb_stb && !o_instr_wb_cyc) || !i_instr_wb_ack;
assign instr_valid              = o_instr_wb_stb && o_instr_wb_cyc && i_instr_wb_ack & !shelve;
assign pipeline_is_not_empty    =         predecode_val                      ||     
                                          (decode_condition_code    != NV)   ||
                                          (issue_condition_code_ff  != NV)   ||
                                          (shifter_condition_code_ff!= NV)   ||
                                          alu_dav_ff                         ||
                                          memory_dav_ff;  

// ----------------------------------------------------------------------------

// =========================
// FETCH STAGE 
// =========================
zap_fetch_main
#(
        .BP_ENTRIES(BP_ENTRIES)
) 
u_zap_fetch_main (
        // Input.
        .i_clk                          (i_clk), 
        .i_reset                        (reset),

        .i_code_stall                   (code_stall),

        .i_clear_from_writeback         (clear_from_writeback),
        .i_clear_from_decode            (clear_from_decode),

        .i_data_stall                   (1'd0), 

        .i_clear_from_alu               (clear_from_alu),

        .i_stall_from_shifter           (1'd0), 
        .i_stall_from_issue             (1'd0), 
        .i_stall_from_decode            (1'd0), 

        .i_pc_ff                        (o_instr_wb_adr),
        .i_instruction                  (i_instr_wb_dat),
        .i_valid                        (instr_valid),
        .i_instr_abort                  (i_instr_wb_err),

        .i_cpsr_ff_t                    (alu_flags_ff[T]),

        // Output.
        .o_instruction                  (fetch_instruction),
        .o_valid                        (fetch_valid),
        .o_instr_abort                  (fetch_instr_abort),
        .o_pc_plus_8_ff                 (fetch_pc_plus_8_ff),
        .o_pc_ff                        (fetch_pc_ff),


        .i_confirm_from_alu             (confirm_from_alu),
        .i_pc_from_alu                  (shifter_pc_ff),
        .i_taken                        (shifter_taken_ff),
        .o_taken                        (fetch_bp_state)
);

// =========================
// FIFO.
// =========================
zap_fifo
#( .WDT(67), .DEPTH(FIFO_DEPTH) ) U_ZAP_FIFO (
        .i_clk                          (i_clk),
        .i_reset                        (i_reset),
        .i_clear_from_writeback         (clear_from_writeback),

        .i_write_inhibit                ( code_stall ),
        .i_data_stall                   ( data_stall ),

        .i_clear_from_alu               (clear_from_alu),
        .i_stall_from_shifter           (stall_from_shifter),
        .i_stall_from_issue             (stall_from_issue),  
        .i_stall_from_decode            (stall_from_decode),
        .i_clear_from_decode            (clear_from_decode),

        .i_instr                        ({fetch_pc_plus_8_ff, fetch_instr_abort, fetch_instruction, fetch_bp_state}),
        .i_valid                        (fetch_valid),
        .o_instr                        ({fifo_pc_plus_8, fifo_instr_abort, fifo_instruction, fifo_bp_state}),
        .o_valid                        (fifo_valid),

        .o_wb_stb                       (o_instr_wb_stb),
        .o_wb_stb_nxt                   (o_instr_wb_stb_nxt),
        .o_wb_cyc                       (o_instr_wb_cyc)
);

// =========================
// COMPRESSED DECODER STAGE
// =========================
zap_thumb_decoder u_zap_thumb_decoder (
.i_clk                                  (i_clk),
.i_reset                                (i_reset),
.i_clear_from_writeback                 (clear_from_writeback),
.i_data_stall                           (data_stall),
.i_clear_from_alu                       (clear_from_alu),
.i_stall_from_shifter                   (stall_from_shifter),
.i_stall_from_issue                     (stall_from_issue),
.i_stall_from_decode                    (stall_from_decode),
.i_clear_from_decode                    (clear_from_decode),

.i_taken                                (fifo_bp_state),
.i_instruction                          (fifo_instruction),
.i_instruction_valid                    (fifo_valid),
.i_irq                                  (fifo_valid ? irq && !alu_flags_ff[I] : 1'd0), // Pass interrupt only if mask = 0 and instruction exists.
.i_fiq                                  (fifo_valid ? fiq && !alu_flags_ff[F] : 1'd0), // Pass interrupt only if mask = 0 and instruction exists.
.i_iabort                               (fifo_instr_abort),
.o_iabort                               (thumb_iabort),
.i_cpsr_ff_t                            (alu_flags_ff[T]),
.i_pc_ff                                (alu_flags_ff[T] ? fifo_pc_plus_8 - 32'd4 : fifo_pc_plus_8 - 32'd8),
.i_pc_plus_8_ff                         (fifo_pc_plus_8),

.o_instruction                          (thumb_instruction),
.o_instruction_valid                    (thumb_valid),
.o_und                                  (thumb_und),
.o_force32_align                        (thumb_force32),
.o_pc_ff                                (thumb_pc_ff),
.o_pc_plus_8_ff                         (thumb_pc_plus_8_ff),
.o_irq                                  (thumb_irq),
.o_fiq                                  (thumb_fiq),
.o_taken_ff                             (thumb_bp_state)
);

// =========================
// PREDECODE STAGE 
// =========================
zap_predecode_main #(
        .ARCH_REGS(ARCH_REGS),
        .PHY_REGS(PHY_REGS),
        .SHIFT_OPS(SHIFT_OPS),
        .ALU_OPS(ALU_OPS),
        .COPROCESSOR_INTERFACE_ENABLE(1'd1),
        .COMPRESSED_EN(1'd1)
)
u_zap_predecode (
        // Input.
        .i_clk                          (i_clk),
        .i_reset                        (reset),

        .i_clear_from_writeback         (clear_from_writeback),
        .i_data_stall                   (data_stall), 
        .i_clear_from_alu               (clear_from_alu),
        .i_stall_from_shifter           (stall_from_shifter),
        .i_stall_from_issue             (stall_from_issue),

        .i_irq                          (thumb_irq),
        .i_fiq                          (thumb_fiq),

        .i_abt                          (thumb_iabort),
        .i_pc_plus_8_ff                 (thumb_pc_plus_8_ff),
        .i_pc_ff                        (thumb_pc_plus_8_ff - 32'd8),

        .i_cpu_mode_t                   (alu_flags_ff[T]),
        .i_cpu_mode_mode                (alu_flags_ff[`CPSR_MODE]),

        .i_instruction                  (thumb_instruction),
        .i_instruction_valid            (thumb_valid),
        .i_taken                        (thumb_bp_state),

        .i_force32                      (thumb_force32),
        .i_und                          (thumb_und),

        .i_copro_done                   (copro_done),
        .i_pipeline_dav                 (pipeline_is_not_empty),

        // Output.
        .o_stall_from_decode            (stall_from_decode),
        .o_pc_plus_8_ff                 (predecode_pc_plus_8),

        .o_pc_ff                        (predecode_pc),
        .o_irq_ff                       (predecode_irq),
        .o_fiq_ff                       (predecode_fiq),
        .o_abt_ff                       (predecode_abt),
        .o_und_ff                       (predecode_und),

        .o_force32align_ff              (predecode_force32),

        .o_copro_dav_ff                 (copro_dav),
        .o_copro_word_ff                (copro_word),

        .o_clear_from_decode            (clear_from_decode),
        .o_pc_from_decode               (pc_from_decode),

        .o_instruction_ff               (predecode_inst),
        .o_instruction_valid_ff         (predecode_val),

        .o_taken_ff                     (predecode_taken)
);

// =====================
// DECODE STAGE 
// =====================

zap_decode_main #(
        .ARCH_REGS(ARCH_REGS),
        .PHY_REGS(PHY_REGS),
        .SHIFT_OPS(SHIFT_OPS),
        .ALU_OPS(ALU_OPS)
)
u_zap_decode_main (
        .o_decompile                    (decode_decompile),

        // Input.
        .i_clk                          (i_clk),
        .i_reset                        (reset),

        .i_clear_from_writeback         (clear_from_writeback),
        .i_data_stall                   (data_stall),
        .i_clear_from_alu               (clear_from_alu),
        .i_stall_from_shifter           (stall_from_shifter),
        .i_stall_from_issue             (stall_from_issue),
        .i_thumb_und                    (predecode_und),
        .i_irq                          (predecode_irq),
        .i_fiq                          (predecode_fiq),
        .i_abt                          (predecode_abt),
        .i_pc_plus_8_ff                 (predecode_pc_plus_8),
        .i_pc_ff                        (predecode_pc),
       
        .i_cpsr_ff_mode                 (alu_flags_ff[`CPSR_MODE]),
        .i_cpsr_ff_i                    (alu_flags_ff[I]),
        .i_cpsr_ff_f                    (alu_flags_ff[F]),
       
        .i_instruction                  (predecode_inst),
        .i_instruction_valid            (predecode_val),
        .i_taken                        (predecode_taken),
        .i_force32align                 (predecode_force32),

        // Output.
        .o_condition_code_ff            (decode_condition_code),
        .o_destination_index_ff         (decode_destination_index),
        .o_alu_source_ff                (decode_alu_source_ff),
        .o_alu_operation_ff             (decode_alu_operation_ff),
        .o_shift_source_ff              (decode_shift_source_ff),
        .o_shift_operation_ff           (decode_shift_operation_ff),
        .o_shift_length_ff              (decode_shift_length_ff),
        .o_flag_update_ff               (decode_flag_update_ff),
        .o_mem_srcdest_index_ff         (decode_mem_srcdest_index_ff),
        .o_mem_load_ff                  (decode_mem_load_ff),
        .o_mem_store_ff                 (decode_mem_store_ff),
        .o_mem_pre_index_ff             (decode_mem_pre_index_ff),
        .o_mem_unsigned_byte_enable_ff  (decode_mem_unsigned_byte_enable_ff),
        .o_mem_signed_byte_enable_ff    (decode_mem_signed_byte_enable_ff),
        .o_mem_signed_halfword_enable_ff(decode_mem_signed_halfword_enable_ff),
        .o_mem_unsigned_halfword_enable_ff (decode_mem_unsigned_halfword_enable_ff),
        .o_mem_translate_ff             (decode_mem_translate_ff),
        .o_pc_plus_8_ff                 (decode_pc_plus_8_ff),
        .o_pc_ff                        (decode_pc_ff),
        .o_switch_ff                    (decode_switch_ff), 
        .o_irq_ff                       (decode_irq_ff),
        .o_fiq_ff                       (decode_fiq_ff),
        .o_abt_ff                       (decode_abt_ff),
        .o_swi_ff                       (decode_swi_ff),
        .o_und_ff                       (decode_und_ff),
        .o_force32align_ff              (decode_force32_ff),
        .o_taken_ff                     (decode_taken_ff)
);

// ==================
// ISSUE 
// ==================

zap_issue_main #(
        .PHY_REGS(PHY_REGS),
        .SHIFT_OPS(SHIFT_OPS),
        .ALU_OPS(ALU_OPS)
       
)
u_zap_issue_main
(
        .i_decompile(decode_decompile),
        .o_decompile(issue_decompile),

        .i_und_ff(decode_und_ff),
        .o_und_ff(issue_und_ff),

        .i_taken_ff(decode_taken_ff),
        .o_taken_ff(issue_taken_ff),

        .i_pc_ff(decode_pc_ff),
        .o_pc_ff(issue_pc_ff),

        // Inputs
        .i_clk                          (i_clk), 
        .i_reset                        (reset),
        .i_clear_from_writeback         (clear_from_writeback),
        .i_stall_from_shifter           (stall_from_shifter),
        .i_data_stall                   (data_stall), 
        .i_clear_from_alu               (clear_from_alu),
        .i_pc_plus_8_ff                 (decode_pc_plus_8_ff),
        .i_condition_code_ff            (decode_condition_code),
        .i_destination_index_ff         (decode_destination_index),
        .i_alu_source_ff                (decode_alu_source_ff),
        .i_alu_operation_ff             (decode_alu_operation_ff),
        .i_shift_source_ff              (decode_shift_source_ff),
        .i_shift_operation_ff           (decode_shift_operation_ff),
        .i_shift_length_ff              (decode_shift_length_ff),
        .i_flag_update_ff               (decode_flag_update_ff),
        .i_mem_srcdest_index_ff         (decode_mem_srcdest_index_ff),
        .i_mem_load_ff                  (decode_mem_load_ff),
        .i_mem_store_ff                 (decode_mem_store_ff),
        .i_mem_pre_index_ff             (decode_mem_pre_index_ff),
        .i_mem_unsigned_byte_enable_ff  (decode_mem_unsigned_byte_enable_ff),
        .i_mem_signed_byte_enable_ff    (decode_mem_signed_byte_enable_ff),
        .i_mem_signed_halfword_enable_ff(decode_mem_signed_halfword_enable_ff),
        .i_mem_unsigned_halfword_enable_ff(decode_mem_unsigned_halfword_enable_ff),
        .i_mem_translate_ff             (decode_mem_translate_ff),
        .i_irq_ff                       (decode_irq_ff),
        .i_fiq_ff                       (decode_fiq_ff),
        .i_abt_ff                       (decode_abt_ff),
        .i_swi_ff                       (decode_swi_ff),
        .i_cpu_mode                     (alu_flags_ff), 
        // Needed to resolve CPSR refs.

        .i_force32align_ff              (decode_force32_ff),
        .o_force32align_ff              (issue_force32_ff),

        // Register file.
        .i_rd_data_0                    (rd_data_0),
        .i_rd_data_1                    (rd_data_1),
        .i_rd_data_2                    (rd_data_2),
        .i_rd_data_3                    (rd_data_3),

        // Feedback.
        .i_shifter_destination_index_ff (shifter_destination_index_ff),
        .i_alu_destination_index_ff     (alu_destination_index_ff),
        .i_memory_destination_index_ff  (memory_destination_index_ff),
        .i_alu_dav_nxt                  (alu_dav_nxt),
        .i_alu_dav_ff                   (alu_dav_ff),
        .i_memory_dav_ff                (memory_dav_ff),
        .i_alu_destination_value_nxt    (alu_alu_result_nxt),
        .i_alu_destination_value_ff     (alu_alu_result_ff),
        .i_memory_destination_value_ff  (memory_alu_result_ff),
        .i_shifter_mem_srcdest_index_ff (shifter_mem_srcdest_index_ff),
        .i_alu_mem_srcdest_index_ff     (alu_mem_srcdest_index_ff),
        .i_memory_mem_srcdest_index_ff  (memory_mem_srcdest_index_ff),
        .i_shifter_mem_load_ff          (shifter_mem_load_ff),
        .i_alu_mem_load_ff              (alu_mem_load_ff),
        .i_memory_mem_load_ff           (memory_mem_load_ff),
        .i_memory_mem_srcdest_value_ff  (memory_mem_rd_data),

        // Switch indicator.
        .i_switch_ff                    (decode_switch_ff),
        .o_switch_ff                    (issue_switch_ff),

        // Outputs.
        .o_rd_index_0                   (rd_index_0),
        .o_rd_index_1                   (rd_index_1),
        .o_rd_index_2                   (rd_index_2),
        .o_rd_index_3                   (rd_index_3),
        .o_condition_code_ff            (issue_condition_code_ff),
        .o_destination_index_ff         (issue_destination_index_ff),
        .o_alu_operation_ff             (issue_alu_operation_ff),
        .o_shift_operation_ff           (issue_shift_operation_ff),
        .o_flag_update_ff               (issue_flag_update_ff),
        .o_mem_srcdest_index_ff         (issue_mem_srcdest_index_ff),
        .o_mem_load_ff                  (issue_mem_load_ff),
        .o_mem_store_ff                 (issue_mem_store_ff),
        .o_mem_pre_index_ff             (issue_mem_pre_index_ff),
        .o_mem_unsigned_byte_enable_ff  (issue_mem_unsigned_byte_enable_ff),
        .o_mem_signed_byte_enable_ff    (issue_mem_signed_byte_enable_ff),
        .o_mem_signed_halfword_enable_ff(issue_mem_signed_halfword_enable_ff),
        .o_mem_unsigned_halfword_enable_ff(issue_mem_unsigned_halfword_enable_ff),
        .o_mem_translate_ff             (issue_mem_translate_ff),
        .o_irq_ff                       (issue_irq_ff),
        .o_fiq_ff                       (issue_fiq_ff),
        .o_abt_ff                       (issue_abt_ff),
        .o_swi_ff                       (issue_swi_ff),

        .o_alu_source_value_ff          (issue_alu_source_value_ff),
        .o_shift_source_value_ff        (issue_shift_source_value_ff),
        .o_shift_length_value_ff        (issue_shift_length_value_ff),
        .o_mem_srcdest_value_ff         (issue_mem_srcdest_value_ff),

        .o_alu_source_ff                (issue_alu_source_ff),
        .o_shift_source_ff              (issue_shift_source_ff),
        .o_stall_from_issue             (stall_from_issue),
        .o_pc_plus_8_ff                 (issue_pc_plus_8_ff),
        .o_shifter_disable_ff           (issue_shifter_disable_ff)
);

// =======================
// SHIFTER STAGE 
// =======================

zap_shifter_main #(
        .PHY_REGS(PHY_REGS),
        .ALU_OPS(ALU_OPS),
        .SHIFT_OPS(SHIFT_OPS)
)
u_zap_shifter_main
(
        .i_decompile                    (issue_decompile),
        .o_decompile                    (shifter_decompile),

        .i_pc_ff                        (issue_pc_ff),
        .o_pc_ff                        (shifter_pc_ff),

        .i_taken_ff                     (issue_taken_ff),
        .o_taken_ff                     (shifter_taken_ff),

        .i_und_ff                       (issue_und_ff),
        .o_und_ff                       (shifter_und_ff),

        .o_nozero_ff                    (shifter_nozero_ff),

        .i_clk                          (i_clk), 
        .i_reset                        (reset),

        .i_clear_from_writeback         (clear_from_writeback),
        .i_data_stall                   (data_stall), 
        .i_clear_from_alu               (clear_from_alu),
        .i_condition_code_ff            (issue_condition_code_ff),
        .i_destination_index_ff         (issue_destination_index_ff),
        .i_alu_operation_ff             (issue_alu_operation_ff),
        .i_shift_operation_ff           (issue_shift_operation_ff),
        .i_flag_update_ff               (issue_flag_update_ff),
        .i_mem_srcdest_index_ff         (issue_mem_srcdest_index_ff),
        .i_mem_load_ff                  (issue_mem_load_ff),
        .i_mem_store_ff                 (issue_mem_store_ff),
        .i_mem_pre_index_ff             (issue_mem_pre_index_ff),
        .i_mem_unsigned_byte_enable_ff  (issue_mem_unsigned_byte_enable_ff),
        .i_mem_signed_byte_enable_ff    (issue_mem_signed_byte_enable_ff),
        .i_mem_signed_halfword_enable_ff(issue_mem_signed_halfword_enable_ff),     
        .i_mem_unsigned_halfword_enable_ff(issue_mem_unsigned_halfword_enable_ff),
        .i_mem_translate_ff             (issue_mem_translate_ff),
        .i_irq_ff                       (issue_irq_ff),
        .i_fiq_ff                       (issue_fiq_ff),
        .i_abt_ff                       (issue_abt_ff),
        .i_swi_ff                       (issue_swi_ff),
        .i_alu_source_ff                (issue_alu_source_ff),
        .i_shift_source_ff              (issue_shift_source_ff),
        .i_alu_source_value_ff          (issue_alu_source_value_ff),
        .i_shift_source_value_ff        (issue_shift_source_value_ff),
        .i_shift_length_value_ff        (issue_shift_length_value_ff),
        .i_mem_srcdest_value_ff         (issue_mem_srcdest_value_ff),
        .i_pc_plus_8_ff                 (issue_pc_plus_8_ff),
        .i_disable_shifter_ff           (issue_shifter_disable_ff),

        // Next CPSR.
        .i_cpsr_nxt                     (alu_cpsr_nxt),
        .i_cpsr_ff                      (alu_flags_ff),

        // Feedback
        .i_alu_value_nxt                (alu_alu_result_nxt),
        .i_alu_dav_nxt                  (alu_dav_nxt),

        // Switch indicator.
        .i_switch_ff                    (issue_switch_ff),
        .o_switch_ff                    (shifter_switch_ff),

        // Force32
        .i_force32align_ff              (issue_force32_ff),
        .o_force32align_ff              (shifter_force32_ff),

        // Outputs.
        
        .o_mem_srcdest_value_ff         (shifter_mem_srcdest_value_ff),
        .o_alu_source_value_ff          (shifter_alu_source_value_ff),
        .o_shifted_source_value_ff      (shifter_shifted_source_value_ff),
        .o_shift_carry_ff               (shifter_shift_carry_ff),

        .o_pc_plus_8_ff                 (shifter_pc_plus_8_ff),         

        .o_mem_srcdest_index_ff         (shifter_mem_srcdest_index_ff),
        .o_mem_load_ff                  (shifter_mem_load_ff),
        .o_mem_store_ff                 (shifter_mem_store_ff),
        .o_mem_pre_index_ff             (shifter_mem_pre_index_ff),
        .o_mem_unsigned_byte_enable_ff  (shifter_mem_unsigned_byte_enable_ff),
        .o_mem_signed_byte_enable_ff    (shifter_mem_signed_byte_enable_ff),
        .o_mem_signed_halfword_enable_ff(shifter_mem_signed_halfword_enable_ff),   
        .o_mem_unsigned_halfword_enable_ff(shifter_mem_unsigned_halfword_enable_ff),
        .o_mem_translate_ff             (shifter_mem_translate_ff),

        .o_condition_code_ff            (shifter_condition_code_ff),
        .o_destination_index_ff         (shifter_destination_index_ff),
        .o_alu_operation_ff             (shifter_alu_operation_ff),
        .o_flag_update_ff               (shifter_flag_update_ff),

        // Interrupts.
        .o_irq_ff                       (shifter_irq_ff), 
        .o_fiq_ff                       (shifter_fiq_ff), 
        .o_abt_ff                       (shifter_abt_ff), 
        .o_swi_ff                       (shifter_swi_ff),

        // Stall
        .o_stall_from_shifter           (stall_from_shifter)
);

// ===============
// ALU STAGE 
// ===============

zap_alu_main #(
        .PHY_REGS(PHY_REGS),
        .SHIFT_OPS(SHIFT_OPS),
        .ALU_OPS(ALU_OPS) 
)
u_zap_alu_main
(
        .i_decompile                    (shifter_decompile),
        .o_decompile                    (alu_decompile),

        .i_hijack                       ( wb_hijack     ),
        .i_hijack_op1                   ( wb_hijack_op1 ),
        .i_hijack_op2                   ( wb_hijack_op2 ),
        .i_hijack_cin                   ( wb_hijack_cin ),
        .o_hijack_sum                   ( alu_hijack_sum ),

        .i_taken_ff                     (shifter_taken_ff),
        .o_confirm_from_alu             (confirm_from_alu),

        .i_pc_ff                        (shifter_pc_ff),

        .i_und_ff                       (shifter_und_ff),
        .o_und_ff                       (alu_und_ff),

        .i_nozero_ff                    ( shifter_nozero_ff ),

         .i_clk                          (i_clk),
         .i_reset                        (reset),
         .i_clear_from_writeback         (clear_from_writeback),   
         .i_data_stall                   (data_stall), 
         .i_cpsr_nxt                     (cpsr_nxt), 
         .i_flag_update_ff               (shifter_flag_update_ff),
         .i_switch_ff                    (shifter_switch_ff),

         .i_force32align_ff              (shifter_force32_ff),

         .i_mem_srcdest_value_ff        (shifter_mem_srcdest_value_ff),
         .i_alu_source_value_ff         (shifter_alu_source_value_ff), 
         .i_shifted_source_value_ff     (shifter_shifted_source_value_ff),
         .i_shift_carry_ff              (shifter_shift_carry_ff),
         .i_pc_plus_8_ff                (shifter_pc_plus_8_ff),

         .i_abt_ff                      (shifter_abt_ff), 
         .i_irq_ff                      (shifter_irq_ff), 
         .i_fiq_ff                      (shifter_fiq_ff), 
         .i_swi_ff                      (shifter_swi_ff),

         .i_mem_srcdest_index_ff        (shifter_mem_srcdest_index_ff),     
         .i_mem_load_ff                 (shifter_mem_load_ff),                     
         .i_mem_store_ff                (shifter_mem_store_ff),                         
         .i_mem_pre_index_ff            (shifter_mem_pre_index_ff),                
         .i_mem_unsigned_byte_enable_ff (shifter_mem_unsigned_byte_enable_ff),     
         .i_mem_signed_byte_enable_ff   (shifter_mem_signed_byte_enable_ff),       
         .i_mem_signed_halfword_enable_ff(shifter_mem_signed_halfword_enable_ff),        
         .i_mem_unsigned_halfword_enable_ff(shifter_mem_unsigned_halfword_enable_ff),      
         .i_mem_translate_ff            (shifter_mem_translate_ff),  

         .i_condition_code_ff           (shifter_condition_code_ff),
         .i_destination_index_ff        (shifter_destination_index_ff),
         .i_alu_operation_ff            (shifter_alu_operation_ff),  // {OP,S}

         .i_data_mem_fault              (i_data_wb_err),

         .o_alu_result_nxt              (alu_alu_result_nxt),

         .o_alu_result_ff               (alu_alu_result_ff),

         .o_abt_ff                      (alu_abt_ff),
         .o_irq_ff                      (alu_irq_ff),
         .o_fiq_ff                      (alu_fiq_ff),
         .o_swi_ff                      (alu_swi_ff),

         .o_dav_ff                      (alu_dav_ff),
         .o_dav_nxt                     (alu_dav_nxt),

         .o_pc_plus_8_ff                (alu_pc_plus_8_ff),

         // Data access address. Ignore [1:0].
         .o_mem_address_ff              (alu_address_ff),    
         .o_clear_from_alu              (clear_from_alu),
         .o_pc_from_alu                 (pc_from_alu),
         .o_destination_index_ff        (alu_destination_index_ff),
         .o_flags_ff                    (alu_flags_ff),       // Output flags.
         .o_flags_nxt                   (alu_cpsr_nxt),

         .o_mem_srcdest_value_ff           (), 
         .o_mem_srcdest_index_ff           (alu_mem_srcdest_index_ff),     
         .o_mem_load_ff                    (alu_mem_load_ff),                     
         .o_mem_store_ff                   (), 

         .o_ben_ff                         (), 
 
         .o_mem_unsigned_byte_enable_ff    (alu_ubyte_ff),     
         .o_mem_signed_byte_enable_ff      (alu_sbyte_ff),       
         .o_mem_signed_halfword_enable_ff  (alu_shalf_ff),        
         .o_mem_unsigned_halfword_enable_ff(alu_uhalf_ff),      
         .o_mem_translate_ff               (o_mem_translate),
        
        .o_address_nxt ( alu_address_nxt ),

        .o_data_wb_we_nxt  (o_data_wb_we_nxt),
        .o_data_wb_cyc_nxt (o_data_wb_cyc_nxt),
        .o_data_wb_stb_nxt (o_data_wb_stb_nxt),
        .o_data_wb_dat_nxt (o_data_wb_dat_nxt),
        .o_data_wb_sel_nxt (o_data_wb_sel_nxt),

        .o_data_wb_we_ff   (o_data_wb_we),
        .o_data_wb_cyc_ff  (o_data_wb_cyc),
        .o_data_wb_stb_ff  (o_data_wb_stb),
        .o_data_wb_dat_ff  (o_data_wb_dat),
        .o_data_wb_sel_ff  (o_data_wb_sel)

);

// ====================
// MEMORY 
// ====================

zap_memory_main #(
       .PHY_REGS(PHY_REGS) 
)
u_zap_memory_main
(
        .i_decompile                    (alu_decompile),
        .o_decompile                    (memory_decompile),

        .i_und_ff                       (alu_und_ff),
        .o_und_ff                       (memory_und_ff),

        .i_mem_address_ff               (alu_address_ff),

        
        .i_clk                          (i_clk),                      
        .i_reset                        (reset),

        .i_sbyte_ff                     (alu_sbyte_ff),     // Signed byte.
        .i_ubyte_ff                     (alu_ubyte_ff),     // Unsigned byte.
        .i_shalf_ff                     (alu_shalf_ff),     // Signed half word.
        .i_uhalf_ff                     (alu_uhalf_ff),     // Unsigned half word.
        
        .i_clear_from_writeback         (clear_from_writeback),
        .i_data_stall                   (data_stall),
        .i_alu_result_ff                (alu_alu_result_ff),
        .i_flags_ff                     (alu_flags_ff), 
        
        .i_mem_load_ff                  (alu_mem_load_ff),

        .i_mem_rd_data                 (i_data_wb_dat),// From memory.

        .i_mem_fault                    (i_data_wb_err),      // From cache.

        .o_mem_fault                    (memory_data_abt_ff),         


        .i_dav_ff                       (alu_dav_ff),
        .i_pc_plus_8_ff                 (alu_pc_plus_8_ff),
         
        .i_destination_index_ff         (alu_destination_index_ff),
         
        .i_irq_ff                       (alu_irq_ff),
        .i_fiq_ff                       (alu_fiq_ff),
        .i_instr_abort_ff               (alu_abt_ff),
        .i_swi_ff                       (alu_swi_ff),
        
        // Used to speed up loads. 
        .i_mem_srcdest_index_ff         (alu_mem_srcdest_index_ff), 

        // Can come in handy since this is reused for several other things.
        .i_mem_srcdest_value_ff         (o_data_wb_dat),                        
 
        .o_alu_result_ff                (memory_alu_result_ff),
        .o_flags_ff                     (memory_flags_ff),         

        .o_destination_index_ff         (memory_destination_index_ff),
        .o_mem_srcdest_index_ff         (memory_mem_srcdest_index_ff),
 
        .o_dav_ff                       (memory_dav_ff),
        .o_pc_plus_8_ff                 (memory_pc_plus_8_ff),
         
        .o_irq_ff                       (memory_irq_ff),
        .o_fiq_ff                       (memory_fiq_ff),
        .o_swi_ff                       (memory_swi_ff),
        .o_instr_abort_ff               (memory_instr_abort_ff),
         
        .o_mem_load_ff                  (memory_mem_load_ff),


        .o_mem_rd_data                 (memory_mem_rd_data)
);

// ==================
// WRITEBACK 
// ==================

zap_writeback #(
        .PHY_REGS(PHY_REGS)
)
u_zap_writeback
(
        .i_decompile            (memory_decompile),
        .o_decompile            (rb_decompile),

        .o_shelve               (shelve),

        .i_clk                  (i_clk), // ZAP clock.


        .i_reset                (reset),           // ZAP reset.
        .i_valid                (memory_dav_ff),
        .i_data_stall           (data_stall),
        .i_clear_from_alu       (clear_from_alu),
        .i_pc_from_alu          (pc_from_alu),
        .i_stall_from_decode    (stall_from_decode),
        .i_stall_from_issue     (stall_from_issue),
        .i_stall_from_shifter   (stall_from_shifter),

        .i_thumb                (alu_flags_ff[T]), // To indicate thumb state.

        .i_clear_from_decode    (clear_from_decode),
        .i_pc_from_decode       (pc_from_decode),

        .i_code_stall           (code_stall),  

        // Used to valid writes on i_wr_index1.
        .i_mem_load_ff          (memory_mem_load_ff), 

        .i_rd_index_0           (rd_index_0), 
        .i_rd_index_1           (rd_index_1), 
        .i_rd_index_2           (rd_index_2), 
        .i_rd_index_3           (rd_index_3),

        .i_wr_index             (memory_destination_index_ff),
        .i_wr_data              (memory_alu_result_ff),
        .i_flags                (memory_flags_ff),
        .i_wr_index_1           (memory_mem_srcdest_index_ff),// load index.
        .i_wr_data_1            (memory_mem_rd_data),         // load data.

        .i_irq                  (memory_irq_ff),
        .i_fiq                  (memory_fiq_ff),
        .i_instr_abt            (memory_instr_abort_ff),
        .i_data_abt             (memory_data_abt_ff),
        .i_swi                  (memory_swi_ff),    
        .i_und                  (memory_und_ff),

        .i_pc_buf_ff            (memory_pc_plus_8_ff),

        .i_copro_reg_en         (copro_reg_en),
        .i_copro_reg_wr_index   (copro_reg_wr_index),
        .i_copro_reg_rd_index   (copro_reg_rd_index),
        .i_copro_reg_wr_data    (copro_reg_wr_data),

        .o_copro_reg_rd_data_ff (copro_reg_rd_data),
        
        .o_rd_data_0            (rd_data_0),         
        .o_rd_data_1            (rd_data_1),         
        .o_rd_data_2            (rd_data_2),         
        .o_rd_data_3            (rd_data_3),

        .o_pc                   (o_instr_wb_adr),
        .o_pc_nxt               (o_instr_wb_adr_nxt),
        .o_cpsr_nxt             (cpsr_nxt),
        .o_clear_from_writeback (clear_from_writeback),

        .o_hijack               (wb_hijack),
        .o_hijack_op1           (wb_hijack_op1),
        .o_hijack_op2           (wb_hijack_op2),
        .o_hijack_cin           (wb_hijack_cin),

        .i_hijack_sum           (alu_hijack_sum)
);

// ==================================
// CP15 CB
// ==================================

zap_cp15_cb u_zap_cp15_cb (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_cp_word              (copro_word),
        .i_cp_dav               (copro_dav),
        .o_cp_done              (copro_done),
        .i_cpsr                 (o_cpsr),
        .o_reg_en               (copro_reg_en),
        .o_reg_wr_data          (copro_reg_wr_data),
        .i_reg_rd_data          (copro_reg_rd_data),
        .o_reg_wr_index         (copro_reg_wr_index),
        .o_reg_rd_index         (copro_reg_rd_index),

        .i_fsr                  (i_fsr),
        .i_far                  (i_far),
        .o_dac                  (o_dac),
        .o_baddr                (o_baddr),
        .o_mmu_en               (o_mmu_en),
        .o_sr                   (o_sr),
        .o_dcache_inv           (o_dcache_inv),
        .o_icache_inv           (o_icache_inv),
        .o_dcache_clean         (o_dcache_clean),
        .o_icache_clean         (o_icache_clean),
        .o_dtlb_inv             (o_dtlb_inv),
        .o_itlb_inv             (o_itlb_inv),
        .o_dcache_en            (o_dcache_en),
        .o_icache_en            (o_icache_en),
        .i_dcache_inv_done      (i_dcache_inv_done),
        .i_icache_inv_done      (i_icache_inv_done),
        .i_dcache_clean_done    (i_dcache_clean_done),
        .i_icache_clean_done    (i_icache_clean_done)
);

reg [(8*8)-1:0] CPU_MODE; // Max 8 characters i.e. 64-bit string.

always @*
case(o_cpsr[`CPSR_MODE])
FIQ:     CPU_MODE = "FIQ"; 
IRQ:     CPU_MODE = "IRQ";
USR:     CPU_MODE = "USR";
UND:     CPU_MODE = "UND";
SVC:     CPU_MODE = "SVC";
ABT:     CPU_MODE = "ABT";
SYS:     CPU_MODE = "SYS";
default: CPU_MODE = "???";
endcase


endmodule // zap_core.v

`default_nettype wire
