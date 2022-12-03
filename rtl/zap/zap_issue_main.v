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
//  This stage converts register indices into actual values. Register indices
//  are also pumped forward to allow resolution in the shift stage. PC
//  references must be resolved here since the value gives PC + 8. Instructions
//  requiring shifts stall if the target registers are in the outputs of this
//  stage. We do not issue a multiply if the source is still in the output of this 
//  stage just like shifts. That's to ensure incorrect registers are not
//  read.
// ----------------------------------------------------------------------------

`default_nettype none

module zap_issue_main
#(
        // Parameters.

        // Number of physical registers.
        parameter PHY_REGS = 46,

        // Although ARM mentions only 16 ALU operations, the processor
        // internally performs many more operations.
        parameter ALU_OPS   = 32,

        // Number of supported shift operations.
        parameter SHIFT_OPS = 5
)
(
        // Decompile path
        input   wire    [64*8-1:0]              i_decompile,
        output  reg     [64*8-1:0]              o_decompile,

        // PC in
        input wire [31:0]                       i_pc_ff,
        output reg [31:0]                       o_pc_ff,

        // BP signals.
        input wire   [1:0]                      i_taken_ff,
        output reg   [1:0]                      o_taken_ff,

        // Clock and reset.
        input  wire                             i_clk,    // ZAP clock.
        input  wire                             i_reset, // Active high sync.

        // CPSR.
        input wire       [31:0]                 i_cpu_mode,

        // Clear and stall signals.
        input wire                              i_clear_from_writeback,
        input wire                              i_data_stall,          
        input wire                              i_clear_from_alu,
        input wire                              i_stall_from_shifter,

        // From decode
        input wire  [31:0]                      i_pc_plus_8_ff,

        // -----------------------------------
        // Inputs from decode.
        // Look at the decode stage for the 
        // meaning of these ports...
        // -----------------------------------        

        input wire      [3:0]                   i_condition_code_ff,
        
        input wire      [$clog2(PHY_REGS )-1:0] i_destination_index_ff,
        
        input wire      [32:0]                  i_alu_source_ff,
        input wire      [$clog2(ALU_OPS)-1:0]   i_alu_operation_ff,
        
        input wire      [32:0]                  i_shift_source_ff,
        input wire      [$clog2(SHIFT_OPS)-1:0] i_shift_operation_ff,
        input wire      [32:0]                  i_shift_length_ff,
        
        input wire                              i_flag_update_ff,
        
        input wire    [$clog2(PHY_REGS )-1:0]   i_mem_srcdest_index_ff,            
        input wire                              i_mem_load_ff,                     
        input wire                              i_mem_store_ff,                         
        input wire                              i_mem_pre_index_ff,                
        input wire                              i_mem_unsigned_byte_enable_ff,     
        input wire                              i_mem_signed_byte_enable_ff,       
        input wire                              i_mem_signed_halfword_enable_ff,        
        input wire                              i_mem_unsigned_halfword_enable_ff,      
        input wire                              i_mem_translate_ff,                     
		
        input wire                              i_irq_ff,                               
        input wire                              i_fiq_ff,                               
        input wire                              i_abt_ff,                               
        input wire                              i_swi_ff,                               

        // From register file. Read ports.
        input wire  [31:0]                      i_rd_data_0,
        input wire  [31:0]                      i_rd_data_1,
        input wire  [31:0]                      i_rd_data_2,
        input wire  [31:0]                      i_rd_data_3,

        // Force 32 bit address alignment.
        input wire                              i_force32align_ff,
        output reg                              o_force32align_ff,

        // For undefined instr.
        input wire                         i_und_ff,
        output reg                         o_und_ff,

        // ---------------------
        // Feedback Network
        // ---------------------

        //
        // Destination index feedback. Each stage is represented as
        // combinational logic followed by flops(FFs).
        //

        // The ALU never changes destination anyway. Destination from shifter.
        input wire  [$clog2(PHY_REGS )-1:0]     i_shifter_destination_index_ff,

        // Flopped destination from the ALU.
        input wire  [$clog2(PHY_REGS )-1:0]     i_alu_destination_index_ff,      

        // Flopped destination from the memory stage.
        input wire  [$clog2(PHY_REGS )-1:0]     i_memory_destination_index_ff, 

        //
        // Data valid(dav) for each stage in the pipeline. Used to validate the
        // pipeline vector when sniffing for register values yet to be written.
        //

        // Taken from alu_nxt instead of shifter_ff because ALU can invalidate
        // instructions.
        input wire                              i_alu_dav_nxt,            
        input wire                              i_alu_dav_ff,
        input wire                              i_memory_dav_ff,

        //
        // The actual thing we need (i.e. data), 
        // the value of stuff we are looking for.
        //

        // Taken from alu_nxt since ALU can change this.
        input wire  [31:0]                      i_alu_destination_value_nxt,    

        // ALU flopped result.
        input wire  [31:0]                      i_alu_destination_value_ff,      

        // Result in the memory stage of the pipeline.
        input wire  [31:0]                      i_memory_destination_value_ff,   

        //
        // For load-store locks and memory acceleration, we need srcdest
        // index. Memory loads can be accelerated with a direct load from
        // memory stage instead of register stage(WB).
        //
        input wire  [5:0]                       i_shifter_mem_srcdest_index_ff,
        input wire  [5:0]                       i_alu_mem_srcdest_index_ff,
        input wire  [5:0]                       i_memory_mem_srcdest_index_ff,
        input wire                              i_shifter_mem_load_ff,//1 if load.
        input wire                              i_alu_mem_load_ff,
        input wire                              i_memory_mem_load_ff,

        // Memory accelerator values for loads. External memory bys is
        // connected to this.
        input wire  [31:0]                      i_memory_mem_srcdest_value_ff,   

        // ARM to compressed switch.
        input wire i_switch_ff,
        output reg o_switch_ff,

        // Outputs to register file.
        output reg      [$clog2(PHY_REGS )-1:0] o_rd_index_0,
        output reg      [$clog2(PHY_REGS )-1:0] o_rd_index_1,
        output reg      [$clog2(PHY_REGS )-1:0] o_rd_index_2,
        output reg      [$clog2(PHY_REGS )-1:0] o_rd_index_3,

        // Outputs to shifter stage.
        output reg       [3:0]                   o_condition_code_ff,
        output reg       [$clog2(PHY_REGS )-1:0] o_destination_index_ff,
        output reg       [$clog2(ALU_OPS)-1:0]   o_alu_operation_ff,
        output reg       [$clog2(SHIFT_OPS)-1:0] o_shift_operation_ff,
        output reg                               o_flag_update_ff,

        // Memory operation related.        
        output reg     [$clog2(PHY_REGS )-1:0]   o_mem_srcdest_index_ff,            
        output reg                               o_mem_load_ff,                     
        output reg                               o_mem_store_ff,
        output reg                               o_mem_pre_index_ff,                
        output reg                               o_mem_unsigned_byte_enable_ff,     
        output reg                               o_mem_signed_byte_enable_ff,       
        output reg                               o_mem_signed_halfword_enable_ff,
        output reg                               o_mem_unsigned_halfword_enable_ff,
        output reg                               o_mem_translate_ff,                
        
        // Interrupts.
        output reg                               o_irq_ff,
        output reg                               o_fiq_ff,
        output reg                               o_abt_ff,
        output reg                               o_swi_ff,

        // Register values are given here.

        // ALU source value would be the value of non-shifted operand in ARM.
        output reg      [31:0]                  o_alu_source_value_ff,

        // Shifter source value would be the value of the operand to be shifted.
        output reg      [31:0]                  o_shift_source_value_ff,

        // Shift length i.e., amount to shift i.e, shamt.
        output reg      [31:0]                  o_shift_length_value_ff,

        // For stores, value to be stored.
        output reg      [31:0]                  o_mem_srcdest_value_ff, 

        //
        // Indices/Immeds go here. It might seem odd that we are sending index
        // values and register values (above). The issue stage selects
        // the appropriate value. Note again that while the above are values,
        // these are indexes/immediates.
        //
        output reg      [32:0]                  o_alu_source_ff,
        output reg      [32:0]                  o_shift_source_ff,

        // Stall everything before this if 1.
        output reg                              o_stall_from_issue,

        // The PC value.
        output reg     [31:0]                   o_pc_plus_8_ff,

        //
        // Shifter disable. In the next stage, the output
        // will bypass the shifter. Not actually bypass it but will
        // go to the ALU value corrector unit via a MUX essentially bypassing
        // the shifter.
        //
        output reg                              o_shifter_disable_ff
);

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

reg o_shifter_disable_nxt;

reg [31:0] o_alu_source_value_nxt, 
           o_shift_source_value_nxt, 
           o_shift_length_value_nxt, 
           o_mem_srcdest_value_nxt;

// Individual lock signals. These are ORed to get the final lock.
reg shift_lock;
reg load_lock;

                        
reg lock;               // Asserted when an instruction cannot be issued and 
                        // leads to all stages before it stalling.

always @*
        lock = shift_lock | load_lock;

task clear;
begin
        o_condition_code_ff               <= NV;
        o_irq_ff                          <= 0;         
        o_fiq_ff                          <= 0;         
        o_abt_ff                          <= 0;         
        o_swi_ff                          <= 0;
        o_und_ff                          <= 0;
        o_flag_update_ff                  <= 0;      
end
endtask

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
        else if ( lock )
        begin
                clear;
        end
        else
        begin
                o_condition_code_ff               <= i_condition_code_ff;
                o_destination_index_ff            <= i_destination_index_ff;
                o_alu_operation_ff                <= i_alu_operation_ff;
                o_shift_operation_ff              <= i_shift_operation_ff;
                o_flag_update_ff                  <= i_flag_update_ff;
                o_mem_srcdest_index_ff            <= i_mem_srcdest_index_ff;           
                o_mem_load_ff                     <= i_mem_load_ff;                    
                o_mem_store_ff                    <= i_mem_store_ff;                   
                o_mem_pre_index_ff                <= i_mem_pre_index_ff;               
                o_mem_unsigned_byte_enable_ff     <= i_mem_unsigned_byte_enable_ff;    
                o_mem_signed_byte_enable_ff       <= i_mem_signed_byte_enable_ff;      
                o_mem_signed_halfword_enable_ff   <= i_mem_signed_halfword_enable_ff;  
                o_mem_unsigned_halfword_enable_ff <= i_mem_unsigned_halfword_enable_ff;
                o_mem_translate_ff                <= i_mem_translate_ff;               
                o_irq_ff                          <= i_irq_ff;                         
                o_fiq_ff                          <= i_fiq_ff;                         
                o_abt_ff                          <= i_abt_ff;                         
                o_swi_ff                          <= i_swi_ff;   
                o_pc_plus_8_ff                    <= i_pc_plus_8_ff;
                o_shifter_disable_ff              <= o_shifter_disable_nxt;
                o_alu_source_ff                   <= i_alu_source_ff;
                o_shift_source_ff                 <= i_shift_source_ff;
                o_alu_source_value_ff             <= o_alu_source_value_nxt;
                o_shift_source_value_ff           <= o_shift_source_value_nxt;
                o_shift_length_value_ff           <= o_shift_length_value_nxt;
                o_mem_srcdest_value_ff            <= o_mem_srcdest_value_nxt;
                o_switch_ff                       <= i_switch_ff;
                o_force32align_ff                 <= i_force32align_ff;
                o_und_ff                          <= i_und_ff;
                o_taken_ff                        <= i_taken_ff;
                o_pc_ff                           <= i_pc_ff;
                
                // For debug
                o_decompile                       <= i_decompile;
        end
end

// Get values from the feedback network.
always @*
begin

        
        o_alu_source_value_nxt  = 
        get_register_value (    i_alu_source_ff, 
                                0, 
                                i_shifter_destination_index_ff, 
                                i_alu_dav_nxt, 
                                i_alu_destination_value_nxt, 
                                i_alu_destination_value_ff, 
                                i_alu_destination_index_ff, 
                                i_alu_dav_ff, 
                                i_memory_destination_index_ff, 
                                i_memory_dav_ff, 
                                i_memory_mem_srcdest_index_ff, 
                                i_memory_mem_load_ff, 
                                i_rd_data_0, 
                                i_rd_data_1, 
                                i_rd_data_2, 
                                i_rd_data_3, i_memory_mem_srcdest_value_ff, i_cpu_mode, i_pc_plus_8_ff 
        );
        
        
        o_shift_source_value_nxt= 
        get_register_value (    i_shift_source_ff,     
                                1,
                                i_shifter_destination_index_ff, 
                                i_alu_dav_nxt, 
                                i_alu_destination_value_nxt, 
                                i_alu_destination_value_ff,
                                i_alu_destination_index_ff, 
                                i_alu_dav_ff, 
                                i_memory_destination_index_ff, 
                                i_memory_dav_ff, 
                                i_memory_mem_srcdest_index_ff, 
                                i_memory_mem_load_ff,
                                i_rd_data_0, 
                                i_rd_data_1, 
                                i_rd_data_2, 
                                i_rd_data_3, i_memory_mem_srcdest_value_ff, i_cpu_mode, i_pc_plus_8_ff 
        );
        
        o_shift_length_value_nxt= 
        get_register_value (    i_shift_length_ff,     
                                2,
                                i_shifter_destination_index_ff, 
                                i_alu_dav_nxt, 
                                i_alu_destination_value_nxt, 
                                i_alu_destination_value_ff,
                                i_alu_destination_index_ff, 
                                i_alu_dav_ff, 
                                i_memory_destination_index_ff, 
                                i_memory_dav_ff, 
                                i_memory_mem_srcdest_index_ff, 
                                i_memory_mem_load_ff,
                                i_rd_data_0, 
                                i_rd_data_1, 
                                i_rd_data_2, 
                                i_rd_data_3, i_memory_mem_srcdest_value_ff, i_cpu_mode, i_pc_plus_8_ff 
        );
        
        // Value of a register index, never an immediate.
        o_mem_srcdest_value_nxt = 
        get_register_value (    i_mem_srcdest_index_ff,
                                3,
                                i_shifter_destination_index_ff, 
                                i_alu_dav_nxt, 
                                i_alu_destination_value_nxt, 
                                i_alu_destination_value_ff,
                                i_alu_destination_index_ff, 
                                i_alu_dav_ff, 
                                i_memory_destination_index_ff, 
                                i_memory_dav_ff, 
                                i_memory_mem_srcdest_index_ff, 
                                i_memory_mem_load_ff,
                                i_rd_data_0, 
                                i_rd_data_1, 
                                i_rd_data_2, 
                                i_rd_data_3, i_memory_mem_srcdest_value_ff, i_cpu_mode, i_pc_plus_8_ff    
        ); 

end


// Apply index to register file.
always @*
begin
        o_rd_index_0 = i_alu_source_ff;
        o_rd_index_1 = i_shift_source_ff; 
        o_rd_index_2 = i_shift_length_ff;
        o_rd_index_3 = i_mem_srcdest_index_ff;
end


//
// Straightforward read feedback function. Looks at all stages of the pipeline
// to extract the latest value of the register. 
// There is some complexity here to perform accelerated memory reads. 
//
function [31:0] get_register_value ( 

        // The register inex to search for. This might be a constant too.
        input [32:0]                    index,                                 

        // Register read port activated for this function.
        input [1:0]                     rd_port,                                

        // Destination on the output of the shifter stage.
        input [32:0]                    i_shifter_destination_index_ff,      

        // ALU output is valid.
        input                           i_alu_dav_nxt,     

        // ALU output.
        input [31:0]                    i_alu_destination_value_nxt,      

        // ALU flopped result.
        input [31:0]                    i_alu_destination_value_ff,   

        // ALU flopped destination index.
        input [$clog2(PHY_REGS)-1:0]    i_alu_destination_index_ff,             

        // Valid flopped (EX stage).
        input                           i_alu_dav_ff,                          

        // Memory stage destination index (pointer)
        input [$clog2(PHY_REGS)-1:0]    i_memory_destination_index_ff,   

        // Memory stage valid.
        input                           i_memory_dav_ff,                      

        // Memory stage srcdest index. The srcdest is basically the data
        // register index.
        input [$clog2(PHY_REGS)-1:0]    i_memory_mem_srcdest_index_ff,      

        // Memory load instruction in memory stage.    
        input                           i_memory_mem_load_ff,               

        // Data read from register file.
        input [31:0]                    i_rd_data_0, i_rd_data_1, i_rd_data_2, i_rd_data_3, 
                                        i_memory_mem_srcdest_value_ff, i_cpu_mode, i_pc_plus_8_ff
);

reg [31:0] get;

begin

`ifdef ISSUE_DEBUG
        $display($time, "Received index as %d and rd_port %d", index, rd_port);
