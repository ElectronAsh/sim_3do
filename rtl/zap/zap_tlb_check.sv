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
// --  Examines TLB entries to authorize access.                              --                     
// --                                                                         --  
// -----------------------------------------------------------------------------



module zap_tlb_check (   // ZAP TLB Processing Logic.

i_clk,          // Clock
i_clkena,       // Clock enable.

i_mmu_en,       // MMU enable.

// Dynamics
i_va,           // Virtual address.
i_rd,           // WB rd.
i_wr,           // WB wr.

// Static almost.
i_cpsr,
i_sr,
i_dac_reg,

// Data from TLB block RAMs.
i_sptlb_rdata, i_sptlb_rdav,
i_lptlb_rdata, i_lptlb_rdav,
i_setlb_rdata, i_setlb_rdav,
i_fptlb_rdata, i_fptlb_rdav,

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
parameter FPAGE_TLB_ENTRIES   = 8;

`include "zap_localparams.svh"
`include "zap_defines.svh"

localparam APSR_BAD = 1'd0;
localparam APSR_OK  = 1'd1;

input logic                              i_clk;          // Clock signal.
input logic                              i_clkena;       // Clock enable.

input logic                              i_mmu_en;       // MMU enable.

input logic [31:0]                       i_va;           // Virtual address.
input logic                              i_rd;           // Read request.
input logic                              i_wr;           // Write request.

input logic [`ZAP_CPSR_MODE]             i_cpsr;         // CPSR.
input logic [1:0]                        i_sr;           // Status Register.
input logic [31:0]                       i_dac_reg;      // Domain Access Control Register.

input logic [`ZAP_SPAGE_TLB_WDT  -1:0]   i_sptlb_rdata;  // Small page TLB.              
input logic                              i_sptlb_rdav;   // TLB entry valid.

input logic [`ZAP_LPAGE_TLB_WDT  -1:0]   i_lptlb_rdata;  // Large page TLB read data.
input logic                              i_lptlb_rdav;   // Large page TLB valid.

input logic [`ZAP_SECTION_TLB_WDT-1:0]   i_setlb_rdata;  // Small page TLB read data.
input logic                              i_setlb_rdav;   // Small page TLB valid.

input logic [`ZAP_FPAGE_TLB_WDT-1:0]     i_fptlb_rdata;  // Fine page TLB read data.
input logic                              i_fptlb_rdav;   // Fine page TLB valid.

output logic                            o_walk;         // Signal page walk.
output logic [7:0]                      o_fsr;          // FSR. 0 means all OK.
output logic [31:0]                     o_far;          // Fault Address Register.
output logic                            o_cacheable;    // Cacheble stats of the PTE.
output logic [31:0]                     o_phy_addr;     // Physical address.

// ----------------------------------------------------------------------------

localparam [64 - `ZAP_SPAGE_TLB_WDT   - 1 : 0] CONST_0_SP = {(64 - `ZAP_SPAGE_TLB_WDT  ){1'd0}};
localparam [64 - `ZAP_LPAGE_TLB_WDT   - 1 : 0] CONST_0_LP = {(64 - `ZAP_LPAGE_TLB_WDT  ){1'd0}};
localparam [64 - `ZAP_FPAGE_TLB_WDT   - 1 : 0] CONST_0_FP = {(64 - `ZAP_FPAGE_TLB_WDT  ){1'd0}};
localparam [64 - `ZAP_SECTION_TLB_WDT - 1 : 0] CONST_0_SE = {(64 - `ZAP_SECTION_TLB_WDT){1'd0}};

always @ ( posedge i_clk ) if ( i_clkena )
begin:blk1
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
                unique if ( (i_sptlb_rdata[`ZAP_SPAGE_TLB__TAG] == i_va[`ZAP_VA__SPAGE_TAG]) && i_sptlb_rdav )
                begin
                        // Entry found in small page TLB.
                        o_fsr <= get_fsr
                        (
                                1'd0, 1'd1, 1'd0, 1'd0,         // Small page.
                                i_va[`ZAP_VA__SPAGE_AP_SEL],
                                i_cpsr[`ZAP_CPSR_MODE] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                {CONST_0_SP, i_sptlb_rdata}
                        ) ;

                        o_phy_addr <= {i_sptlb_rdata[`ZAP_SPAGE_TLB__BASE], i_va[11:0]};
                        {dummy, o_cacheable} <= i_sptlb_rdata[`ZAP_SECTION_TLB__CB] >> 1;

                end
                else if ( (i_lptlb_rdata[`ZAP_LPAGE_TLB__TAG] == i_va[`ZAP_VA__LPAGE_TAG]) && i_lptlb_rdav )
                begin
                        // Entry found in large page TLB.
                        o_fsr <= get_fsr
                        (
                                1'd0, 1'd0, 1'd1, 1'd0,         // Large page.
                                i_va[`ZAP_VA__LPAGE_AP_SEL],
                                i_cpsr[`ZAP_CPSR_MODE] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                {CONST_0_LP, i_lptlb_rdata}
                        ) ;

                        o_phy_addr <= {i_lptlb_rdata[`ZAP_LPAGE_TLB__BASE], i_va[15:0]};
                        {dummy, o_cacheable} <= i_lptlb_rdata[`ZAP_LPAGE_TLB__CB] >> 1;
                end
                else if ( (i_setlb_rdata[`ZAP_SECTION_TLB__TAG] == i_va[`ZAP_VA__SECTION_TAG]) && i_setlb_rdav )
                begin
                        // Entry found in section TLB.
                        o_fsr <= get_fsr
                        (
                                1'd1, 1'd0, 1'd0, 1'd0,         // Section.
                                2'd0,                           // DONT CARE. Sections do not further divisions in AP SEL.
                                i_cpsr[`ZAP_CPSR_MODE] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                {CONST_0_SE, i_setlb_rdata}
                        ) ;

                        o_phy_addr <= {i_setlb_rdata[`ZAP_SECTION_TLB__BASE], i_va[19:0]};
                        {dummy, o_cacheable} <= i_setlb_rdata[`ZAP_SECTION_TLB__CB] >> 1;
                end
                else if( (i_fptlb_rdata[`ZAP_FPAGE_TLB__TAG] == i_va[`ZAP_VA__FPAGE_TAG]) && i_fptlb_rdav )
                begin
                        // Entry found in fine page TLB.
                        o_fsr <= get_fsr
                        (
                                1'd0, 1'd0, 1'd0, 1'd1,
                                2'd0,                    
                                i_cpsr[`ZAP_CPSR_MODE] == USR,
                                i_rd,
                                i_wr,
                                i_sr,
                                i_dac_reg,
                                {CONST_0_FP, i_fptlb_rdata}
                        );

                        o_phy_addr <= {i_fptlb_rdata[`ZAP_FPAGE_TLB__BASE], i_va[9:0]};
                        {dummy, o_cacheable} <= i_fptlb_rdata[`ZAP_FPAGE_TLB__CB] >> 1;
                end
                else
                begin
                        // Trigger TLB walk.
                        o_walk <= 1'd1;
                end
        end // Else MMU disabled.
end

// ----------------------------------------------------------------------------

function  [7:0] get_fsr (                              // Return 0 means OK to access else is a valid FSR.
input                   section, spage, lpage, fpage,  // Select one.
input   [1:0]           ap_sel,                        // AP sel bits. dont care for sections or fine pages.
input                   user, rd, wr,                  // Access properties.
input [1:0]             sr,                            // S and R bits.
input [31:0]            dac_reg,                       // DAC register.
input [63:0]            tlb                            // TLB entry.
);

logic [3:0]  apsr; // Concat of AP and SR.
logic [1:0]  dac;  // DAC bits.
logic [29:0] dummy;// 30-bit dummy variable. ** UNUSED **


/* verilator lint_off VARHIDDEN */
logic        unused;
/* verilator lint_on VARHIDDEN */

begin
        dummy  = 30'd0;
        apsr   = 4'd0;
        dac    = 2'd0;

        unused = |{dummy, tlb[63:36], tlb[31:16], tlb[3:0]};

        // Get AP and DAC.

        unique if ( section ) // section.
        begin
                        apsr[3:2]  = (tlb  [ `ZAP_SECTION_TLB__AP ]);
                {dummy,  dac[1:0]} = (dac_reg >> (tlb  [ `ZAP_SECTION_TLB__DAC_SEL ] << 1));
        end
        else if ( spage ) // small page.
        begin
                {dummy[5:0], apsr[3:2]} = (tlb  [ `ZAP_SPAGE_TLB__AP ]) >> ({30'd0, ap_sel} << 32'd1); 
                {dummy,  dac[1:0]}      = (dac_reg >> (tlb  [ `ZAP_SPAGE_TLB__DAC_SEL ] << 1));
        end
        else if ( fpage ) // fine page
        begin
                        apsr[3:2]  = (tlb [ `ZAP_FPAGE_TLB__AP ]);
                {dummy,  dac[1:0]} = (dac_reg >> (tlb [ `ZAP_FPAGE_TLB__DAC_SEL ] << 1));
        end
        else if ( lpage ) // large page.
        begin
                {dummy[5:0], apsr[3:2]} = (tlb  [ `ZAP_LPAGE_TLB__AP ]) >> ({30'd0, ap_sel} << 32'd1); 
                {dummy,  dac[1:0]}      = (dac_reg >> (tlb  [ `ZAP_LPAGE_TLB__DAC_SEL ] << 1));
        end

        // Concat AP and SR bits finally.
        apsr[1:0]  = sr[1:0];

        case(dac)

        DAC_MANAGER: 
        begin
                get_fsr = '0; // No fault.
        end                

        DAC_CLIENT: 
                if ( is_apsr_ok ( user, rd, wr, apsr ) == APSR_OK )
                begin
                        get_fsr = '0; // No fault.
                end
                else
                begin
                        unique if ( section )  get_fsr = {tlb[`ZAP_SECTION_TLB__DAC_SEL], FSR_SECTION_PERMISSION_FAULT};
                          else if ( spage   )  get_fsr = {tlb[`ZAP_SPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT   };
                          else if ( fpage   )  get_fsr = {tlb[`ZAP_FPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT   };
                          else if ( lpage   )  get_fsr = {tlb[`ZAP_LPAGE_TLB__DAC_SEL]  , FSR_PAGE_PERMISSION_FAULT   };
                end

        default: 
        begin 
                unique if  ( section )  get_fsr = {tlb[`ZAP_SECTION_TLB__DAC_SEL], FSR_SECTION_DOMAIN_FAULT};
                  else if  ( spage   )  get_fsr = {tlb[`ZAP_SPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   };
                  else if  ( fpage   )  get_fsr = {tlb[`ZAP_FPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   };
                  else if  ( lpage   )  get_fsr = {tlb[`ZAP_LPAGE_TLB__DAC_SEL],   FSR_PAGE_DOMAIN_FAULT   };
        end

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

function  is_apsr_ok ( input user, input rd, input wr, input [3:0] apsr);
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

endmodule // zap_tlb_check.v

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
