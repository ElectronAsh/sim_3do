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
// --  Examines TLB entries to authorize access. Purely combo logic.          --                     
// --                                                                         --  
// -----------------------------------------------------------------------------

`default_nettype none

module zap_tlb_check (   // ZAP TLB Processing Logic.

i_mmu_en,       // MMU enable.

// Dynamics
i_va,           // Virtual address.
i_rd,           // WB rd.
i_wr,           // WB wr.

// Static almost.
i_cpsr,
i_sr,
i_dac_reg,

// Data from TLB dist RAMs.
i_sptlb_rdata, i_sptlb_rdav,
i_lptlb_rdata, i_lptlb_rdav,
i_setlb_rdata, i_setlb_rdav,

// Outputs to other units.
o_walk,                 // Need to page walk.
o_fsr,                  // FSR.
o_far,                  // FAR. 0 means no fault. This is a 4-bit number.
o_cacheable,            // Cacheable based on PTE.
o_phy_addr              // Physical address.

);

// Pass this from top.
parameter LPAGE_TLB_ENTRIES   = 8;
parameter SPAGE_TLB_ENTRIES   = 8;
parameter SECTION_TLB_ENTRIES = 8;

`include "zap_localparams.vh"
`include "zap_defines.vh"
`include "zap_functions.vh"

input wire                              i_mmu_en;       // MMU enable.

input wire [31:0]                       i_va;           // Virtual address.
input wire                              i_rd;           // Read request.
input wire                              i_wr;           // Write request.

input wire [31:0]                       i_cpsr;         // CPSR.
input wire [1:0]                        i_sr;           // Status Register.
input wire [31:0]                       i_dac_reg;      // Domain Access Control Register.

input wire [`SPAGE_TLB_WDT  -1:0]       i_sptlb_rdata;  // Small page TLB.              
input wire                              i_sptlb_rdav;   // TLB entry valid.

input wire [`LPAGE_TLB_WDT  -1:0]       i_lptlb_rdata;  // Large page TLB read data.
input wire                              i_lptlb_rdav;   // Large page TLB valid.

