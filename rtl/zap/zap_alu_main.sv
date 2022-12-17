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
// -- This is the main ZAP arithmetic and logic unit. Apart from shfits     --
// -- and multiplies, all other arithmetic and logic is performed here.     --
// -- Also data memory access signals are generated at the end of the clock --
// -- cycle.  Instructions that fail condition checks are invalidated here. --
// --                                                                       --
// ---------------------------------------------------------------------------



module zap_alu_main #(

        parameter [31:0] PHY_REGS  = 32'd46, // Number of physical registers.
        parameter [31:0] ALU_OPS   = 32'd32, // Number of arithmetic operations.
        parameter [31:0] FLAG_WDT  = 32'd32, // Width of active CPSR.
        parameter [31:0] CPSR_INIT = 32'd0   // Initial value of CPSR.
)
(
        // ------------------------------------------------------------------
        // Decompile Interface. Only for debug.
        // ------------------------------------------------------------------

        input logic      [64*8-1:0]              i_decompile,
        output logic      [64*8-1:0]             o_decompile,
        output logic                             o_decompile_valid,

        // ------------------------------------------------------------------
        // Clock and reset
        // ------------------------------------------------------------------

        input logic                              i_clk,                       // Clock.
        input logic                              i_reset,                     // sync active high reset.

        // -------------------------------------------------------------------
        // Clear and Stall signals.
        // -------------------------------------------------------------------

        input logic                              i_clear_from_writeback,      // Clear unit.
        input logic                              i_data_stall,                // DCACHE stall.

        // -------------------------------------------------------------------
        // Misc. signals
        // -------------------------------------------------------------------

        input logic  [31:0]                      i_cpsr_nxt,                  // From passive CPSR.
        input logic                              i_switch_ff,                 // Switch state.
        input logic   [1:0]                      i_taken_ff,                  // Branch prediction.
        input logic   [31:0]                     i_ppc_ff,                    // Predicted PC.
        input logic   [31:0]                     i_pc_ff,                     // Addr of instr.
        input logic                              i_nozero_ff,                 // Zero flag will not be set.

        // ------------------------------------------------------------------
        // Source values
        // ------------------------------------------------------------------

        input logic  [31:0]                      i_alu_source_value_ff,       // ALU source value.
        input logic  [31:0]                      i_shifted_source_value_ff,   // Shifted source value.
        input logic                              i_shift_carry_ff,            // Carry from shifter.        
        input logic                              i_shift_sat_ff,              // Saturation indication from shifter.
        input logic  [31:0]                      i_pc_plus_8_ff,              // PC + 8 value.

        // ------------------------------------------------------------------
        // Interrupt Tagging
        // ------------------------------------------------------------------

        input logic                              i_abt_ff,                    // ABT flagged.
        input logic                              i_irq_ff,                    // IRQ flagged.
        input logic                              i_fiq_ff,                    // FIQ flagged.
        input logic                              i_swi_ff,                    // SWI flagged.
        input logic                              i_und_ff,                    // Flagged undefined instructions.
        input logic                              i_data_mem_fault,            // Flagged Data abort.

        // ------------------------------------------------------------------
        // Memory Access Related
        // ------------------------------------------------------------------

        input logic  [31:0]                      i_mem_srcdest_value_ff,           // Value to store. 
        input logic  [$clog2   (PHY_REGS)-1:0]   i_mem_srcdest_index_ff,           // LD/ST Memory data register index.    
        input logic                              i_mem_load_ff,                    // LD/ST Memory load.
        input logic                              i_mem_store_ff,                   // LD/ST Memory store.                    
        input logic                              i_mem_pre_index_ff,               // LD/ST Pre/Post index.
        input logic                              i_mem_unsigned_byte_enable_ff,    // LD/ST uint8_t  data type.
        input logic                              i_mem_signed_byte_enable_ff,      // LD/ST int8_t   data type.
        input logic                              i_mem_signed_halfword_enable_ff,  // LD/ST int16_t data type.
        input logic                              i_mem_unsigned_halfword_enable_ff,// LD/ST uint16_t  data type.
        input logic                              i_mem_translate_ff,               // LD/ST Force user view of memory.
        input logic                              i_force32align_ff,                // Force address alignment to 32-bit.

        // -------------------------------------------------------------------
        // ALU controls
        // -------------------------------------------------------------------

        input logic  [3:0]                       i_condition_code_ff,            // CC associated with instr.
        input logic  [$clog2   (PHY_REGS)-1:0]   i_destination_index_ff,         // Target register index.
        input logic  [$clog2   (ALU_OPS)-1:0]    i_alu_operation_ff,             // Operation to perform.
        input logic                              i_flag_update_ff,               // Update flags if 1.

        // -----------------------------------------------------------------
        // ALU result
        // -----------------------------------------------------------------

        output logic [31:0]                       o_alu_result_nxt,           // For feedback. ALU result _nxt version.
        output logic [31:0]                       o_alu_result_ff,            // ALU result flopped version.
        output logic                              o_dav_ff,                   // Instruction valid.
        output logic                              o_dav_nxt,                  // Instruction valid _nxt version.
        output logic [FLAG_WDT-1:0]               o_flags_ff,                 // Output flags (CPSR).
        output logic [FLAG_WDT-1:0]               o_flags_nxt,                // CPSR next.
        output logic [$clog2   (PHY_REGS)-1:0]    o_destination_index_ff,     // Destination register index.

        // -----------------------------------------------------------------
        // Interrupt Tagging
        // -----------------------------------------------------------------

        output logic                              o_abt_ff,                   // Instruction abort flagged.
        output logic                              o_irq_ff,                   // IRQ flagged.
        output logic                              o_fiq_ff,                   // FIQ flagged.
        output logic                              o_swi_ff,                   // SWI flagged.
        output logic                              o_und_ff,                   // Flagged undefined instructions

        // -----------------------------------------------------------------
        // Jump Controls, BP Confirm, PC + 8
        // -----------------------------------------------------------------

        output logic [31:0]                       o_pc_plus_8_ff,             // Instr address + 8.
        output logic                              o_clear_from_alu,           // ALU commands a pipeline clear and a predictor correction.
        output logic [31:0]                       o_pc_from_alu,              // Corresponding address to go to is provided here.
        output logic                              o_confirm_from_alu,         // Tell branch predictor it was correct.
        output logic [1:0]                        o_taken_ff,

        // ----------------------------------------------------------------
        // Memory access related
        // ----------------------------------------------------------------

        output logic  [$clog2   (PHY_REGS)-1:0]   o_mem_srcdest_index_ff,                 // LD/ST data register.
        output logic                              o_mem_load_ff,                          // LD/ST load indicator.
        output logic [31:0]                       o_mem_address_ff,                       // LD/ST address to access.
        output logic                              o_mem_unsigned_byte_enable_ff,          // uint8_t
        output logic                              o_mem_signed_byte_enable_ff,            // int8_t
        output logic                              o_mem_signed_halfword_enable_ff,        // int16_t
        output logic                              o_mem_unsigned_halfword_enable_ff,      // uint16_t
        output logic                              o_mem_translate_ff,                     // LD/ST force user view of memory.

        // -------------------------------------------------------------
        // Wishbone signal outputs.
        // -------------------------------------------------------------

        output logic                              o_data_wb_we_ff,
        output logic                              o_data_wb_cyc_ff,
        output logic                              o_data_wb_stb_ff,
        output logic [31:0]                       o_data_wb_dat_ff,
        output logic [3:0]                        o_data_wb_sel_ff 
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

// ------------------------------------------------------------------------------
// Variables
// ------------------------------------------------------------------------------

// Memory srcdest value (i.e., data)
logic [31:0]                     mem_srcdest_value_nxt;

// Byte enable generator.
logic [3:0]                      ben_nxt;

// Address about to be output. Used to drive tag RAMs etc.
logic [31:0]                      mem_address_nxt;

/* 
   Sleep flop. When 1 unit sleeps i.e., does not produce any output except on
   the first clock cycle where LR is calculated using the ALU.
*/
logic                             sleep_ff, sleep_nxt;

/*
   CPSR (Active CPSR). The active CPSR is from the where the CPU flags are
   read out and the mode also is. Mode changes via manual writes to CPSR
   are first written to the active and they then propagate to the passive CPSR
   in the writeback stage. This reduces the pipeline flush penalty.
*/
logic [31:0]                      flags_ff, flags_nxt;

logic [31:0]                      rm, rn; // RM = shifted source value Rn for
                                        // non shifted source value. These are
                                        // values and not indices.


logic [5:0]                       clz_rm; // Count leading zeros in Rm.

// Destination index about to be output.
logic [$clog2   (PHY_REGS)-1:0]      o_destination_index_nxt;

// 1s complement of Rm and Rn.
logic [31:0] not_rm;
logic [31:0] not_rn;

// Wires which connect to an adder.
logic [31:0]                      op1;
logic [31:0]                      op2;
logic                             cin;

// 32-bit adder with carry input and carry output.
logic [32:0]                      sum;

logic [31:0]                      tmp_flags, tmp_sum;

// Opcode.
logic [$clog2   (ALU_OPS)-1:0]   opcode;

// Output regs NXT pins.
logic                            o_data_wb_we_nxt;
logic                            o_data_wb_cyc_nxt;
logic                            o_data_wb_stb_nxt;
logic [31:0]                     o_data_wb_dat_nxt;
logic [3:0]                      o_data_wb_sel_nxt;

// Clear
logic [1:0]                      w_clear_from_alu;
logic [31:0]                     w_pc_from_alu_0, w_pc_from_alu_1, w_pc_from_alu_2, w_pc_from_alu_3;
logic [1:0]                      r_clear_from_alu;
logic                            w_confirm_from_alu;

// Precompute adder
logic [31:0]                     quick_sum;

// Decompile valid.
logic                            o_decompile_valid_nxt;

// -------------------------------------------------------------------------------
// Assigns
// -------------------------------------------------------------------------------

always_comb opcode = i_alu_operation_ff;
always_comb not_rm = ~rm;
always_comb not_rn = ~rn;
always_comb quick_sum = rm + rn;

/*
   For memory stores, we must generate correct byte enables. This is done
   by examining access type inputs.Same for loads too.
   If there is neither a load or a store, the old value is preserved.
*/
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

// -------------------------------------------------------------------------------
// Adder
// -------------------------------------------------------------------------------

zap_adder u_zap_adder ( .a(op1), .b(op2), .c(cin), .sum(sum));

// -------------------------------------------------------------------------------
// CLZ logic.
// -------------------------------------------------------------------------------

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

// ----------------------------------------------------------------------------
// Aliases
// ----------------------------------------------------------------------------

always_comb
begin
        rm          = i_shifted_source_value_ff;
        rn          = i_alu_source_value_ff;
        o_flags_ff  = flags_ff;
        o_flags_nxt = flags_nxt;
end

// -----------------------------------------------------------------------------
// Sequential logic.
// -----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                // On reset, processor enters supervisory mode with interrupts
                // masked.
                reset;
                clear ( CPSR_INIT );
        end
        else if ( i_clear_from_writeback ) 
        begin
                // Clear but take CPSR from writeback.
                clear ( i_cpsr_nxt );
        end
        else if ( i_data_stall )
        begin
                // Preserve values.
        end
        else if ( i_data_mem_fault || sleep_ff )
        begin
                // Clear and preserve flags. Keep sleeping.
                clear ( flags_ff );
                sleep_ff                         <= 1'd1; 
                o_dav_ff                         <= 1'd0; // Don't give any output.
                o_decompile_valid                <= 1'd0;
        end
        else if ( o_clear_from_alu )
        begin
                clear ( flags_ff );
        end
        else
        begin
                // Clock out all flops normally.

                o_alu_result_ff                  <= o_alu_result_nxt;
                o_dav_ff                         <= o_dav_nxt;                
                o_pc_plus_8_ff                   <= i_pc_plus_8_ff;
                o_destination_index_ff           <= o_destination_index_nxt;
                flags_ff                         <= flags_nxt;
                o_abt_ff                         <= i_abt_ff;
                o_taken_ff                       <= i_taken_ff;
                o_irq_ff                         <= i_irq_ff;
                o_fiq_ff                         <= i_fiq_ff;
                o_swi_ff                         <= i_swi_ff;
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
                r_clear_from_alu                <= w_clear_from_alu;

                w_pc_from_alu_0                 <= i_ppc_ff;
                w_pc_from_alu_1                 <= sum[31:0];
                w_pc_from_alu_2                 <= tmp_sum;
                w_pc_from_alu_3                 <= i_pc_ff + (flags_ff[T] ? 32'd2 : 32'd4);

                o_confirm_from_alu              <= w_confirm_from_alu;

                o_decompile                     <= i_decompile;
                o_decompile_valid               <= o_decompile_valid_nxt;
        end
end

// Retime the output.
always_comb
begin
        case(r_clear_from_alu)
        2'd0   : o_pc_from_alu = w_pc_from_alu_0; 
        2'd1   : o_pc_from_alu = w_pc_from_alu_1;
        2'd2   : o_pc_from_alu = w_pc_from_alu_2;
        2'd3   : o_pc_from_alu = w_pc_from_alu_3;
        endcase
end

// ----------------------------------------------------------------------------

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
        else if ( i_data_stall ) 
        begin 
                // Save state.
        end
        else if ( i_data_mem_fault || sleep_ff ) 
        begin
                o_data_wb_cyc_nxt = 0;
                o_data_wb_stb_nxt = 0;
                o_data_wb_we_nxt  = 0;
        end
        else
        begin
                o_data_wb_cyc_nxt = o_dav_nxt ? i_mem_load_ff | i_mem_store_ff : 1'd0;
                o_data_wb_stb_nxt = o_dav_nxt ? i_mem_load_ff | i_mem_store_ff : 1'd0;
                o_data_wb_we_nxt  = o_dav_nxt ? i_mem_store_ff                 : 1'd0;
                o_data_wb_dat_nxt = mem_srcdest_value_nxt; 
                o_data_wb_sel_nxt = ben_nxt;
        end
end

// ----------------------------------------------------------------------------
// Used to generate access address.
// ----------------------------------------------------------------------------

always_comb
begin:pre_post_index_address_generator
        /* 
         * Memory address output based on pre or post index.
         * For post-index, update is done after memory access.
         * For pre-index, update is done before memory access.
         */
        if ( i_mem_pre_index_ff == 0 )  
                mem_address_nxt = rn;               // Postindex; 
        else                            
                mem_address_nxt = sum[31:0];        // Preindex.
        
        // If a force 32 align is set, make the lower 2 bits as zero.
        if ( i_force32align_ff )
                mem_address_nxt[1:0] = 2'b00;
end

// ---------------------------------------------------------------------------------
// Used to generate ALU result + Flags
// ---------------------------------------------------------------------------------

always_comb
begin: alu_result

        logic [$clog2 (ALU_OPS)-1:0] op;
        logic n,z,c,v;
        logic [31:0] exp_mask;

        op        = 0;
        {n,z,c,v} = 0;
        exp_mask  = 0;

        // Default value.
        tmp_flags = flags_ff;        

        // If it is a logical instruction.
        if (            opcode == {2'd0, AND}     || 
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
                        rn, rm, flags_ff[31:28], 
                        opcode, opcode == SAT_MOV ? 1'd0 : i_flag_update_ff, i_nozero_ff, 
                        i_shift_carry_ff 
                );

                // Set only Q flag from shift stage. Don't touch other Flags.
                if ( opcode == SAT_MOV )
                begin
                        tmp_flags      = flags_ff;
                        tmp_flags[27]  = tmp_flags[27] | i_shift_sat_ff; // Sticky.
                end
        end

        /*
         * Flag MOV(FMOV) i.e., MOV to CPSR and MMOV handler.
         * FMOV moves to CPSR and flushes the pipeline.
         * MMOV moves to SPSR and does not flush the pipeline.
         */
        else if ( opcode == {1'd0, FMOV} || opcode == {1'd0, MMOV} )
        begin: fmov_mmov
                // Read entire CPSR or SPSR.
                tmp_sum = opcode == {1'd0, FMOV} ? flags_ff : i_mem_srcdest_value_ff;

                // Generate a proper mask.
                exp_mask = {{8{rn[3]}},{8{rn[2]}},{8{rn[1]}},{8{rn[0]}}};

                // Change only specific bits as specified by the mask.
                for ( int i=0;i<32;i++ )
                begin
                        if ( exp_mask[i] )
                                tmp_sum[i] = rm[i];
                end

                /*
                 * FMOV moves to the CPSR in ALU and writeback. 
                 * No register is changed. The MSR out of this will have
                 * a target to CPSR.
                 */
                if ( opcode == {1'd0, FMOV} )
                begin
                        tmp_flags = tmp_sum;
                end
        end
        else
        begin: blk3
                op         = opcode;

                // Assign output of adder to flags after some minimal logic.
                c = sum[32];
                z = (sum[31:0] == 0);
                n = sum[31];

                // Overflow.
                if ( ( op == {2'd0, ADD}   || 
                       op == {2'd0, ADC}   || 
                       op == {1'd0, OP_QADD}  ||
                       op == {1'd0, OP_QDADD} ||
                       op == {2'd0, CMN} ) && (rn[31] == rm[31]) && (sum[31] != rn[31]) )
                begin
                        v = 1;
                end
                else if ( (op[$clog2(ALU_OPS)-1:0] == {2'd0, RSB} || 
                           op[$clog2(ALU_OPS)-1:0] == {2'd0, RSC}) && (rm[31] == !rn[31]) && (sum[31] != rm[31] ) )
                begin
                        v = 1;
                end
                else if ( (op == {2'd0, SUB}      || 
                           op == {2'd0, SBC}      || 
                           op == {1'd0, OP_QSUB}  ||
                           op == {1'd0, OP_QDSUB} ||
                           op == {2'd0, CMP}) && (rn[31] != rm[31]) && (sum[31] != rn[31]) ) // rn - rm
                begin
                        v = 1;
                end
                else
                begin
                        v = 0;
                end

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
                                tmp_flags[27] = (v || i_shift_sat_ff || tmp_flags[27]) ? 1'd1 : 1'd0; // Sticky.
                        else
                                tmp_flags[31:28] = {n,z,c,v};
                end

                // Write out the result.
                tmp_sum = op == {1'd0, CLZ} ? {26'd0, clz_rm} : sum[31:0]; 

                // Saturating operations.
                if ( op == {1'd0, OP_QADD } || 
                     op == {1'd0, OP_QSUB } || 
                     op == {1'd0, OP_QDADD} || 
                     op == {1'd0, OP_QDSUB} )
                begin        
                        if ( v ) // result saturated due to ALU operation.
                        begin
                                if ( op == {1'd0, OP_QADD} || op == {1'd0, OP_QDADD} )
                                begin
                                        // Find the direction of saturation.
                                        if ( rm[31] )
                                                tmp_sum = {1'd1, {31{1'd0}}};
                                        else
                                                tmp_sum = {1'd0, {31{1'd1}}};
                                end
                                else
                                begin
                                        // Use rn to determine saturation.
                                        if ( rn[31] )
                                                tmp_sum = {1'd1, {31{1'd0}}};
                                        else
                                                tmp_sum = {1'd0, {31{1'd1}}};
                                end
                        end
                end
        end

        // Drive nxt pin of result register.
        o_alu_result_nxt = tmp_sum;
end

// ----------------------------------------------------------------------------
// Flag propagation and branch prediction feedback unit
// ----------------------------------------------------------------------------

always_comb
begin: flags_bp_feedback

        w_clear_from_alu         = 2'd0;

        sleep_nxt                = sleep_ff;
        flags_nxt                = tmp_flags;
        o_destination_index_nxt  = i_destination_index_ff;
        w_confirm_from_alu       = 1'd0;

         // Check if condition is satisfied.
        o_dav_nxt = is_cc_satisfied ( i_condition_code_ff, flags_ff[31:28] );

        // Decompile valid. Valid condition code but unqualified.
        if ( i_condition_code_ff != NV && !o_dav_nxt )
                o_decompile_valid_nxt = 1'd1;
        else
                o_decompile_valid_nxt = 1'd0;

        if ( i_irq_ff || i_fiq_ff || i_abt_ff || i_swi_ff || i_und_ff ) 
        begin
                //
                // Any sign of an interrupt is present, put unit to sleep.
                // The current instruction will not be executed ultimately.
                // However o_dav_nxt = 1 since interrupt must be carried on.
                //
                o_dav_nxt = 1'd1;
                sleep_nxt = 1'd1;
        end
        else if ( (opcode == {1'd0, FMOV}) && o_dav_nxt ) // Writes to CPSR...
        begin
                w_clear_from_alu        = 2'd1; // Need to flush everything because we might end up fetching stuff in KERNEL instead of USER mode.

                // USR cannot change mode. Will silently fail.
                flags_nxt[`ZAP_CPSR_MODE]   = (flags_nxt[`ZAP_CPSR_MODE] == USR) ? USR : flags_nxt[`ZAP_CPSR_MODE]; // Security.
        end
        else if ( i_destination_index_ff == {2'd0, ARCH_PC} && (i_condition_code_ff != NV))
        begin
                if ( i_flag_update_ff && o_dav_nxt ) // PC update with S bit. Context restore. 
                begin
                        o_destination_index_nxt     = PHY_RAZ_REGISTER;
                        w_clear_from_alu            = 2'd2;

                        flags_nxt                   = i_mem_srcdest_value_ff;   
                        // Restore CPSR from SPSR.

                        flags_nxt[`ZAP_CPSR_MODE]   = (flags_nxt[`ZAP_CPSR_MODE] == USR) ? 
                        USR : flags_nxt[`ZAP_CPSR_MODE]; // Security.
                end
                else if ( o_dav_nxt ) // Branch taken and no flag update.
                begin
                        if ( i_taken_ff == SNT || i_taken_ff == WNT ) 
                        // Incorrectly predicted. Need to branch.
                        begin
                                // Quick branches - Flush everything before.
                                // Dumping ground since PC change is done. 
                                // Jump to branch target for fast switching.

                                o_destination_index_nxt = PHY_RAZ_REGISTER;
                                w_clear_from_alu        = 2'd2;

                                if ( i_switch_ff ) 
                                begin
                                        flags_nxt[T]            = tmp_sum[0];
                                end
                        end
                        else    // Correctly predicted as taken...
                        begin
                                // If thumb bit changes, flush everything before
                                if ( i_switch_ff && (tmp_sum[0] != flags_ff[T]) )
                                begin
                                        // Quick branches! PC goes to RAZ register since
                                        // change is done. Flush pipe before.

                                        o_destination_index_nxt = PHY_RAZ_REGISTER;                     
                                        w_clear_from_alu        = 2'd2;
                                        flags_nxt[T]            = tmp_sum[0];   
                                end
                                else
                                begin
                                        //
                                        // Check predicted PC based on opcode...
                                        // Two ways to branch:
                                        // First line is for B/BL/ADD.
                                        // Second line is for MOV PC, LR
                                        // ALU will only check these conditions.
                                        // i.e., MOV and ADD instructions which
                                        // destine to PC.
                                        //
                                        if ( opcode == {2'd0, ADD} ? (i_ppc_ff == quick_sum) : 
                                             opcode == {2'd0, MOV} ? (i_ppc_ff == rm) : 1'd0 )  
                                        begin
                                                // No mode change, do not change anything.

                                                o_destination_index_nxt = PHY_RAZ_REGISTER;
                                                w_clear_from_alu        = 2'd0;

                                                // Send confirmation message to branch predictor.

                                                // This DOES matter.
                                                w_confirm_from_alu = 1'd1; 
                                        end
                                        else // PC not predicted correctly. Go to correct vector.
                                        begin
                                                o_destination_index_nxt = PHY_RAZ_REGISTER;
                                                w_clear_from_alu        = 2'd2;
                                        end
                                end
                        end
                end
                else    // Branch not taken. CC failed.
                begin
                        //
                        // Wrong prediction as taken. Go back to the same
                        // branch. Non branches are always predicted as not-taken.
                        // Inform predictor of its mistake.
                        //
                        if ( i_taken_ff == WT || i_taken_ff == ST ) 
                        begin
                                // Go to the next instruction as this branch
                                // is NOT taken.
                                w_clear_from_alu = 2'd3;
                        end
                        else // Correct prediction. Branch is not taken.
                        begin
                                w_clear_from_alu = 2'd0;
                        end
                end
        end
        else if ( i_mem_srcdest_index_ff == {2'd0, ARCH_PC} && o_dav_nxt && i_mem_load_ff)
        begin
                // Loads to PC also puts the unit to sleep.
                sleep_nxt = 1'd1;
        end

        // If the current instruction is invalid, do not update flags.
        if ( o_dav_nxt == 1'd0 ) 
                flags_nxt = flags_ff;
end

// ----------------------------------------------------------------------------
// MUX structure on the inputs of the adder.
// ----------------------------------------------------------------------------

// These are adder connections. Data processing and FMOV use these.
always_comb
begin: adder_ip_mux
        logic [$clog2(ALU_OPS)-1:0] op;
        logic                       flag;

        flag       = flags_ff[C];
        op         = i_alu_operation_ff;

        case ( op )
        {1'd0, FMOV}:
        begin              
                op1 = i_pc_plus_8_ff    ; 
                op2 = ~32'd4            ; 
                cin = 1'd1              ;              
        end
        {2'd0, ADD}, 
        {1'd0, OP_QADD}, 
        {1'd0, OP_QDADD}: 
        begin         
                op1 = rn        ; 
                op2 = rm        ;   
                cin = 1'd0      ;              
        end
        {2'd0, ADC}: 
        begin              
                op1 = rn        ; 
                op2 = rm        ; 
                cin = flag      ;              
        end
        {2'd0, SUB}, 
        {1'd0, OP_QSUB}, 
        {1'd0, OP_QDSUB}: 
        begin         
                op1 = rn     ; 
                op2 = not_rm ; 
                cin =   1'd1 ;               
        end
        {2'd0, RSB}: 
        begin              
                op1 = rm     ; 
                op2 = not_rn ; 
                cin =   1'd1 ;                     
        end
        {2'd0, SBC}: 
        begin              
                op1 = rn     ; 
                op2 = not_rm ; 
                cin = !flag  ;              
        end
        {2'd0, RSC}: 
        begin              
                op1 = rm     ; 
                op2 = not_rn ; 
                cin = !flag  ;              
        end

        // Target is not written.
        {2'd0, CMP}: 
        begin
                op1 = rn  ;     
                op2 = not_rm ; 
                cin = 1'd1;               
        end 
        {2'd0, CMN}:    
        begin 
                op1 = rn  ; 
                op2 = rm  ; 
                cin = 1'd0;               
        end 

        // Default.
        default: 
        begin 
                op1 = 0; 
                op2 = 0; 
                cin = 0; 
        end
        endcase
end

// ----------------------------------------------------------------------------
// Functions
// ----------------------------------------------------------------------------

// Process logical instructions.
function [35:0] process_logical_instructions 
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
                rd = 0;
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
                        // This specifically states that we must NOT set the 
                        // ZERO flag under any circumstance. 
                        flags_out[_Z] = 1'd0;
                else
                        flags_out[_Z] = (rd == 0);

                flags_out[_N] = rd[31];
        end

        process_logical_instructions = {flags_out, rd};     
end
endfunction

/*
 * This task automatic clears out the flip-flops in this module.
 * The flag input is used to preserve/force flags to 
 * a specific state.
 */
task automatic clear ( input [31:0] flags );
begin
                o_decompile_valid                <= 1'd0;
                o_clear_from_alu                 <= 0;
                o_dav_ff                         <= 0;
                flags_ff                         <= flags;
                o_abt_ff                         <= 0;
                o_irq_ff                         <= 0;
                o_fiq_ff                         <= 0;
                o_swi_ff                         <= 0;
                o_und_ff                         <= 0;
                sleep_ff                         <= 0;
                o_mem_load_ff                    <= 0;
end
endtask

/*
 * The reason we use the duplicate function is to copy value over the memory
 * bus for memory stores. If we have a byte write to address 1, then the
 * memory controller basically takes address 0 and byte enable 0010 and writes
 * to address 1. This enables implementation of a 32-bit memory controller
 * with byte enables to control updates as is commonly done. Basically this
 * is to faciliate byte and halfword based writes on a 32-bit aligned memory
 * bus using byte enables. The rules are simple:
 * For a byte access - duplicate the lower byte of the register 4 times.
 * For halfword access - duplicate the lower 16-bit of the register twice.
 */

function [31:0] duplicate (     input ub, // Unsigned byte. 
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

/*
 *  Generate byte enables based on access mode.
 *  This function is similar in spirit to the previous one. The
 *  byte enables are generated in such a way that along with
 *  duplicate - byte and halfword accesses are possible.
 *  Rules -
 *  For a byte access, generate a byte enable with a 1 at the
 *  position that the lower 2-bits read (0,1,2,3).
 *  For a halfword access, based on lower 2-bits, if it is 00,
 *  make no change to byte enable (0011) else if it is 10, then
 *  make byte enable as (1100) which is basically the 32-bit
 *  address + 2 (and 3) which will be written. 
 */  
function [3:0] generate_ben (   input ub, // Unsigned byte. 
                                input sb, // Signed byte.
                                input uh, // Unsigned halfword.
                                input sh, // Signed halfword.
                                input [1:0] addr       );
logic [3:0] x;
begin
        if ( ub || sb ) // Byte oriented.
        begin
                case ( addr[1:0] ) // Based on address lower 2-bits.
                0: x = 1;
                1: x = 1 << 1;
                2: x = 1 << 2;
                3: x = 1 << 3;
                endcase
        end 
        else if ( uh || sh ) // Halfword. A word = 2 half words.
        begin
                case ( addr[1] )
                0: x = 4'b0011;
                1: x = 4'b1100;
                endcase
        end
        else
        begin
                x = 4'b1111; // Word oriented.
        end

        generate_ben = x;
end
endfunction // generate_ben

task automatic reset;
begin
                o_alu_result_ff                  <= 0; 
                o_dav_ff                         <= 0; 
                o_pc_plus_8_ff                   <= 0; 
                o_destination_index_ff           <= 0; 
                flags_ff                         <= 0; 
                o_abt_ff                         <= 0; 
                o_irq_ff                         <= 0; 
                o_fiq_ff                         <= 0; 
                o_swi_ff                         <= 0; 
                o_mem_srcdest_index_ff           <= 0; 
                o_mem_srcdest_index_ff           <= 0; 
                o_mem_load_ff                    <= 0; 
                o_mem_unsigned_byte_enable_ff    <= 0; 
                o_mem_signed_byte_enable_ff      <= 0; 
                o_mem_signed_halfword_enable_ff  <= 0; 
                o_mem_unsigned_halfword_enable_ff<= 0; 
                o_mem_translate_ff               <= 0; 
                w_pc_from_alu_0                  <= 0;
                w_pc_from_alu_1                  <= 0;
                w_pc_from_alu_2                  <= 0;
                w_pc_from_alu_3                  <= 0;
                o_decompile                      <= 0; 
                o_taken_ff                       <= 0;
                o_confirm_from_alu               <= 0;
end
endtask

endmodule // zap_alu_main.v



// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
