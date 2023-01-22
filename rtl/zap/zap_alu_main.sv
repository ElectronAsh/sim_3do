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
// This is the main ZAP arithmetic and logic unit. Apart from shfits
// and multiplies, all other arithmetic and logic is performed here.
// Also data memory access signals are generated at the end of the clock
// cycle.  Instructions that fail condition checks are invalidated here.
//

module zap_alu_main #(
        parameter logic [31:0] PHY_REGS  = 32'd46, // Number of physical registers.
        parameter logic [31:0] ALU_OPS   = 32'd32, // Number of arithmetic operations.
        parameter logic [31:0] FLAG_WDT  = 32'd32, // Width of active CPSR.
        parameter logic [31:0] CPSR_INIT = 32'd0   // Initial value of CPSR.
)
(
        // ------------------------------------------------------------------
        // Decompile Interface. Only for debug.
        // ------------------------------------------------------------------

        //
        // Decompile interface. Decompile valid is generated from here. It
        // is intended to be used to indicate those decompiles that did
        // not pass CC test.
        //
        input logic      [64*8-1:0]              i_decompile,
        output logic      [64*8-1:0]             o_decompile,
        output logic                             o_decompile_valid,

        // Last uop indication interface.
        input logic                              i_uop_last,
        output logic                             o_uop_last,

        // ------------------------------------------------------------------
        // Clock and reset
        // ------------------------------------------------------------------

        // Clock
        input logic                              i_clk,

        // Reset
        input logic                              i_reset,

        // -------------------------------------------------------------------
        // Clear and Stall signals.
        // -------------------------------------------------------------------

        // Unit is flushed from writeback.
        input logic                              i_clear_from_writeback,

        // Stall from data cache.
        input logic                              i_data_stall,

        // -------------------------------------------------------------------
        // Misc. signals
        // -------------------------------------------------------------------

        // CPU process ID for FCSE.
        input logic  [6:0]                       i_cpu_pid,

        //
        // CPSR from writeback. This is the passive CPSR. Assign to active
        // CPSR on clear from writeback.
        //
        input logic  [31:0]                      i_cpsr_nxt,

        // Switch A/T states based on bit 0 of the jump address.
        input logic                              i_switch_ff,

        // Branch state.
        input logic   [1:0]                      i_taken_ff,

        // Predicted PC from BTB.
        input logic   [31:0]                     i_ppc_ff,

        // Instruction address.
        input logic   [31:0]                     i_pc_ff,

        // When asserted, zero flag is not set.
        input logic                              i_nozero_ff,

        // ------------------------------------------------------------------
        // Operand Interface
        // ------------------------------------------------------------------

        // ALU source's value.
        input logic  [31:0]                      i_alu_source_value_ff,

        // Shifted source's value.
        input logic  [31:0]                      i_shifted_source_value_ff,

        // Carry from barrel shifter.
        input logic                              i_shift_carry_ff,

        // Saturation indication from barrel shifter.
        input logic                              i_shift_sat_ff,

        // PC with offet. Need not be +8, can be +4 too.
        input logic  [31:0]                      i_pc_plus_8_ff,

        // Conditional code
        input logic  [3:0]                       i_condition_code_ff,

        // Destination register index.
        input logic  [$clog2   (PHY_REGS)-1:0]   i_destination_index_ff,

        // ALU operation to perform.
        input logic  [$clog2   (ALU_OPS)-1:0]    i_alu_operation_ff,

        // Update flags if 1.
        input logic                              i_flag_update_ff,

        // ------------------------------------------------------------------
        // Interrupt Tagging
        // ------------------------------------------------------------------

        // Instruction abort tagged.
        input logic                              i_abt_ff,

        // IRQ tagged.
        input logic                              i_irq_ff,

        // FIQ tagged. Cannot have IRQ and FIQ at the same time.
        input logic                              i_fiq_ff,

        // SWI tagged. Cannot occur if IRQ/FIQ are present.
        input logic                              i_swi_ff,

        // Flagged undefined instructions.
        input logic                              i_und_ff,

        // Fault indication from DCache controller.
        input logic                              i_data_mem_fault,

        // Passed on from input.
        output logic                              o_abt_ff,
        output logic                              o_irq_ff,
        output logic                              o_fiq_ff,
        output logic                              o_und_ff,

        // Software interrupt tagged. CC is checked.
        output logic                              o_swi_ff,

        // ------------------------------------------------------------------
        // Memory Access Related
        // ------------------------------------------------------------------

        // Value to store to memory.
        input logic  [31:0]                      i_mem_srcdest_value_ff,

        // Data register index.
        input logic  [$clog2   (PHY_REGS)-1:0]   i_mem_srcdest_index_ff,

        // Indicates a memory load.
        input logic                              i_mem_load_ff,

        // Indicates a memory store.
        input logic                              i_mem_store_ff,

        // Preindex/Postindex_n
        input logic                              i_mem_pre_index_ff,

        // Memory transfer data types.
        input logic                              i_mem_unsigned_byte_enable_ff,
        input logic                              i_mem_signed_byte_enable_ff,
        input logic                              i_mem_signed_halfword_enable_ff,
        input logic                              i_mem_unsigned_halfword_enable_ff,

        // Force user view of memory.
        input logic                              i_mem_translate_ff,

        //
        // Force address to be 32-bit aligned before generating byte
        // enables.
        //
        input logic                              i_force32align_ff,

        // Load/Store data register index.
        output logic  [$clog2   (PHY_REGS)-1:0]   o_mem_srcdest_index_ff,

        // Memory load required.
        output logic                              o_mem_load_ff,

        // Memory access address. Need not be 32-bit aligned.
        output logic [31:0]                       o_mem_address_ff,

        // Memory access data types.
        output logic                              o_mem_unsigned_byte_enable_ff,
        output logic                              o_mem_signed_byte_enable_ff,
        output logic                              o_mem_signed_halfword_enable_ff,
        output logic                              o_mem_unsigned_halfword_enable_ff,

        //  Force user's view of memory.
        output logic                              o_mem_translate_ff,

        // -----------------------------------------------------------------
        // ALU result interface.
        // -----------------------------------------------------------------

        //
        // Note that these do not include CLZ/saturated values. That
        // comes on the alternate port, partially.
        //

        // Force align.
        output logic                              o_force32align_ff,

        // ALU next value to allow back-to-back execution.
        output logic [31:0]                       o_alu_result_nxt,

        // Flopped ALU result.
        output logic [31:0]                       o_alu_result_ff,

        // ALU stage output valid. CC success/interrupt tagged.
        output logic                              o_dav_ff,

        // Next version of the above to allow back-to-back execution.
        output logic                              o_dav_nxt,

        // Active CPSR out.
        output logic [FLAG_WDT-1:0]               o_flags_ff,

        //
        // Active CPSR next. For back-to-back execution. Doesn't go through
        // a lot of logic in the shifter (the module which consumes this).
        //
        output logic [FLAG_WDT-1:0]               o_flags_nxt,

        // Destination register index.
        output logic [$clog2   (PHY_REGS)-1:0]    o_destination_index_ff,

        // -----------------------------------------------------------------
        // Jump Controls, BP Confirm, PC + 8
        // -----------------------------------------------------------------

        // PC ahead value. Need not always be +8 - depends on A/T mode.
        output logic [31:0]                       o_pc_plus_8_ff,

        // ALU commands pipeline clear and a predictor correction.
        output logic                              o_clear_from_alu,

        // Corresponding address to go to is provided here.
        output logic [31:0]                       o_pc_from_alu,

        // Tell branch predictor it was correct.
        output logic                              o_confirm_from_alu,

        // Tells the current branch state.
        output logic [1:0]                        o_taken_ff,

        // ----------------------------------------------------------------
        // Standard Wishbone B3 signal outputs.
        // ----------------------------------------------------------------

        output logic                              o_data_wb_we_ff,

        // Driven together.
        output logic                              o_data_wb_cyc_ff,
        output logic                              o_data_wb_stb_ff,

        output logic [31:0]                       o_data_wb_dat_ff,
        output logic [3:0]                        o_data_wb_sel_ff,

        // ----------------------------------------------------------------
        // Alternate result
        // ----------------------------------------------------------------

        //
        // Either CLZ data is presented here on the sign bit of the
        // rm/rn registers.
        //
        output logic    [31:0]                    o_alt_result_ff,

        //
        // 0x0 - Take from alu_result.
        // 0x1 - CLZ output is presented on alt_result.
        // 0x2 - Potential overflow (Sign bit is present on LSB of alt_result).
        //       See o_flags_ff[27] for overflow.
        output logic    [1:0]                     o_alt_dav_ff
);