input wire [`SECTION_TLB_WDT-1:0]       i_setlb_rdata;  // Small page TLB read data.
input wire                              i_setlb_rdav;   // Small page TLB valid.

output reg                              o_walk;         // Signal page walk.
output reg [7:0]                        o_fsr;          // FSR. 0 means all OK.
output reg [31:0]                       o_far;          // Fault Address Register.
output reg                              o_cacheable;    // Cacheble stats of the PTE.
output reg [31:0]                       o_phy_addr;     // Physical address.

always @*
begin

        // Default values. Taken for MMU disabled esp.
        o_fsr       = 0;        // No fault.
        o_far       = i_va;     // Fault address.
        o_phy_addr  = i_va;     // VA = PA
        o_walk      = 0;        // Walk disabled.
        o_cacheable = 0;        // Uncacheable.

        if ( i_mmu_en && (i_rd|i_wr) ) // MMU enabled.
        begin
                if ( (i_sptlb_rdata[`SPAGE_TLB__TAG] == i_va[`VA__SPAGE_TAG]) && i_sptlb_rdav )
                begin
                        // Entry found in small page TLB.
                        o_fsr = get_fsr
                        (
                                1'd0, 1'd1, 1'd0,               // Small page.
                                i_va[`VA__SPAGE_AP_SEL],
                                i_cpsr[4:0] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                i_sptlb_rdata
                        ) ;

                        o_phy_addr = {i_sptlb_rdata[`SPAGE_TLB__BASE], 
                                      i_va[11:0]};

                        o_cacheable = i_sptlb_rdata[`SECTION_TLB__CB] >> 1;

                end
                else if ( (i_lptlb_rdata[`LPAGE_TLB__TAG] == i_va[`VA__LPAGE_TAG]) && i_lptlb_rdav )
                begin
                        // Entry found in large page TLB.
                        o_fsr = get_fsr
                        (
                                1'd0, 1'd0, 1'd1,               // Large page.
                                i_va[`VA__LPAGE_AP_SEL],
                                i_cpsr[4:0] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                i_lptlb_rdata
                        ) ;

                        o_phy_addr = {i_lptlb_rdata[`LPAGE_TLB__BASE],
                                        i_va[15:0]};

                        o_cacheable = i_lptlb_rdata[`LPAGE_TLB__CB] >> 1;
                end
                else if ( (i_setlb_rdata[`SECTION_TLB__TAG] == i_va[`VA__SECTION_TAG]) && i_setlb_rdav )
                begin
                        // Entry found in section TLB.
                        o_fsr = get_fsr
                        (
                                1'd1, 1'd0, 1'd0,               // Section.
                                2'd0,                           // DONT CARE. Sections do not further divisions in AP SEL.
                                i_cpsr[4:0] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                i_setlb_rdata
                        ) ;

                        o_phy_addr = {i_setlb_rdata[`SECTION_TLB__BASE],
                                        i_va[19:0]};

                        o_cacheable = i_setlb_rdata[`SECTION_TLB__CB] >> 1;
                end
                else
                begin
                        // Trigger TLB walk.
                        o_walk = 1'd1;
                end
        end // Else MMU disabled.
end

// ----------------------------------------------------------------------------

function  [7:0] get_fsr ( // Return 0 means OK to access else is a valid FSR.
input                   section, spage, lpage,  // Select one.
input   [1:0]           ap_sel,                 // AP sel bits. dont care for sections.
input                   user, rd, wr,           // Access properties.
input [1:0]             sr,                     // S and R bits.
input [31:0]            dac_reg,                // DAC register.
input [63:0]            tlb                     // TLB entry.
);

reg [3:0] apsr; // Concat of AP and SR.
reg [1:0] dac;  // DAC bits.

begin
        if ( section ) 
        begin
                apsr = (tlb  [ `SECTION_TLB__AP ]) >> (section ? 0 : (ap_sel << 1)); 
                dac  = (dac_reg >> (tlb  [ `SECTION_TLB__DAC_SEL ] << 1));
        end
        else if ( spage )
        begin
                apsr = (tlb  [ `SPAGE_TLB__AP ]) >> (section ? 0 : (ap_sel << 1)); 
                dac  = (dac_reg >> (tlb  [ `SPAGE_TLB__DAC_SEL ] << 1));
        end
        else // large page.
        begin
                apsr = (tlb  [ `LPAGE_TLB__AP ]) >> (section ? 0 : (ap_sel << 1)); 
                dac  = (dac_reg >> (tlb  [ `LPAGE_TLB__DAC_SEL ] << 1));
        end

        case(dac)
        DAC_MANAGER: get_fsr = 0; // No fault.

        DAC_CLIENT : get_fsr = is_apsr_ok ( user, rd, wr, apsr ) ? 0 : 
        (
         section ? {tlb[`SECTION_TLB__DAC_SEL], FSR_SECTION_PERMISSION_FAULT}:
         spage   ? {tlb[`SPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT   }:
                   {tlb[`LPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT   }
        );
 
        default    : get_fsr = 
        section ?    {tlb[`SECTION_TLB__DAC_SEL], FSR_SECTION_DOMAIN_FAULT} :
        spage   ?    {tlb[`SPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   } :
                     {tlb[`LPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   } ;
        endcase
end

endfunction

// ----------------------------------------------------------------------------

// 
// Function to check APSR bits.
// 
// Returns 0 for failure, 1 for okay.
// Checks AP and SR bits.
//

localparam APSR_BAD = 1'd0;
localparam APSR_OK  = 1'd1;

function  is_apsr_ok ( input user, input rd, input wr, input [3:0] apsr);
reg x;
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


endmodule // zap_tlb_check.v
`default_nettype wire
