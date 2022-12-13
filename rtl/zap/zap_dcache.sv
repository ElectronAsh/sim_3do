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
// -- This is the top level cache module that contains the MMU and cache.     --
// -- This is the data cache.                                                 --
// --                                                                         --
// -----------------------------------------------------------------------------

module zap_dcache #(

parameter [31:0] CACHE_SIZE             = 1024, 
parameter [31:0] SPAGE_TLB_ENTRIES      = 8,
parameter [31:0] LPAGE_TLB_ENTRIES      = 8,
parameter [31:0] SECTION_TLB_ENTRIES    = 8,
parameter [31:0] FPAGE_TLB_ENTRIES      = 8,
parameter [31:0] CACHE_LINE             = 8,
parameter        BE_32_ENABLE           = 0

) /* Port List */ (

// Clock and reset.
input   logic            i_clk,
input   logic            i_reset,

// RAM stall.
input   logic            i_stall,

// Signals to check (Provide 1 cycle before TLB+cache access).
input   logic   [31:0]   i_address_check,
input   logic            i_wr_check,
input   logic            i_rd_check,

// Address of TLB+Cache access
input   logic    [31:0]  i_address,

// Address of RAM read.
input   logic    [31:0]  i_address_nxt,

// Other control signals from/to processor.
input   logic            i_rd,
input   logic            i_wr,
input   logic [3:0]      i_ben,
input   logic [31:0]     i_dat,
output logic  [31:0]     o_dat,
output  logic            o_ack,
output  logic            o_err,
output  logic [7:0]      o_fsr,
output  logic [31:0]     o_far,
output  logic            o_err2,
input   logic [63:0]     i_reg_idx, /* Register to load to. added */
output  logic [63:0]     o_lock,    /* Register that is locked. added */
output  logic [31:0]     o_reg_dat, /* Register data. aded */
output  logic [63:0]     o_reg_idx, /* Register index. added */

// MMU controls from/to processor.
input   logic            i_mmu_en,
input   logic            i_cache_en,
input   logic            i_cache_inv_req,
input   logic            i_cache_clean_req,
output logic             o_cache_inv_done,
output  logic            o_cache_clean_done,

input   logic [`ZAP_CPSR_MODE] i_cpsr,
input   logic [1:0]            i_sr,
input   logic [31:0]           i_baddr,
input   logic [31:0]           i_dac_reg,
input  logic                   i_tlb_inv,

// Wishbone. Signals from all 4 modules are ORed.
output logic              o_wb_stb, o_wb_stb_nxt, 
output logic              o_wb_cyc, o_wb_cyc_nxt,
output logic              o_wb_wen, o_wb_wen_nxt,
output logic  [3:0]       o_wb_sel, o_wb_sel_nxt,
output logic  [31:0]      o_wb_dat, o_wb_dat_nxt,
output logic  [31:0]      o_wb_adr, o_wb_adr_nxt,
output logic  [2:0]       o_wb_cti, o_wb_cti_nxt,
input  logic [31:0]       i_wb_dat,
input  logic              i_wb_ack

);

`include "zap_defines.svh"
`include "zap_localparams.svh"

localparam                      S0=0;
localparam                      S1=1;
localparam                      S2=2;

logic [2:0]                      wb_stb; 
logic [2:0]                      wb_cyc; 
logic [2:0]                      wb_wen;
logic [3:0]                      wb_sel [2:0];
logic [31:0]                     wb_dat [2:0];
logic [31:0]                     wb_adr [2:0];
logic [2:0]                      wb_cti [2:0];
logic [31:0]                     tlb_phy_addr;
logic [7:0]                      tlb_fsr;
logic [31:0]                     tlb_far;
logic                            tlb_fault;
logic                            tlb_cacheable;
logic                            tlb_busy;
logic [CACHE_LINE*8-1:0]         tr_cache_line;
logic [CACHE_LINE*8-1:0]         cf_cache_line;
logic [CACHE_LINE-1:0]           cf_cache_line_ben;
logic                            cf_cache_tag_wr_en;
logic [`ZAP_CACHE_TAG_WDT-1:0]   tr_cache_tag, cf_cache_tag;
logic                            tr_cache_tag_valid;
logic                            tr_cache_tag_dirty, cf_cache_tag_dirty;
logic                            cf_cache_clean_req, cf_cache_inv_req;
logic                            tr_cache_inv_done, tr_cache_clean_done;
logic [2:0]                      wb_ack;
logic [1:0]                      state_ff, state_nxt;
logic [31:0]                     cache_address;
logic                            hold;
logic                            idle;

// Selection 2 of Wishbone CTI[2x3] is always on all CPU supported modes.
always_comb wb_cti[2] = 3'd0;

// Basic cache FSM - serves as Master 0.
zap_dcache_fsm #(.CACHE_SIZE(CACHE_SIZE), .CACHE_LINE(CACHE_LINE), .BE_32_ENABLE(BE_32_ENABLE)) u_zap_cache_fsm (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address              (i_address),
        .i_rd                   (i_rd),
        .i_wr                   (i_wr),
        .i_din                  (i_dat),
        .o_idle                 (idle),
        .i_ben                  (i_ben),
        .o_dat                  (o_dat),
        .o_ack                  (o_ack),
        .o_err                  (o_err),
        .o_fsr                  (o_fsr),
        .o_far                  (o_far),
        .i_cache_en             (i_cache_en),
        .i_cache_inv            (i_cache_inv_req),
        .i_cache_clean          (i_cache_clean_req),
        .o_cache_inv_done       (o_cache_inv_done),
        .o_cache_clean_done     (o_cache_clean_done),
        .i_cache_line           (tr_cache_line),
        .i_cache_tag_dirty      (tr_cache_tag_dirty),
        .i_cache_tag            (tr_cache_tag),
        .i_cache_tag_valid      (tr_cache_tag_valid),
        .o_cache_tag            (cf_cache_tag),
        .o_cache_tag_dirty      (cf_cache_tag_dirty),
        .o_cache_tag_wr_en      (cf_cache_tag_wr_en),
        .o_cache_line           (cf_cache_line),
        .o_cache_line_ben       (cf_cache_line_ben),
        .o_cache_clean_req      (cf_cache_clean_req),
        .i_cache_clean_done     (tr_cache_clean_done),
        .o_cache_inv_req        (cf_cache_inv_req),
        .i_cache_inv_done       (tr_cache_inv_done),
        .i_phy_addr             (tlb_phy_addr),
        .i_fsr                  (tlb_fsr),
        .i_far                  (tlb_far),
        .i_fault                (tlb_fault),
        .i_cacheable            (tlb_cacheable),
        .i_busy                 (tlb_busy),
        .o_err2                 (o_err2),
        .o_address              (cache_address),
        .o_wb_cyc_nxt           (wb_cyc[0]),
        .o_hold                 (hold),
        .i_reg_idx              (i_reg_idx),
        .o_lock                 (o_lock),
        .o_reg_dat              (o_reg_dat),
        .o_reg_idx              (o_reg_idx),

        /* verilator lint_off PINCONNECTEMPTY */
        .o_wb_cyc_ff            (),
        .o_wb_stb_ff            (),
        .o_wb_adr_ff            (),
        .o_wb_dat_ff            (),
        .o_wb_sel_ff            (),
        .o_wb_wen_ff            (),
        .o_wb_cti_ff            (),
        /* verilator lint_on PINCONNECTEMPTY */

        .o_wb_stb_nxt           (wb_stb[0]),
        .o_wb_adr_nxt           (wb_adr[0]),
        .o_wb_dat_nxt           (wb_dat[0]),
        .o_wb_sel_nxt           (wb_sel[0]),
        .o_wb_wen_nxt           (wb_wen[0]),
        .o_wb_cti_nxt           (wb_cti[0]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[0])
);

