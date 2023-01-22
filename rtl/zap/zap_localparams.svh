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

// We can safely turn of UNSED warnings since this file is a common include file, so some local params will end being
// unused in some files anyway.

/* verilator lint_off UNUSED */

// Identifier for L1
localparam [1:0] SECTION_ID = 2'b10;
localparam [1:0] PAGE_ID    = 2'b01;
localparam [1:0] FINE_ID    = 2'b11; // Fine page.

// Identifier for L2
localparam [1:0] SPAGE_ID   = 2'b10;
localparam [1:0] LPAGE_ID   = 2'b01;
localparam [1:0] FPAGE_ID   = 2'b11; // Fine page.

// APSR bits.
// K  U (kernel user) permissions.
localparam [3:0] APSR_NA_NA = 4'b00_00;
localparam [3:0] APSR_RO_RO = 4'b00_01;
localparam [3:0] APSR_RO_NA = 4'b00_10;
localparam [3:0] APSR_RW_NA = 4'b01_??;
localparam [3:0] APSR_RW_RO = 4'b10_??;
localparam [3:0] APSR_RW_RW = 4'b11_??;

// DAC bits.
localparam [1:0] DAC_MANAGER = 2'b11;
localparam [1:0] DAC_CLIENT  = 2'b01;

// FSR related.

// Section.
localparam [3:0] FSR_SECTION_DOMAIN_FAULT      = 4'b1001;
localparam [3:0] FSR_SECTION_TRANSLATION_FAULT = 4'b0101;
localparam [3:0] FSR_SECTION_PERMISSION_FAULT  = 4'b1101;
localparam [3:0] FSR_L1_EXTERNAL_ABORT         = 4'b1100;

// Page.
localparam [3:0] FSR_PAGE_TRANSLATION_FAULT    = 4'b0111;
localparam [3:0] FSR_PAGE_DOMAIN_FAULT         = 4'b1011;
localparam [3:0] FSR_PAGE_PERMISSION_FAULT     = 4'b1111;
localparam [3:0] FSR_L2_EXTERNAL_ABORT         = 4'b1110;

// Terminal exception
parameter [3:0] TERMINAL_EXCEPTION              = 4'b0010;

//////////////////////
// Opcodes
//////////////////////

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

// Saturating addition/subtraction.
localparam [4:0] OP_QADD   = 25;
localparam [4:0] OP_QSUB   = 26;
localparam [4:0] OP_QDADD  = 27;
localparam [4:0] OP_QDSUB  = 28;

// Multiplication (DSP).
localparam [5:0] SMULW0  = 30;
localparam [5:0] SMULW1  = 32;
localparam [5:0] SMUL00  = 34;
localparam [5:0] SMUL01  = 36;
localparam [5:0] SMUL10  = 38;
localparam [5:0] SMUL11  = 40;

// MAC (DSP)
localparam [5:0] SMLA00   = 42;
localparam [5:0] SMLA01   = 44;
localparam [5:0] SMLA10   = 46;
localparam [5:0] SMLA11   = 48;
localparam [5:0] SMLAW0   = 50;
localparam [5:0] SMLAW1   = 52;

// MAC(DSP) - Long.
localparam [5:0] SMLAL00L = 54;
localparam [5:0] SMLAL00H = 55;
localparam [5:0] SMLAL01L = 56;
localparam [5:0] SMLAL01H = 57;
localparam [5:0] SMLAL10L = 58;
localparam [5:0] SMLAL10H = 59;
localparam [5:0] SMLAL11L = 60;
localparam [5:0] SMLAL11H = 61;

// FADD - Directly access flags.
localparam [5:0] FADD     = 62;

// Alias
localparam [5:0] OP_SMULW0   = 30;
localparam [5:0] OP_SMULW1   = 32;
localparam [5:0] OP_SMUL00   = 34;
localparam [5:0] OP_SMUL01   = 36;
localparam [5:0] OP_SMUL10   = 38;
localparam [5:0] OP_SMUL11   = 40;
localparam [5:0] OP_SMLA00   = 42;
localparam [5:0] OP_SMLA01   = 44;
localparam [5:0] OP_SMLA10   = 46;
localparam [5:0] OP_SMLA11   = 48;
localparam [5:0] OP_SMLAW0   = 50;
localparam [5:0] OP_SMLAW1   = 52;
localparam [5:0] OP_SMLAL00L = 54;
localparam [5:0] OP_SMLAL00H = 55;
localparam [5:0] OP_SMLAL01L = 56;
localparam [5:0] OP_SMLAL01H = 57;
localparam [5:0] OP_SMLAL10L = 58;
localparam [5:0] OP_SMLAL10H = 59;
localparam [5:0] OP_SMLAL11L = 60;
localparam [5:0] OP_SMLAL11H = 61;


// MOV only with SAT. Doesn't touch other flags. SAT comes from multiplier.
localparam [5:0] SAT_MOV   = 49;