`endif

        if   ( index[32] )                 // Catch constant here.
        begin
`ifdef ISSUE_DEBUG
                        $display($time, "Constant detect. Returning %x", index[31:0]);
`endif

                        get = index[31:0]; 
        end
        else if ( index == PHY_RAZ_REGISTER )   // Catch RAZ here.
        begin
               // Return 0. 
`ifdef ISSUE_DEBUG               
               $display($time, "RAZ returned 0...");
`endif
                get = 32'd0;
        end
        else if   ( index == ARCH_PC )  // Catch PC here. ARCH index = PHY index so no problem.
        begin
                 get = i_pc_plus_8_ff;
`ifdef ISSUE_DEBUG
                 $display($time, "PC requested... given as %x", get);
`endif
        end
        else if ( index == PHY_CPSR )   // Catch CPSR here.
        begin
                get = i_cpu_mode; 
        end

        // Match in ALU stage.
        else if   ( index == i_shifter_destination_index_ff && i_alu_dav_nxt  )                 
        begin   // ALU effectively never changes destination so no need to look at _nxt.
                        get =  i_alu_destination_value_nxt;         
`ifdef ISSUE_DEBUG
                        $display($time, "Matched shifter destination index %x ... given as %x", i_shifter_destination_index_ff, get);
`endif
        end

        // Match in output of ALU stage.
        else if   ( index == i_alu_destination_index_ff && i_alu_dav_ff       )                 
        begin
                        get =  i_alu_destination_value_ff;
`ifdef ISSUE_DEBUG
                        $display($time, "Matched ALU destination index %x ... given as %x", i_alu_destination_index_ff, get);
