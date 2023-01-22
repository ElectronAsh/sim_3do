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

`ifndef _ZAP_DEFINES_VH_
`define _ZAP_DEFINES_VH_

`define ZAP_BASE                    19:16   // Base address extend.
`define ZAP_DP_RA                   19:16   // ALU source. DDI0100E rn.
`define ZAP_SRCDEST                 15:12   // Data src/dest register MEMOPS.
`define ZAP_DP_RD                   15:12   // Destination source.
`define ZAP_DP_RB                   3:0     // Shift source. DDI0100E refers to this as rm.

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
`define ZAP_SECTION_TLB__TAG     32+(32-$clog2(SECTION_TLB_ENTRIES)-20)-1:32
`define ZAP_SECTION_TLB__BASE    31:20
`define ZAP_SECTION_TLB__AP      11:10
`define ZAP_SECTION_TLB__DAC_SEL 8:5
`define ZAP_SECTION_TLB__CB      3:2

// Large page TLB Structure - 1:0 is undefined
`define ZAP_LPAGE_TLB__TAG       32+(32-$clog2(LPAGE_TLB_ENTRIES)-16)-1:32
`define ZAP_LPAGE_TLB__BASE      31:16
`define ZAP_LPAGE_TLB__DAC_SEL   15:12
`define ZAP_LPAGE_TLB__AP        11:4
`define ZAP_LPAGE_TLB__CB        3:2

// Small page TLB Structure - 1:0 is undefined
`define ZAP_SPAGE_TLB__TAG       36+(32-$clog2(SPAGE_TLB_ENTRIES)-12)-1:36
`define ZAP_SPAGE_TLB__BASE      35:16
`define ZAP_SPAGE_TLB__DAC_SEL   15:12
`define ZAP_SPAGE_TLB__AP        11:4
`define ZAP_SPAGE_TLB__CB        3:2

// Fine page TLB Structure - 1:0 is undefined
`define ZAP_FPAGE_TLB__TAG        32+(32-$clog2(FPAGE_TLB_ENTRIES)-10)-1:32
`define ZAP_FPAGE_TLB__BASE       31:10
`define ZAP_FPAGE_TLB__DAC_SEL    9:6
`define ZAP_FPAGE_TLB__AP         5:4
`define ZAP_FPAGE_TLB__CB         3:2

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

// Misc.
`define ZAP_DEFAULT_XX            XX = 'X

`endif
