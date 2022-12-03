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

// Identifier for L1
localparam [1:0] SECTION_ID = 2'b10;
localparam [1:0] PAGE_ID    = 2'b01;

// Identifier for L2
localparam [1:0] SPAGE_ID   = 2'b10;
localparam [1:0] LPAGE_ID   = 2'b01;

// APSR bits.
// K  U (kernel user) permissions.
localparam APSR_NA_NA = 4'b00_00;
localparam APSR_RO_RO = 4'b00_01;
localparam APSR_RO_NA = 4'b00_10;
localparam APSR_RW_NA = 4'b01_??;
localparam APSR_RW_RO = 4'b10_??;
localparam APSR_RW_RW = 4'b11_??;

// DAC bits.
localparam DAC_MANAGER = 2'b11;
localparam DAC_CLIENT  = 2'b01;

// FSR related.
// These localparams relate to FSR values. Notice how
// only some FSR values make sense in this implementation.

//Section.
localparam [3:0] FSR_SECTION_DOMAIN_FAULT      = 4'b1001; 
localparam [3:0] FSR_SECTION_TRANSLATION_FAULT = 4'b0101;
localparam [3:0] FSR_SECTION_PERMISSION_FAULT  = 4'b1101;

//Page.
localparam [3:0] FSR_PAGE_TRANSLATION_FAULT    = 4'b0111;
localparam [3:0] FSR_PAGE_DOMAIN_FAULT         = 4'b1011;
localparam [3:0] FSR_PAGE_PERMISSION_FAULT     = 4'b1111;



///////////////////////////////////////////////////////////////////////////////

// Standard opcodes.
// These map to the opcode map in the spec.
localparam [3:0] AND   = 0;
localparam [3:0] EOR   = 1;
localparam [3:0] SUB   = 2;
localparam [3:0] RSB   = 3;
localparam [3:0] ADD   = 4;
localparam [3:0] ADC   = 5;
localparam [3:0] SBC   = 6;
localparam [3:0] RSC   = 7;
localparam [3:0] TST   = 8;
localparam [3:0] TEQ   = 9;
localparam [3:0] CMP   = 10;
localparam [3:0] CMN   = 11;
localparam [3:0] ORR   = 12;
localparam [3:0] MOV   = 13;
localparam [3:0] BIC   = 14;
localparam [3:0] MVN   = 15;

// Internal opcodes used to 
// implement some instructions.
localparam [4:0] MUL   = 16; // Multiply ( 32 x 32 = 32 ) -> Translated to MAC.
localparam [4:0] MLA   = 17; // Multiply-Accumulate ( 32 x 32 + 32 = 32 ). 

// Flag MOV. Will write upper 4-bits to flags if mask bit [3] is set to 1. 
// Also writes to target register similarly. 
// Mask bit comes from non-shift operand.
localparam [4:0] FMOV  = 18; 

// Same as FMOV but does not touch the flags in the ALU. This is MASK MOV. 
// Set to 1 will update, 0 will not 
// (0000 -> No updates, 0001 -> [7:0] update) and so on.
localparam [4:0] MMOV  = 19; 

localparam [4:0] UMLALL = 20; // Unsigned multiply accumulate (Write lower reg).
localparam [4:0] UMLALH = 21;

localparam [4:0] SMLALL = 22; // Signed multiply accumulate (Write lower reg).
localparam [4:0] SMLALH = 23;

localparam [4:0] CLZ    = 24; // Count Leading zeros.

// Conditionals defined as per v4 spec.
localparam EQ =  4'h0;
localparam NE =  4'h1;
localparam CS =  4'h2;
localparam CC =  4'h3;
localparam MI =  4'h4;
localparam PL =  4'h5;
localparam VS =  4'h6;
localparam VC =  4'h7;
localparam HI =  4'h8;
localparam LS =  4'h9;
localparam GE =  4'hA;
localparam LT =  4'hB;
localparam GT =  4'hC;
localparam LE =  4'hD;
localparam AL =  4'hE;
localparam NV =  4'hF; // NeVer execute!

// CPSR flags.
localparam N = 31;
localparam Z = 30;
localparam C = 29;
localparam V = 28;
localparam I = 7;
localparam F = 6;
localparam T = 5;

// For transferring indices/immediates across stages.
localparam              INDEX_EN       =       1'd0;
localparam              IMMED_EN       =       1'd1;

// Processor Modes
localparam FIQ = 5'b10_001;
localparam IRQ = 5'b10_010;
localparam ABT = 5'b10_111;
localparam SVC = 5'b10_011;
localparam USR = 5'b10_000;
localparam SYS = 5'b11_111;
localparam UND = 5'b11_011;

// Instruction definitions.
/* ARM */

