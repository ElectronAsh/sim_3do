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
// --  Implements a 16-bit instruction decoder. The 16-bit instruction set is --
// --  not logically organized so as to save on encoding and thus the functs  --
// --  seem a bit complex.                                                    --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

module zap_predecode_compress (
        // Clock and reset.
        input wire              i_clk,

        // Input from I-cache.
        // Instruction and valid qualifier.
        input wire [31:0]       i_instruction,
        input wire              i_instruction_valid,

        // Offset input.
        input wire [11:0]       i_offset,

        // Interrupts. Active high level sensitive signals.
        input wire              i_irq,
        input wire              i_fiq,

        // Ensure compressed mode is active (T bit).
        input wire              i_cpsr_ff_t, 

        //
        // Outputs to the ARM decoder.
        // 
        
        // Instruction, valid, undefined by this decoder and force 32-bit
        // align signals (requires memory to keep lower 2 bits as 00).
        output reg [34:0]       o_instruction,
        output reg              o_instruction_valid,
        output reg              o_und,
        output reg              o_force32_align, 

        // Interrupt status output.
        output reg              o_irq,
        output reg              o_fiq
);

///////////////////////////////////////////////////////////////////////////////

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

///////////////////////////////////////////////////////////////////////////////

reg [11:0] offset_w;  // Previous offset.

///////////////////////////////////////////////////////////////////////////////

always @*
        offset_w = i_offset;

///////////////////////////////////////////////////////////////////////////////

always @*
begin
        // If you are not in compressed mode, just pass stuff on.
        o_instruction_valid     = i_instruction_valid;
        o_und                   = 0;
        o_instruction           = i_instruction;
        o_irq                   = i_irq;
        o_fiq                   = i_fiq;
        o_force32_align         = 0;

        if ( i_cpsr_ff_t && i_instruction_valid ) // compressed mode enable
        begin
                casez ( i_instruction[15:0] )
                        T_BLX1                  : decode_blx1;
                        T_BLX2                  : decode_blx2;
                        T_ADD_SUB_LO            : decode_add_sub_lo; 
                        T_SWI                   : decode_swi;
                        T_BRANCH_COND           : decode_conditional_branch; 
                        T_BRANCH_NOCOND         : decode_unconditional_branch;
                        T_BL                    : decode_bl;
                        T_BX                    : decode_bx;
                        T_SHIFT                 : decode_shift;
                        T_MCAS_IMM              : decode_mcas_imm;    // MOV,CMP,ADD,SUB IMM.
                        T_ALU_LO                : decode_alu_lo;
                        T_ALU_HI                : decode_alu_hi;
                        T_PC_REL_LOAD           : decode_pc_rel_load; // LDR Rd, [PC, {#imm8,0,0}] 
                        T_LDR_STR_5BIT_OFF      : decode_ldr_str_5bit_off;
                        T_LDRH_STRH_5BIT_OFF    : decode_ldrh_strh_5bit_off;
                        T_LDRH_STRH_REG         : decode_ldrh_strh_reg; // Complex. 
                        T_SP_REL_LDR_STR        : decode_sp_rel_ldr_str;
                        T_LDMIA_STMIA           : decode_ldmia_stmia;
                        T_POP_PUSH              : decode_pop_push;
                        T_GET_ADDR              : decode_get_addr;
                        T_MOD_SP                : decode_mod_sp;
                        default: 
                        begin
                                `ifdef COMP_DEBUG
                                $display($time, "%m: Not implemented in compressed decoder!!!");
                                `endif
                                o_und = 1; // Will take UND trap.
                        end
                endcase 
        end
end

///////////////////////////////////////////////////////////////////////////////

