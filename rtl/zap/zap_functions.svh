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

// Swap data based on SEL. Use on wishbone input.
function automatic [31:0] be_32 (input [31:0] dat, input [3:0] sel);
        case(sel)
        4'b1000: return {24'd0, dat[31:24]};
        4'b0100: return {16'd0, dat[23:16], 8'd0};
        4'b0010: return  {8'd0, dat[15:8], 16'd0};
        4'b0001: return {dat[7:0], 24'd0};
        4'b1100: return {16'd0, dat[31:16]};
        4'b0011: return {dat[15:0], 16'd0};
        default: return dat;
        endcase
endfunction

// Swap sel based on value
function automatic [3:0] be_sel_32 (input [3:0] sel);
        case(sel)
        4'b0001: return 4'b1000;
        4'b0010: return 4'b0100;
        4'b0100: return 4'b0010;
        4'b1000: return 4'b0001;
        4'b0011: return 4'b1100;
        4'b1100: return 4'b0011;
        4'b1111: return sel;
        default: return {4{1'dx}}; // Synthesis will OPTIMIZE. OK to do for FPGA synthesis.
        endcase
endfunction

//
// Function to check if condition is satisfied for instruction
// execution. Returns 1 if satisfied, 0 if not.
//

function automatic is_cc_satisfied
(
        input [3:0] cc,         // 31:28 of the instruction.
        input [3:0] fl          // CPSR flags.
);
logic ok,n,z,c,v;
begin: blk1
        {n,z,c,v} = fl;

        case(cc)
        EQ:     ok =  z;
        NE:     ok = !z;
        CS:     ok = c;
        CC:     ok = !c;
        MI:     ok = n;
        PL:     ok = !n;
        VS:     ok = v;
        VC:     ok = !v;
        HI:     ok = c && !z;
        LS:     ok = !c || z;
        GE:     ok = (n == v);
        LT:     ok = (n != v);
        GT:     ok = (n == v) && !z;
        LE:     ok = (n != v) || z;

        AL:     ok = 1'd1; // Always execute.
        NV:     ok = 1'd0; // Never eXecute.

        default:ok = 'x;   // Propagate X.
        endcase

        is_cc_satisfied = ok;
end
endfunction

//
// Translate function.
//
//
// Used to implement CPU modes. The register file is basically a flat array
// of registers. Based on mode, we select some of those to implement banking.
//

function automatic  [5:0] translate (

        input [4:0] index,      // Requested instruction index.
        input [4:0] cpu_mode    // Current CPU mode.

);
begin
        // User/System mode map.
        case ( index )
                      0:      translate = PHY_USR_R0;
                      1:      translate = PHY_USR_R1;
                      2:      translate = PHY_USR_R2;
                      3:      translate = PHY_USR_R3;
                      4:      translate = PHY_USR_R4;
                      5:      translate = PHY_USR_R5;
                      6:      translate = PHY_USR_R6;
                      7:      translate = PHY_USR_R7;
                      8:      translate = PHY_USR_R8;
                      9:      translate = PHY_USR_R9;
                      10:     translate = PHY_USR_R10;
                      11:     translate = PHY_USR_R11;
                      12:     translate = PHY_USR_R12;
                      13:     translate = PHY_USR_R13;
                      14:     translate = PHY_USR_R14;
                      15:     translate = PHY_PC;

            RAZ_REGISTER:     translate = PHY_RAZ_REGISTER;
               ARCH_CPSR:     translate = PHY_CPSR;
          ARCH_CURR_SPSR:     translate = PHY_CPSR;

              //
              // USR2 registers are looped back to USER registers.
              // in all modes
              //
              ARCH_USR2_R8:   translate = PHY_USR_R8;
              ARCH_USR2_R9:   translate = PHY_USR_R9;
              ARCH_USR2_R10:  translate = PHY_USR_R10;
              ARCH_USR2_R11:  translate = PHY_USR_R11;
              ARCH_USR2_R12:  translate = PHY_USR_R12;
              ARCH_USR2_R13:  translate = PHY_USR_R13;
              ARCH_USR2_R14:  translate = PHY_USR_R14;

              ARCH_DUMMY_REG0:translate = PHY_DUMMY_REG0;
              ARCH_DUMMY_REG1:translate = PHY_DUMMY_REG1;
                default      :translate = {1'd0, index};
        endcase

        // Override per specific mode.
        case ( cpu_mode )
                FIQ:
                begin
                        case ( index )
                                8:      translate = PHY_FIQ_R8;
                                9:      translate = PHY_FIQ_R9;
                                10:     translate = PHY_FIQ_R10;
                                11:     translate = PHY_FIQ_R11;
                                12:     translate = PHY_FIQ_R12;
                                13:     translate = PHY_FIQ_R13;
                                14:     translate = PHY_FIQ_R14;
                    ARCH_CURR_SPSR:     translate = PHY_FIQ_SPSR;
                           default:;
                        endcase
                end

                IRQ:
                begin
                        case ( index )
                                13:     translate = PHY_IRQ_R13;
                                14:     translate = PHY_IRQ_R14;
                    ARCH_CURR_SPSR:     translate = PHY_IRQ_SPSR;
                          default:;
                        endcase
                end

                ABT:
                begin
                        case ( index )
                                13:     translate = PHY_ABT_R13;
                                14:     translate = PHY_ABT_R14;
                    ARCH_CURR_SPSR:     translate = PHY_ABT_SPSR;
                           default:;
                        endcase
                end

                UND:
                begin
                        case ( index )
                                13:     translate = PHY_UND_R13;
                                14:     translate = PHY_UND_R14;
                    ARCH_CURR_SPSR:     translate = PHY_UND_SPSR;
                           default:;
                        endcase
                end

                SVC:
                begin
                        case ( index )
                                13:     translate = PHY_SVC_R13;
                                14:     translate = PHY_SVC_R14;
                    ARCH_CURR_SPSR:     translate = PHY_SVC_SPSR;
                           default:;
                        endcase
                end

                USR:;
                SYS:;

                default:
                begin
                        translate = 'x;
                end
        endcase

        if ( cpu_mode inside {USR,SYS,FIQ,IRQ,SVC,UND,ABT} )
        begin
                assert((index == ARCH_USR2_R8 && translate  == PHY_USR_R8) || index !=ARCH_USR2_R8 )
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R9 && translate  == PHY_USR_R9) || index !=ARCH_USR2_R9 )
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R10 && translate == PHY_USR_R10) || index !=ARCH_USR2_R10)
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R11 && translate == PHY_USR_R11) || index !=ARCH_USR2_R11)
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R12 && translate == PHY_USR_R12) || index !=ARCH_USR2_R12)
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R13 && translate == PHY_USR_R13) || index !=ARCH_USR2_R13)
                else $fatal(2, "USR loopback fail");

                assert((index == ARCH_USR2_R14 && translate == PHY_USR_R14) || index !=ARCH_USR2_R14)
                else $fatal(2, "USR loopback fail");
        end
end
endfunction


