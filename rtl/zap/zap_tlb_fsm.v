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
// --  An automatic page fetching system.                                     --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none

`include "zap_defines.vh"

module zap_tlb_fsm #(

// Pass from top.
parameter LPAGE_TLB_ENTRIES   = 8,
parameter SPAGE_TLB_ENTRIES   = 8,
parameter SECTION_TLB_ENTRIES = 8

)(

/* Clock and Reset */
input   wire                    i_clk,
input   wire                    i_reset,

/* From CP15 */
input   wire                    i_mmu_en,
input   wire   [31:0]           i_baddr,

/* From cache FSM */
input   wire   [31:0]           i_address,

/* From TLB check unit */
input   wire                    i_walk,
input   wire    [7:0]           i_fsr,
input   wire    [31:0]          i_far,
input   wire                    i_cacheable,
input   wire    [31:0]          i_phy_addr,

/* To main cache FSM */
output reg    [7:0]             o_fsr,
output  reg   [31:0]            o_far,
output  reg                     o_fault,
output  reg   [31:0]            o_phy_addr,
output  reg                     o_cacheable,
output  reg                     o_busy,

/* To TLBs */
output reg      [`SECTION_TLB_WDT-1:0] o_setlb_wdata,
output reg                      o_setlb_wen,
output reg      [`SPAGE_TLB_WDT-1:0] o_sptlb_wdata,
output reg                      o_sptlb_wen,
output  reg     [`LPAGE_TLB_WDT-1:0] o_lptlb_wdata,
output  reg                     o_lptlb_wen,

/* Wishbone signals NXT */
output  wire                    o_wb_cyc_nxt,
output  wire                    o_wb_stb_nxt,
output  wire    [31:0]          o_wb_adr_nxt,

/* Wishbone Signals */
output wire                     o_wb_cyc,
output wire                     o_wb_stb,
output wire                     o_wb_wen,
output wire [3:0]               o_wb_sel, o_wb_sel_nxt,
output wire [31:0]              o_wb_adr,
input  wire [31:0]              i_wb_dat,
input  wire                     i_wb_ack,

// Unused.
output wire o_unused_ok

);

