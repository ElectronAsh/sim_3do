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
// -- This module performs core ARM instruction decoding by translating ARM   --
// -- instructions into an internal long format that can be processed by core --
// -- logic. Note that the predecode stage must change the 32-bit instr. to   --
// -- 36-bit before feeding it into this unit.                                --
// --                                                                         --
// -----------------------------------------------------------------------------




module zap_decode (

i_irq,  // IRQ request from previous stage.
i_fiq,  // FIQ request from previous stage.
i_abt,  // Code abort flagged from previous stage.

// Instruction input from pre-decode.
i_instruction,
i_instruction_valid,

//
// CPU mode from active CPSR. Required to prevent CPSR change on MSR 
// instruction in USR mode.
//
i_cpsr_ff_mode,

//
// Bits related to decoded instruction...
// 

o_condition_code,       // 4-bit CC.
o_destination_index,    // Destination register.
o_alu_source,           // ALU source register.
o_alu_operation,        // ALU operation to be performed.
o_shift_source,         // Register to be treated as input to shifter.
o_shift_operation,      // Shift operation to perform.
o_shift_length,         // Length of the shift operation.
o_flag_update,          // 1 means flags must be updated.

// Memory related.
o_mem_srcdest_index,            // Data register.
o_mem_load,                     // Load operation.
o_mem_store,                    // Store operation.
o_mem_pre_index,                // Pre-Index.
o_mem_unsigned_byte_enable,     // Access treated as uint8_t.
o_mem_signed_byte_enable,       // Access treated as int8_t.
o_mem_signed_halfword_enable,   // Access treated as int16_t.
o_mem_unsigned_halfword_enable, // Access treated as uint16_t.
o_mem_translate,                // Force user view of memory.

o_und,   // Declare as undecodable. 
o_switch // Switch between ARM and Thumb may be needed if this is 1.

);

// ----------------------------------------------------------------------------

        // Number of architectural registers.
        parameter ARCH_REGS = 32;

        // Number of opcodes.
        parameter ALU_OPS   = 32;

        // Number of shift operations.
        parameter SHIFT_OPS = 6;


                // I/O Ports.
                input   logic                             i_irq, i_fiq, i_abt;
                input    logic   [35:0]                   i_instruction;          
                input    logic                            i_instruction_valid;
                input   logic    [4:0]                    i_cpsr_ff_mode; 
                output   logic    [3:0]                   o_condition_code;
                output   logic    [$clog2(ARCH_REGS)-1:0] o_destination_index;
                output   logic    [32:0]                  o_alu_source;
                output   logic    [$clog2(ALU_OPS)-1:0]   o_alu_operation;
                output   logic    [32:0]                  o_shift_source;
                output   logic    [$clog2(SHIFT_OPS)-1:0] o_shift_operation;
                output   logic    [32:0]                  o_shift_length;
                output  logic                             o_flag_update;
                output  logic   [$clog2(ARCH_REGS)-1:0]   o_mem_srcdest_index;
                output  logic                             o_mem_load;      
                output  logic                             o_mem_store;
                output  logic                             o_mem_pre_index;   
                output  logic                             o_mem_unsigned_byte_enable;
                output  logic                             o_mem_signed_byte_enable;       
                output  logic                             o_mem_signed_halfword_enable;
                output  logic                             o_mem_unsigned_halfword_enable;
                output  logic                             o_mem_translate;   
                output  logic                             o_und;
                output  logic                             o_switch;

// ----------------------------------------------------------------------------

`include "zap_defines.svh"
`include "zap_localparams.svh"

// Related to memory operations.
localparam [1:0] SIGNED_BYTE            = 2'd0;
localparam [1:0] UNSIGNED_HALF_WORD     = 2'd1;
localparam [1:0] SIGNED_HALF_WORD       = 2'd2;

// Global variables.
logic [35:0] instruction;