// ----------------------------------------------------------------------------
// Includes
// ----------------------------------------------------------------------------

`include "zap_defines.svh"
`include "zap_localparams.svh"
`include "zap_functions.svh"

// -----------------------------------------------------------------------------
// Localparams
// -----------------------------------------------------------------------------

// Local N,Z,C,V structures.
localparam [1:0] _N  = 2'd3;
localparam [1:0] _Z  = 2'd2;
localparam [1:0] _C  = 2'd1;

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

// Memory srcdest value (i.e., data)
logic [31:0]                     mem_srcdest_value_nxt;

// Byte enable generator.
logic [3:0]                      ben_nxt;

// Address about to be output. Used to drive tag RAMs etc.
logic [31:0]                      mem_address_nxt;

//
//  Sleep flop. When 1 unit sleeps i.e., does not produce any output except on
//  the first clock cycle where LR is calculated using the ALU.
//
logic                             sleep_ff, sleep_nxt;

//
// CPSR (Active CPSR). The active CPSR is from the where the CPU flags are
// read out and the mode also is. Mode changes via manual writes to CPSR
// are first written to the active and they then propagate to the passive CPSR
// in the writeback stage. This reduces the pipeline flush penalty.
//
logic [31:0]                      flags_ff, flags_nxt;

//
// RM = shifted source value Rn for non shifted source value. These are
// values and not indices.
//
logic [31:0]                      rm, rn;

// clz_rm = CLZ (rm)
logic [5:0]                       clz_rm;

// Destination index about to be output.
logic [$clog2   (PHY_REGS)-1:0]      o_destination_index_nxt;

// Wires which connect to an adder.
logic [31:0]                      op1;
logic [31:0]                      op2;
logic                             cin;

// 32-bit adder with carry input and carry output.
logic [32:0]                      sum;

logic [31:0]                      tmp_flags, tmp_sum, tmp_sum_x;
logic [1:0]                       valid_x;

// Opcode.
logic [$clog2   (ALU_OPS)-1:0]   opcode;

// Output regs NXT pins.
logic                            o_data_wb_we_nxt;
logic                            o_data_wb_cyc_nxt;
logic                            o_data_wb_stb_nxt;
logic [31:0]                     o_data_wb_dat_nxt;
logic [3:0]                      o_data_wb_sel_nxt;

// Clear
enum logic [1:0] {
        CONTINUE,
        BRANCH_TARGET,
        NEXT_INSTR_RESYNC
} w_clear_from_alu;

// PCs
logic [31:0]                     w_pc_from_alu_btarget;
logic [31:0]                     w_pc_from_alu_resync;

// BP controls.
logic [1:0]                      r_clear_from_alu;
logic                            w_confirm_from_alu;

// Precompute adder
logic [31:0]                     quick_sum;
logic [31:0]                     quick_diff;

// Decompile valid.
logic                            o_decompile_valid_nxt;
logic                            o_uop_last_nxt;

// Misc.
logic                            arith_overflow;
logic                            load_to_pc;
logic                            branch_instruction;

// ----------------------------------------------------------------------------
// Aliases
// ----------------------------------------------------------------------------

assign opcode       = i_alu_operation_ff;
assign quick_sum    = rn + rm;
assign quick_diff   = rn - rm;
assign  rm          = i_shifted_source_value_ff;
assign  rn          = i_alu_source_value_ff;
assign  o_flags_ff  = flags_ff;
assign  o_flags_nxt = o_dav_nxt ? flags_nxt : flags_ff;

// ----------------------------------------------------------------------------
// Memory byte enable/duplicate calculation.
// ----------------------------------------------------------------------------

//
// For memory stores, we must generate correct byte enables. This is done
// by examining access type inputs.Same for loads too.
// If there is neither a load or a store, the old value is preserved.
//
always_comb ben_nxt =                generate_ben (
                                                 i_mem_unsigned_byte_enable_ff,
                                                 i_mem_signed_byte_enable_ff,
                                                 i_mem_unsigned_halfword_enable_ff,
                                                 i_mem_unsigned_halfword_enable_ff,
                                                 mem_address_nxt[1:0]);

always_comb mem_srcdest_value_nxt =  duplicate (
                                                 i_mem_unsigned_byte_enable_ff,
                                                 i_mem_signed_byte_enable_ff,
                                                 i_mem_unsigned_halfword_enable_ff,
                                                 i_mem_unsigned_halfword_enable_ff,
                                                 i_mem_srcdest_value_ff );

// ----------------------------------------------------------------------------
// MUX structure on the inputs of the adder.
// ----------------------------------------------------------------------------

assign {op1, op2, cin}
        = i_alu_operation_ff == {2'd0, ADD}     ? {rn,  rm, 1'd0}
        : i_alu_operation_ff == {1'd0, OP_QADD} ? {rn,  rm, 1'd0}
        : i_alu_operation_ff == {1'd0, OP_QDADD}? {rn,  rm, 1'd0}
        : i_alu_operation_ff == {2'd0, CMN}     ? {rn,  rm, 1'd0}
        : i_alu_operation_ff == {2'd0, ADC}     ? {rn,  rm, flags_ff[C]}

        : i_alu_operation_ff == {2'd0, SUB}     ? {rn, ~rm, 1'd1}
        : i_alu_operation_ff == {1'd0, OP_QSUB} ? {rn, ~rm, 1'd1}
        : i_alu_operation_ff == {1'd0, OP_QDSUB}? {rn, ~rm, 1'd1}
        : i_alu_operation_ff == {2'd0, CMP}     ? {rn, ~rm, 1'd1}
        : i_alu_operation_ff == {2'd0, SBC}     ? {rn, ~rm, flags_ff[C]}

        : i_alu_operation_ff == {2'd0, RSB}     ? {rm, ~rn, 1'd1}
        : i_alu_operation_ff == {2'd0, RSC}     ? {rm, ~rn, flags_ff[C]}

        : '0;

// ----------------------------------------------------------------------------
// Adder
// ----------------------------------------------------------------------------

assign sum[32:0] = {1'd0, op1} + {1'd0, op2} + {32'd0, cin};

//
// Overflow is true is both operands are of the same sign but the sum isn't of
// the same sign.
//
assign arith_overflow = (op1[31] == op2[31]) & (op1[31] != sum[31]);

// ----------------------------------------------------------------------------
// CLZ logic.
// ----------------------------------------------------------------------------

always_comb // CLZ implementation.
begin
        casez(rm)
        32'b1???????????????????????????????:   clz_rm = 6'd00;
        32'b01??????????????????????????????:   clz_rm = 6'd01;
        32'b001?????????????????????????????:   clz_rm = 6'd02;
        32'b0001????????????????????????????:   clz_rm = 6'd03;
        32'b00001???????????????????????????:   clz_rm = 6'd04;
        32'b000001??????????????????????????:   clz_rm = 6'd05;
        32'b0000001?????????????????????????:   clz_rm = 6'd06;
        32'b00000001????????????????????????:   clz_rm = 6'd07;
        32'b000000001???????????????????????:   clz_rm = 6'd08;
        32'b0000000001??????????????????????:   clz_rm = 6'd09;
        32'b00000000001?????????????????????:   clz_rm = 6'd10;
        32'b000000000001????????????????????:   clz_rm = 6'd11;
        32'b0000000000001???????????????????:   clz_rm = 6'd12;
        32'b00000000000001??????????????????:   clz_rm = 6'd13;
        32'b000000000000001?????????????????:   clz_rm = 6'd14;
        32'b0000000000000001????????????????:   clz_rm = 6'd15;
        32'b00000000000000001???????????????:   clz_rm = 6'd16;
        32'b000000000000000001??????????????:   clz_rm = 6'd17;
        32'b0000000000000000001?????????????:   clz_rm = 6'd18;
        32'b00000000000000000001????????????:   clz_rm = 6'd19;
        32'b000000000000000000001???????????:   clz_rm = 6'd20;
        32'b0000000000000000000001??????????:   clz_rm = 6'd21;
        32'b00000000000000000000001?????????:   clz_rm = 6'd22;
        32'b000000000000000000000001????????:   clz_rm = 6'd23;
        32'b0000000000000000000000001???????:   clz_rm = 6'd24;
        32'b00000000000000000000000001??????:   clz_rm = 6'd25;
        32'b000000000000000000000000001?????:   clz_rm = 6'd26;
        32'b0000000000000000000000000001????:   clz_rm = 6'd27;
        32'b00000000000000000000000000001???:   clz_rm = 6'd28;
        32'b000000000000000000000000000001??:   clz_rm = 6'd29;
        32'b0000000000000000000000000000001?:   clz_rm = 6'd30;
        32'b00000000000000000000000000000001:   clz_rm = 6'd31;
        default:                                clz_rm = 6'd32; // All zeros.
        endcase
end

// -----------------------------------------------------------------------------
// Sequential logic.
// -----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                o_decompile_valid                <= 1'd0;
                o_uop_last                       <= 1'd0;
                o_clear_from_alu                 <= 0;
                o_dav_ff                         <= 0;
                o_alt_dav_ff                     <= 0;
                flags_ff                         <= CPSR_INIT;
                o_abt_ff                         <= 0;
                o_irq_ff                         <= 0;
                o_fiq_ff                         <= 0;
                o_swi_ff                         <= 0;
                o_und_ff                         <= 0;
                sleep_ff                         <= 0;
                o_mem_load_ff                    <= 0;
                o_force32align_ff                <= 0;

                o_alt_result_ff                  <= 'x; //
                o_alu_result_ff                  <= 'x; //
                o_pc_plus_8_ff                   <= 'x; //
                o_destination_index_ff           <= 'x; //
                o_mem_srcdest_index_ff           <= 'x; //
                o_mem_srcdest_index_ff           <= 'x; //
                o_mem_unsigned_byte_enable_ff    <= 'x; //
                o_mem_signed_byte_enable_ff      <= 'x; //
                o_mem_signed_halfword_enable_ff  <= 'x; //
                o_mem_unsigned_halfword_enable_ff<= 'x; //
                o_mem_translate_ff               <= 'x; //
                w_pc_from_alu_btarget            <= 'x; //
                w_pc_from_alu_resync             <= 'x; //
                o_decompile                      <= 'x; //
                o_taken_ff                       <= 'x; //
                o_confirm_from_alu               <= 'x; //
        end
        else if ( i_clear_from_writeback )
        begin
                // Clear but take CPSR from writeback.
                o_decompile_valid                <= 1'd0;
                o_uop_last                       <= 1'd0;
                o_clear_from_alu                 <= 0;
                o_dav_ff                         <= 0;
                o_alt_dav_ff                     <= 0;
                flags_ff                         <= i_cpsr_nxt;
                o_abt_ff                         <= 0;
                o_irq_ff                         <= 0;
                o_fiq_ff                         <= 0;
                o_swi_ff                         <= 0;
                o_und_ff                         <= 0;
                sleep_ff                         <= 0;
                o_mem_load_ff                    <= 0;
                o_force32align_ff                <= 0;

                o_alt_result_ff                  <= 'x; //
                o_alu_result_ff                  <= 'x; //
                o_pc_plus_8_ff                   <= 'x; //
                o_destination_index_ff           <= 'x; //
                o_mem_srcdest_index_ff           <= 'x; //
                o_mem_srcdest_index_ff           <= 'x; //
                o_mem_unsigned_byte_enable_ff    <= 'x; //
                o_mem_signed_byte_enable_ff      <= 'x; //
                o_mem_signed_halfword_enable_ff  <= 'x; //
                o_mem_unsigned_halfword_enable_ff<= 'x; //
                o_mem_translate_ff               <= 'x; //
                w_pc_from_alu_btarget            <= 'x; //
                w_pc_from_alu_resync             <= 'x; //
                o_decompile                      <= 'x; //
                o_taken_ff                       <= 'x; //
                o_confirm_from_alu               <= 'x; //
        end
        else if ( (i_data_mem_fault || sleep_ff) && !i_data_stall )
        begin
                // Clear and preserve flags. Keep sleeping.
                o_decompile_valid                <= 1'd0;
                o_uop_last                       <= 1'd0;
                o_clear_from_alu                 <= 0;
                o_dav_ff                         <= 0;
                o_alt_dav_ff                     <= 0;
                o_abt_ff                         <= 0;
                o_irq_ff                         <= 0;
                o_fiq_ff                         <= 0;
                o_swi_ff                         <= 0;
                o_und_ff                         <= 0;
                sleep_ff                         <= 1'd1;
                o_mem_load_ff                    <= 0;
                o_force32align_ff                <= 0;
        end
        else if ( o_clear_from_alu && !i_data_stall )
        begin
                // Clear and preserve flags. Wake up from sleep.
                o_decompile_valid                <= 1'd0;
                o_uop_last                       <= 1'd0;
                o_clear_from_alu                 <= 0;
                o_dav_ff                         <= 0;
                o_alt_dav_ff                     <= 0;
                o_abt_ff                         <= 0;
                o_irq_ff                         <= 0;
                o_fiq_ff                         <= 0;
                o_swi_ff                         <= 0;
                o_und_ff                         <= 0;
                sleep_ff                         <= 0;
                o_mem_load_ff                    <= 0;
                o_force32align_ff                <= 0;
        end
        else if ( !i_data_stall )
        begin
                // Clock out all flops normally.

                o_force32align_ff                <= i_force32align_ff;
                o_alu_result_ff                  <= o_alu_result_nxt;

                // Alternate result.
                o_alt_result_ff                  <= tmp_sum_x;
                o_alt_dav_ff                     <= valid_x;

                o_dav_ff                         <= o_dav_nxt;
                o_pc_plus_8_ff                   <= i_pc_plus_8_ff;
                o_destination_index_ff           <= o_destination_index_nxt;
                flags_ff                         <= o_flags_nxt;
                o_abt_ff                         <= i_abt_ff;
                o_taken_ff                       <= i_taken_ff;
                o_irq_ff                         <= i_irq_ff;
                o_fiq_ff                         <= i_fiq_ff;
                o_swi_ff                         <= i_swi_ff && o_dav_nxt;
                o_mem_srcdest_index_ff           <= i_mem_srcdest_index_ff;
                o_mem_srcdest_index_ff           <= i_mem_srcdest_index_ff;

                // Load or store must come up only if an actual LDR/STR is
                // detected.
                o_mem_load_ff                    <= o_dav_nxt ? i_mem_load_ff : 1'd0;

                o_mem_unsigned_byte_enable_ff    <= i_mem_unsigned_byte_enable_ff;
                o_mem_signed_byte_enable_ff      <= i_mem_signed_byte_enable_ff;
                o_mem_signed_halfword_enable_ff  <= i_mem_signed_halfword_enable_ff;
                o_mem_unsigned_halfword_enable_ff<= i_mem_unsigned_halfword_enable_ff;
                o_mem_translate_ff               <= i_mem_translate_ff;
                sleep_ff                         <= sleep_nxt;
                o_und_ff                         <= i_und_ff;

                o_clear_from_alu                <= |w_clear_from_alu;
                r_clear_from_alu                <=  w_clear_from_alu;

                w_pc_from_alu_btarget           <= tmp_sum;
                w_pc_from_alu_resync            <= i_pc_ff + (flags_ff[T] ? 32'd2 : 32'd4);

                o_confirm_from_alu              <= w_confirm_from_alu;

                o_decompile                     <= i_decompile;
                o_decompile_valid               <= o_decompile_valid_nxt;
                o_uop_last                      <= o_uop_last_nxt;
        end
end

// Retime the output.
always_comb
begin
        case ( r_clear_from_alu )
        BRANCH_TARGET     : o_pc_from_alu = w_pc_from_alu_btarget;
        NEXT_INSTR_RESYNC : o_pc_from_alu = w_pc_from_alu_resync;
        default:            o_pc_from_alu = 'dx; // Synthesis will OPTIMIZE.
                                                 // OK to do for FPGA synthesis.
        endcase
end

always_ff @ ( posedge i_clk ) // Wishbone flops.
begin
        if ( i_reset )
        begin
                // Wishbone updates.
                o_data_wb_cyc_ff                <= 1'd0;
                o_data_wb_stb_ff                <= 1'd0;
                o_data_wb_we_ff                 <= '0;
                o_data_wb_dat_ff                <= '0;
                o_data_wb_sel_ff                <= '0;
                o_mem_address_ff                <= '0;
        end
        else
        begin
                // Wishbone updates.
                o_data_wb_cyc_ff                <= o_data_wb_cyc_nxt;
                o_data_wb_stb_ff                <= o_data_wb_stb_nxt;
                o_data_wb_we_ff                 <= o_data_wb_we_nxt;
                o_data_wb_dat_ff                <= o_data_wb_dat_nxt;
                o_data_wb_sel_ff                <= o_data_wb_sel_nxt;

                // Hold WB address on stall. This is the flop.
                if ( !i_data_stall )
                begin
                        o_mem_address_ff  <= mem_address_nxt;
                end
        end
end

// -----------------------------------------------------------------------------
// WB next state logic.
// -----------------------------------------------------------------------------

always_comb
begin
        // Preserve values.
        o_data_wb_cyc_nxt = o_data_wb_cyc_ff;
        o_data_wb_stb_nxt = o_data_wb_stb_ff;
        o_data_wb_we_nxt  = o_data_wb_we_ff;
        o_data_wb_dat_nxt = o_data_wb_dat_ff;
        o_data_wb_sel_nxt = o_data_wb_sel_ff;

        if ( i_clear_from_writeback )
        begin
                o_data_wb_cyc_nxt = 0;
                o_data_wb_stb_nxt = 0;
        end
        else if
        (
                (~i_data_stall) &
                (i_data_mem_fault | sleep_ff | o_clear_from_alu )
        )
        begin
                o_data_wb_cyc_nxt = 0;
                o_data_wb_stb_nxt = 0;
                o_data_wb_we_nxt  = 0;
        end
        else if ( !i_data_stall )
        begin
                o_data_wb_cyc_nxt = o_dav_nxt & (i_mem_load_ff | i_mem_store_ff);
                o_data_wb_stb_nxt = o_dav_nxt & (i_mem_load_ff | i_mem_store_ff);
                o_data_wb_we_nxt  = o_dav_nxt & i_mem_store_ff;
                o_data_wb_dat_nxt = mem_srcdest_value_nxt;
                o_data_wb_sel_nxt = ben_nxt;
        end
end

// ----------------------------------------------------------------------------
// Used to generate access address.
// ----------------------------------------------------------------------------

always_comb
begin:pre_post_index_address_generator
        //
        // Memory address output based on pre or post index.
        // For post-index, update is done after memory access.
        // For pre-index, update is done before memory access.
        //
        if ( i_mem_pre_index_ff == 0 )
        begin
                mem_address_nxt = rn;               // Postindex;
        end
        else if ( i_alu_operation_ff == {2'd0, ADD} )
        begin
                mem_address_nxt = quick_sum[31:0];        // Preindex.
        end
        else if ( i_alu_operation_ff == {2'd0, SUB} )
        begin
                mem_address_nxt = quick_diff[31:0];
        end
        else
        begin
                mem_address_nxt = 'x;
        end

        // FCSE.
        if ( mem_address_nxt[31:25] == 0 )
        begin
                mem_address_nxt[31:25] = i_cpu_pid;
        end
end

// -----------------------------------------------------------------------------
// Used to generate ALU result + Flags
// ----------------------------------------------------------------------------

always_comb
begin: alu_result

        logic [$clog2 (ALU_OPS)-1:0] op;
        logic n,z,c,v;
        logic [31:0] exp_mask;

        // Default values.
        op        = 0;
        {n,z,c,v} = 0;
        exp_mask  = 0;
        tmp_flags = flags_ff;

        // If it is a logical instruction.
        if
        (
                opcode == {2'd0, AND}     ||
                opcode == {2'd0, EOR}     ||
                opcode == {2'd0, MOV}     ||
                opcode == {  SAT_MOV}     ||
                opcode == {2'd0, MVN}     ||
                opcode == {2'd0, BIC}     ||
                opcode == {2'd0, ORR}     ||
                opcode == {2'd0, TST}     ||
                opcode == {2'd0, TEQ}
        )
        begin
                // Call the logical processing function.
                {tmp_flags[31:28], tmp_sum} = process_logical_instructions (
                        rn,
                        rm,
                        flags_ff[31:28],
                        opcode, opcode == SAT_MOV ? 1'd0 : i_flag_update_ff,
                        i_nozero_ff,
                        i_shift_carry_ff
                );

                //
                // If SAT_MOV = 0x1
                // Set only Q flag from shift stage. Don't touch other Flags.
                //
                if ( opcode == SAT_MOV )
                begin
                        tmp_flags      = flags_ff;
                        tmp_flags[27]  = tmp_flags[27] | i_shift_sat_ff; // Sticky.
                end
        end

        //
        // Flag MOV(FMOV) i.e., MOV to CPSR and MMOV handler.
        // FMOV moves to CPSR and flushes the pipeline.
        // MMOV moves to SPSR and does not flush the pipeline. (MSR to SPSR)
        //
        else if ( opcode == {1'd0, FMOV} || opcode == {1'd0, MMOV} )
        begin
                exp_mask  =  {{8{rn[3]}},{8{rn[2]}},{8{rn[1]}},{8{rn[0]}}};
                tmp_sum   =  {32{1'dx}};

                for(int i=0;i<32;i++)
                begin
                        case ( opcode )
                        {1'd0, FMOV}: tmp_flags[i] = exp_mask[i] ? rm[i] : flags_ff[i];
                        {1'd0, MMOV}: tmp_sum[i]   = exp_mask[i] ? rm[i] : i_mem_srcdest_value_ff[i];
                        default     : {tmp_flags, tmp_sum} = {64{1'dx}}; // Never happens !
                        endcase
                end
        end
        else if ( opcode == FADD )
        begin
                tmp_sum = flags_ff;
        end
        else
        begin
                op         = opcode;

                // Assign output of adder to flags after some minimal logic.
                c = sum[32];
                z = (sum[31:0] == 0);
                n = sum[31];
                v = arith_overflow;

                //
                // If you choose not to update flags, do not change the flags.
                // Otherwise, they will contain their newly computed values.
                //
                if ( i_flag_update_ff )
                begin
                        if ( op == {1'd0, OP_QADD } ||
                             op == {1'd0, OP_QSUB } ||
                             op == {1'd0, OP_QDADD} ||
                             op == {1'd0, OP_QDSUB})
                        begin
                                tmp_flags[27] = (v || i_shift_sat_ff ||
                                                 tmp_flags[27]) ? 1'd1 : 1'd0;
                        end
                        else
                        begin
                                tmp_flags[31:28] = {n,z,c,v};
                        end
                end

                tmp_sum = sum[31:0];
        end

        o_alu_result_nxt = tmp_sum;
end

//
// Partially handle CLZ and saturating operations.
//
always_comb
begin
        valid_x   = 2'd0;
        tmp_sum_x = '0;

        if ( opcode == {1'd0, CLZ} )
        begin
                tmp_sum_x = {26'd0, clz_rm};
                valid_x   = 2'd1;
        end
        else if
        (
             opcode == {1'd0, OP_QADD } ||
             opcode == {1'd0, OP_QSUB } ||
             opcode == {1'd0, OP_QDADD} ||
             opcode == {1'd0, OP_QDSUB}
        )
        begin
                valid_x   = 2'd2;
                tmp_sum_x =  opcode == {1'd0, OP_QADD } ||
                             opcode == {1'd0, OP_QDADD} ?
                             {31'd0, rm[31]} : {31'd0, rn[31]};
        end
end

// ----------------------------------------------------------------------------
// Flag propagation and branch prediction feedback unit
// ----------------------------------------------------------------------------

assign load_to_pc = i_mem_srcdest_index_ff == {2'd0, ARCH_PC} &&
                    o_dav_nxt                                 &&
                    i_mem_load_ff;

assign  o_dav_nxt  = is_cc_satisfied ( i_condition_code_ff, flags_ff[31:28] )
                     || i_irq_ff || i_fiq_ff || i_abt_ff || i_und_ff;

assign  sleep_nxt  =    i_irq_ff   ||
                        i_fiq_ff   ||
                        i_abt_ff   ||
                        i_und_ff   ||
                        load_to_pc ||
                        (i_swi_ff && o_dav_nxt);

// Debug
always_comb
begin
        // Decompile valid. Valid condition code but unqualified.
        if ( i_condition_code_ff != NV && !o_dav_nxt )
        begin
                o_decompile_valid_nxt = 1'd1;
                o_uop_last_nxt        = i_uop_last;
        end
        else
        begin
                o_decompile_valid_nxt = 1'd0;
                o_uop_last_nxt        = o_dav_nxt ? i_uop_last : 1'd0;
        end
end

// Assertion.
always @ ( posedge i_clk )
begin
        if ( opcode == {1'd0, MMOV} && o_dav_nxt && !i_reset )
        begin
                assert ( flags_ff[ZAP_CPSR_MODE:0] != USR &&
                         flags_ff[ZAP_CPSR_MODE:0] != SYS ) else
                $info(2, "Warning: Writing to SPSR in USR/SYS in UNDEFINED.");

                assert ( flags_ff[T] == o_flags_nxt[T] ) else
                $info(2, "Warning: Changing T bit using MSR in UNDEFINED.");
        end

        if ( opcode == {1'd0, FMOV} && o_dav_nxt && !i_reset )
        begin
                if ( flags_ff[ZAP_CPSR_MODE:0] == USR )
                begin
                        assert ( tmp_flags[7:0] == flags_ff[7:0] ) else
                        $info("Info: USR attempting to change 23:0 of CPSR. Blocked.");
                end
        end
        else if ( i_destination_index_ff == {2'd0, ARCH_PC} &&
                  i_condition_code_ff != NV && !i_reset && i_flag_update_ff )
        begin
                assert (~(flags_ff[ZAP_CPSR_MODE:0] == USR || flags_ff[ZAP_CPSR_MODE:0] == SYS))
                else $info("Warning: Attempting to read SPSR in USR/SYS mode for context restore.");
        end
end

assign branch_instruction = i_destination_index_ff == {2'd0, ARCH_PC} &&
                           (i_condition_code_ff != NV);

always_comb
begin: flags_bp_feedback

        w_clear_from_alu         = CONTINUE;
        flags_nxt                = tmp_flags;
        o_destination_index_nxt  = i_destination_index_ff;
        w_confirm_from_alu       = 1'd0;

        if ( (opcode == {1'd0, FMOV}) && o_dav_nxt ) // Writes to CPSR...
        begin
                // Write destination to NULL.
                o_destination_index_nxt = PHY_RAZ_REGISTER;

                // If 7:0 is touched, RESYNC pipeline.
                if ( flags_ff[7:0] != flags_nxt[7:0] )
                begin
                        w_clear_from_alu        = NEXT_INSTR_RESYNC;
                end
                else
                begin
                        w_clear_from_alu        = CONTINUE;
                end

                // USR cannot change 7:0 of CPSR. Will silently fail.
                flags_nxt[7:0]   =
                (
                        flags_ff[ZAP_CPSR_MODE:0] == USR
                ) ?
                flags_ff [7:0] :
                flags_nxt[7:0] ; // Security.
        end
        else if ( branch_instruction )
        begin: branch_block
                o_destination_index_nxt = PHY_RAZ_REGISTER;

                if ( i_flag_update_ff && o_dav_nxt )
                // PC update with S bit. Context restore.
                begin
                        w_clear_from_alu            = BRANCH_TARGET;

                        // Restore CPSR from SPSR if not in USR/SYS mode.

                        if ( flags_ff[ZAP_CPSR_MODE:0] == USR ||
                             flags_ff[ZAP_CPSR_MODE:0] == SYS )
                        begin
                                flags_nxt = flags_ff;
                        end
                        else
                        begin
                                flags_nxt = i_mem_srcdest_value_ff;
                        end
                end
                else if ( o_dav_nxt ) // Branch taken and no flag update.
                begin
                        // A/T mode switch. Resync anyway.
                        if ( i_switch_ff && flags_nxt[T] != tmp_sum[0] )
                        begin
                                w_clear_from_alu = BRANCH_TARGET;
                                flags_nxt[T]     = tmp_sum[0];
                        end
                        // Incorrectly predicted. Need to branch.
                        else if ( i_taken_ff == SNT || i_taken_ff == WNT )
                        begin
                                w_clear_from_alu        = BRANCH_TARGET;
                        end
                        //
                        // Correctly predicted as taken. Check predicted PC based
                        // on opcode.  Two ways to branch: First line is for B/BL/ADD.
                        // Second line is for MOV PC, LR ALU will only check
                        // these conditions. i.e., MOV and ADD instructions
                        // which destine to PC.
                        //
                        else if
                        (
                                // Check branch target address.
                                opcode == {2'd0, ADD} ? (i_ppc_ff == quick_sum):
                                opcode == {2'd0, MOV} ? (i_ppc_ff == rm) : 1'd0
                        )
                        begin // Everything's good.
                                w_clear_from_alu        = CONTINUE;
                        end
                        else // PC not predicted correctly. Go to correct vector.
                        begin
                                w_clear_from_alu        = BRANCH_TARGET;
                        end
                end
                else
                // Branch not taken. CC failed.
                begin
                        w_clear_from_alu =
                        // Predicted taken
                        ( i_taken_ff == WT || i_taken_ff == ST ) ?
                         NEXT_INSTR_RESYNC : // Resync to next instruction.
                         CONTINUE;           // Keep going.
                end

                w_confirm_from_alu = ( w_clear_from_alu == CONTINUE );

        end: branch_block
end

// ----------------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------------

// Process logical instructions.
function automatic [35:0] process_logical_instructions
(
                input [31:0]                    RN,
                input [31:0]                    RM,
                input [3:0]                     flags,
                input [$clog2   (ALU_OPS)-1:0]  op,
                input                           flag_upd,
                input                           nozero,
                input                           shift_carry
);
begin: blk2
        logic [31:0] rd;
        logic [3:0] flags_out;

        // Avoid accidental latch inference.
        rd        = 0;
        flags_out = 0;

        case(op)
        {2'd0, AND}: rd = RN &   RM;
        {2'd0, EOR}: rd = RN ^   RM;
        {2'd0, BIC}: rd = RN & ~(RM);
        {2'd0, MOV}: rd =        RM;
            SAT_MOV: rd =        RM;
        {2'd0, MVN}: rd =      ~(RM);
        {2'd0, ORR}: rd = RN |   RM;
        {2'd0, TST}: rd = RN &   RM; // Target is not written.
        {2'd0, TEQ}: rd = RN ^   RM; // Target is not written.
        default:
        begin
                rd = 'x;
        end
        endcase

        // Suppose flags are not going to change at ALL.
        flags_out = flags;

        // Assign values to the flags only if an update is requested. Note that V
        // is not touched even if change is requested.
        if ( flag_upd ) // 0x0 for SAT_MOV.
        begin
                // V is preserved since flags_out = flags

                flags_out[_C] = shift_carry;

                if ( nozero )
                begin
                        // This specifically states that we must NOT set the
                        // ZERO flag under any circumstance.
                        flags_out[_Z] = 1'd0;
                end
                else
                begin
                        flags_out[_Z] = (rd == 0);
                end

                flags_out[_N] = rd[31];
        end

        process_logical_instructions = {flags_out, rd};
end
endfunction

//
// The reason we use the duplicate function is to copy value over the memory
// bus for memory stores. If we have a byte write to address 1, then the
// memory controller basically takes address 0 and byte enable 0010 and writes
// to address 1. This enables implementation of a 32-bit memory controller
// with byte enables to control updates as is commonly done. Basically this
// is to faciliate byte and halfword based writes on a 32-bit aligned memory
// bus using byte enables. The rules are simple:
// For a byte access - duplicate the lower byte of the register 4 times.
// For halfword access - duplicate the lower 16-bit of the register twice.
//

function automatic [31:0] duplicate (
                                input ub, // Unsigned byte.
                                input sb, // Signed byte.
                                input uh, // Unsigned halfword.
                                input sh, // Signed halfword.
                                input [31:0] val        );
logic [31:0] x;
begin
        if ( ub || sb)
        begin
                // Byte.
                x = {val[7:0], val[7:0], val[7:0], val[7:0]};
        end
        else if (uh || sh)
        begin
                // Halfword.
                x = {val[15:0], val[15:0]};
        end
        else
        begin
                x = val;
        end

        duplicate = x;
end
endfunction

//
// Generate byte enables based on access mode.
// This function is similar in spirit to the previous one. The
// byte enables are generated in such a way that along with
// duplicate - byte and halfword accesses are possible.
// Rules -
// For a byte access, generate a byte enable with a 1 at the
// position that the lower 2-bits read (0,1,2,3).
// For a halfword access, based on lower 2-bits, if it is 00,
// make no change to byte enable (0011) else if it is 10, then
// make byte enable as (1100) which is basically the 32-bit
// address + 2 (and 3) which will be written.
//
function automatic [3:0] generate_ben (
                                input ub, // Unsigned byte.
                                input sb, // Signed byte.
                                input uh, // Unsigned halfword.
                                input sh, // Signed halfword.
                                input [1:0] addr       );
logic [3:0] x;
begin
        if ( ub || sb ) // Byte oriented.
        begin
                case ( addr[1:0] ) // Based on address lower 2-bits.
                2'd0: x = 4'b0001;
                2'd1: x = 4'b0010;
                2'd2: x = 4'b0100;
                2'd3: x = 4'b1000;
             default: x = 'x;
                endcase
        end
        else if ( uh || sh ) // Halfword. A word = 2 half words.
        begin
                case ( addr[1] )
                1'd0: x = 4'b0011;
                1'd1: x = 4'b1100;
            default : x = 'x;
                endcase
        end
        else
        begin
                x = 4'b1111; // Word oriented.
        end

        generate_ben = x;
end
endfunction // generate_ben

endmodule

// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