// Conditionals defined as per v5T spec.
localparam [3:0] EQ =  4'h0;
localparam [3:0] NE =  4'h1;
localparam [3:0] CS =  4'h2;
localparam [3:0] CC =  4'h3;
localparam [3:0] MI =  4'h4;
localparam [3:0] PL =  4'h5;
localparam [3:0] VS =  4'h6;
localparam [3:0] VC =  4'h7;
localparam [3:0] HI =  4'h8;
localparam [3:0] LS =  4'h9;
localparam [3:0] GE =  4'hA;
localparam [3:0] LT =  4'hB;
localparam [3:0] GT =  4'hC;
localparam [3:0] LE =  4'hD;
localparam [3:0] AL =  4'hE;
localparam [3:0] NV =  4'hF; // NeVer execute!

// CPSR flags.
localparam [31:0] N             = 31;
localparam [31:0] Z             = 30;
localparam [31:0] C             = 29;
localparam [31:0] V             = 28;
localparam [31:0] Q             = 27;
localparam [31:0] I             = 7;
localparam [31:0] F             = 6;
localparam [31:0] T             = 5;
localparam [31:0] ZAP_CPSR_MODE = 4;

// For transferring indices/immediates across stages.
localparam [0:0] INDEX_EN = 1'd0;
localparam [0:0] IMMED_EN = 1'd1;

// Processor Modes
localparam [4:0] FIQ = 5'b10_001;
localparam [4:0] IRQ = 5'b10_010;
localparam [4:0] ABT = 5'b10_111;
localparam [4:0] SVC = 5'b10_011;
localparam [4:0] USR = 5'b10_000;
localparam [4:0] SYS = 5'b11_111;
localparam [4:0] UND = 5'b11_011;

// Instruction definitions.
// MODE32

// DSP multiplication accumulate (DSP)

localparam      [31:0]  SMLAxy                                          =                                       32'b????_00010_00_0_????_????_????_1_??_0_????;
localparam      [31:0]  SMLAWy                                          =                                       32'b????_00010_01_0_????_????_????_1_?0_0_????;
localparam      [31:0]  SMLALxy                                         =                                       32'b????_00010_10_0_????_????_????_1_??_0_????;

// DSP multiply (16-bit).
localparam      [31:0]  SMULWy                                          =                                       32'b????_00010_01_0_????_0000_????_1_?1_0_????;
localparam      [31:0]  SMULxy                                          =                                       32'b????_00010_11_0_????_0000_????_1_??_0_????;

// CLZ
localparam      [31:0]  CLZ_INSTRUCTION                                 =                                       32'b????_00010_11_0_1111_????_1111_0_00_1_????;

// Saturating add.
localparam      [31:0]  QADD                                            =                                       32'b????_00010_00_0_????_????_0000_0101_????;
localparam      [31:0]  QSUB                                            =                                       32'b????_00010_01_0_????_????_0000_0101_????;
localparam      [31:0]  QDADD                                           =                                       32'b????_00010_10_0_????_????_0000_0101_????;
localparam      [31:0]  QDSUB                                           =                                       32'b????_00010_11_0_????_????_0000_0101_????;

// PLD (NOP)
localparam      [31:0]  PLD                                             =                                       32'b1111_01?1?101_????_1111_????????????;

// Data processing.
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
localparam      [31:0]  MCR2                                            =                                       32'b1111_1110???0_????????????_???1_????;

// Read from coprocessor.
localparam      [31:0]  MRC                                             =                                       32'b????_1110_???_1_????_????_1111_???_1_????;
localparam      [31:0]  MRC2                                            =                                       32'b1111_1110???1_????????????_???1_????;

// LDC, STC
localparam      [31:0]  LDC                                             =                                       32'b????_110_????1_????_????_????_????????;
localparam      [31:0]  STC                                             =                                       32'b????_110_????0_????_????_????_????????;

// LDC2, STC2
localparam      [31:0]  LDC2                                            =                                       32'b1111_110????1_????????????_????_????;
localparam      [31:0]  STC2                                            =                                       32'b1111_110????0_????????????_????_????;

// CDP
localparam      [31:0]  CDP                                             =                                       32'b????_1110_????????_????????_????????;

// BLX(1)
localparam      [31:0] BLX1                                             =                                       32'b1111_101_?_????????_????????_????????;

// BLX(2)
localparam      [31:0] BLX2                                             =                                       32'b????_00010010_1111_1111_1111_0011_????;

// BKPT
localparam      [31:0] BKPT                                             =                                       32'b1110_00010010_????_????_????_0111_????;

// 16-bit ISA

//B
localparam      [15:0]  T_BRANCH_COND                                   =                                       16'b1101_????_????????; // Overlaps with SWI.
localparam      [15:0]  T_BRANCH_NOCOND                                 =                                       16'b11100_???????????;
localparam      [15:0]  T_BL                                            =                                       16'b1111_?_???????????;
localparam      [15:0]  T_BLX1                                          =                                       16'b11101_???????????;
localparam      [15:0]  T_BLX2                                          =                                       16'b010001111_?_???_000;
localparam      [15:0]  T_BX                                            =                                       16'b010001110_?_???_000;

