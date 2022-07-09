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
//                                                                            --    
// TLB management unit for the ZAP processor. The TLB units use single cycle  --
// clearing memories since TLBs are shallow.                                  --
//                                                                            --
// -----------------------------------------------------------------------------

`default_nettype none
module zap_tlb #(

parameter LPAGE_TLB_ENTRIES   = 8,
parameter SPAGE_TLB_ENTRIES   = 8,
parameter SECTION_TLB_ENTRIES = 8

) (

// Clock and reset.
input   wire            i_clk,
input   wire            i_reset,

// From cache FSM (processor)
input   wire    [31:0]  i_address,
input   wire    [31:0]  i_address_nxt,
input   wire            i_rd,
input   wire            i_wr,

// CPSR, SR, DAC register.
input   wire    [31:0]  i_cpsr,
input   wire    [1:0]   i_sr,
input   wire    [31:0]  i_dac_reg,
input   wire    [31:0]  i_baddr,

// From CP15.
input   wire            i_mmu_en,
input   wire            i_inv,

// To cache FSM.
output  wire    [31:0]  o_phy_addr,
output  wire    [7:0]   o_fsr,
output  wire    [31:0]  o_far,
output  wire            o_fault,
output  wire            o_cacheable,
output  wire            o_busy,

// Wishbone memory interface - Needs to go through some OR gates.
output wire             o_wb_stb_nxt,
output wire             o_wb_cyc_nxt,
output wire [31:0]      o_wb_adr_nxt,
output wire             o_wb_wen_nxt,
output wire [3:0]       o_wb_sel_nxt,
input  wire [31:0]      i_wb_dat,
output wire [31:0]      o_wb_dat_nxt,
input  wire             i_wb_ack 

);

// ----------------------------------------------------------------------------

assign o_wb_dat_nxt = 32'd0;

`include "zap_localparams.vh"
`include "zap_defines.vh"
`include "zap_functions.vh"

