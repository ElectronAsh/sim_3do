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
// -- This is the top level cache module that contains the MMU and cache.     --
// -- This will be instantiated twice in the processor TOP, once for          --
// -- instruction and the other for data.                                     --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

module zap_cache #(

parameter [31:0] CACHE_SIZE             = 1024, 
parameter [31:0] SPAGE_TLB_ENTRIES      = 8,
parameter [31:0] LPAGE_TLB_ENTRIES      = 8,
parameter [31:0] SECTION_TLB_ENTRIES    = 8

) /* Port List */ (

// Clock and reset.
input   wire            i_clk,
input   wire            i_reset,

// Address from processor.
input   wire    [31:0]  i_address,
input   wire    [31:0]  i_address_nxt,

// Other control signals from/to processor.
input   wire            i_rd,
input   wire            i_wr,
input   wire [3:0]      i_ben,
input   wire [31:0]     i_dat,
output wire  [31:0]     o_dat,
output  wire            o_ack,
output  wire            o_err,
output  wire [7:0]      o_fsr,
output wire [31:0]      o_far,

// MMU controls from/to processor.
input   wire            i_mmu_en,
input   wire            i_cache_en,
input   wire            i_cache_inv_req,
input   wire            i_cache_clean_req,
output wire             o_cache_inv_done,
output  wire            o_cache_clean_done,
input   wire [31:0]     i_cpsr,
input   wire [1:0]      i_sr,
input   wire [31:0]     i_baddr,
input   wire [31:0]     i_dac_reg,
input  wire             i_tlb_inv,

// Wishbone. Signals from all 4 modules are ORed.
output reg              o_wb_stb, o_wb_stb_nxt, 
output reg              o_wb_cyc, o_wb_cyc_nxt,
output reg              o_wb_wen, o_wb_wen_nxt,
output reg  [3:0]       o_wb_sel, o_wb_sel_nxt,
output reg  [31:0]      o_wb_dat, o_wb_dat_nxt,
output reg  [31:0]      o_wb_adr, o_wb_adr_nxt,
output reg  [2:0]       o_wb_cti, o_wb_cti_nxt,
input  wire [31:0]      i_wb_dat,
input  wire             i_wb_ack

);

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

localparam                      S0=0;
localparam                      S1=1;
localparam                      S2=2;

