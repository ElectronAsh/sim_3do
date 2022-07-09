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

`ifndef _ZAP_DEFINES_VH_
`define _ZAP_DEFINES_VH_

`define CPSR_MODE 4:0

`define BASE_EXTEND             33      // Base address register for MEMOPS.
`define BASE                    19:16   // Base address extend.

`define SRCDEST_EXTEND          32      // Data Src/Dest extend register for MEMOPS.
`define SRCDEST                 15:12   // Data src/dest register MEMOPS.

`define DP_RD_EXTEND            33      // Destination source extend.
`define DP_RD                   15:12   // Destination source.

`define DP_RB_EXTEND            32      // Shift source extend.
`define DP_RB                   3:0     // Shift source. ARM refers to this as rm.

`define DP_RA                   19:16   // ALU source. ARM rn.
`define DP_RA_EXTEND            34      // ALU source extend. ARM rn.

`define OPCODE_EXTEND           35      // To differentiate lower and higher -> 
                                        // 1 means higher, 0 lower.

// Instruction fields in CP15 instruction.
`define opcode_2                7:5        
`define crm                     3:0
`define crn                     19:16
`define cp_id                   11:8

// ----------------------------------------------------------------------------

// Generic defines.
`define ID 1:0  // Determine type of descriptor.

// Virtual Address Breakup
`define VA__TABLE_INDEX       31:20
`define VA__L2_TABLE_INDEX    19:12
`define VA__4K_PAGE_INDEX     11:0
`define VA__64K_PAGE_INDEX    15:0
`define VA__1M_SECTION_INDEX  19:0

`define VA__TRANSLATION_BASE  31:14

`define VA__CACHE_INDEX      4+$clog2(CACHE_SIZE/16)-1:4
`define VA__SECTION_INDEX   20+$clog2(SECTION_TLB_ENTRIES)-1:20
`define VA__LPAGE_INDEX     16+$clog2(LPAGE_TLB_ENTRIES)-1:16
`define VA__SPAGE_INDEX     12+$clog2(SPAGE_TLB_ENTRIES)-1:12

`define VA__CACHE_TAG       31:4+$clog2(CACHE_SIZE/16)

`define VA__SPAGE_TAG       31:12+$clog2(SPAGE_TLB_ENTRIES)
`define VA__LPAGE_TAG       31:16+$clog2(LPAGE_TLB_ENTRIES)
`define VA__SECTION_TAG     31:20+$clog2(SECTION_TLB_ENTRIES)

`define VA__SPAGE_AP_SEL    11:10    
`define VA__LPAGE_AP_SEL    15:14

// L1 Section Descriptior Breakup
`define L1_SECTION__BASE      31:20
`define L1_SECTION__DAC_SEL   8:5
`define L1_SECTION__AP        11:10
`define L1_SECTION__CB        3:2

// L1 Page Descriptor Breakup
`define L1_PAGE__PTBR    31:10
`define L1_PAGE__DAC_SEL 8:5

// L2 Page Descriptor Breakup
`define L2_SPAGE__BASE   31:12
`define L2_SPAGE__AP     11:4
`define L2_SPAGE__CB     3:2

`define L2_LPAGE__BASE   31:16
`define L2_LPAGE__AP     11:4
`define L2_LPAGE__CB     3:2

// Section TLB Structure - 1:0 is undefined.
`define SECTION_TLB__BASE    31:20
`define SECTION_TLB__DAC_SEL 8:5
`define SECTION_TLB__AP     11:10
`define SECTION_TLB__CB     3:2
`define SECTION_TLB__TAG 32+(32-$clog2(SECTION_TLB_ENTRIES)-20)-1:32

// Lpage TLB Structure - 1:0 is undefined
`define LPAGE_TLB__BASE      31:16
`define LPAGE_TLB__DAC_SEL   15:12 // Squeezed in blank space.
`define LPAGE_TLB__AP        11:4
`define LPAGE_TLB__CB        3:2
`define LPAGE_TLB__TAG 32+(32-$clog2(LPAGE_TLB_ENTRIES)-16)-1:32

// Spage TLB Structure - 1:0 is undefined
`define SPAGE_TLB__BASE      31:12
`define SPAGE_TLB__AP        11:4
`define SPAGE_TLB__CB        3:2
`define SPAGE_TLB__DAC_SEL   35:32
`define SPAGE_TLB__TAG 36+(32-$clog2(SPAGE_TLB_ENTRIES)-12)-1:36

// Cache tag width. Tag consists of the tag and the physical address. valid and dirty are stored as flops.
`define CACHE_TAG__TAG             (31 - 4 - $clog2(CACHE_SIZE/16) + 1) -1   : 0  
`define CACHE_TAG__PA         27 + (31 - 4 - $clog2(CACHE_SIZE/16) + 1) : 31 - 4 - $clog2(CACHE_SIZE/16) + 1 
`define CACHE_TAG_WDT         27 + (31 - 4 - $clog2(CACHE_SIZE/16) + 1) + 1

// TLB widths.
`define SECTION_TLB_WDT       (32 + (32-$clog2(SECTION_TLB_ENTRIES)-20))
`define LPAGE_TLB_WDT         (32 + (32-$clog2(LPAGE_TLB_ENTRIES)-16))
`define SPAGE_TLB_WDT         (36 + (32-$clog2(SPAGE_TLB_ENTRIES)-12))

// ----------------------------------------------------------------------------

`endif