`endif
        end

        // Match in output of memory stage.
        else if   ( index == i_memory_destination_index_ff && i_memory_dav_ff )                
        begin 
                        get =  i_memory_destination_value_ff;
`ifdef ISSUE_DEBUG
                        $display($time, "Matched memory destination index %x ... given as %x", i_memory_destination_index_ff, get);
`endif
        end
        else    // Index not found in the pipeline, fallback to register access.                     
        begin                        
`ifdef ISSUE_DEBUG
                $display($time, "Register read on rd_port %x", rd_port );
`endif
                                  
                case ( rd_port )
                        0: get = i_rd_data_0;
                        1: get = i_rd_data_1;
                        2: get = i_rd_data_2;
                        3: get = i_rd_data_3;
                endcase
`ifdef ISSUE_DEBUG
                $display($time, "Reg read -> Returned value %x", get);
`endif
        end

        // The memory accelerator. If the required stuff is present in the memory unit, short circuit.
        if ( index == i_memory_mem_srcdest_index_ff && i_memory_mem_load_ff && i_memory_dav_ff )
        begin
`ifdef ISSUE_DEBUG
                $display($time, "Memory accelerator gets value %x", i_memory_mem_srcdest_value_ff);
`endif

                get = i_memory_mem_srcdest_value_ff;
        end

        get_register_value = get;
end
endfunction 


// Stall all previous stages if a lock occurs.
always @*
begin
        o_stall_from_issue = lock;
end


always @*
begin
        // Look for reads from registers to be loaded from memory. Four
        // register sources may cause a load lock.
        load_lock =     determine_load_lock 
                        ( i_alu_source_ff  , 
                        o_mem_srcdest_index_ff, 
                        o_condition_code_ff, 
                        o_mem_load_ff, 
                        i_shifter_mem_srcdest_index_ff, 
                        i_alu_dav_nxt, 
                        i_shifter_mem_load_ff, 
                        i_alu_mem_srcdest_index_ff, 
                        i_alu_dav_ff, 
                        i_alu_mem_load_ff ) 
                        || 
                        determine_load_lock 
                        ( 
                        i_shift_source_ff, 
                        o_mem_srcdest_index_ff, 
                        o_condition_code_ff, 
                        o_mem_load_ff, 
                        i_shifter_mem_srcdest_index_ff, 
                        i_alu_dav_nxt, 
                        i_shifter_mem_load_ff, 
                        i_alu_mem_srcdest_index_ff, 
                        i_alu_dav_ff, 
                        i_alu_mem_load_ff ) 
                        ||
                        determine_load_lock 
                        ( i_shift_length_ff, 
                        o_mem_srcdest_index_ff, 
                        o_condition_code_ff, 
                        o_mem_load_ff, 
                        i_shifter_mem_srcdest_index_ff, 
                        i_alu_dav_nxt, 
                        i_shifter_mem_load_ff, 
                        i_alu_mem_srcdest_index_ff, 
                        i_alu_dav_ff, 
                        i_alu_mem_load_ff )
                        ||
                        determine_load_lock
                        ( i_mem_srcdest_index_ff, 
                        o_mem_srcdest_index_ff, 
                        o_condition_code_ff, 
                        o_mem_load_ff, 
                        i_shifter_mem_srcdest_index_ff, 
                        i_alu_dav_nxt, 
                        i_shifter_mem_load_ff, 
                        i_alu_mem_srcdest_index_ff, 
                        i_alu_dav_ff, 
                        i_alu_mem_load_ff );

        // A shift lock occurs if the current instruction requires a shift amount as a register
        // other than LSL #0 or RORI if the operands are right on the output of this
        // stage because in that case we do not have the register value and thus
        // a shift lock.
        shift_lock =    (!(
                                i_shift_operation_ff    == LSL && 
                                i_shift_length_ff[31:0] == 32'd0 && 
                                i_shift_length_ff[32]   == IMMED_EN
                        )
                        && // If it is not LSL #0 AND...
                        !(
                                i_shift_operation_ff == RORI // The amount to rotate and rotate are self contained.
                        )
                        && // If it is not RORI AND...
                        (
                                // Stuff is locked.
                                shifter_lock_check ( i_shift_source_ff, o_destination_index_ff, o_condition_code_ff ) ||
                                shifter_lock_check ( i_shift_length_ff, o_destination_index_ff, o_condition_code_ff ) ||
                                shifter_lock_check ( i_alu_source_ff  , o_destination_index_ff, o_condition_code_ff )   
                        )) || 
                        (
                                // If it is a multiply and stuff is locked.
                                (i_alu_operation_ff == UMLALL || 
                                 i_alu_operation_ff == UMLALH || 
                                 i_alu_operation_ff == SMLALL || 
                                 i_alu_operation_ff == SMLALH) && 
                                (
                                        shifter_lock_check ( i_shift_source_ff, o_destination_index_ff, o_condition_code_ff ) ||
                                        shifter_lock_check ( i_shift_length_ff, o_destination_index_ff, o_condition_code_ff ) ||
                                        shifter_lock_check ( i_alu_source_ff  , o_destination_index_ff, o_condition_code_ff ) ||
                                        shifter_lock_check ( i_mem_srcdest_index_ff, o_destination_index_ff, o_condition_code_ff )  
                                )
                        ) // If it is multiply (MAC). 

                        ||
                        (       // If the instruction is not LSL #0 and previous instruction has flag
                                // updates, we stall.

                               !o_shifter_disable_nxt && 
                                o_flag_update_ff
                        );
end

always @*
begin
        // Shifter disable.
        o_shifter_disable_nxt = (       
                                        i_shift_operation_ff    == LSL && 
                                        i_shift_length_ff[31:0] == 32'd0 && 
                                        i_shift_length_ff[32]   == IMMED_EN
                                ); 
        // If it is LSL #0, we can disable the shifter.
end

// ----------------------------------------------------------------------------

// Shifter lock check.
function shifter_lock_check ( 
        input [32:0] index, 
        input [$clog2(PHY_REGS)-1:0] o_destination_index_ff,
        input [3:0] o_condition_code_ff
);
begin
        // Simply check if the operand index is on the output of this unit
        // and that the output is valid.
        if ( o_destination_index_ff == index && o_condition_code_ff != NV )
                shifter_lock_check = 1'd1;
        else
                shifter_lock_check = 1'd0;

        // If immediate, no lock obviously.
        if ( index[32] == IMMED_EN || index == PHY_RAZ_REGISTER )
                shifter_lock_check = 1'd0;
end        
endfunction

// ----------------------------------------------------------------------------

// Load lock. Activated when a read from a register follows a load to that
// register.
function determine_load_lock ( 
input [32:0]                    index,
input [$clog2(PHY_REGS)-1:0]    o_mem_srcdest_index_ff,
input [3:0]                     o_condition_code_ff,
input                           o_mem_load_ff,
input  [$clog2(PHY_REGS)-1:0]   i_shifter_mem_srcdest_index_ff,
input                           i_alu_dav_nxt,
input                           i_shifter_mem_load_ff,
input  [$clog2(PHY_REGS)-1:0]   i_alu_mem_srcdest_index_ff,
input                           i_alu_dav_ff,
input                           i_alu_mem_load_ff
);
begin
        determine_load_lock = 1'd0;

        // Look for that load instruction in the required pipeline stages. 
        // If found, we cannot issue the current instruction since old value 
        // will be read.
        if ( 
                ( index == o_mem_srcdest_index_ff          && 
                  o_condition_code_ff != NV                && 
                  o_mem_load_ff )                          ||
                ( index == i_shifter_mem_srcdest_index_ff  && 
                   i_alu_dav_nxt                           &&
                   i_shifter_mem_load_ff )                 ||
                (  index == i_alu_mem_srcdest_index_ff     && 
                   i_alu_dav_ff                            && 
                   i_alu_mem_load_ff )       
        )
                determine_load_lock = 1'd1;

        // Locks occur only for indices...
        if ( index[32] == IMMED_EN || index == PHY_RAZ_REGISTER )
                determine_load_lock = 1'd0;
end
endfunction

endmodule // zap_issue_main.v
`default_nettype wire