// Cache Tag RAM - As a master - this performs cache clean - Master 1.
zap_cache_tag_ram #(.CACHE_SIZE(CACHE_SIZE), .CACHE_LINE(CACHE_LINE)) u_zap_cache_tag_ram     (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address_nxt          (i_address_nxt),
        .i_address              (cache_address),
        .i_hold                 (hold || i_stall),
        .i_cache_en             (i_cache_en),
        .i_cache_line           (cf_cache_line),
        .o_cache_line           (tr_cache_line),
        .i_cache_line_ben       (cf_cache_line_ben),
        .i_cache_tag_wr_en      (cf_cache_tag_wr_en),
        .i_cache_tag            (cf_cache_tag),
        .i_cache_tag_dirty      (cf_cache_tag_dirty),
        .o_cache_tag            (tr_cache_tag),
        .o_cache_tag_valid      (tr_cache_tag_valid),
        .o_cache_tag_dirty      (tr_cache_tag_dirty),
        .i_cache_inv_req        (cf_cache_inv_req),
        .o_cache_inv_done       (tr_cache_inv_done),
        .i_cache_clean_req      (cf_cache_clean_req),
        .o_cache_clean_done     (tr_cache_clean_done),

        /* verilator lint_off PINCONNECTEMPTY */
        .o_wb_cyc_ff            (),
        .o_wb_stb_ff            (),
        .o_wb_adr_ff            (),
        .o_wb_dat_ff            (),
        .o_wb_sel_ff            (),
        .o_wb_wen_ff            (),
        .o_wb_cti_ff            (),
        /* verilator lint_on PINCONNECTEMPTY */

        .o_wb_cyc_nxt           (wb_cyc[1]),
        .o_wb_stb_nxt           (wb_stb[1]),
        .o_wb_adr_nxt           (wb_adr[1]),
        .o_wb_dat_nxt           (wb_dat[1]),
        .o_wb_sel_nxt           (wb_sel[1]),
        .o_wb_wen_nxt           (wb_wen[1]),
        .o_wb_cti_nxt           (wb_cti[1]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[1])
);