task decode_get_addr;
begin: dcdGetAddr
        reg [11:0] imm;
        reg [3:0] rd;

        rd              = i_instruction[10:8];
        imm[7:0]        = i_instruction[7:0];
        imm[11:8]       = 4'd15; // To achieve a left shift of 2 i.e., *4

        o_instruction = 0;

        // ADD Rd, PC, imm
        o_instruction[31:0] = {AL, 2'b00, 1'b1, ADD, 1'd0, 4'd15, rd, imm}; 

        // ADD Rd, SP, imm
        if ( i_instruction[11] ) // SP
        begin
            o_instruction[31:0] = {AL, 2'b00, 1'b1, ADD, 1'd0, 4'd13, rd, imm}; 
        end
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_mod_sp;
begin: dcdModSp
        reg [11:0] imm;

        imm[7:0]        = i_instruction[6:0];
        imm[11:8]       = 4'd15; // To achieve a left shift of 2 i.e., *4

        o_instruction = 0;

        o_instruction[31:0] = {AL, 2'b00, 1'b1, ADD, 1'd0, 4'd13, 4'd13, imm};           

        // SUB/ADD R13, R13, imm
        if ( i_instruction[7] != 0 ) // SUB
        begin
         o_instruction[31:0] = {AL, 2'b00, 1'b1, SUB, 1'd0, 4'd13, 4'd13, imm};  
        end
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_pop_push;
begin: decodePopPush
        //
        // Uses an FD stack. Thus it is DA type i.e., post index down by 4. 
        // Writeback is implicit so make W = 0.
        //

        reg [3:0] base;
        reg [15:0] reglist; 

        o_instruction = 0;
        base = 13;

        reglist = i_instruction[7:0];

        if ( i_instruction[8] == 1 && i_instruction[11] ) // Pop.
        begin
                reglist[15] = 1'd1;
        end
        else if ( i_instruction[8] == 1 && !i_instruction[11] ) // Push.
        begin
                reglist[14] = 1'd1;
        end

        o_instruction = {AL, 3'b100, 1'd0, 1'd0, 1'd0, 1'd1, i_instruction[11], 
                                                        base, reglist};
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_ldmia_stmia;
begin: dcdLdmiaStmia
        // Implicit IA type i.e., post index up by 4. Make WB = 1.

        reg [3:0] base;
        reg [15:0] reglist;

        base = i_instruction[10:8];
        reglist = i_instruction[7:0];

        o_instruction = 0;
        o_instruction = {AL, 3'b100, 1'd0, 1'd1, 1'd0, 1'd1, i_instruction[11], 
                                base, reglist};
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_sp_rel_ldr_str;
begin: dcdLdrRelStr
        reg [3:0] srcdest;
        reg [3:0] base;
        reg [11:0] imm;

        srcdest = i_instruction[10:8];
        base    = ARCH_SP;
        imm    = i_instruction[7:0] << 2;

        o_instruction = 0;
        o_instruction = {AL, 3'b010, 1'd1, 1'd0, 1'd0, 1'd0, i_instruction[11], 
                        base, srcdest, imm};
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_ldrh_strh_reg;
begin: dcdLdrhStrh
        // Use different load store format, instead of 3'b010, use 3'b011

        reg X,S,H;
        reg [3:0] srcdest, base;
        reg [11:0] offset;

        X = i_instruction[9];
        S = i_instruction[10];
        H = i_instruction[11];
        srcdest = i_instruction[2:0];
        base    = i_instruction[5:3];
        offset = i_instruction[8:6];

        o_instruction = 0;

        if ( X == 0 )
        begin
          case({H,S})
          0: o_instruction = {AL, 3'b011, 1'd1, 1'd0, 1'd0, 1'd0, 1'd0, base, srcdest, offset};// STR
          1: o_instruction = {AL, 3'b011, 1'd1, 1'd0, 1'd1, 1'd0, 1'd0, base, srcdest, offset};// STRB
          2: o_instruction = {AL, 3'b011, 1'd1, 1'd0, 1'd0, 1'd0, 1'd1, base, srcdest, offset};// LDR
          3: o_instruction = {AL, 3'b011, 1'd1, 1'd0, 1'd1, 1'd0, 1'd1, base, srcdest, offset};// LDRB
          endcase
        end
        else
        begin
         case({S,H})
         0: o_instruction = {AL, 3'b000, 1'd1, 1'd0, 1'd0, 1'd0, 1'd0, base, srcdest, 4'd0, 2'b01,offset[3:0]};// STRH
         1: o_instruction = {AL, 3'b000, 1'd1, 1'd0, 1'd0, 1'd0, 1'd1, base, srcdest, 4'd0, 2'b01,offset[3:0]};// LDRH
         2: o_instruction = {AL, 3'b000, 1'd1, 1'd0, 1'd0, 1'd0, 1'd1, base, srcdest, 4'd0, 2'b10,offset[3:0]};// LDSB
         3: o_instruction = {AL, 3'b000, 1'd1, 1'd0, 1'd0, 1'd0, 1'd1, base, srcdest, 4'd0, 2'b11,offset[3:0]};// LDSH
         endcase
        end
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_ldrh_strh_5bit_off;
begin: dcdLdrhStrh5BitOff

        reg [3:0] rn;
        reg [3:0] rd;
        reg [7:0] imm;

        o_instruction = 0;

        rn = i_instruction[5:3];
        rd = i_instruction[2:0];
        imm[7:0] = i_instruction[10:6] << 1;  

        // Unsigned halfword transfer
        o_instruction = {AL, 3'b000, 1'd1, 1'd0, 1'd1, 1'd0, i_instruction[11], 
                                        rn, rd, imm[7:4], 2'b01,imm[3:0]};
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_ldr_str_5bit_off;
begin: dcLdrStr5BitOff
        reg [3:0] rn;
        reg [3:0] rd;
        reg [11:0] imm;

        o_instruction = 0;

        rn = i_instruction[5:3];
        rd = i_instruction[2:0];

        if ( i_instruction[12] == 1'd0 )
                imm[11:0] = i_instruction[10:6] << 2;        
        else
                imm[11:0] = i_instruction[10:6];

        o_instruction = {AL, 3'b010, 1'd1, 1'd0, i_instruction[12], 1'd0, 
                                               i_instruction[11], rn, rd, imm};
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_pc_rel_load;
begin: dcPcRelLoad
        reg [3:0] rd;
        reg [11:0] imm;

        rd = i_instruction[10:8];
        imm = i_instruction[7:0] << 2;

        o_force32_align = 1'd1;
        o_instruction = 0;
        o_instruction = {AL, 3'b010, 1'd1, 1'd0, 1'd0, 1'd0, 
                                        1'd1, 4'b1111, rd, imm};  
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_alu_hi;
begin:dcAluHi
        // Performs operations on HI registers (atleast some of them). 
        reg [1:0] op;
        reg [3:0] rd;
        reg [3:0] rs;

        o_instruction = 0;

        op = i_instruction[9:8];
        rd = {i_instruction[7], i_instruction[2:0]};        
        rs = {i_instruction[6], i_instruction[5:3]};

        case(op)
        0: o_instruction[31:0] = {AL, 2'b00, 1'b0, ADD, 1'b0, rd, rd, 8'd0, rs}; // ADD Rd, Rd, Rs 
        1: o_instruction[31:0] = {AL, 2'b00, 1'b0, CMP, 1'b1, rd, rd, 8'd0, rs}; // CMP Rd, Rs
        2: o_instruction[31:0] = {AL, 2'b00, 1'b0, MOV, 1'b0, rd, rd, 8'd0, rs}; // MOV Rd, Rs
        3:
        begin
                $display($time, "%m: This should never happen, should be taken by BX...!");
                $finish;
        end
        endcase
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_alu_lo;
begin: tskDecAluLo
        reg [3:0] op;
        reg [3:0] rs, rd;
        reg [3:0] rn;

        op = i_instruction[9:6];
        rs = i_instruction[5:3];
        rd = i_instruction[2:0];

        o_instruction = 0;

        case(op)
        0:      o_instruction[31:0] = {AL, 2'b00, 1'b0, AND, 1'd1, rd, rd, 8'd0, rs};                   // ANDS Rd, Rd, Rs
        1:      o_instruction[31:0] = {AL, 2'b00, 1'b0, EOR, 1'd1, rd, rd, 8'd0, rs};                   // EORS Rd, Rd, Rs
        2:      o_instruction[31:0] = {AL, 2'b00, 1'b0, MOV, 1'd1, rd, rd, rs, 1'd0, LSL, 1'd1, rd};    // MOVS Rd, Rd, LSL Rs
        3:      o_instruction[31:0] = {AL, 2'b00, 1'b0, MOV, 1'd1, rd, rd, rs, 1'd0, LSR, 1'd1, rd};    // MOVS Rd, Rd, LSR Rs
        4:      o_instruction[31:0] = {AL, 2'b00, 1'b0, MOV, 1'd1, rd, rd, rs, 1'd0, ASR, 1'd1, rd};    // MOVS Rd, Rd, ASR Rs
        5:      o_instruction[31:0] = {AL, 2'b00, 1'b0, ADC, 1'd1, rd, rd, 8'd0, rs};                   // ADCS Rd, Rd, Rs
        6:      o_instruction[31:0] = {AL, 2'b00, 1'b0, SBC, 1'd1, rd, rd, 8'd0, rs};                   // SBCS Rd, Rs, Rs        
        7:      o_instruction[31:0] = {AL, 2'b00, 1'b0, MOV, 1'd1, rd, rd, rs, 1'd0, ROR, 1'd1, rd};    // MOVS Rd, Rd, ROR Rs.
        8:      o_instruction[31:0] = {AL, 2'b00, 1'b0, TST, 1'd1, rd, rd, 8'd0, rs};                   // TST Rd, Rs
        9:      o_instruction[31:0] = {AL, 2'b00, 1'b1, RSB, 1'd1, rs, rd, 12'd0};                      // Rd = 0 - Rs
        10:     o_instruction[31:0] = {AL, 2'b00, 1'b1, CMP, 1'd1, rd, rd, 8'd0, rs};                   // CMP Rd, Rs
        11:     o_instruction[31:0] = {AL, 2'b00, 1'b1, CMN, 1'd1, rd, rd, 8'd0, rs};                   // CMN Rd, Rs
        12:     o_instruction[31:0] = {AL, 2'b00, 1'b1, ORR, 1'd1, rd, rd, 8'd0, rs};                   // ORRS Rd, Rd, rs 
        13:     o_instruction[31:0] = {AL, 4'b0000, 3'b000, 1'd1, rd, 4'd0, rd, 4'b1001, rs};           // MULS Rd, Rs, Rd
        14:     o_instruction[31:0] = {AL, 2'b00, 1'b1, BIC, 1'd1, rd, rd, 8'd0, rs};                   // BICS rd, rd, rs 
        15:     o_instruction[31:0] = {AL, 2'b00, 1'b1, MVN, 1'd1, rd, rd, 8'd0, rs};                   // MVNS rd, rd, rs
        endcase
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_mcas_imm;
begin: tskDecodeMcasImm
        reg [1:0]  op;
        reg [3:0]  rd;
        reg [11:0] imm;

        o_instruction = 0;

        op = i_instruction[12:11];
        rd = i_instruction[10:8];
        imm =i_instruction[7:0];

        case (op)
                0:
                begin
                        // MOV Rd, Offset8
                        o_instruction[31:0] = {AL, 2'b00, 1'b1, MOV, 1'd1, rd, rd, imm};  
                end
                1:
                begin
                        // CMP Rd, Offset8
                        o_instruction[31:0] = {AL, 2'b00, 1'b1, CMP, 1'd1, rd, rd, imm};  
                end
                2:
                begin
                        // ADDS Rd, Rd, Offset8
                        o_instruction[31:0] = {AL, 2'b00, 1'b1, ADD, 1'd1, rd, rd, imm};  
                end
                3:
                begin
                        // SUBS Rd, Rd, Offset8
                        o_instruction[31:0] = {AL, 2'b00, 1'b1, SUB, 1'd1, rd, rd, imm};  
                end
        endcase
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_add_sub_lo;
begin: tskDecodeAddSubLo
        reg [3:0] rn, rd, rs;
        reg [11:0] imm;

        o_instruction = 0;

        rn = i_instruction[8:6];
        rd = i_instruction[2:0];
        rs = i_instruction[5:3];
        imm = rn;

        case({i_instruction[9], i_instruction[10]})
        0:
        begin
                // Add Rd, Rs, Rn - Instr spec shift.
                o_instruction[31:0] = {AL, 2'b00, 1'b0, ADD, 1'd1, rs, rd, 8'd0, rn};  
        end
        1:
        begin
                // Adds Rd, Rs, #Offset3 - Immediate.
                o_instruction[31:0] = {AL, 2'b00, 1'b1, ADD, 1'd1, rn, rd, imm};  
        end
        2:
        begin
                // SUBS Rd, Rs, Rn - Instr spec shift.
                o_instruction[31:0] = {AL, 2'b00, 1'b0, SUB, 1'd1, rs, rd, 8'd0, rn}; 
        end
        3:
        begin
                // SUBS Rd, Rs, #Offset3 - Immediate.
                o_instruction[31:0] = {AL, 2'b00, 1'b1, SUB, 1'd1, rn, rd, imm}; 
        end
        endcase
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_conditional_branch;
begin
        // An MSB of 1 indicates a left shift of 1.
        o_instruction           = {1'd1, 2'b0, i_instruction[11:8], 3'b101, 1'b0, 24'd0}; 
        o_instruction[23:0]     = $signed(i_instruction[7:0]); 
end        
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_unconditional_branch;
begin
        // An MSB of 1 indicates a left shift of 1.
        o_instruction           = {1'd1, 2'b0, AL, 3'b101, 1'b0, 24'd0}; 
        o_instruction[23:0]     = $signed(i_instruction[10:0]);        
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_blx1;
begin
        o_instruction = 0; // Default value.

        // Generate a BLX1.
        o_instruction[31:25] =  7'b1111_101;    // BLX1 identifier.   
        o_instruction[24]    =  1'd0;           // H - bit.
        o_instruction[23:0]  =  ($signed(offset_w) << 12) | (i_instruction[10:0] << 1);  // Corrected.
        o_irq                = 1'd0;
        o_fiq                = 1'd0;
end
endtask

////////////////////////////////////////////////////////////////////////////////

task decode_blx2;
begin
        o_instruction = {4'b1110,4'b0001,4'b0010,4'b1111,4'b1111,4'b1111,4'b0011, i_instruction[6:3]}; 
        o_irq         = 1'd0;
        o_fiq         = 1'd0; 
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_bl;
begin
        case ( i_instruction[11] )
                1'd0:
                begin
                        // Send out a dummy instruction. Preserve lower
                        // 12-bits though to serve as offset. Set condition
                        // code to NV.
                        o_instruction        = i_instruction[11:0];
                        o_instruction[31:28] = 4'b1111;
                        o_irq                = 1'd0;
                        o_fiq                = 1'd0;
                end
                1'd1:
                begin
                        // Generate a full jump.
                        o_instruction = {1'd1, 2'b0, AL, 3'b101, 1'b1, 24'd0};
                        o_instruction[23:0] = ($signed(offset_w) << 12) | (i_instruction[10:0] << 1);  // Corrected.
                        o_irq           = 1'd0;
                        o_fiq           = 1'd0;
                end
        endcase
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_bx;
begin
        // Generate a BX Rm.
        o_instruction = 32'b0000_0001_0010_1111_1111_1111_0001_0000;
        o_instruction[31:28] = AL;
        o_instruction[3:0]   = i_instruction[6:3];
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_swi;
begin
        // Generate a SWI.
        o_instruction = 32'b0000_1111_0000_0000_0000_0000_0000_0000;
        o_instruction[31:28] = AL;
        o_instruction[7:0]   = i_instruction[7:0]; 
end
endtask

///////////////////////////////////////////////////////////////////////////////

task decode_shift;
begin
        // Compressed shift instructions. Decompress to ARM with instruction specified shift.
        o_instruction           = 32'd0;                // Extension -> 0.
        o_instruction[31:28]    = AL;                   // Always execute.
        o_instruction[27:26]    = 2'b00;                // Data processing.
        o_instruction[25]       = 1'd0;                 // Immediate is ZERO.
        o_instruction[24:21]    = MOV;                  // Operation is MOV.
        o_instruction[20]       = 1'd1;                 // Do update flags.
        o_instruction[19:16]    = 4'd0;                 // ALU source. Doesn't matter.
        o_instruction[15:12]    = i_instruction[2:0] ;  // Destination. 
        o_instruction[11:7]     = i_instruction[10:6];  // Shamt.
        o_instruction[6:5]      = i_instruction[12:11]; // Shtype.
        o_instruction[3:0]      = i_instruction[5:3];   // Shifter source.
end
endtask

///////////////////////////////////////////////////////////////////////////////

endmodule
`default_nettype wire
