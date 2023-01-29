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

`ifndef _ZAP_DEFINES_VH_
`define _ZAP_DEFINES_VH_

`define ZAP_CPSR_MODE               4:0     // CPSR bits.

`define ZAP_BASE_EXTEND             33      // Base address register for MEMOPS.
`define ZAP_BASE                    19:16   // Base address extend.

`define ZAP_SRCDEST_EXTEND          32      // Data Src/Dest extend register for MEMOPS.
`define ZAP_SRCDEST                 15:12   // Data src/dest register MEMOPS.

`define ZAP_DP_RD_EXTEND            33      // Destination source extend.
`define ZAP_DP_RD                   15:12   // Destination source.

`define ZAP_DP_RB_EXTEND            32      // Shift source extend.
`define ZAP_DP_RB                   3:0     // Shift source. ARM refers to this as rm.

`define ZAP_DP_RA                   19:16   // ALU source. ARM rn.
`define ZAP_DP_RA_EXTEND            34      // ALU source extend. ARM rn.

`define ZAP_OPCODE_EXTEND           35      // To differentiate lower and higher for multiplication -> 
                                        // 1 means higher, 0 lower.

// Instruction fields in CP15 instruction.
`define ZAP_OPCODE_2                7:5        
`define ZAP_CRM                     3:0
`define ZAP_CRN                     19:16
`define ZAP_CP_ID                   11:8

// ----------------------------------------------------------------------------

// Generic defines.
`define ZAP_DESC_ID               1:0  // Determine type of descriptor.

// Virtual Address Breakup
`define ZAP_VA__TABLE_INDEX       31:20
`define ZAP_VA__L2_TABLE_INDEX    19:12
`define ZAP_VA__4K_PAGE_INDEX     11:0
`define ZAP_VA__64K_PAGE_INDEX    15:0
`define ZAP_VA__1K_PAGE_INDEX     9:0
`define ZAP_VA__1M_SECTION_INDEX  19:0

`define ZAP_VA__TRANSLATION_BASE  31:14

`define ZAP_VA__SECTION_INDEX   20+$clog2(SECTION_TLB_ENTRIES)-1:20
`define ZAP_VA__LPAGE_INDEX     16+$clog2(LPAGE_TLB_ENTRIES)-1:16
`define ZAP_VA__SPAGE_INDEX     12+$clog2(SPAGE_TLB_ENTRIES)-1:12
`define ZAP_VA__FPAGE_INDEX     10+$clog2(FPAGE_TLB_ENTRIES)-1:10

`define ZAP_VA__SPAGE_TAG       31:12+$clog2(SPAGE_TLB_ENTRIES)
`define ZAP_VA__LPAGE_TAG       31:16+$clog2(LPAGE_TLB_ENTRIES)
`define ZAP_VA__SECTION_TAG     31:20+$clog2(SECTION_TLB_ENTRIES)
`define ZAP_VA__FPAGE_TAG       31:10+$clog2(FPAGE_TLB_ENTRIES)

`define ZAP_VA__SPAGE_AP_SEL    11:10    
`define ZAP_VA__LPAGE_AP_SEL    15:14

// L1 Section Descriptior Breakup
`define ZAP_L1_SECTION__BASE      31:20
`define ZAP_L1_SECTION__DAC_SEL   8:5
`define ZAP_L1_SECTION__AP        11:10
`define ZAP_L1_SECTION__CB        3:2

// L1 Page Descriptor Breakup
`define ZAP_L1_PAGE__PTBR    31:10
`define ZAP_L1_PAGE__DAC_SEL 8:5

// L1 fine page descriptor breakup
`define ZAP_L1_FINE__PTBR    31:10
`define ZAP_L1_FINE__DAC_SEL 8:5

// L2 Page Small Descriptor Breakup
`define ZAP_L2_SPAGE__BASE   31:12
`define ZAP_L2_SPAGE__AP     11:4
`define ZAP_L2_SPAGE__CB     3:2

// L2 Large Page Descriptor Breakup
`define ZAP_L2_LPAGE__BASE   31:16
`define ZAP_L2_LPAGE__AP     11:4
`define ZAP_L2_LPAGE__CB     3:2

// L2 Fine Page Descriptor Breakup
`define ZAP_L2_FPAGE__BASE   31:10 
`define ZAP_L2_FPAGE__AP     5:4
`define ZAP_L2_FPAGE__CB     3:2

// Section TLB Structure - 1:0 is undefined.
`define ZAP_SECTION_TLB__BASE    31:20
`define ZAP_SECTION_TLB__DAC_SEL 8:5
`define ZAP_SECTION_TLB__AP      11:10
`define ZAP_SECTION_TLB__CB      3:2
`define ZAP_SECTION_TLB__TAG     32+(32-$clog2(SECTION_TLB_ENTRIES)-20)-1:32