localparam      [31:0]  DATA_PROCESSING_IMMEDIATE                       =                                       32'b????_00_1_????_?_????_????_????????????;
localparam      [31:0]  DATA_PROCESSING_REGISTER_SPECIFIED_SHIFT        =                                       32'b????_00_0_????_?_????_????_????0??1????;
localparam      [31:0]  DATA_PROCESSING_INSTRUCTION_SPECIFIED_SHIFT     =                                       32'b????_00_0_????_?_????_????_???????0????;       

// BL never reaches the unit.
localparam      [31:0]  BRANCH_INSTRUCTION                              =                                       32'b????_101?_????_????_????_????_????_????;

localparam      [31:0]  MRS                                             =                                       32'b????_00010_?_001111_????_????_????_????;
localparam      [31:0]  MSR_IMMEDIATE                                   =                                       32'b????_00_1_10?10_????_1111_????_????_????;

localparam      [31:0]  MSR                                             =                                       32'b????_00_0_10?10_????_1111_????_????_????;

localparam      [31:0]  LS_INSTRUCTION_SPECIFIED_SHIFT                  =                                       32'b????_01_1_?????_????_????_????_????_????; 
localparam      [31:0]  LS_IMMEDIATE                                    =                                       32'b????_01_0_?????_????_????_????_????_????;

localparam      [31:0]  BX_INST                                         =                                       32'b????_0001_0010_1111_1111_1111_0001_????;

localparam      [31:0]  MULT_INST                                       =                                       32'b????_0000_00?_?_????_????_????_1001_????;

// M MULT INST - UMULL, UMLAL, SMULL, SMLAL.
localparam      [31:0]  LMULT_INST                                      =                                       32'b????_0000_1??_?_????_????_????_1001_????;

// Halfword memory.
localparam      [31:0]  HALFWORD_LS                                     =                                       32'b????_000_?????_????_????_????_1??1_????;

// Software interrupt.
localparam      [31:0]  SOFTWARE_INTERRUPT                              =                                       32'b????_1111_????_????_????_????_????_????;

// Swap.
localparam      [31:0]  SWAP                                            =                                       32'b????_00010_?_00_????_????_00001001_????;

// Write to coprocessor.
localparam      [31:0]  MCR                                             =                                       32'b????_1110_???_0_????_????_1111_???_1_????;        

// Read from coprocessor.
localparam      [31:0]  MRC                                             =                                       32'b????_1110_???_1_????_????_1111_???_1_????;

// LDC, STC
localparam      [31:0]  LDC                                             =                                       32'b????_110_????1_????_????_????_????????;
localparam      [31:0]  STC                                             =                                       32'b????_110_????0_????_????_????_????????;

// CDP
localparam      [31:0]  CDP                                             =                                       32'b????_1110_????????_????????_????????;

// CLZ
localparam      [31:0]  CLZ_INSTRUCTION                                 =                                       32'b????_00010110_1111_????_1111_0001_????;

// BLX(1)
localparam      [31:0] BLX1                                             =                                       32'b1111_101_?_????????_????????_????????; 

// BLX(2)
localparam      [31:0] BLX2                                             =                                       32'b????_00010010_1111_1111_1111_0011_????;

/* Thumb ISA */

//B
localparam      [15:0]  T_BRANCH_COND                                   =                                       16'b1101_????_????????;
localparam      [15:0]  T_BRANCH_NOCOND                                 =                                       16'b11100_???????????;
localparam      [15:0]  T_BL                                            =                                       16'b1111_?_???????????;
localparam      [15:0]  T_BX                                            =                                       16'b01000111_0_?_???_000;
localparam      [15:0]  T_BLX1                                          =                                       16'b11101_???????????;
localparam      [15:0]  T_BLX2                                          =                                       16'b010001111_?_???_000;

// SWI
localparam      [15:0]  T_SWI                                           =                                       16'b11011111_????????;

// Shifts.
localparam      [15:0]  T_SHIFT                                         =                                       16'b000_??_?????_???_???;

// Add sub LO.
localparam      [15:0]  T_ADD_SUB_LO                                    =                                       16'b00011_?_?_???_???_???;

// MCAS Imm.
localparam      [15:0]  T_MCAS_IMM                                      =                                       16'b001_??_???_????????;

// ALU Lo.
localparam      [15:0]  T_ALU_LO                                        =                                       16'b010000_????_???_???;

// ALU hi.
localparam      [15:0]  T_ALU_HI                                        =                                       16'b010001_??_?_?_???_???;

// *Get address.
localparam      [15:0]  T_GET_ADDR                                      =                                       16'b1010_?_???_????????;

// *Add offset to SP.
localparam      [15:0]  T_MOD_SP                                        =                                       16'b10110000_?_????_???;

// PC relative load.
localparam      [15:0]  T_PC_REL_LOAD                                   =                                       16'b01001_???_????????;

// LDR_STR_5BIT_OFF
localparam      [15:0] T_LDR_STR_5BIT_OFF                               =                                       16'b011_?_?_?????_???_???;

