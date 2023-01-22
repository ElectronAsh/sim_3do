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
// Examines TLB entries to authorize access.
//

`include "zap_defines.svh"

module zap_tlb_check #(

        parameter logic [31:0] LPAGE_TLB_ENTRIES   = 32'd8,
        parameter logic [31:0] SPAGE_TLB_ENTRIES   = 32'd8,
        parameter logic [31:0] SECTION_TLB_ENTRIES = 32'd8,
        parameter logic [31:0] FPAGE_TLB_ENTRIES   = 32'd8

)
(
input logic                              i_clk,          // Clock signal.
input logic                              i_clkena,       // Clock enable.

input logic                              i_mmu_en,       // MMU enable.

input logic [31:0]                       i_va,           // Virtual address.
input logic                              i_rd,           // Read request.
input logic                              i_wr,           // Write request.

input logic [ZAP_CPSR_MODE:0]             i_cpsr,         // CPSR.
input logic [1:0]                        i_sr,           // Status Register.
input logic [31:0]                       i_dac_reg,      // Domain Access Control Register.

input logic [`ZAP_SPAGE_TLB_WDT  -1:0]   i_sptlb_rdata,  // Small page TLB.
input logic                              i_sptlb_rdav,   // TLB entry valid.

input logic [`ZAP_LPAGE_TLB_WDT  -1:0]   i_lptlb_rdata,  // Large page TLB read data.
input logic                              i_lptlb_rdav,   // Large page TLB valid.

input logic [`ZAP_SECTION_TLB_WDT-1:0]   i_setlb_rdata,  // Small page TLB read data.
input logic                              i_setlb_rdav,   // Small page TLB valid.