// Lpage TLB Structure - 1:0 is undefined
`define ZAP_LPAGE_TLB__BASE      31:16
`define ZAP_LPAGE_TLB__DAC_SEL   15:12 // Squeezed in blank space.
`define ZAP_LPAGE_TLB__AP        11:4
`define ZAP_LPAGE_TLB__CB        3:2
`define ZAP_LPAGE_TLB__TAG       32+(32-$clog2(LPAGE_TLB_ENTRIES)-16)-1:32

// Spage TLB Structure - 1:0 is undefined
`define ZAP_SPAGE_TLB__BASE      31:12
`define ZAP_SPAGE_TLB__DAC_SEL   35:32
`define ZAP_SPAGE_TLB__AP        11:4
`define ZAP_SPAGE_TLB__CB        3:2
`define ZAP_SPAGE_TLB__TAG       36+(32-$clog2(SPAGE_TLB_ENTRIES)-12)-1:36

// Fpage TLB Structure - 5:0 is undefined
`define ZAP_FPAGE_TLB__BASE       31:10
`define ZAP_FPAGE_TLB__DAC_SEL    8:5
`define ZAP_FPAGE_TLB__AP         9:8  
`define ZAP_FPAGE_TLB__CB         7:6 
`define ZAP_FPAGE_TLB__TAG        32+(32-$clog2(FPAGE_TLB_ENTRIES)-10)-1:32     

// Cache tag width. Tag consists of the tag and the physical address. valid and dirty are stored as flops.
`define ZAP_VA__CACHE_INDEX        $clog2(CACHE_LINE)+$clog2(CACHE_SIZE/CACHE_LINE)-1:$clog2(CACHE_LINE)
`define ZAP_VA__CACHE_TAG          31 : $clog2(CACHE_LINE)+$clog2(CACHE_SIZE/CACHE_LINE)
`define ZAP_CACHE_TAG__TAG         (31 - $clog2(CACHE_LINE) - $clog2(CACHE_SIZE/CACHE_LINE) + 1) -1   : 0  
`define ZAP_CACHE_TAG__PA          31 - $clog2(CACHE_LINE) + (31 - $clog2(CACHE_LINE) - $clog2(CACHE_SIZE/CACHE_LINE) + 1) : 31 - $clog2(CACHE_LINE) - $clog2(CACHE_SIZE/CACHE_LINE) + 1 
`define ZAP_CACHE_TAG_WDT          31 - $clog2(CACHE_LINE) + (31 - $clog2(CACHE_LINE) - $clog2(CACHE_SIZE/CACHE_LINE) + 1) + 1

// TLB widths.
`define ZAP_SECTION_TLB_WDT       (32 + (32-$clog2(SECTION_TLB_ENTRIES)-20))
`define ZAP_LPAGE_TLB_WDT         (32 + (32-$clog2(LPAGE_TLB_ENTRIES)-16))
`define ZAP_SPAGE_TLB_WDT         (36 + (32-$clog2(SPAGE_TLB_ENTRIES)-12))
`define ZAP_FPAGE_TLB_WDT         (32 + (32-$clog2(FPAGE_TLB_ENTRIES)-10))

// ----------------------------------------------------------------------------

`define ZAP_DECOMPILE_CCC            cond_code(i_instruction[31:28])
`define ZAP_DECOMPILE_CRB            arch_reg_num({i_instruction[`ZAP_DP_RB_EXTEND], i_instruction[`ZAP_DP_RB]})
`define ZAP_DECOMPILE_CRD            arch_reg_num({i_instruction[`ZAP_DP_RD_EXTEND], i_instruction[`ZAP_DP_RD]})
`define ZAP_DECOMPILE_CRD1           arch_reg_num({i_instruction[`ZAP_SRCDEST_EXTEND], i_instruction[`ZAP_SRCDEST]})
`define ZAP_DECOMPILE_CRN            arch_reg_num({i_instruction[`ZAP_DP_RA_EXTEND], i_instruction[`ZAP_DP_RA]})
`define ZAP_DECOMPILE_CRN1           arch_reg_num({i_instruction[`ZAP_BASE_EXTEND], i_instruction[`ZAP_BASE]})
`define ZAP_DECOMPILE_CRM            arch_reg_num({i_instruction[`ZAP_DP_RB_EXTEND], i_instruction[`ZAP_DP_RB]});
`define ZAP_DECOMPILE_COPCODE        get_opcode({i_instruction[`ZAP_OPCODE_EXTEND], i_instruction[24:21]})
`define ZAP_DECOMPILE_CSHTYPE        get_shtype(i_instruction[6:5])
`define ZAP_DECOMPILE_CRS            arch_reg_num(i_instruction[11:8]);
`define ZAP_DECOMPILE_XUMULL         3'b100
`define ZAP_DECOMPILE_XUMLAL         3'b101
`define ZAP_DECOMPILE_XSMULL         3'b110
`define ZAP_DECOMPILE_XSMLAL         3'b111

`endif