// ZAP TLB control module. Includes TLB RAM inside - Master 2.
zap_tlb #(
        .LPAGE_TLB_ENTRIES      (LPAGE_TLB_ENTRIES),
        .SPAGE_TLB_ENTRIES      (SPAGE_TLB_ENTRIES),
        .SECTION_TLB_ENTRIES    (SECTION_TLB_ENTRIES),
        .FPAGE_TLB_ENTRIES      (FPAGE_TLB_ENTRIES)
)
u_zap_tlb (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_address      (i_address),
        .i_address_nxt  (i_address_nxt),
        .i_address_check(i_address_check),
        .i_idle         (idle),
        .i_wr_check     (i_wr_check),
        .i_rd_check     (i_rd_check),
        .i_hold         (hold || i_stall),
        .i_cpsr         (i_cpsr),
        .i_sr           (i_sr),
        .i_dac_reg      (i_dac_reg),
        .i_baddr        (i_baddr),
        .i_mmu_en       (i_mmu_en),
        .i_inv          (i_tlb_inv),
        .o_phy_addr     (tlb_phy_addr),
        .o_fsr          (tlb_fsr),
        .o_far          (tlb_far),
        .o_fault        (tlb_fault),
        .o_cacheable    (tlb_cacheable),
        .o_busy         (tlb_busy),
        .o_wb_stb_nxt   (wb_stb[2]),
        .o_wb_cyc_nxt   (wb_cyc[2]),
        .o_wb_adr_nxt   (wb_adr[2]),
        .o_wb_wen_nxt   (wb_wen[2]),
        .o_wb_sel_nxt   (wb_sel[2]),
        .o_wb_dat_nxt   (wb_dat[2]),
        .i_wb_dat       (i_wb_dat),
        .i_wb_ack       (wb_ack[2])
);

// Sequential Block
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                state_ff <= S0;
                o_wb_stb <= 1'd0;
                o_wb_cyc <= 1'd0; 
                o_wb_adr <= 32'd0;
                o_wb_cti <= CTI_CLASSIC;
                o_wb_sel <= 4'd0;
                o_wb_dat <= 32'd0;
                o_wb_wen <= 1'd0;
        end
        else
        begin
                state_ff <= state_nxt;
                o_wb_stb <= o_wb_stb_nxt; 
                o_wb_cyc <= o_wb_cyc_nxt; 
                o_wb_adr <= o_wb_adr_nxt; 
                o_wb_cti <= o_wb_cti_nxt; 
                o_wb_sel <= o_wb_sel_nxt; 
                o_wb_dat <= o_wb_dat_nxt; 
                o_wb_wen <= o_wb_wen_nxt; 
        end
end

// Next state logic.
always_comb
begin
        state_nxt = state_ff;

        // Change state only if strobe is inactive or strobe has just completed.
        if ( !o_wb_stb || (o_wb_stb && i_wb_ack) ) 
        begin
                casez({wb_cyc[2],wb_cyc[1],wb_cyc[0]})
                3'b1?? : state_nxt = S2; // TLB.
                3'b01? : state_nxt = S1; // Tag.
                3'b001 : state_nxt = S0; // Cache.
                default: state_nxt = state_ff;                                       
                endcase
        end
end

// Route ACKs to respective masters.
always_comb
begin
        wb_ack = 0;

        case(state_ff)
        S0: wb_ack[0] = i_wb_ack;
        S1: wb_ack[1] = i_wb_ack;
        S2: wb_ack[2] = i_wb_ack;
        endcase
end

// Combo signals for external MUXing.
always_comb
begin
        o_wb_stb_nxt = wb_stb[state_nxt];
        o_wb_cyc_nxt = wb_cyc[state_nxt];
        o_wb_adr_nxt = wb_adr[state_nxt];
        o_wb_dat_nxt = wb_dat[state_nxt];
        o_wb_cti_nxt = wb_cti[state_nxt];
        o_wb_sel_nxt = wb_sel[state_nxt];
        o_wb_wen_nxt = wb_wen[state_nxt];
end

endmodule // zap_cache