`include "zap_localparams.vh"
`include "zap_defines.vh"
`include "zap_functions.vh"

// ----------------------------------------------------------------------------

/* States */
localparam IDLE                 = 0; /* Idle State */
localparam FETCH_L1_DESC        = 1; /* Fetch L1 descriptor */
localparam FETCH_L2_DESC        = 2; /* Fetch L2 descriptor */
localparam REFRESH_CYCLE        = 3; /* Refresh TLBs and cache */
localparam FETCH_L1_DESC_0      = 4;
localparam FETCH_L2_DESC_0      = 5;
localparam NUMBER_OF_STATES     = 6; 

// ----------------------------------------------------------------------------

reg [3:0] dac_ff, dac_nxt;                              /* Scratchpad register */
reg [$clog2(NUMBER_OF_STATES)-1:0] state_ff, state_nxt; /* State register */

/* Wishbone related */
reg        wb_stb_nxt, wb_stb_ff;
reg        wb_cyc_nxt, wb_cyc_ff;
reg [31:0] wb_adr_nxt, wb_adr_ff;

// ----------------------------------------------------------------------------

/* Tie output flops to ports. */
assign o_wb_cyc         = wb_cyc_ff;
assign o_wb_stb         = wb_stb_ff;
assign o_wb_adr         = wb_adr_ff;

assign o_wb_cyc_nxt     = wb_cyc_nxt;
assign o_wb_stb_nxt     = wb_stb_nxt;
assign o_wb_adr_nxt     = wb_adr_nxt;

reg [3:0] wb_sel_nxt, wb_sel_ff;

/* Tied PORTS */
assign o_wb_wen = 1'd0;
assign o_wb_sel = wb_sel_ff;
assign o_wb_sel_nxt = wb_sel_nxt;

assign o_unused_ok = 0 || i_baddr[13:0];

reg [31:0] dff, dnxt; /* Wishbone memory buffer. */

/* Combinational logic */
always @*
begin: blk1

        o_fsr           = 0;
        o_far           = 0;
        o_fault         = 0;
        o_busy          = 0;
        o_phy_addr      = i_phy_addr;
        o_cacheable     = i_cacheable;
        o_setlb_wen     = 0;
        o_lptlb_wen     = 0;
        o_sptlb_wen     = 0;
        o_setlb_wdata  = 0;
        o_sptlb_wdata   = 0;
        o_lptlb_wdata   = 0;

        /* Kill wishbone access unless overridden */
        wb_stb_nxt      = 0;
        wb_cyc_nxt      = 0;
        wb_adr_nxt      = 0;
        wb_sel_nxt      = 0;

        dac_nxt         = dac_ff;
        state_nxt       = state_ff;

        dnxt            = dff;

        case ( state_ff )
        IDLE:
        begin
                if ( i_mmu_en )
                begin
                        if ( i_walk )
                        begin
                                $display($time, " - %m :: Page fault! Need to page walk! i_walk = %b", i_walk);
                                $display($time, " - %m :: Core generated address %x", i_address);
                                $display($time, " - %m :: Moving to FETCH_L1_DESC. i_baddr = %x baddr_tran_base = %x addr_va_table_index = %x", 
                                         i_baddr, i_baddr[`VA__TRANSLATION_BASE], i_address[`VA__TABLE_INDEX]);

                                `ifdef TLB_DEBUG
                                        $stop;
                                `endif

                                o_busy = 1'd1;

                                /*
                                 * We need to page walk to get the page table.
                                 * Call for access to L1 level page table.
                                 */
                                tsk_prpr_wb_rd({i_baddr[`VA__TRANSLATION_BASE], 
                                           i_address[`VA__TABLE_INDEX], 2'd0});

                                state_nxt = FETCH_L1_DESC_0;
                        end
                        else if ( i_fsr[3:0] != 4'b0000 ) /* Access Violation. */
                        begin
                                $display($time, " - %m :: Access violation fsr = %x far = %x...", i_fsr, i_far);

                                `ifdef TLB_DEBUG
                                        $stop;
                                `endif

                                o_fault = 1'd1;
                                o_busy  = 1'd0;
                                o_fsr   = i_fsr;
                                o_far   = i_far;
                        end
                        else
                        begin
                                `ifdef DISP_TLB_SUCCESS
                                        $display($time, " - %m :: TLB Hit for address = %x MMU enable = %x!", i_address, i_mmu_en);
                                `endif

                                `ifdef TLB_DEBUG
                                        $stop;
                                `endif
                        end
                end
        end

        FETCH_L1_DESC_0:
        begin
                $display($time, " - %m :: In state FETCH_L1_DESC_0");

                o_busy = 1;

                if ( i_wb_ack )
                begin
                        dnxt = i_wb_dat;
                        state_nxt = FETCH_L1_DESC;

                        $display($time, " - %m :: Received %x from WB. Moving to FETCH_L1_DESC...", dnxt );
                end
                else tsk_hold_wb_access;
        end

        FETCH_L1_DESC:
        begin
                /*
                 * What we would have fetched is the L1 descriptor.
                 * Examine it. dff holds the L1 descriptor.
                 */

                $display($time, " - %m :: In FETCH_L1_DESC state...");

                o_busy = 1'd1;

                if ( 1 ) 
                begin
                        $display($time, " - %m :: ACK received. Read data is %x", i_wb_dat);

                        `ifdef TLB_DEBUG
                                $stop;
                        `endif

                        case ( dff[`ID] )

                        SECTION_ID:
                        begin
                                /*
                                 * It is a section itself so there is no need
                                 * for another fetch. Simply reload the TLB
                                 * and we are good.
                                 */  
                                o_setlb_wen       = 1'd1;
                                o_setlb_wdata     = {i_address[`VA__SECTION_TAG], 
                                                     dff};
                                state_nxt       = REFRESH_CYCLE; 

                                $display($time, " - %m :: It is a section ID. Writing to section TLB as %x. Moving to refresh cycle...", o_setlb_wdata);

                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m ::             SECTION DESCRIPTOR DETAILS                  #");
                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m :: # BASE ADDRESS  = 0x%x ", o_setlb_wdata[`SECTION_TLB__BASE]);
                                $display($time, " - %m :: # DAC           = 0b%b",  o_setlb_wdata[`SECTION_TLB__DAC_SEL]);
                                $display($time, " - %m :: # AP bits       = 0b%b",  o_setlb_wdata[`SECTION_TLB__AP]);
                                $display($time, " - %m :: # Cacheable     = 0b%b",  o_setlb_wdata[`SECTION_TLB__CB] >> 1);
                                $display($time, " - %m :: # Bufferable    = 0b%b",  o_setlb_wdata[`SECTION_TLB__CB] & 2'b01);
                                $display($time, " - %m :: #########################################################");

                                `ifdef TLB_DEBUG                
                                        $stop;
                                `endif
                        end

                        PAGE_ID:
                        begin
                                /*
                                 * Page ID requires that DAC from current
                                 * descriptor is remembered because when we
                                 * reload the TLB, it would be useful. Anyway,
                                 * we need to initiate another access.
                                 */      
                                dac_nxt         = dff[`L1_PAGE__DAC_SEL];  // dac register holds the dac sel for future use.
                                state_nxt       = FETCH_L2_DESC_0;

                                tsk_prpr_wb_rd({dff[`L1_PAGE__PTBR], 
                                                  i_address[`VA__L2_TABLE_INDEX], 2'd0});

                                $display($time, " - %m :: L1 received Page ID.");

                                `ifdef TLB_DEBUG
                                        $stop;
                                `endif
                        end               

                        default: /* Generate section translation fault. Fault Class II */
                        begin
                                o_fsr        = FSR_SECTION_TRANSLATION_FAULT;
                                o_fsr        = {dff[`L1_SECTION__DAC_SEL], o_fsr[3:0]};
                                o_far        = i_address;
                                o_fault      = 1'd1;
                                o_busy       = 1'd0;
                                state_nxt    = IDLE;

                                $display($time, " - %m :: FSR section translation fault!");

                                `ifdef TLB_DEBUG
                                        $stop;
                                `endif
                        end
 
                        endcase
                end
                else tsk_hold_wb_access;
        end

        FETCH_L2_DESC_0:
        begin
                        o_busy = 1;

                        if ( i_wb_ack )
                        begin
                                dnxt            = i_wb_dat;
                                state_nxt       = FETCH_L2_DESC;
                        end 
                        else 
                        begin
                                tsk_hold_wb_access;
                        end
        end

        FETCH_L2_DESC:
        begin
                o_busy = 1'd1;

                if ( 1 )
                begin
                        case ( dff[`ID] ) // dff holds L2 descriptor. dac_ff holds L1 descriptor DAC.
                        SPAGE_ID:
                        begin
                                /* Update TLB */
                                o_sptlb_wen   = 1'd1;

                                /* Define TLB fields to write */
                                o_sptlb_wdata[`SPAGE_TLB__TAG]     = i_address[`VA__SPAGE_TAG];
                                o_sptlb_wdata[`SPAGE_TLB__DAC_SEL] = dac_ff;                    /* DAC selector from L1. */
                                o_sptlb_wdata[`SPAGE_TLB__AP]      = dff[`L2_SPAGE__AP];
                                o_sptlb_wdata[`SPAGE_TLB__CB]      = dff[`L2_SPAGE__CB];
                                o_sptlb_wdata[`SPAGE_TLB__BASE]    = dff[`L2_SPAGE__BASE];

                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m ::               SPAGE DESCRIPTOR DETAILS                  #");
                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m :: # BASE ADDRESS  = 0x%x ", o_sptlb_wdata[`SPAGE_TLB__BASE]);
                                $display($time, " - %m :: # DAC           = 0b%b",  o_sptlb_wdata[`SPAGE_TLB__DAC_SEL]);
                                $display($time, " - %m :: # AP bits       = 0b%b",  o_sptlb_wdata[`SPAGE_TLB__AP]);
                                $display($time, " - %m :: # Cacheable     = 0b%b",  o_sptlb_wdata[`SPAGE_TLB__CB] >> 1);
                                $display($time, " - %m :: # Bufferable    = 0b%b",  o_sptlb_wdata[`SPAGE_TLB__CB] & 2'b01);
                                $display($time, " - %m :: #########################################################");

                                /* Go to REFRESH */
                                state_nxt   = REFRESH_CYCLE;
                        end

                        LPAGE_ID:
                        begin
                                /* Update TLB */
                                o_lptlb_wen   = 1'd1;

                                /* DAC is inserted in between to save bits */
                                o_lptlb_wdata = {i_address[`VA__LPAGE_TAG], dac_ff, dff};

                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m ::               LPAGE DESCRIPTOR DETAILS                  #");
                                $display($time, " - %m :: #########################################################");
                                $display($time, " - %m :: # BASE ADDRESS  = 0x%x ", o_lptlb_wdata[`LPAGE_TLB__BASE]);
                                $display($time, " - %m :: # DAC           = 0b%b",  o_lptlb_wdata[`LPAGE_TLB__DAC_SEL]);
                                $display($time, " - %m :: # AP bits       = 0b%b",  o_lptlb_wdata[`LPAGE_TLB__AP]);
                                $display($time, " - %m :: # Cacheable     = 0b%b",  o_lptlb_wdata[`LPAGE_TLB__CB] >> 1);
                                $display($time, " - %m :: # Bufferable    = 0b%b",  o_lptlb_wdata[`LPAGE_TLB__CB] & 2'b01);
                                $display($time, " - %m :: #########################################################");

                                state_nxt   = REFRESH_CYCLE;
                        end

                        default: /* Fault Class II */
                        begin
                                o_busy    = 1'd0;
                                o_fault   = 1'd1;
                                o_fsr     = FSR_PAGE_TRANSLATION_FAULT;
                                o_fsr     = {1'd0, dac_ff, o_fsr[3:0]};
                                o_far     = i_address;
                                state_nxt = IDLE;
                        end
                        endcase
                end
                else tsk_hold_wb_access;
        end

        REFRESH_CYCLE:
        begin
                $display($time, " - %m :: Entered refresh cycle. Moving to IDLE...");

                `ifdef TLB_DEBUG
                        $stop;
                `endif

                o_busy    = 1'd1;
                state_nxt = IDLE;
        end

        endcase
end

// ----------------------------------------------------------------------------

// Clocked Logic.
always @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                 state_ff        <=      IDLE;
                 wb_stb_ff       <=      0;
                 wb_cyc_ff       <=      0;
                 wb_adr_ff       <=      0;
                 wb_sel_ff       <=      0;
        end
        else
        begin
                state_ff        <=      state_nxt;
                wb_stb_ff       <=      wb_stb_nxt;
                wb_cyc_ff       <=      wb_cyc_nxt;
                wb_adr_ff       <=      wb_adr_nxt;
                dac_ff          <=      dac_nxt;
                wb_sel_ff       <=      wb_sel_nxt;
                dff             <=      dnxt;
        end
end

// ----------------------------------------------------------------------------

task tsk_hold_wb_access;
begin
        wb_stb_nxt = wb_stb_ff;
        wb_cyc_nxt = wb_cyc_ff;
        wb_adr_nxt = wb_adr_ff;
        wb_sel_nxt = wb_sel_ff;
end
endtask

task tsk_prpr_wb_rd ( input [31:0] adr );
begin
        $display($time, " - %m :: Reading from location %x", adr);

        `ifdef TLB_DEBUG
                $stop;
        `endif

        wb_stb_nxt      = 1'd1;
        wb_cyc_nxt      = 1'd1;
        wb_adr_nxt      = adr;
        wb_sel_nxt[3:0] = 4'b1111;
end
endtask

// ----------------------------------------------------------------------------

// assertions_start

always @ (posedge i_mmu_en)
begin
        $display($time, " - %m :: MMU Enabled!");
end

always @ (negedge i_mmu_en)
begin
        $display($time, " - %m :: MMU Disabled!");
end

// assertions_end

endmodule // zap_tlb_fsm.v

`default_nettype wire