// LDRH_STRH_5BIT_OFF
localparam      [15:0] T_LDRH_STRH_5BIT_OFF                             =                                       16'b1000_?_?????_???_???;

// Signed LDR/STR
localparam      [15:0]  T_LDRH_STRH_REG                                 =                                       16'b0101_???_???_???_???;

// SP relative LDR/STR
localparam      [15:0]  T_SP_REL_LDR_STR                                =                                       16'b1001_?_???_????????;

// LDMIA/STMIA
localparam      [15:0]  T_LDMIA_STMIA                                   =                                       16'b1100_?_???_????????;

// PUSH POP
localparam      [15:0]  T_POP_PUSH                                      =                                       16'b1011_?_10_?_????????;

//
// Architectural Registers.
// Architectural registers are registered defined by the architecture plus
// a few more. Basically instructions index into architectural registers.
//
localparam [3:0] ARCH_SP   = 13;
localparam [3:0] ARCH_LR   = 14;
localparam [3:0] ARCH_PC   = 15;
localparam RAZ_REGISTER    = 16; // Serves as $0 does on MIPS.

// These always point to user registers irrespective of mode.
localparam ARCH_USR2_R8    = 18; 
localparam ARCH_USR2_R9    = 19;
localparam ARCH_USR2_R10   = 20;
localparam ARCH_USR2_R11   = 21;
localparam ARCH_USR2_R12   = 22;
localparam ARCH_USR2_R13   = 23;
localparam ARCH_USR2_R14   = 24;

// Dummy architectural registers.
localparam ARCH_DUMMY_REG0 = 25;
localparam ARCH_DUMMY_REG1 = 26;

// CPSR and SPSR.
localparam ARCH_CPSR       = 17;
localparam ARCH_CURR_SPSR  = 27; // Alias to real SPSR.

// Total architectural registers.
localparam TOTAL_ARCH_REGS = 28;

//
// Physical registers.
// Physical registers can be mapped directly into the internal
// register file.
//
localparam  PHY_PC               =       15; // DO NOT CHANGE!
localparam  PHY_RAZ_REGISTER     =       16; // DO NOT CHANGE!
localparam  PHY_CPSR             =       17; // DO NOT CHANGE!

localparam  PHY_USR_R0           =       0;
localparam  PHY_USR_R1           =       1;
localparam  PHY_USR_R2           =       2;
localparam  PHY_USR_R3           =       3;
localparam  PHY_USR_R4           =       4;
localparam  PHY_USR_R5           =       5;
localparam  PHY_USR_R6           =       6;
localparam  PHY_USR_R7           =       7;
localparam  PHY_USR_R8           =       8;
localparam  PHY_USR_R9           =       9;
localparam  PHY_USR_R10          =       10;
localparam  PHY_USR_R11          =       11;
localparam  PHY_USR_R12          =       12;
localparam  PHY_USR_R13          =       13;
localparam  PHY_USR_R14          =       14;

localparam  PHY_FIQ_R8           =       18;
localparam  PHY_FIQ_R9           =       19;
localparam  PHY_FIQ_R10          =       20;
localparam  PHY_FIQ_R11          =       21;
localparam  PHY_FIQ_R12          =       22;
localparam  PHY_FIQ_R13          =       23;
localparam  PHY_FIQ_R14          =       24;

localparam  PHY_IRQ_R13          =       25;
localparam  PHY_IRQ_R14          =       26;

localparam  PHY_SVC_R13          =       27;
localparam  PHY_SVC_R14          =       28;

localparam  PHY_UND_R13          =       29;
localparam  PHY_UND_R14          =       30;

localparam  PHY_ABT_R13          =       31;
localparam  PHY_ABT_R14          =       32;     

// Dummy registers for various purposes.
localparam  PHY_DUMMY_REG0       =       33;
localparam  PHY_DUMMY_REG1       =       34;

// SPSRs.
localparam  PHY_FIQ_SPSR         =       35;
localparam  PHY_IRQ_SPSR         =       36;
localparam  PHY_SVC_SPSR         =       37;
localparam  PHY_UND_SPSR         =       38;
localparam  PHY_ABT_SPSR         =       39;

//
// Count of total registers 
// (Can go up to 64 with no problems). Used to set register index widths of
// the control signals.
//
localparam  TOTAL_PHY_REGS       =       40;

// Shift type.
localparam [1:0] LSL  = 0;
localparam [1:0] LSR  = 1;
localparam [1:0] ASR  = 2;
localparam [1:0] ROR  = 3;
localparam [2:0] RRC  = 4; // Encoded as ROR #0.
localparam [2:0] RORI = 5;
localparam [2:0] ROR_1= 6; // ROR with instruction specified shift.

// Wishbone CTI.
localparam CTI_CLASSIC  = 3'b000;
localparam CTI_BURST    = 3'b010;
localparam CTI_EOB      = 3'b111;