input logic [`ZAP_FPAGE_TLB_WDT-1:0]     i_fptlb_rdata,  // Fine page TLB read data.
input logic                              i_fptlb_rdav,   // Fine page TLB valid.

output logic                            o_walk,         // Signal page walk.
output logic [7:0]                      o_fsr,          // FSR. 0 means all OK.
output logic [31:0]                     o_far,          // Fault Address Register.
output logic                            o_cacheable,    // Cacheble stats of the PTE.
output logic [31:0]                     o_phy_addr      // Physical address.
);

`include "zap_localparams.svh"

localparam logic APSR_BAD = 1'd0;
localparam logic APSR_OK  = 1'd1;

logic [3:0] match;

// 0: Small Page
assign  match[0] = (i_sptlb_rdata[`ZAP_SPAGE_TLB__TAG] == i_va[`ZAP_VA__SPAGE_TAG]) && i_sptlb_rdav;

// 1: Large Page
assign  match[1] = (i_lptlb_rdata[`ZAP_LPAGE_TLB__TAG] == i_va[`ZAP_VA__LPAGE_TAG]) && i_lptlb_rdav;

// 2: Section
assign  match[2] = (i_setlb_rdata[`ZAP_SECTION_TLB__TAG] == i_va[`ZAP_VA__SECTION_TAG]) && i_setlb_rdav;

// 3: Fine Page
assign  match[3] = (i_fptlb_rdata[`ZAP_FPAGE_TLB__TAG] == i_va[`ZAP_VA__FPAGE_TAG]) && i_fptlb_rdav;

always @ ( posedge i_clk )
begin
        if ( i_clkena )
        begin : tlb_match_logic

                logic dummy;
                logic unused;

                dummy  <= 1'd0;
                unused <= |dummy;

                // Default values. Taken for MMU disabled esp.
                o_fsr       <= 0;        // No fault.
                o_far       <= i_va;     // Fault address.
                o_phy_addr  <= i_va;     // VA = PA
                o_walk      <= 0;        // Walk disabled.
                o_cacheable <= 0;        // Uncacheable.


                if ( i_mmu_en && (i_rd || i_wr) ) // MMU enabled and R/W operation.
                begin
                        case ( match[3:0] )

                        4'b0001:
                        begin
                                // Entry found in small page TLB.
                                o_fsr <= get_fsr_spage
                                (
                                        i_va[`ZAP_VA__SPAGE_AP_SEL],
                                        i_cpsr[ZAP_CPSR_MODE:0] == USR,
                                        i_rd,
                                        i_wr,
                                        i_sr,
                                        i_dac_reg,
                                        i_sptlb_rdata[15:0]
                                ) ;

                                o_phy_addr <= {i_sptlb_rdata[`ZAP_SPAGE_TLB__BASE], i_va[11:0]};
                                {dummy, o_cacheable} <= i_sptlb_rdata[`ZAP_SECTION_TLB__CB] >> 1;

                        end

                        4'b0010:
                        begin
                                // Entry found in large page TLB.
                                o_fsr <= get_fsr_lpage
                                (
                                        i_va[`ZAP_VA__LPAGE_AP_SEL],
                                        i_cpsr[ZAP_CPSR_MODE:0] == USR,
                                        i_rd,
                                        i_wr,
                                        i_sr,
                                        i_dac_reg,
                                        i_lptlb_rdata[15:0]
                                ) ;

                                o_phy_addr <= {i_lptlb_rdata[`ZAP_LPAGE_TLB__BASE], i_va[15:0]};
                                {dummy, o_cacheable} <= i_lptlb_rdata[`ZAP_LPAGE_TLB__CB] >> 1;
                        end

                        4'b0100:
                        begin
                                // Entry found in section TLB.
                                o_fsr <= get_fsr_section
                                (
                                        i_cpsr[ZAP_CPSR_MODE:0] == USR,
                                        i_rd,
                                        i_wr,
                                        i_sr,
                                        i_dac_reg,
                                        i_setlb_rdata[19:0]
                                ) ;

                                o_phy_addr <= {i_setlb_rdata[`ZAP_SECTION_TLB__BASE], i_va[19:0]};
                                {dummy, o_cacheable} <= i_setlb_rdata[`ZAP_SECTION_TLB__CB] >> 1;
                        end

                        4'b1000:
                        begin
                                // Entry found in fine page TLB.
                                o_fsr <= get_fsr_fpage
                                (
                                        i_cpsr[ZAP_CPSR_MODE:0] == USR,
                                        i_rd,
                                        i_wr,
                                        i_sr,
                                        i_dac_reg,
                                        i_fptlb_rdata[9:0]
                                );

                                o_phy_addr <= {i_fptlb_rdata[`ZAP_FPAGE_TLB__BASE], i_va[9:0]};
                                {dummy, o_cacheable} <= i_fptlb_rdata[`ZAP_FPAGE_TLB__CB] >> 1;
                        end

                        4'b0000:
                        begin
                                // No match. Trigger TLB walk.
                                o_walk <= 1'd1;
                        end

                        default: // Mimics full case.
                        begin
                                //
                                // OK to assign X. Never happens. Synthsis wil
                                // OPTIMIZE. OK to do for FPGA synthesis.
                                //
                                o_fsr       <= 'X;
                                o_phy_addr  <= 'X;
                                o_walk      <= 'X;
                                o_far       <= 'X;
                                o_cacheable <= 'X;
                        end
                        endcase

                end // Else MMU disabled.
        end : tlb_match_logic
end

////////////////
// Functions
////////////////

function automatic [7:0] get_fsr_fpage (           // Return 0 means OK to access else is a valid FSR.
input                   user, rd, wr,              // Access properties.
input [1:0]             sr,                        // S and R bits.
input [15:0][1:0]       dac_reg,                   // DAC register.
input [9:0]             tlb                        // TLB entry.
);

logic [3:0]  apsr; // Concat of AP and SR.
logic [1:0]  dac;  // DAC bits.

/* verilator lint_off VARHIDDEN */
logic        unused;
/* verilator lint_on VARHIDDEN */

begin
         unused = |{tlb[1:0], tlb[`ZAP_FPAGE_TLB__CB]};

         apsr[3:2] = tlb [ `ZAP_FPAGE_TLB__AP ];
          dac[1:0] = dac_reg[tlb [ `ZAP_FPAGE_TLB__DAC_SEL ]];
         apsr[1:0] = sr[1:0];

        case(dac)

        DAC_MANAGER: return '0; // No fault.

        DAC_CLIENT:
                if ( is_apsr_ok ( user, rd, wr, apsr ) == APSR_OK )
                begin
                        return '0; // No fault.
                end
                else
                begin
                        return {tlb[`ZAP_FPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT};
                end

        default: return {tlb[`ZAP_FPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   };

        endcase
end

endfunction

function automatic [7:0] get_fsr_section (             // Return 0 means OK to access else is a valid FSR.
input                   user, rd, wr,                  // Access properties.
input [1:0]             sr,                            // S and R bits.
input [15:0][1:0]       dac_reg,                       // DAC register.
input [19:0]            tlb                            // TLB entry.
);

logic [3:0]  apsr; // Concat of AP and SR.
logic [1:0]  dac;  // DAC bits.
logic        unused;

begin
        unused = |{tlb[19:12], tlb[9], tlb[4], tlb[`ZAP_SECTION_TLB__CB]};

        // Get AP and DAC.
        apsr[3:2]  = tlb     [ `ZAP_SECTION_TLB__AP ];
        dac[1:0]   = dac_reg [tlb [ `ZAP_SECTION_TLB__DAC_SEL ]];
        apsr[1:0]  = sr      [1:0];

        // Generate error based on DAC.
        if ( tlb[1:0] == 2'b00 )
        begin
                return {tlb[`ZAP_L1_SECTION__DAC_SEL], FSR_SECTION_TRANSLATION_FAULT};
        end
        else if ( tlb[1:0] == 2'b11 )
        begin
                return {tlb[`ZAP_L1_SECTION__DAC_SEL], FSR_L1_EXTERNAL_ABORT};
        end
        else
        begin
                case(dac)
                DAC_MANAGER: return '0; // No fault.
                DAC_CLIENT:
                        if ( is_apsr_ok ( user, rd, wr, apsr ) == APSR_OK )
                        begin
                                return '0; // No fault.
                        end
                        else
                        begin
                                 return {tlb[`ZAP_SECTION_TLB__DAC_SEL], FSR_SECTION_PERMISSION_FAULT};
                        end
                default: return {tlb[`ZAP_SECTION_TLB__DAC_SEL], FSR_SECTION_DOMAIN_FAULT};
                endcase
        end
end

endfunction

function automatic [7:0] get_fsr_spage (               // Return 0 means OK to access else is a valid FSR.
input   [1:0]           ap_sel,                        // AP sel bits. dont care for sections or fine pages.
input                   user, rd, wr,                  // Access properties.
input [1:0]             sr,                            // S and R bits.
input [15:0][1:0]       dac_reg,                       // DAC register.
input [15:0]            tlb                            // TLB entry.
);

logic [3:0]  apsr; // Concat of AP and SR.
logic [1:0]  dac;  // DAC bits.

/* verilator lint_off VARHIDDEN */
logic  [5:0] unused;
/* verilator lint_on VARHIDDEN */

begin
        // Get AP and DAC.
        {unused, apsr[3:2]}     = (tlb  [ `ZAP_SPAGE_TLB__AP ]) >> ({30'd0, ap_sel} << 32'd1);
        dac[1:0]                = dac_reg [tlb[ `ZAP_SPAGE_TLB__DAC_SEL ]];
        apsr[1:0]               = sr[1:0];

        unused[1:0]            |= tlb[`ZAP_SPAGE_TLB__CB];

        if ( tlb[1:0] == 2'b00 )
        begin
                return {tlb[`ZAP_L1_PAGE__DAC_SEL], FSR_PAGE_TRANSLATION_FAULT};
        end
        else if ( tlb[1:0] == 2'b11 )
        begin
                return {tlb[`ZAP_L1_PAGE__DAC_SEL], FSR_L2_EXTERNAL_ABORT};
        end
        else
        begin
                case(dac)

                DAC_MANAGER: return '0; // No fault.

                DAC_CLIENT:
                        if ( is_apsr_ok ( user, rd, wr, apsr ) == APSR_OK )
                        begin
                                return '0; // No fault.
                        end
                        else
                        begin
                                return {tlb[`ZAP_SPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT};
                        end

                default: return {tlb[`ZAP_SPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT};

                endcase
        end
end
endfunction

function automatic [7:0] get_fsr_lpage (               // Return 0 means OK to access else is a valid FSR.
input   [1:0]           ap_sel,                        // AP sel bits. dont care for sections or fine pages.
input                   user, rd, wr,                  // Access properties.
input [1:0]             sr,                            // S and R bits.
input [15:0][1:0]       dac_reg,                       // DAC register.
input [15:0]            tlb                            // TLB entry.
);

logic [3:0]  apsr; // Concat of AP and SR.
logic [1:0]  dac;  // DAC bits.
logic [5:0]  dummy;// 30-bit dummy variable. UNUSED.


/* verilator lint_off VARHIDDEN */
logic        unused;
/* verilator lint_on VARHIDDEN */

begin
        unused = |{dummy, tlb[1:0], tlb[`ZAP_LPAGE_TLB__CB]};

        // Get AP and DAC.

        {dummy, apsr[3:2]} = (tlb[ `ZAP_LPAGE_TLB__AP ]) >> ({30'd0, ap_sel} << 32'd1);
        dac[1:0]           = dac_reg[tlb[ `ZAP_LPAGE_TLB__DAC_SEL ]];
        apsr[1:0]          = sr[1:0];

        case(dac)

        DAC_MANAGER:return '0; // No fault.

        DAC_CLIENT:
                if ( is_apsr_ok ( user, rd, wr, apsr ) == APSR_OK )
                begin
                        return '0; // No fault.
                end
                else
                begin
                        return {tlb[`ZAP_LPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT};
                end

        default:return {tlb[`ZAP_LPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   };

        endcase
end

endfunction

//
// Function to check APSR bits.
//
// Returns 0 for failure, 1 for okay.
// Checks AP and SR bits.
//

function automatic is_apsr_ok ( input user, input rd, input wr, input [3:0] apsr);
logic x;
begin
        x = APSR_BAD; // Assume fail.

        casez (apsr)
                APSR_NA_NA: x = APSR_BAD;               // No access.
                APSR_RO_RO: x = !wr;                    // Reads allowed for all.
                APSR_RO_NA: x = !user && rd;            // Only kernel reads.
                APSR_RW_NA: x = !user;                  // Only kernel access.
                APSR_RW_RO: x = !user | (user && rd);   // User RO, Kernel RW.
                APSR_RW_RW: x = APSR_OK;                // Grant all the time.
                default   : x = APSR_BAD;               // Deny all the time.
        endcase

        // Assign to function. Return.
        is_apsr_ok = x;
end
endfunction

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