wire [`SECTION_TLB_WDT-1:0]     setlb_wdata, setlb_rdata;
wire [`LPAGE_TLB_WDT-1:0]       lptlb_wdata, lptlb_rdata;
wire [`SPAGE_TLB_WDT-1:0]       sptlb_wdata, sptlb_rdata;
wire                            sptlb_wen, lptlb_wen, setlb_wen;
wire                            sptlb_ren, lptlb_ren, setlb_ren;
wire                            walk;
wire [7:0]                      fsr;
wire [31:0]                     far;
wire                            cacheable;
wire [31:0]                     phy_addr;

// ----------------------------------------------------------------------------

zap_mem_inv_block #(.WIDTH(`SECTION_TLB_WDT), .DEPTH(SECTION_TLB_ENTRIES)) 
u_section_tlb (
.i_clk          (i_clk),
.i_reset        (i_reset),

.i_wdata        (setlb_wdata),
.i_wen          (setlb_wen),
.i_ren          (1'd1),

.i_inv          (i_inv | !i_mmu_en),

.i_raddr        (i_address_nxt[`VA__SECTION_INDEX]),
.i_waddr        (i_address[`VA__SECTION_INDEX]),

.o_rdata        (setlb_rdata),
.o_rdav         (setlb_ren)
);

// ----------------------------------------------------------------------------

zap_mem_inv_block #(.WIDTH(`LPAGE_TLB_WDT), .DEPTH(LPAGE_TLB_ENTRIES)) 
u_lpage_tlb   (
.i_clk          (i_clk),
.i_reset        (i_reset),

.i_wdata        (lptlb_wdata),
.i_wen          (lptlb_wen),
.i_ren          (1'd1),

.i_inv          (i_inv | !i_mmu_en),

.i_raddr        (i_address_nxt[`VA__LPAGE_INDEX]),
.i_waddr        (i_address[`VA__LPAGE_INDEX]),

.o_rdata        (lptlb_rdata),
.o_rdav         (lptlb_ren)
);

// ----------------------------------------------------------------------------

zap_mem_inv_block #(.WIDTH(`SPAGE_TLB_WDT), .DEPTH(SPAGE_TLB_ENTRIES)) 
u_spage_tlb   (
.i_clk          (i_clk),
.i_reset        (i_reset),

.i_wdata        (sptlb_wdata),
.i_wen          (sptlb_wen),
.i_ren          (1'd1),

.i_inv          (i_inv | !i_mmu_en),

.i_raddr        (i_address_nxt[`VA__SPAGE_INDEX]),
.i_waddr        (i_address[`VA__SPAGE_INDEX]),

.o_rdata        (sptlb_rdata),
.o_rdav         (sptlb_ren)
);

// ----------------------------------------------------------------------------

zap_tlb_check #(
.LPAGE_TLB_ENTRIES(LPAGE_TLB_ENTRIES), 
.SPAGE_TLB_ENTRIES(SPAGE_TLB_ENTRIES), 
.SECTION_TLB_ENTRIES(SECTION_TLB_ENTRIES)) 
u_zap_tlb_check (

.i_mmu_en       (i_mmu_en),
.i_va           (i_address),
.i_rd           (i_rd),
.i_wr           (i_wr),

.i_cpsr         (i_cpsr),
.i_sr           (i_sr),
.i_dac_reg      (i_dac_reg),

.i_sptlb_rdata  (sptlb_rdata),
.i_sptlb_rdav   (sptlb_ren),

.i_lptlb_rdata  (lptlb_rdata),
.i_lptlb_rdav   (lptlb_ren),

.i_setlb_rdata  (setlb_rdata),
.i_setlb_rdav   (setlb_ren),

.o_walk         (walk),
.o_fsr          (fsr),
.o_far          (far),
.o_cacheable    (cacheable),
.o_phy_addr     (phy_addr)

);

// ----------------------------------------------------------------------------

zap_tlb_fsm #(
.LPAGE_TLB_ENTRIES      (LPAGE_TLB_ENTRIES),
.SPAGE_TLB_ENTRIES      (SPAGE_TLB_ENTRIES),
.SECTION_TLB_ENTRIES    (SECTION_TLB_ENTRIES)
) u_zap_tlb_fsm (
.o_unused_ok    (),             // UNCONNECTED. For lint.
.i_clk          (i_clk),
.i_reset        (i_reset),
.i_mmu_en       (i_mmu_en),
.i_baddr        (i_baddr),
.i_address      (i_address),
.i_walk         (walk),
.i_fsr          (fsr),
.i_far          (far),
.i_cacheable    (cacheable),
.i_phy_addr     (phy_addr),

.o_fsr          (o_fsr),
.o_far          (o_far),
.o_fault        (o_fault),
.o_phy_addr     (o_phy_addr),
.o_cacheable    (o_cacheable),
.o_busy         (o_busy),

.o_setlb_wdata  (setlb_wdata),
.o_setlb_wen    (setlb_wen),

.o_sptlb_wdata  (sptlb_wdata),
.o_sptlb_wen    (sptlb_wen),

.o_lptlb_wdata  (lptlb_wdata),
.o_lptlb_wen    (lptlb_wen),

.o_wb_cyc       (),
.o_wb_stb       (),
.o_wb_wen       (o_wb_wen_nxt),
.o_wb_sel       (),
.o_wb_adr       (),
.i_wb_dat       (i_wb_dat),
.i_wb_ack       (i_wb_ack),

.o_wb_sel_nxt   (o_wb_sel_nxt),
.o_wb_cyc_nxt   (o_wb_cyc_nxt),
.o_wb_stb_nxt   (o_wb_stb_nxt),
.o_wb_adr_nxt   (o_wb_adr_nxt)
);

// ----------------------------------------------------------------------------

endmodule
`default_nettype wire
