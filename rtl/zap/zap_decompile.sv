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
// -- When running in simulation mode, this module will decompile binary    --
// -- ARM instructions to assembler instructions for debug purposes.        --
// -- When running in synthesis mode, the output of this module is tied     --       
// -- to a constant since this module really finds use only in debug.       --      
// -- Define DEBUG_EN during simulation to help in debugging.               -- 
// --                                                                       --
// ---------------------------------------------------------------------------



module zap_decompile #(parameter [31:0] INS_WDT = 32'd36) ( 
                input logic      [36-1:0]        i_instruction,  // 36-bit instruction into decode.
                input logic                      i_dav,          // Instruction valid.
                output logic      [64*8-1:0]     o_decompile     // 1024 bytes max of assembler string.
        );

`ifdef DEBUG_EN
                        /* ONLY IN SIMULATION */

                        `include "zap_defines.svh"
                        `include "zap_localparams.svh"

                        initial $display("DEBUG_EN defined in ZAP decompile. Use only for Sim.");
                        
                        always @*
                        begin
                                        if ( !i_dav ) 
                                        begin
                                                o_decompile = "IGNORE";                                                        
                                        end
                                        else if ( i_instruction ==? BLX1 )
                                        begin
                                                $sformat(o_decompile, "BLX1 H=%b %x", i_instruction[24], i_instruction[23:0]);
                                        end
                                        else if ( i_instruction ==? BLX2 )
                                        begin
                                                $sformat(o_decompile, "BLX2 r%d", i_instruction[3:0]);
                                        end
                                        else if ( i_instruction[27:24] == 4'b1110 && i_instruction[4] ) 
                                        begin
                                                if ( i_instruction[20] )  // Register <- CPSR
                                                        $sformat(o_decompile, "MRC%s", `ZAP_DECOMPILE_CCC);
                                                else                     // CPSR <- Register.
                                                        $sformat(o_decompile, "MCR%s", `ZAP_DECOMPILE_CCC);
                                        end
                                        else if ( i_instruction[27:25] == 3'b100 ) // LDM/STM
                                        begin
                                                if ( i_instruction[20] ) // Load
                                                        $sformat(o_decompile, "LDM%s %b %b %b", `ZAP_DECOMPILE_CCC, i_instruction[24:20], 
                                                                                i_instruction[19:16], i_instruction[15:0]); 
                                                else
                                                        $sformat(o_decompile, "STM%s %b %b %b", `ZAP_DECOMPILE_CCC, i_instruction[24:20], 
                                                                                i_instruction[19:16], i_instruction[15:0]); 
                                        end
                                        else 
                                        casez ( i_instruction[31:0] )
                                        SMLAxy, SMLAWy, SMLALxy,
                                        SMULWy, SMULxy:                                 decode_dsp_mult     ( i_instruction ); //
                        
                                        QADD,                                           
                                        QSUB,
                                        QDADD,
                                        QDSUB:                                          decode_sataddsub   ( i_instruction ); //       
                        
                                        CLZ_INSTRUCTION:                                decode_clz         ( i_instruction ); //
                                        BX_INST:                                        decode_bx          ( i_instruction ); //
                                        MRS:                                            decode_mrs         ( i_instruction ); //  
                                        MSR_IMMEDIATE:                                  decode_msr_immed   ( i_instruction ); //
                                        MSR:                                            decode_msr         ( i_instruction ); //
                                        DATA_PROCESSING_IMMEDIATE:                      decode_dp_immed    ( i_instruction ); //
                                        DATA_PROCESSING_REGISTER_SPECIFIED_SHIFT:       decode_dp_rss      ( i_instruction ); //
                                        DATA_PROCESSING_INSTRUCTION_SPECIFIED_SHIFT:    decode_dp_iss      ( i_instruction ); //
                                        BRANCH_INSTRUCTION:                             decode_branch      ( i_instruction ); //   
                                        LS_INSTRUCTION_SPECIFIED_SHIFT:                 decode_ls_iss      ( i_instruction ); //
                                        LS_IMMEDIATE:                                   decode_ls          ( i_instruction ); //
                                        MULT_INST:                                      decode_mult        ( i_instruction ); //
                                        LMULT_INST:                                     decode_lmult       ( i_instruction ); //
                                        HALFWORD_LS:                                    decode_halfword_ls ( i_instruction ); // 
                                        SOFTWARE_INTERRUPT:                             decode_swi         ( i_instruction ); //
                        
                                        default:
                                        begin
                                                o_decompile = "UNRECOGNIZED INSTRUCTION!";                                
                                        end
                                        endcase
                        end
                        
                        task automatic decode_clz ( input [INS_WDT-1:0] i_instruction );
                        begin
                                $sformat(o_decompile, "CLZ%s %0d %0d", `ZAP_DECOMPILE_CCC, i_instruction[15:12], i_instruction[3:0]);
                        end
                        endtask
                        
                        task automatic decode_dsp_mult ( input [INS_WDT-1:0] i_instruction );
                        begin:blk_ddspmult
                                logic [1:0] mul;
                                logic       y, x;
                        
                                mul = i_instruction[22:21];
                                y   = i_instruction[6];
                                x   = i_instruction[5]; 
                        
                                if ( mul == 2'b00 )
                                begin
                                        $sformat(o_decompile, "CC=%s SMLA%0b %0d %0d %0d %0d", 
                                                                `ZAP_DECOMPILE_CCC,
                                                                $unsigned({y,x}),
                                                                $unsigned(i_instruction[19:16]),
                                                                $unsigned(i_instruction[3:0]),
                                                                $unsigned(i_instruction[11:8]),
                                                                $unsigned(i_instruction[15:12]));
                                end
                                else if ( mul == 2'b01 && x == 1 && i_instruction[15:12] == 0 )
                                begin
                                        $sformat(o_decompile, "CC=%s SMULW%0b %0d %0d %0d", 
                                                                `ZAP_DECOMPILE_CCC,
                                                                $unsigned(y),
                                                                $unsigned(i_instruction[19:16]),
                                                                $unsigned(i_instruction[3:0]),
                                                                $unsigned(i_instruction[11:8]));                
                                end
                                else if ( mul == 2'b10 )
                                begin
                                        $sformat(o_decompile, "CC=%s SMLAL%0b %0d %0d %0d %0d",
                                                                `ZAP_DECOMPILE_CCC,
                                                                $unsigned({y,x}),
                                                                $unsigned(i_instruction[15:12]),
                                                                $unsigned(i_instruction[19:16]),
                                                                $unsigned(i_instruction[3:0]),
                                                                $unsigned(i_instruction[11:8]));
                                end
                                else if ( mul == 2'b11 && i_instruction[15:12] == 0 )
                                begin
                                        $sformat(o_decompile, "CC=%s SMUL%0b %0d %0d %0d", 
                                                                `ZAP_DECOMPILE_CCC,
                                                                $unsigned({y,x}),
                                                                $unsigned(i_instruction[19:16]),
                                                                $unsigned(i_instruction[3:0]),
                                                                $unsigned(i_instruction[11:8]));
                                end
                        end
                        endtask
                        
                        task automatic decode_sataddsub ( input [INS_WDT-1:0] i_instruction );
                        begin:blkdecodesataddsub
                                logic [8*8-1:0] opcode;
                        
                                if ( i_instruction[22:21] == 0 )
                                        opcode = "QADD";
                                else if ( i_instruction[22:21] == 1 )
                                        opcode = "QSUB";
                                else if ( i_instruction[22:21] == 2 )
                                        opcode = "QDADD";
                                else
                                        opcode = "QDSUB";
                        
                                $sformat(o_decompile, "CC=%s %s %0d %0d %0d", `ZAP_DECOMPILE_CCC, opcode, $unsigned(i_instruction[15:12]), 
                                                                                $unsigned(i_instruction[3:0]),
                                                                                $unsigned(i_instruction[19:16]));
                        end
                        endtask
                        
                        task automatic decode_swi ( input [INS_WDT-1:0] i_instruction );
                        begin
                                $sformat(o_decompile, "SWIAL %0d", $unsigned(i_instruction[24:0])); 
                        end
                        endtask
                        
                        task automatic decode_branch ( input [INS_WDT-1:0] i_instruction );
                        begin
                                if ( !i_instruction[24] )
                                        $sformat(o_decompile, "B%s %0d", `ZAP_DECOMPILE_CCC, $signed(i_instruction[23:0]));
                                else
                                        $sformat(o_decompile, "BL%s %0d", `ZAP_DECOMPILE_CCC, $signed(i_instruction[23:0]));
                        end
                        endtask
                        
                        task automatic decode_bx ( input [INS_WDT-1:0] i_instruction );
                        begin
                                $sformat(o_decompile, "BX%s %s", `ZAP_DECOMPILE_CCC, `ZAP_DECOMPILE_CRB );
                        end
                        endtask
                        
                        task automatic decode_dp_immed ( input [INS_WDT-1:0] i_instruction );
                        begin:blk111
                                logic [6*8-1:0] opcode; reg [4*8-1:0] cc, dest_reg, src_reg;
                                integer imm_amt, ror_amt;
                        
                                opcode   = `ZAP_DECOMPILE_COPCODE; 
                                cc       = `ZAP_DECOMPILE_CCC;
                                dest_reg = `ZAP_DECOMPILE_CRD; 
                                src_reg  = `ZAP_DECOMPILE_CRN;
                                imm_amt  = $unsigned(i_instruction[7:0]);
                                ror_amt  = $unsigned(i_instruction[11:8]);                        
                        
                                $sformat(o_decompile, "%s%s %s,%s,%0d ROR %0d", opcode, cc, dest_reg, src_reg, imm_amt, ror_amt);
                        end
                        endtask
                        
                        task automatic decode_dp_rss ( input [INS_WDT-1:0] i_instruction );
                        begin:bk222
                                logic [4*8-1:0] cc, dest_reg, src_reg, sh_src_reg, shamt_reg;
                                logic [6*8-1:0] opcode;
                                logic [5*8-1:0] shtype;
                                integer shamt;
                        
                                opcode      = `ZAP_DECOMPILE_COPCODE;
                                cc          = `ZAP_DECOMPILE_CCC;
                                dest_reg    = `ZAP_DECOMPILE_CRD;
                                src_reg     = `ZAP_DECOMPILE_CRN;
                                shtype      = `ZAP_DECOMPILE_CSHTYPE;
                                sh_src_reg  = `ZAP_DECOMPILE_CRM;
                                shamt_reg   = `ZAP_DECOMPILE_CRS;
                        
                                $sformat(o_decompile, "%s%s %s,%s,%s %s %s", opcode, cc, dest_reg, src_reg, sh_src_reg, shtype, shamt_reg);
                        end
                        endtask
                        
                        task automatic decode_dp_iss ( input [INS_WDT-1:0] i_instruction );
                        begin:blk333
                                logic [4*8-1:0] cc, dest_reg, src_reg, sh_src_reg; 
                                logic [6*8-1:0] opcode;
                                logic [4*8-1:0] shtype;
                                integer shamt;
                        
                                opcode      = `ZAP_DECOMPILE_COPCODE;
                                cc          = `ZAP_DECOMPILE_CCC;
                                dest_reg    = `ZAP_DECOMPILE_CRD;
                                src_reg     = `ZAP_DECOMPILE_CRN;
                                shtype      = `ZAP_DECOMPILE_CSHTYPE;
                                sh_src_reg  = `ZAP_DECOMPILE_CRM;
                                shamt       = $unsigned(i_instruction[11:7]);
                        
                                $sformat(o_decompile, "%s%s %s,%s,%s %s %0d", opcode, cc, dest_reg, src_reg, sh_src_reg, shtype, shamt);
                        end
                        endtask
                        
                        task automatic decode_mrs ( input [INS_WDT-1:0] i_instruction );
                        begin
                                if ( i_instruction[22] ) // SPSR
                                        $sformat(o_decompile, "MRS%s %s,SPSR",`ZAP_DECOMPILE_CCC, `ZAP_DECOMPILE_CRD); 
                                else                     // CPSR
                                        $sformat(o_decompile, "MRS%s %s,CPSR",`ZAP_DECOMPILE_CCC, `ZAP_DECOMPILE_CRD);
                        end
                        endtask
                        
                        task automatic decode_msr ( input [INS_WDT-1:0] i_instruction );
                        begin
                                if ( i_instruction[22] ) // SPSR
                                        $sformat(o_decompile, "MSR%s SPSR,%s",`ZAP_DECOMPILE_CCC, `ZAP_DECOMPILE_CRB); 
                                else
                                        $sformat(o_decompile, "MSR%s CPSR,%s", `ZAP_DECOMPILE_CCC, `ZAP_DECOMPILE_CRB);
                        end
                        endtask
                        
                        task automatic decode_msr_immed ( input [INS_WDT-1:0] i_instruction );
                        begin
                                 if ( i_instruction[22] ) // SPSR
                                        $sformat(o_decompile, "MSR%s SPSR,%dROR%d",`ZAP_DECOMPILE_CCC, $unsigned(i_instruction[7:0]), $unsigned(i_instruction[11:8])); 
                                else
                                        $sformat(o_decompile, "MSR%s CPSR,%dROR%d",`ZAP_DECOMPILE_CCC, $unsigned(i_instruction[7:0]), $unsigned(i_instruction[11:8]));
                        end
                        endtask
                        
                        // LS ISS
                        task automatic decode_ls_iss ( input [INS_WDT-1:0] i_instruction );
                        begin:blk2323
                                logic [32*8-1:0] ls_iss_offset;
                        
                                $sformat(ls_iss_offset, "%s%s%d", `ZAP_DECOMPILE_CRB, `ZAP_DECOMPILE_CSHTYPE, $unsigned(i_instruction[11:7]));
                        
                                // If word load
                                if ( i_instruction[20] ) 
                                        if ( !i_instruction[22] ) 
                                        begin
                                        case ( {i_instruction[24], i_instruction[21]} ) 
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%s %s[%s,%s]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"LDR%s %s[%s,%s]" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"LDR%s %s[%s],%s" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%s T%s[%s],%s", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                        else
                                        begin
                                        case( {i_instruction[24], i_instruction[21]}  )
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%sB %s[%s,%s]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"LDR%sB %s[%s,%s]" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"LDR%sB %s[%s],%s" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%sB T%s[%s],%s", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                else
                                        if ( !i_instruction[22] ) 
                                        begin
                                        case ( {i_instruction[24], i_instruction[21]} ) 
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%s %s[%s,%s]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"STR%s %s[%s,%s]",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"STR%s %s[%s],%s",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%s T%s[%s],%s", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                        else
                                        begin
                                        case( {i_instruction[24], i_instruction[21]} )
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%sB %s[%s,%s]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"STR%sB %s[%s,%s]",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"STR%sB %s[%s],%s",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%sB T%s[%s],%s", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                        end
                        endtask
                        
                        // LS immediate
                        task automatic decode_ls ( input [INS_WDT-1:0] i_instruction );
                        begin:blk4343
                                integer ls_iss_offset; // Forgive the naming convention...
                        
                                ls_iss_offset = i_instruction[11:0];
                        
                                // If word load
                                if ( i_instruction[20] ) 
                                        if ( !i_instruction[22] ) 
                                        begin
                                        case ( {i_instruction[24], i_instruction[21]} ) 
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%s %s[%s,%0d]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"LDR%s %s[%s,%0d]" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"LDR%s %s[%s],%0d" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%s T%s[%s],%0d", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                        else
                                        begin
                                        case( {i_instruction[24], i_instruction[21]}  )
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%sB %s[%s,%0d]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"LDR%sB %s[%s,%0d]" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"LDR%sB %s[%s],%0d" , `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"LDR%sB T%s[%s],%0d", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                else
                                        if ( !i_instruction[22] ) 
                                        begin
                                        case ( {i_instruction[24], i_instruction[21]} ) 
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%s %s[%s,%0d]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"STR%s %s[%s,%0d]",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"STR%s %s[%s],%0d",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%s T%s[%s],%0d", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                                        else
                                        begin
                                        case( {i_instruction[24], i_instruction[21]} )
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%sB %s[%s,%0d]!", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex with writeback
                                        {1'd1, 1'd0}: $sformat(o_decompile,"STR%sB %s[%s,%0d]",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Preindex without writeback
                                        {1'd0, 1'd0}: $sformat(o_decompile,"STR%sB %s[%s],%0d",  `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset); // Post index
                                        {1'd1, 1'd1}: $sformat(o_decompile,"STR%sB T%s[%s],%0d", `ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRD1,`ZAP_DECOMPILE_CRN1, ls_iss_offset);// Force user view of memory.
                                        endcase
                                        end
                        
                        end
                        endtask
                        
                        // Mult. MUL, MLA
                        task automatic decode_mult ( input [INS_WDT-1:0] i_instruction );
                        begin
                                if ( i_instruction[21] == 1'd0 ) 
                                        $sformat(o_decompile, "MUL%s %s,%s,%s",`ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRN,`ZAP_DECOMPILE_CRD,arch_reg_num(i_instruction[11:8]));      
                                else
                                        $sformat(o_decompile, "MLA%s %s,%s,%s,%s",`ZAP_DECOMPILE_CCC,`ZAP_DECOMPILE_CRN,`ZAP_DECOMPILE_CRD,arch_reg_num(i_instruction[11:8]), arch_reg_num(i_instruction[3:0]));
                        end
                        endtask
                        
                        // Long Mult. UMULL, UMLAL, SMULL, SMLAL
                        task automatic decode_lmult ( input [INS_WDT-1:0] i_instruction );
                        begin
                              case(i_instruction[23:21])
                                `ZAP_DECOMPILE_XUMULL: $sformat(o_decompile, "UMULL %s:%s=%s*%s" ,i_instruction[19:16], i_instruction[15:12], i_instruction[3:0], i_instruction[11:8] );  
                                `ZAP_DECOMPILE_XUMLAL: $sformat(o_decompile, "UMLAL %s:%s+=%s*%s",i_instruction[19:16], i_instruction[15:12], i_instruction[3:0], i_instruction[11:8] );
                                `ZAP_DECOMPILE_XSMULL: $sformat(o_decompile, "SMULL %s:%s=%s*%s" ,i_instruction[19:16], i_instruction[15:12], i_instruction[3:0], i_instruction[11:8] );
                                `ZAP_DECOMPILE_XSMLAL: $sformat(o_decompile, "SMLAL %s:%s+=%s*%s",i_instruction[19:16], i_instruction[15:12], i_instruction[3:0], i_instruction[11:8] );
                              endcase 
                        end
                        endtask
                        
                        task automatic decode_halfword_ls ( input [INS_WDT-1:0] i_instruction );
                        begin
                              o_decompile = "***HALFWORD LD/ST***"; 
                        end
                        endtask
                        
                        // Returns shift type.
                        function [4*8-1:0] get_shtype ( input [2:0] x );
                        begin
                                case(x)
                                0: get_shtype = "LSL"; 
                                1: get_shtype = "LSR";
                                2: get_shtype = "ASR";
                                3: get_shtype = "ROR";
                                4: get_shtype = "RRC";
                                5: get_shtype = "RORI";
                                6: get_shtype = "ROR1";
                                7: get_shtype = "<-->";
                                endcase
                        end
                        endfunction
                        
                        // Returns opcode in english.
                        function [6*8-1:0] get_opcode ( input [4:0] x ); 
                        begin
                                case(x)
                                0: get_opcode = "AND"        ;  //= 0;
                                1: get_opcode = "EOR"        ;  //= 1;
                                2: get_opcode = "SUB"        ;  //= 2;
                                3: get_opcode = "RSB"        ;  //= 3;
                                4: get_opcode = "ADD"        ;  //= 4;
                                5: get_opcode = "ADC"        ;  //= 5;
                                6: get_opcode = "SBC"        ;  //= 6;
                                7: get_opcode = "RSC"        ;  //= 7;
                                8: get_opcode = "TST"        ;  //= 8;
                                9: get_opcode = "TEQ"        ;  //= 9;
                                10:get_opcode = "CMP"        ;  //= 10;
                                11:get_opcode = "CMN"        ;  //= 11;
                                12:get_opcode = "ORR"        ;  //= 12;
                                13:get_opcode = "MOV"        ;  //= 13;
                                14:get_opcode = "BIC"        ;  //= 14;
                                15:get_opcode = "MVN"        ;  //= 15;
                                16:get_opcode = "MUL"        ;  //= 16; // Multiply ( 32 x 32 = 32 ) -> Translated to MAC.
                                17:get_opcode = "MLA"        ;  //= 17; // Multiply-Accumulate ( 32 x 32 + 32 = 32 ). 
                                18:get_opcode = "FMOV"       ;  //= 18; 
                                19:get_opcode = "MMOV"       ;  //= 19; 
                                20:get_opcode = "UMLALL"     ;  //= 20; // Unsigned multiply accumulate (Write lower reg).
                                21:get_opcode = "UMLALH"     ;  //= 21;
                                22:get_opcode = "SMLALL"     ;  //= 22; // Signed multiply accumulate (Write lower reg).
                                23:get_opcode = "SMLALH"     ;  //= 23;
                                24:get_opcode = "CLZ"        ;  //= 24; // Count Leading zeros.
                                default: get_opcode = "<-->";
                                endcase
                        end
                        endfunction
                        
                        // Returns arch reg number (5 bit number as input.)
                        function [4*8-1:0] arch_reg_num ( input [4:0] reg_num );
                        begin:blk434234
                                logic [4*8-1:0] x;
                        
                                case(reg_num)
                                        5'd0 :  x = "R0  ";
                                        5'd1 :  x = "R1  ";
                                        5'd2 :  x = "R2  ";
                                        5'd3 :  x = "R3  ";
                                        5'd4 :  x = "R4  ";
                                        5'd5 :  x = "R5  ";
                                        5'd6 :  x = "R6  ";
                                        5'd7 :  x = "R7  ";
                                        5'd8 :  x = "R8  ";
                                        5'd9 :  x = "R9  ";
                                        5'd10 : x = "R10 ";
                                        5'd11 : x = "R11 ";
                                        5'd12 : x = "R12 ";
                                        5'd13 : x = "SP  ";
                                        5'd14 : x = "LR  ";
                                        5'd15 : x = "PC  ";
                                        5'd16 : x = "RAZ ";
                                        5'd17 : x = "CPSR";
                                        5'd18 : x = "R8x ";
                                        5'd19 : x = "R9x ";
                                        5'd20 : x = "R10x";
                                        5'd21 : x = "R11x";
                                        5'd22 : x = "R12x";
                                        5'd23 : x = "R13x";
                                        5'd24 : x = "R14x";
                                        5'd25 : x = "DMY0";
                                        5'd26 : x = "DMY1";
                                        5'd27 : x = "SPSR";
                                        5'd28 : x = "<-->";
                                        5'd29 : x = "<-->";
                                        5'd30 : x = "<-->";
                                        5'd31 : x = "<-->";
                                   endcase        
                        
                                arch_reg_num = x;
                        end
                        endfunction
                        
                        // Returns a text version of the condition code.
                        function [2*8-1:0] cond_code ( input [3:0] cond );
                        begin: blk49329483
                                logic [2*8-1:0] ok;        
                        
                                case(cond)
                                EQ:     ok = "EQ";
                                NE:     ok = "NE";
                                CS:     ok = "CS";
                                CC:     ok = "CC";
                                MI:     ok = "MI";
                                PL:     ok = "PL";
                                VS:     ok = "VS";
                                VC:     ok = "VC";
                                HI:     ok = "HI";
                                LS:     ok = "LS";
                                GE:     ok = "GE";
                                LT:     ok = "LT";
                                GT:     ok = "GT";
                                LE:     ok = "LE";
                                AL:     ok = "AL";
                                NV:     ok = "NV";
                                endcase
                        
                                cond_code = ok;
                        end
                        endfunction

`else 

                        logic  unused;
                        always_comb unused = |{1'd1, i_instruction, i_dav, INS_WDT};
                        always_comb o_decompile = {32'd512{unused}}; // In synthesis mode.

`endif

endmodule // zap_decompile.v



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