wire [2:0]                      wb_stb; 
wire [2:0]                      wb_cyc; 
wire [2:0]                      wb_wen;
wire [3:0]                      wb_sel [2:0];
wire [31:0]                     wb_dat [2:0];
wire [31:0]                     wb_adr [2:0];
wire [2:0]                      wb_cti [2:0];
wire [31:0]                     wb_dat0_cachefsm, wb_dat1_tagram, wb_dat2_tlb;
wire [31:0]                     tlb_phy_addr;
wire [7:0]                      tlb_fsr;
wire [31:0]                     tlb_far;
wire                            tlb_fault;
wire                            tlb_cacheable;
wire                            tlb_busy;
wire [127:0]                    tr_cache_line;
wire [127:0]                    cf_cache_line;
wire [15:0]                     cf_cache_line_ben;
wire                            cf_cache_tag_wr_en;
wire [`CACHE_TAG_WDT-1:0]       tr_cache_tag, cf_cache_tag;
wire                            tr_cache_tag_valid;
wire                            tr_cache_tag_dirty, cf_cache_tag_dirty;
wire                            cf_cache_clean_req, cf_cache_inv_req;
wire                            tr_cache_inv_done, tr_cache_clean_done;
reg [2:0]                       wb_ack;
reg [1:0]                       state_ff, state_nxt;

// Data from each Wishbone master.
assign wb_dat0_cachefsm = wb_dat[0];
assign wb_dat1_tagram   = wb_dat[1];
assign wb_dat2_tlb      = wb_dat[2];

// Bit 2 of Wishbone CTI is always on all CPU supported modes.
assign wb_cti[2] = 0;

// Basic cache FSM - serves as Master 0.
zap_cache_fsm #(.CACHE_SIZE(CACHE_SIZE)) u_zap_cache_fsm (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address              (i_address),
        .i_rd                   (i_rd),
        .i_wr                   (i_wr),
        .i_din                  (i_dat),
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
        .o_wb_cyc_ff            (),
        .o_wb_cyc_nxt           (wb_cyc[0]),
        .o_wb_stb_ff            (),
        .o_wb_stb_nxt           (wb_stb[0]),
        .o_wb_adr_ff            (),
        .o_wb_adr_nxt           (wb_adr[0]),
        .o_wb_dat_ff            (),
        .o_wb_dat_nxt           (wb_dat[0]),
        .o_wb_sel_ff            (),
        .o_wb_sel_nxt           (wb_sel[0]),
        .o_wb_wen_ff            (),
        .o_wb_wen_nxt           (wb_wen[0]),
        .o_wb_cti_ff            (),
        .o_wb_cti_nxt           (wb_cti[0]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[0])
);

// Cache Tag RAM - As a master - this performs cache clean - Master 1.
zap_cache_tag_ram #(.CACHE_SIZE(CACHE_SIZE)) u_zap_cache_tag_ram     (
        .i_clk                  (i_clk),
        .i_reset                (i_reset),
        .i_address_nxt          (i_address_nxt),
        .i_address              (i_address),
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
        .o_wb_cyc_ff            (),
        .o_wb_cyc_nxt           (wb_cyc[1]),
        .o_wb_stb_ff            (),
        .o_wb_stb_nxt           (wb_stb[1]),
        .o_wb_adr_ff            (),
        .o_wb_adr_nxt           (wb_adr[1]),
        .o_wb_dat_ff            (),
        .o_wb_dat_nxt           (wb_dat[1]),
        .o_wb_sel_ff            (),
        .o_wb_sel_nxt           (wb_sel[1]),
        .o_wb_wen_ff            (),
        .o_wb_wen_nxt           (wb_wen[1]),
        .o_wb_cti_ff            (),
        .o_wb_cti_nxt           (wb_cti[1]),
        .i_wb_dat               (i_wb_dat),
        .i_wb_ack               (wb_ack[1])
);

// ZAP TLB control module. Includes TLB RAM inside.
zap_tlb #(
        .LPAGE_TLB_ENTRIES      (LPAGE_TLB_ENTRIES),
        .SPAGE_TLB_ENTRIES      (SPAGE_TLB_ENTRIES),
        .SECTION_TLB_ENTRIES    (SECTION_TLB_ENTRIES))
u_zap_tlb (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_address      (i_address),
        .i_address_nxt  (i_address_nxt),
        .i_rd           (i_rd),
        .i_wr           (i_wr),
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
always @ ( posedge i_clk )
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
always @*
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
always @*
begin
        wb_ack = 0;

        case(state_ff)
        S0: wb_ack[0] = i_wb_ack;
        S1: wb_ack[1] = i_wb_ack;
        S2: wb_ack[2] = i_wb_ack;
        endcase
end

// Combo signals for external MUXing.
always @*
begin
        o_wb_stb_nxt = wb_stb[state_nxt];
        o_wb_cyc_nxt = wb_cyc[state_nxt];
        o_wb_adr_nxt = wb_adr[state_nxt];
        o_wb_dat_nxt = wb_dat[state_nxt];
        o_wb_cti_nxt = wb_cti[state_nxt];
        o_wb_sel_nxt = wb_sel[state_nxt];
        o_wb_wen_nxt = wb_wen[state_nxt];
end

// assertions_start
        reg     xerr = 0;
        
        always @ (posedge i_clk)
        begin 
                // Check if data delivered to processor is 'x'.
                if ( o_dat[0] === 1'dx && o_ack && i_rd )
                begin
                        $display($time, "Error : %m Data went to x when giving data to core.");
                        xerr = xerr + 1;
                        $stop;
                end
        end
// assertions_end

endmodule // zap_cache

`default_nettype wire