// SWI
localparam      [15:0]  T_SWI                                           =                                       16'b1101_1111_????????;

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

// Get address.
localparam      [15:0]  T_GET_ADDR                                      =                                       16'b1010_?_???_????????;

// Add offset to SP.
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

// BKPT
localparam      [15:0]  T_BKPT                                          =                                       16'b10111110_????????;

///////////////////////////////////////////////////////////////////////////////////////////////////////////////////////

//
// Architectural Registers.
// Architectural registers are registered defined by the architecture plus
// a few more. Basically instructions index into architectural registers.
//

localparam [31:0] TOTAL_ARCH_REGS = 28;
localparam [3:0] ARCH_SP                                 = 13;
localparam [3:0] ARCH_LR                                 = 14;
localparam [3:0] ARCH_PC                                 = 15;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] RAZ_REGISTER    = 16; // Serves as $0 does on MIPS.
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R8    = 18;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R9    = 19;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R10   = 20;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R11   = 21;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R12   = 22;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R13   = 23;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_USR2_R14   = 24;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_DUMMY_REG0 = 25;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_DUMMY_REG1 = 26;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_CPSR       = 17;
localparam [$clog2(TOTAL_ARCH_REGS)-1:0] ARCH_CURR_SPSR  = 27; // Alias to real SPSR.

//
// Physical registers.
// Physical registers can be mapped directly into the internal
// register file.
//

localparam [31:0] TOTAL_PHY_REGS                           = 40;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_PC            = 15; // DO NOT CHANGE!
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_RAZ_REGISTER  = 16; // DO NOT CHANGE!
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_CPSR          = 17; // DO NOT CHANGE!
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R0        = 0;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R1        = 1;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R2        = 2;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R3        = 3;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R4        = 4;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R5        = 5;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R6        = 6;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R7        = 7;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R8        = 8;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R9        = 9;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R10       = 10;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R11       = 11;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R12       = 12;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R13       = 13;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_USR_R14       = 14;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R8        = 18;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R9        = 19;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R10       = 20;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R11       = 21;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R12       = 22;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R13       = 23;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_R14       = 24;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_IRQ_R13       = 25;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_IRQ_R14       = 26;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_SVC_R13       = 27;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_SVC_R14       = 28;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_UND_R13       = 29;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_UND_R14       = 30;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_ABT_R13       = 31;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_ABT_R14       = 32;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_DUMMY_REG0    = 33;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_DUMMY_REG1    = 34;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_FIQ_SPSR      = 35;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_IRQ_SPSR      = 36;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_SVC_SPSR      = 37;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_UND_SPSR      = 38;
localparam  [$clog2(TOTAL_PHY_REGS)-1:0] PHY_ABT_SPSR      = 39;

// Shift type.
localparam [1:0] LSL     = 0;
localparam [1:0] LSR     = 1;
localparam [1:0] ASR     = 2;
localparam [1:0] ROR     = 3;
localparam [2:0] RRC     = 4; // Encoded as ROR #0.
localparam [2:0] RORI    = 5;
localparam [2:0] ROR_1   = 6; // ROR with instruction specified shift.
localparam [2:0] LSL_SAT = 7; // Shift left saturated.

// Wishbone CTI.
localparam [2:0] CTI_BURST    = 3'b010;
localparam [2:0] CTI_EOB      = 3'b111;

// Interrupt vectors.
localparam [31:0] RST_VECTOR   = 32'h00000000;
localparam [31:0] UND_VECTOR   = 32'h00000004;
localparam [31:0] SWI_VECTOR   = 32'h00000008;
localparam [31:0] PABT_VECTOR  = 32'h0000000C;
localparam [31:0] DABT_VECTOR  = 32'h00000010;
localparam [31:0] IRQ_VECTOR   = 32'h00000018;
localparam [31:0] FIQ_VECTOR   = 32'h0000001C;

// Branches
localparam  [1:0]    SNT     =       2'b00; // Strongly Not Taken.
localparam  [1:0]    WNT     =       2'b01; // Weakly Not Taken.
localparam  [1:0]    WT      =       2'b10; // Weakly Taken.
localparam  [1:0]    ST      =       2'b11; // Strongly Taken.

// Extension field bits.
localparam [31:0] ZAP_SRCDEST_EXTEND =  32 ;     // Data Src/Dest extend register for MEMOPS.
localparam [31:0] ZAP_DP_RB_EXTEND   =  32 ;     // Shift source extend.
localparam [31:0] ZAP_BASE_EXTEND    =  33 ;     // Base address register for MEMOPS.
localparam [31:0] ZAP_DP_RD_EXTEND   =  33 ;     // Destination source extend.
localparam [31:0] ZAP_DP_RA_EXTEND   =  34 ;     // ALU source extend. DDI0100E rn.
localparam [31:0] ZAP_OPCODE_EXTEND  =  35 ;     // To differentiate lower and higher for multiplication

/* verilator lint_on UNUSED */

// Turn the warning back on.