always_comb
begin: mainBlk1
        instruction                     = i_instruction;

        // If an unrecognized instruction enters this, the output
        // signals an NV state i.e., invalid.
        o_condition_code                = NV;
        o_destination_index             = RAZ_REGISTER;
        o_alu_operation                 = 0;
        o_shift_operation               = 0;
        o_alu_source                    = 0;
        o_shift_source                  = 0;
        o_shift_length                  = 0;
        o_alu_source[32]                = IMMED_EN;
        o_shift_source[32]              = IMMED_EN;
        o_shift_length[32]              = IMMED_EN;
        o_flag_update                   = 0;
        o_mem_srcdest_index             = RAZ_REGISTER;
        o_mem_load                      = 0;
        o_mem_store                     = 0;
        o_mem_translate                 = 0;
        o_mem_pre_index                 = 0;
        o_mem_unsigned_byte_enable      = 0;
        o_mem_signed_byte_enable        = 0;
        o_mem_signed_halfword_enable    = 0;
        o_mem_unsigned_halfword_enable  = 0;
        o_mem_translate                 = 0;
        o_und                           = 0;
        o_switch                        = 0;

        // Based on our pattern match, call the appropriate task
        if ( i_fiq || i_irq || i_abt )
        begin
                // Generate LR = PC - 4.
                o_condition_code    = AL;
                o_alu_operation     = {2'd0, SUB};
                o_alu_source        = {29'd0, ARCH_PC};
                o_alu_source[32]    = INDEX_EN; 
                o_destination_index = {1'd0, ARCH_LR};
                o_shift_source      = 4;
                o_shift_source[32]  = IMMED_EN;
                o_shift_operation   = {1'd0, LSL};
                o_shift_length      = 0;
                o_shift_length[32]  = IMMED_EN;
        end
        else if ( i_instruction_valid )
        begin
                casez ( i_instruction[31:0] )

                PLD:                         
                begin
                        // Generate a NOP i.e., R0 = R0 & R0.
                        o_condition_code    = AL;
                        o_alu_operation     = {2'd0, AND};
                        o_alu_source        = 0;
                        o_alu_source[32]    = INDEX_EN;
                        o_destination_index = 0;
                        o_shift_source      = 0;
                        o_shift_source[32]  = IMMED_EN;
                        o_shift_operation   = {1'd0, LSL};
                        o_shift_length      = 0;
                        o_shift_length[32]  = IMMED_EN;
                end

                SMLAxy, SMLAWy,
                SMLALxy:                      decode_lmul_dsp   ();
                SMULWy, SMULxy:               decode_smul_dsp   ();                
                QADD:                         decode_sat_addsub ();
                QSUB:                         decode_sat_addsub ();
                QDADD:                        decode_sat_addsub ();
                QDSUB:                        decode_sat_addsub ();

                CLZ_INSTRUCTION:              decode_clz  ();
                BX_INST:                      decode_bx   ();
                MRS:                          decode_mrs  ();   
                MSR,MSR_IMMEDIATE:            decode_msr  ();

                DATA_PROCESSING_IMMEDIATE, 
                DATA_PROCESSING_REGISTER_SPECIFIED_SHIFT, 
                DATA_PROCESSING_INSTRUCTION_SPECIFIED_SHIFT:   decode_data_processing ();
                BRANCH_INSTRUCTION:     decode_branch      ();   
                LS_INSTRUCTION_SPECIFIED_SHIFT,
                LS_IMMEDIATE:           decode_ls          ();
                MULT_INST:              decode_mult        ();
                LMULT_INST:             decode_lmult       ();
                HALFWORD_LS:            decode_halfword_ls ();
                SOFTWARE_INTERRUPT:     decode_swi         ();

                default:
                begin
                        decode_und;
                end
                endcase
        end
end    

// ----------------------------------------------------------------------------

// =============================
// Decode QADD/QSUB/QDADD/QDSUB
// =============================
function void decode_sat_addsub ();
begin
        o_condition_code        = instruction[31:28];
        o_flag_update           = 1'd1;

        case(instruction[22:21])
        2'b00: o_alu_operation         = {1'd0, OP_QADD};
        2'b01: o_alu_operation         = {1'd0, OP_QSUB};
        2'b10: o_alu_operation         = {1'd0, OP_QDADD};
        2'b11: o_alu_operation         = {1'd0, OP_QDSUB};
        endcase

        // Processor does Rn - Rm.
 
        // Rn
        o_alu_source            = {29'd0, instruction[3:0]};
        o_alu_source[32]        = INDEX_EN;

        // Rm
        o_shift_source          = {29'd0, instruction[19:16]};
        o_shift_source[32]      = INDEX_EN;

        // Rs
        o_shift_operation       = LSL_SAT;
        o_shift_length          = 1;
        o_shift_length[32]      = IMMED_EN;

        // Destination index.
        o_destination_index     = {1'd0, instruction[15:12]};
end
endfunction

// =============================
// Decode CLZ
// =============================
function void decode_clz ();
begin: tskDecodeClz
        o_condition_code        =       instruction[31:28];
        o_flag_update           =       1'd0; // Instruction does not update any flags.
        o_alu_operation         =       {1'd0, CLZ};  // Added.

        // Rn = 0.
        o_alu_source            =       33'd0;
        o_alu_source[32]        =       IMMED_EN; 

        // Rm = register whose CLZ must be found.
        o_shift_source          =       {28'd0, instruction[`ZAP_DP_RB_EXTEND], instruction[`ZAP_DP_RB]}; // Rm
        o_shift_source[32]      =       INDEX_EN;
        o_shift_operation       =       {1'd0, LSL};
        o_shift_length          =       33'd0;
        o_shift_length[32]      =       IMMED_EN; // Shift length is 0 of course.

        // Destination index.
        o_destination_index     =       {1'd0, instruction[15:12]};
end
endfunction

// =============================
// Decode long multiplication.
// =============================
function void decode_lmult (); // Uses bit 35. rm.rs + {rh, rn}
begin: tskLDecodeMult

        o_condition_code        =       instruction[31:28];
        o_flag_update           =       instruction[20];

        // ARM rd.
        o_destination_index     =       {instruction[`ZAP_DP_RD_EXTEND], 
                                         instruction[19:16]};

        // For MUL, Rd and Rn are interchanged. 
        // For 64bit, this is normally high register.

        o_alu_source            =       {29'd0, instruction[11:8]}; // ARM rs
        o_alu_source[32]        =       INDEX_EN;

        o_shift_source          =       {28'd0, instruction[`ZAP_DP_RB_EXTEND], 
                                         instruction[`ZAP_DP_RB]};
        o_shift_source[32]      =       INDEX_EN;            // ARM rm 

        // ARM rn
        o_shift_length          =       {28'd0, instruction[`ZAP_DP_RA_EXTEND], 
                                         instruction[`ZAP_DP_RD]};

        o_shift_length[32]      =       INDEX_EN;


        // We need to generate output code.
        case ( instruction[22:21] )
        2'b00:
        begin
                // Unsigned MULT64
                o_alu_operation = {1'd0, UMLALH};
                o_mem_srcdest_index = RAZ_REGISTER; // rh.
        end
        2'b01:
        begin
                // Unsigned MAC64. Need mem_srcdest as source for RdHi.
                o_alu_operation = {1'd0, UMLALH};
                o_mem_srcdest_index = {1'd0, instruction[19:16]};
        end
        2'b10:
        begin
                // Signed MULT64
                o_alu_operation = {1'd0, SMLALH};
                o_mem_srcdest_index = RAZ_REGISTER;
        end
        2'b11:
        begin
                // Signed MAC64. Need mem_srcdest as source of RdHi.
                o_alu_operation = {1'd0, SMLALH};
                o_mem_srcdest_index = {1'd0, instruction[19:16]};
        end
        endcase

        if ( instruction[`ZAP_OPCODE_EXTEND] == 1'd0 ) // Low request - change destination index.
        begin
                        o_destination_index = {1'd0, instruction[15:12]}; // Low register.
                        o_alu_operation[0]  = 1'd0;                 // Request low operation.
        end
end
endfunction

// ----------------------------------------------------------------------------

// ===============================
// Decode undefined instructions.
// ===============================
function void decode_und ();
begin
        // Say instruction is undefined.
        o_und = 1'd1;

        // Generate LR = PC - 4
        o_condition_code    = AL;
        o_alu_operation     = {2'd0, SUB};
        o_alu_source        = {29'd0, ARCH_PC};
        o_alu_source[32]    = INDEX_EN; 
        o_destination_index = {1'd0, ARCH_LR};
        o_shift_source      = 33'd4;
        o_shift_source[32]  = IMMED_EN;
        o_shift_operation   = {1'd0, LSL};
        o_shift_length      = 33'd0;
        o_shift_length[32]  = IMMED_EN;
end
endfunction

// ----------------------------------------------------------------------------

// ===========================================
// Decode software interrupt instructions.
// ===========================================
function void decode_swi ();
begin: tskDecodeSWI

        // Generate LR = PC - 4
        o_condition_code    = instruction[31:28];
        o_alu_operation     = {2'd0, SUB};
        o_alu_source        = {29'd0, ARCH_PC};
        o_alu_source[32]    = INDEX_EN; 
        o_destination_index = {1'd0, ARCH_LR};
        o_shift_source      = 33'd4;
        o_shift_source[32]  = IMMED_EN;
        o_shift_operation   = {1'd0, LSL};
        o_shift_length      = 33'd0;
        o_shift_length[32]  = IMMED_EN;
end
endfunction

// ----------------------------------------------------------------------------

// ============================
// Decode halfword LOAD/STORE.
// ============================
function void decode_halfword_ls ();
begin: tskDecodeHalfWordLs
        logic [11:0] temp, temp1;

        temp  = instruction[11:0];
        temp1 = instruction[11:0];

        o_condition_code = instruction[31:28];

        temp[7:4]   = temp[11:8];
        temp[11:8]  = 4'd0;
        temp1[11:4] = 8'd0;

        if ( instruction[22] ) // immediate
        begin
                process_immediate ( {temp} );
        end
        else
        begin
                process_instruction_specified_shift ( {21'd0, temp1} );  
        end

        o_alu_operation     = instruction[23] ? {2'd0, ADD} : {2'd0, SUB};
        o_alu_source        = { 28'd0, instruction[`ZAP_BASE_EXTEND], 
                                instruction[`ZAP_BASE]}; // Pointer register.
        o_alu_source[32]    = INDEX_EN;
        o_mem_load          = instruction[20];
        o_mem_store         = !o_mem_load;
        o_mem_pre_index     = instruction[24];

        // If post-index is used or pre-index is used with writeback,
        // take is as a request to update the base register.
        o_destination_index = (instruction[21] || !o_mem_pre_index) ? 
                                o_alu_source[4:0] : 
                                RAZ_REGISTER; // Pointer register already added.

        o_mem_srcdest_index = {instruction[`ZAP_SRCDEST_EXTEND], 
                               instruction[`ZAP_SRCDEST]};

        // Transfer size.

        o_mem_unsigned_byte_enable      = 1'd0;
        o_mem_unsigned_halfword_enable  = 1'd0;
        o_mem_signed_halfword_enable    = 1'd0;

        case ( instruction[6:5] )
        SIGNED_BYTE:            o_mem_signed_byte_enable       = 1'd1;
        UNSIGNED_HALF_WORD:     o_mem_unsigned_halfword_enable = 1'd1;
        SIGNED_HALF_WORD:       o_mem_signed_halfword_enable   = 1'd1;
        default:
        begin
                o_mem_unsigned_byte_enable      = 1'd0;
                o_mem_unsigned_halfword_enable  = 1'd0;
                o_mem_signed_halfword_enable    = 1'd0;
        end
        endcase
end
endfunction

// ----------------------------------------------------------------------------

// ==============================
// Decode short multiplication.
// ==============================
function void decode_mult ();
begin: tskDecodeMult


        o_condition_code        =       instruction[31:28];
        o_flag_update           =       instruction[20];
        o_alu_operation         =       {1'd0, UMLALL};
        o_destination_index     =       {instruction[`ZAP_DP_RD_EXTEND], 
                                         instruction[19:16]};

        // For MUL, Rd and Rn are interchanged.
        o_alu_source            =       {29'd0, instruction[11:8]}; // ARM rs
        o_alu_source[32]        =       INDEX_EN;

        o_shift_source          =       {28'd0, instruction[`ZAP_DP_RB_EXTEND], 
                                         instruction[`ZAP_DP_RB]};
        o_shift_source[32]      =       INDEX_EN;            // ARM rm 

        // ARM rn - Set for accumulate.
        o_shift_length          =       instruction[21] ? 
                                        {28'd0, instruction[`ZAP_DP_RA_EXTEND], 
                                         instruction[`ZAP_DP_RD]} : 33'd0;

        o_shift_length[32]      =       instruction[21] ? INDEX_EN : IMMED_EN;

        // Set rh = 0.
        o_mem_srcdest_index = RAZ_REGISTER;
end
endfunction

// ----------------------------------------------------------------------------

// ====================================
// Decode 16-bit DSP multiplication
// ====================================

function void decode_smul_dsp ();
begin
        o_condition_code    = instruction[31:28];
        o_flag_update       = 1'd1;
        
        o_alu_operation = ((instruction[22:21] == 2'b01) && instruction[5] && instruction[15:12] == 0) ?
                          (instruction[6] ? OP_SMULW0 : OP_SMULW1) : 
                          (instruction[6:5] == 2'b00 ? OP_SMUL00 :
                           instruction[6:5] == 2'b01 ? OP_SMUL01 :
                           instruction[6:5] == 2'b10 ? OP_SMUL10 :
                           instruction[6:5] == 2'b11 ? OP_SMUL11 : OP_SMUL11) ;

        // ARM rd
        o_destination_index = {instruction[`ZAP_DP_RD_EXTEND], instruction[19:16]};
        
        // ARM Rs.
        o_alu_source = {29'd0, instruction[11:8]};
        o_alu_source[32] = INDEX_EN;

        // ARM rm
        o_shift_source = {28'd0, instruction[`ZAP_DP_RB_EXTEND], instruction[`ZAP_DP_RB]};
        o_shift_source[32] = INDEX_EN;

        // ARM rm=0
        o_shift_length     = 33'd0;
        o_shift_length[32] = INDEX_EN;

        // Set rh=0
        o_mem_srcdest_index = RAZ_REGISTER;
end
endfunction

// ----------------------------------------------------------------------------

// =============================
// Decode 16-bit long DSP (48-bit)
// =============================

function void decode_lmul_dsp (); // (rm.rs) + {rh, rn} = {rh, rn}
begin: tskLDecodeMultDsp

        o_condition_code        =       instruction[31:28];
        o_flag_update           =       1'd1;                   

        // ARM rd.
        o_destination_index     =       {instruction[`ZAP_DP_RD_EXTEND], 
                                         instruction[19:16]};

        // For MUL, Rd and Rn are interchanged. 
        // For 64bit, this is normally high register.

        o_alu_source            =       {29'd0, instruction[11:8]}; // ARM rs
        o_alu_source[32]        =       INDEX_EN;

        o_shift_source          =       {28'd0, instruction[`ZAP_DP_RB_EXTEND], 
                                         instruction[`ZAP_DP_RB]};
        o_shift_source[32]      =       INDEX_EN;            // ARM rm 

        o_shift_length          =       // ARM rn.
                                        {28'd0, instruction[`ZAP_DP_RA_EXTEND], 
                                         instruction[`ZAP_DP_RD]};

        o_shift_length[32]      =       INDEX_EN;                             


        // We need to generate output code.
        casez ( instruction[31:0] )

        SMLAxy:
        begin
                o_alu_operation     = instruction[6:5] == 2'b00 ? SMLA00 :
                                      instruction[6:5] == 2'b01 ? SMLA01 :
                                      instruction[6:5] == 2'b10 ? SMLA10 : 
                                                                  SMLA11 ;
                                       

                o_mem_srcdest_index = RAZ_REGISTER; // rh.
        end

        SMLAWy:
        begin
                o_alu_operation     = instruction[6] ? SMLAW1 : SMLAW0;

                o_mem_srcdest_index = {1'd0, instruction[19:16]}; // rh
        end

        SMLALxy:
        begin
                o_alu_operation     = instruction[6:5] == 2'b00 ? SMLAL00H :
                                      instruction[6:5] == 2'b01 ? SMLAL01H :
                                      instruction[6:5] == 2'b10 ? SMLAL10H :
                                      instruction[6:5] == 2'b11 ? SMLAL11H : SMLAL11H ;

                o_mem_srcdest_index = {1'd0, instruction[19:16]}; // rh
        end

        endcase

        if ( instruction[`ZAP_OPCODE_EXTEND] == 1'd0 && instruction[31:0] ==? SMLALxy ) // Low request.
        begin
                        o_destination_index = {1'd0, instruction[15:12]}; // Low register.
                        o_alu_operation[0]  = 1'd0;                       // Request low operation.

                        o_alu_operation     = 
                                      instruction[6:5] == 2'b00 ? SMLAL00L :
                                      instruction[6:5] == 2'b01 ? SMLAL01L :
                                      instruction[6:5] == 2'b10 ? SMLAL10L :
                                      instruction[6:5] == 2'b11 ? SMLAL11L : SMLAL11L ;
        end
end

endfunction

// ----------------------------------------------------------------------------

// =============================
// BX decode.
// =============================
// Converted into a MOV to PC. The function void of setting the T-bit in the CPSR is
// the job of the writeback stage.
function void decode_bx ();
begin: tskDecodeBx
        logic [32:0] temp;

        temp       = {1'd0, instruction[31:0]};
        temp[31:4] = 0; // Zero out stuff to avoid conflicts in the function.

        process_instruction_specified_shift(temp);

        // The RAW ALU source does not matter.
        o_condition_code        = instruction[31:28];
        o_alu_operation         = {2'd0, MOV};
        o_destination_index     = {1'd0, ARCH_PC};

        // We will force an immediate in alu source to prevent unwanted locks.
        o_alu_source            = 0;
        o_alu_source[32]        = IMMED_EN;

        // Indicate switch. This is a primary differentiator. 
        o_switch = 1;
end
endfunction

// ----------------------------------------------------------------------------

// =============================================
// Task for decoding load-store instructions.
// =============================================
function void decode_ls ();
begin: tskDecodeLs


        o_condition_code = instruction[31:28];

        if ( !instruction[25] ) // immediate
        begin
                o_shift_source          = {21'd0, instruction[11:0]};
                o_shift_source[32]      = IMMED_EN;
                o_shift_length          = 0;
                o_shift_length[32]      = IMMED_EN;
                o_shift_operation       = {1'd0, LSL};                
        end
        else
        begin
              process_instruction_specified_shift ( {21'd0, instruction[11:0]} );  
        end

        o_alu_operation = instruction[23] ? {2'd0, ADD} : {2'd0, SUB};

        // Pointer register.
        o_alu_source    = {28'd0, instruction[`ZAP_BASE_EXTEND], instruction[`ZAP_BASE]};
        o_alu_source[32] = INDEX_EN;
        o_mem_load          = instruction[20];
        o_mem_store         = !o_mem_load;
        o_mem_pre_index     = instruction[24];

        // If post-index is used or pre-index is used with writeback,
        // take is as a request to update the base register.
        o_destination_index = (instruction[21] || !o_mem_pre_index) ? 
                                o_alu_source[4:0] : 
                                RAZ_REGISTER; // Pointer register already added.
        o_mem_unsigned_byte_enable = instruction[22];

        o_mem_srcdest_index = {instruction[`ZAP_SRCDEST_EXTEND], instruction[`ZAP_SRCDEST]};

        if ( !o_mem_pre_index ) // Post-index, writeback has no meaning.
        begin
                if ( instruction[21] )
                begin
                        // Use it for force usr mode memory mappings.
                        o_mem_translate = 1'd1;
                end
        end
end
endfunction

// ----------------------------------------------------------------------------

function void decode_mrs ();
begin

        process_immediate ( {instruction[11:0]} );
        
        o_condition_code    = instruction[31:28];
        o_destination_index = {instruction[`ZAP_DP_RD_EXTEND], instruction[`ZAP_DP_RD]};
        o_alu_source        = instruction[22] ? ARCH_CURR_SPSR : ARCH_CPSR;
        o_alu_source[32]    = INDEX_EN;
        o_alu_operation     = {2'd0, ADD};
end
endfunction

// ----------------------------------------------------------------------------

function void decode_msr ();
begin

        if ( instruction[25] ) // Immediate present.
        begin
                process_immediate ( {instruction[11:0]} );
        end
        else
        begin
                process_instruction_specified_shift ( {21'd0, instruction[11:0]} );
        end

        // Destination.
        o_destination_index = instruction[22] ? ARCH_CURR_SPSR : ARCH_CPSR;

        o_condition_code = instruction[31:28];

        // Make srcdest as SPSR. useful for MMOV.
        o_mem_srcdest_index = ARCH_CURR_SPSR;

        // Select SPSR or CPSR.
        o_alu_operation  = instruction[22] ? {1'd0, MMOV} : {1'd0, FMOV};

        o_alu_source     = {29'd0, instruction[19:16]}; 
        o_alu_source[32] = IMMED_EN;

        // Part of the instruction will silently fail when changing mode bits
        // in user mode. This is as per the ARM spec.
        if  ( i_cpsr_ff_mode == USR )
        begin
                o_alu_source[2:0] = 3'b0;
        end
end
endfunction

// ----------------------------------------------------------------------------

// ========================
// Decode B
// ========================
function void decode_branch ();
begin
        // A branch is decayed into PC = PC + $signed(immed)
        o_condition_code        = instruction[31:28];
        o_alu_operation         = {2'd0, ADD};
        o_destination_index     = {1'd0, ARCH_PC};
        o_alu_source            = {29'd0, ARCH_PC};
        o_alu_source[32]        = INDEX_EN;
        o_shift_source[31:0]    = ($signed({{8{instruction[23]}},instruction[23:0]}));
        o_shift_source[32]      = IMMED_EN;
        o_shift_operation       = {1'd0, LSL};
        o_shift_length          = instruction[34] ? 1 : 2; // Thumb branches sometimes need only a shift of 1.
        o_shift_length[32]      = IMMED_EN; 
end
endfunction

// ----------------------------------------------------------------------------

//
// Common data processing handles the common section of all 3 data processing
// formats.
//
function void decode_data_processing ();
begin
        o_condition_code        = instruction[31:28];
        o_alu_operation         = {2'd0, instruction[24:21]};
        o_flag_update           = instruction[20];
        o_destination_index     = {instruction[`ZAP_DP_RD_EXTEND], instruction[`ZAP_DP_RD]};
        o_alu_source            = {29'd0, instruction[`ZAP_DP_RA]};
        o_alu_source[32]        = INDEX_EN;
        o_mem_srcdest_index     = ARCH_CURR_SPSR;

        if (    o_alu_operation == {2'd0, CMP} || 
                o_alu_operation == {2'd0, CMN} || 
                o_alu_operation == {2'd0, TST} || 
                o_alu_operation == {2'd0, TEQ} )
        begin
                o_destination_index = RAZ_REGISTER;
        end

        casez ( {instruction[25],instruction[7],instruction[4]} )
        3'b1??: process_immediate ( instruction[11:0] );
        3'b0?0: process_instruction_specified_shift ( instruction[32:0] );
        3'b001: process_register_specified_shift ( instruction[32:0] );
        default:
        begin
                // error.
        end
        endcase
end
endfunction

// ----------------------------------------------------------------------------

//
// If an immediate value is to be rotated right by an 
// immediate value, this mode is used.
//
function void process_immediate( input [11:0] xinstruction );
begin
        o_shift_length          = {28'd0, xinstruction[11:8], 1'd0};
        o_shift_length[32]      = IMMED_EN;
        o_shift_source          = {25'd0, xinstruction[7:0]};
        o_shift_source[32]      = IMMED_EN;                        
        o_shift_operation       = RORI;
end
endfunction

// ----------------------------------------------------------------------------

//
// The shifter source is a register but the 
// amount to shift is in the instruction itself.
//
function void process_instruction_specified_shift( input [32:0] xinstruction );
logic unused;
begin
         unused                  = |{xinstruction[31:12],xinstruction[4]};

        // ROR #0 = RRC, ASR #0 = ASR #32, LSL #0 = LSL #0, LSR #0 = LSR #32 
        // ROR #n = ROR_1 #n ( n > 0 )
        o_shift_length          = {28'd0, xinstruction[11:7]};
        o_shift_length[32]      = IMMED_EN;
        o_shift_source          = {28'd0, xinstruction[`ZAP_DP_RB_EXTEND],xinstruction[`ZAP_DP_RB]};
        o_shift_source[32]      = INDEX_EN;
        o_shift_operation       = {1'd0, xinstruction[6:5]};

        case ( o_shift_operation[1:0] )
                LSR: if ( o_shift_length[31:0] == 32'd0 ) o_shift_length[31:0] = 32;
                ASR: if ( o_shift_length[31:0] == 32'd0 ) o_shift_length[31:0] = 32;
                ROR: 
                begin
                        if ( o_shift_length[31:0] == 32'd0 ) 
                                o_shift_operation    = RRC;
                        else
                                o_shift_operation    = ROR_1; 
                                // Differs in carry generation behavior.
                end
                default: // For lint. Default values set in function anyway.
                begin
                end
        endcase

        // Reinforce the fact.
        o_shift_length[32] = IMMED_EN;
end
endfunction

// ----------------------------------------------------------------------------

// The source register and the amount of shift are both in registers.
function void process_register_specified_shift( input [32:0] xinstruction );
logic unused;
begin
        unused                  = |{xinstruction[31:12],xinstruction[7],xinstruction[4]};
        o_shift_length          = {29'd0, xinstruction[11:8]};
        o_shift_length[32]      = INDEX_EN;
        o_shift_source          = {28'd0, xinstruction[`ZAP_DP_RB_EXTEND], xinstruction[`ZAP_DP_RB]};
        o_shift_source[32]      = INDEX_EN;
        o_shift_operation       = {1'd0, xinstruction[6:5]};
end
endfunction

endmodule // zap_decode.v

