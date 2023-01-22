//
//  (C) 2016-2022 Revanth Kamaraj (krevanth)
//
//  This program is free software; you can redistribute it and/or
//  modify it under the terms of the GNU General Public License
//  as published by the Free Software Foundation; either version 3
//  of the License, or (at your option) any later version.
//
//  This program is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU General Public License for more details.
//
//  You should have received a copy of the GNU General Public License
//  along with this program; if not, write to the Free Software
//  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
//  02110-1301, USA.
//
//  This is the core state machine for the memory subsystem. Talks to both
//  processor and the TLB controller. Cache uploads and downloads are done
//  using an incrementing burst on the Wishbone bus for maximum efficiency
//

`include "zap_defines.svh"

module zap_cache_fsm   #(
        parameter logic [31:0] CACHE_SIZE    = 32'd1024,  // Bytes.
        parameter logic [31:0] CACHE_LINE    = 32'd8
)

// ----------------------------------------------
//  Port List
// ----------------------------------------------

(

// Clock and reset
input   logic                      i_clk,
input   logic                      i_reset,

// From/to processor
input   logic    [31:0]            i_address,
input   logic                      i_rd,
input   logic                      i_wr,
input   logic    [31:0]            i_din,
input   logic    [3:0]             i_ben,

output  logic     [31:0]            o_dat,
output  logic                       o_ack,
output  logic                       o_err,
output  logic     [7:0]             o_fsr,
output  logic     [31:0]            o_far,
output  logic                       o_err2,

// From/To CP15 unit
input   logic                      i_cache_en,
input   logic                      i_cache_inv,
input   logic                      i_cache_clean,

output  logic                       o_cache_inv_done,
output  logic                       o_cache_clean_done,

// From/to cache.
input   logic    [CACHE_LINE*8-1:0]     i_cache_line,

input   logic                           i_cache_tag_dirty,
input   logic  [`ZAP_CACHE_TAG_WDT-1:0] i_cache_tag,
input   logic                           i_cache_tag_valid,

output  logic   [`ZAP_CACHE_TAG_WDT-1:0] o_cache_tag,
output  logic                            o_cache_tag_dirty,
output  logic                            o_cache_tag_wr_en,

output  logic     [CACHE_LINE*8-1:0] o_cache_line,
output  logic     [CACHE_LINE-1:0]   o_cache_line_ben,

output  logic                       o_cache_clean_req,
input   logic                       i_cache_clean_done,

output  logic                       o_cache_inv_req,
input   logic                       i_cache_inv_done,

output logic [31:0]                 o_address,

// From/to TLB unit
input   logic    [31:0]            i_phy_addr,
input   logic    [7:0]             i_fsr,
input   logic    [31:0]            i_far,
input   logic                      i_fault,
input   logic                      i_cacheable,
input   logic                      i_busy,
output  logic                      o_hold,

// Cache state
output  logic                      o_idle,

// Bus access ports.
output  logic                   o_wb_cyc_ff, o_wb_cyc_nxt,
output  logic                   o_wb_stb_ff, o_wb_stb_nxt,
output  logic     [31:0]        o_wb_adr_ff, o_wb_adr_nxt,
output  logic     [31:0]        o_wb_dat_ff, o_wb_dat_nxt,
output  logic     [3:0]         o_wb_sel_ff, o_wb_sel_nxt,
output  logic                   o_wb_wen_ff, o_wb_wen_nxt,
output  logic     [2:0]         o_wb_cti_ff, o_wb_cti_nxt,
input   logic                   i_wb_ack,
input   logic    [31:0]         i_wb_dat,
input   logic                   i_wb_err

);

// ----------------------------------------------------------------------------
// Includes and Localparams
// ----------------------------------------------------------------------------

`include "zap_localparams.svh"
`include "zap_defines.svh"

// States
localparam [2:0] IDLE                 = 3'd0; // Resting state.
localparam [2:0] UNCACHEABLE          = 3'd1; // Uncacheable access.
localparam [2:0] UNCACHEABLE_PREPARE  = 3'd2; // Prepare uncacheable access.
localparam [2:0] CLEAN_SINGLE         = 3'd3; // Ultimately cleans up cache line. Parent state
localparam [2:0] FETCH_SINGLE         = 3'd4; // Ultimately validates cache line. Parent state
localparam [2:0] INVALIDATE           = 3'd5; // Cache invalidate parent state
localparam [2:0] CLEAN                = 3'd6; // Cache clean parent state

localparam [31:0] NUMBER_OF_STATES    = 32'd7;

localparam [31:0] ADR_PAD              =  32'd32 - $clog2(CACHE_LINE/4) - 32'd1;
localparam [31:0] ADR_PAD_MINUS_2      =  ADR_PAD - 32'd2;
localparam [31:0] LINE_PAD             = (CACHE_LINE * 32'd8) - 32'd32;

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

logic                                     cache_cmp;
logic                                     cache_dirty;

logic [$clog2(NUMBER_OF_STATES)-1:0]      state_ff, state_nxt;
logic [31:0]                              buf_ff [(CACHE_LINE/4)-1:0];
logic [31:0]                              buf_nxt[(CACHE_LINE/4)-1:0];
logic                                     cache_clean_req_nxt,
                                          cache_clean_req_ff;
logic                                     cache_inv_req_nxt,
                                          cache_inv_req_ff;
logic [$clog2(CACHE_LINE/4):0]            adr_ctr_ff, adr_ctr_nxt; // Needs to take on 0,1,2,3, ... CACHE_LINE/4
logic                                     rhit, whit;              // For debug only.

// From/to processor
logic    [31:0]                           address;
logic                                     wr;
logic    [31:0]                           din;
logic    [3:0]                            ben; // Valid only for writes.
logic    [CACHE_LINE*8-1:0]               cache_line;
logic  [`ZAP_CACHE_TAG_WDT-1:0]           cache_tag; // Tag
logic    [31:0]                           phy_addr;

logic                                     UNUSED_1B, UNUSED_2B, unused;

// ----------------------------------------------------------------------------
// Logic
// ----------------------------------------------------------------------------

// Unused
always_comb unused = |{rhit, whit, UNUSED_1B, UNUSED_2B, phy_addr[$clog2(CACHE_LINE)-1:0]};

// Tie flops to the output
always_comb o_cache_clean_req = cache_clean_req_ff; // Tie req flop to output.
always_comb o_cache_inv_req   = cache_inv_req_ff;   // Tie inv flop to output.

// Alias
always_comb cache_cmp   = (i_cache_tag[`ZAP_CACHE_TAG__TAG] == i_address[`ZAP_VA__CACHE_TAG]);
always_comb cache_dirty = i_cache_tag_dirty;

// Buffers
always_ff @ ( posedge i_clk )
begin
        if ( state_ff == IDLE )
        begin
                address         <= i_address ;
                wr              <= i_wr;
                din             <= i_din;
                ben             <= i_ben;
                cache_line      <= i_cache_line;
                cache_tag       <= i_cache_tag;
                phy_addr        <= i_phy_addr;
        end
end

// Sequential Block
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                o_wb_cyc_ff             <= 0;
                o_wb_stb_ff             <= 0;
                o_wb_wen_ff             <= 'x;
                o_wb_sel_ff             <= 'x;
                o_wb_dat_ff             <= 'x;
                o_wb_cti_ff             <= CTI_EOB;
                o_wb_adr_ff             <= 'x;
                cache_clean_req_ff      <= 0;
                cache_inv_req_ff        <= 0;
                adr_ctr_ff              <= 0;
                state_ff                <= IDLE;
        end
        else
        begin
                o_wb_cyc_ff             <= o_wb_cyc_nxt;
                o_wb_stb_ff             <= o_wb_stb_nxt;
                o_wb_wen_ff             <= o_wb_wen_nxt;
                o_wb_sel_ff             <= o_wb_sel_nxt;
                o_wb_dat_ff             <= o_wb_dat_nxt;
                o_wb_cti_ff             <= o_wb_cti_nxt;
                o_wb_adr_ff             <= o_wb_adr_nxt;
                cache_clean_req_ff      <= cache_clean_req_nxt;
                cache_inv_req_ff        <= cache_inv_req_nxt;
                adr_ctr_ff              <= adr_ctr_nxt;
                state_ff                <= state_nxt;
        end
end

always_ff @ ( posedge i_clk )
begin
        for(int i=0;i<CACHE_LINE/4;i++)
        begin
                buf_ff[i] <= buf_nxt[i];
        end
end

// Idle indication
always_ff @ ( posedge i_clk )
begin
        o_idle <= ~(|state_nxt);
end

// Combo block
always_comb
begin:blk1
       logic [$clog2(CACHE_LINE/4)-1:0] a;

       UNUSED_1B = '0;
       UNUSED_2B = '0;

        // Default values
        a                       = {($clog2(CACHE_LINE/4)){1'd0}};
        state_nxt               = state_ff;
        adr_ctr_nxt             = adr_ctr_ff;
        o_wb_cyc_nxt            = o_wb_cyc_ff;
        o_wb_stb_nxt            = o_wb_stb_ff;
        o_wb_adr_nxt            = o_wb_adr_ff;
        o_wb_dat_nxt            = o_wb_dat_ff;
        o_wb_cti_nxt            = o_wb_cti_ff;
        o_wb_wen_nxt            = o_wb_wen_ff;
        o_wb_sel_nxt            = o_wb_sel_ff;
        cache_clean_req_nxt     = cache_clean_req_ff;
        cache_inv_req_nxt       = cache_clean_req_ff;
        o_fsr                   = 0;
        o_far                   = 0;
        o_cache_tag             = 0;
        o_cache_inv_done        = 0;
        o_cache_clean_done      = 0;
        o_cache_tag_dirty       = 0;
        o_cache_tag_wr_en       = 0;
        o_cache_line            = 0;
        o_cache_line_ben        = 0;
        o_hold                  = 1'd0;

        // Output data port.
        if ( state_ff == UNCACHEABLE )
        begin
                o_dat           = i_wb_dat;
        end
        else
        begin
                o_dat           = adapt_cache_data(i_address[$clog2(CACHE_LINE)-1:2],
                                                   i_cache_line);
        end

        o_ack                   = 0;
        o_err                   = 0;
        o_err2                  = 0;
        o_address               = address;

        for(int i=0;i<CACHE_LINE/4;i++)
        begin
                buf_nxt[i] = buf_ff[i];
        end

        rhit                     = 0;
        whit                     = 0;

        case(state_ff)

        IDLE:
        begin
                kill_access ();

                if ( i_cache_inv )
                begin
                        o_ack     = 1'd0;
                        state_nxt = INVALIDATE;
                end
                else if ( i_cache_clean )
                begin
                        o_ack     = 1'd0;
                        state_nxt = CLEAN;
                end
                else if ( !i_rd && !i_wr )
                begin
                        o_ack = 1'd1;
                end
                else if ( i_fault )
                begin
                        // MMU access fault.
                        o_err = 1'd1;
                        o_ack = 1'd1;
                        o_fsr = i_fsr;
                        o_far = i_far;
                end
                else if ( i_busy )
                begin
                        // Wait it out
                        o_err2 = 1'd1;
                        o_ack  = 1'd1;
                end
                else if ( i_rd || i_wr )
                begin
                        if ( !i_cache_en )
                        begin
                                state_nxt       = UNCACHEABLE;
                                o_ack           = 1'd0; // Wait...
                                o_wb_stb_nxt    = 1'd1;
                                o_wb_cyc_nxt    = 1'd1;
                                o_wb_adr_nxt    = i_address;
                                o_wb_dat_nxt    = i_din;
                                o_wb_wen_nxt    = i_wr;
                                o_wb_sel_nxt    = i_ben;
                                o_wb_cti_nxt    = CTI_EOB;
                        end
                        else if ( i_cacheable )
                        begin
                                case ({cache_cmp,i_cache_tag_valid})

                                2'b11: // Cache Hit
                                begin
                                        if ( i_rd ) // Read request.
                                        begin
                                                rhit    = 1'd1;
                                                o_ack   = 1'd1;
                                        end
                                        else if ( i_wr ) // Write request
                                        begin
                                                o_ack        = 1'd1;
                                                whit         = 1'd1;

                                                o_cache_line =
                                                {(CACHE_LINE/4){i_din}};

                                                o_cache_line_ben  = ben_comp (
                                                        i_address[$clog2(CACHE_LINE)-1:2],
                                                        i_ben );

                                                // Write to tag and also write out physical address.
                                                o_cache_tag_wr_en                = 1'd1;
                                                o_cache_tag[`ZAP_CACHE_TAG__TAG] = i_address[`ZAP_VA__CACHE_TAG];
                                                o_cache_tag_dirty                = 1'd1;
                                                o_cache_tag[`ZAP_CACHE_TAG__PA]  = i_phy_addr[31 : $clog2(CACHE_LINE)];
                                                o_address                        = i_address;
                                        end
                                end

                                2'b01: // Unrelated tag, possibly dirty.
                                begin
                                        // CPU should retry
                                        o_ack  = 1'd1;
                                        o_err2 = 1'd1;

                                        if ( cache_dirty )
                                        begin
                                                // Set up counter
                                                adr_ctr_nxt = 0;

                                                // Clean a single cache line
                                                state_nxt = CLEAN_SINGLE;
                                        end
                                        else if ( i_rd | i_wr )
                                        begin
                                                // Set up counter
                                                adr_ctr_nxt = 0;

                                                // Fetch a single cache line
                                                state_nxt = FETCH_SINGLE;
                                        end
                                end

                                default: // Need to generate a new tag.
                                begin
                                                // CPU should wait.
                                                o_ack  = 1'd1;
                                                o_err2 = 1'd1;

                                                // Set up counter
                                                adr_ctr_nxt = 0;

                                                // Fetch a single cache line
                                                state_nxt = FETCH_SINGLE;
                                end
                                endcase
                        end
                        else // Non cacheable.
                        begin
                                state_nxt       = UNCACHEABLE_PREPARE;
                                o_ack           = 1'd0; // Wait...
                                o_hold          = 1'd1;
                        end
                end
        end

        UNCACHEABLE_PREPARE:
        begin
                o_ack           = 1'd0;
                o_hold          = 1'd1;
                state_nxt       = UNCACHEABLE;
                o_wb_stb_nxt    = 1'd1;
                o_wb_cyc_nxt    = 1'd1;
                o_wb_adr_nxt    = i_phy_addr;
                o_wb_dat_nxt    = i_din;
                o_wb_wen_nxt    = i_wr;
                o_wb_sel_nxt    = i_ben;
                o_wb_cti_nxt    = CTI_EOB;
        end

        UNCACHEABLE:
        // Uncacheable reads and writes definitely go through this.
        begin
                o_ack  = 1'd0;
                o_hold = 1'd1;

                if ( i_wb_ack )
                begin
                        if ( i_wb_err )
                        begin
                                assert ( i_wb_ack) else $fatal(2, "Error: ERR=1 but ACK=0");
                        end

                        o_ack           = 1'd1;
                        o_hold          = 1'd0;
                        state_nxt       = IDLE;
                        o_err           = i_wb_err;
                        o_fsr[3:0]      = TERMINAL_EXCEPTION;

                        kill_access ();
                end
        end

        CLEAN_SINGLE: // Clean single cache line
        begin
                o_ack  = 1'd1;
                o_err2 = i_rd || i_wr ? 1'd1 : 1'd0;

                // Generate address
                adr_ctr_nxt = adr_ctr_ff + ((o_wb_stb_ff && i_wb_ack) ? {{($clog2(CACHE_LINE/4) ){1'd0}}, 1'd1} :
                                                                         {($clog2(CACHE_LINE/4)+1){1'd0}});

                if ( {{ADR_PAD{1'd0}}, adr_ctr_nxt} <= ((CACHE_LINE/4) - 1) )
                begin
                        // Sync up with memory. Use PA in cache tag itself.
                        wb_prpr_write( clean_single_d (cache_line, adr_ctr_nxt),

                                      {cache_tag[`ZAP_CACHE_TAG__PA], {$clog2(CACHE_LINE){1'd0}}} +
                                        ({{ADR_PAD_MINUS_2{1'd0}}, adr_ctr_nxt, 2'd0}),

                                      {{ADR_PAD{1'd0}},adr_ctr_nxt} != ((CACHE_LINE/4) - 1) ?
                                        CTI_BURST : CTI_EOB,

                                        4'b1111);
                end
                else
                begin
                        // Move to wait state
                        kill_access ();
                        state_nxt = IDLE;

                        // Update tag. Remove dirty bit.
                        o_cache_tag_wr_en                      = 1'd1; // Implicitly sets valid (redundant).
                        o_cache_tag[`ZAP_CACHE_TAG__TAG]       = cache_tag[`ZAP_CACHE_TAG__TAG]; // Preserve.
                        o_cache_tag_dirty                      = 1'd0;
                        o_cache_tag[`ZAP_CACHE_TAG__PA]        = cache_tag[`ZAP_CACHE_TAG__PA]; // Preserve.
                end
        end

        FETCH_SINGLE: // Fetch a single cache line
        begin
                o_ack  = 1'd1;
                o_err2 = i_rd || i_wr ? 1'd1 : 1'd0;

                // Generate address
                adr_ctr_nxt = adr_ctr_ff + ((o_wb_stb_ff && i_wb_ack) ? {{($clog2(CACHE_LINE/4) ){1'd0}}, 1'd1} :
                                                                         {($clog2(CACHE_LINE/4)+1){1'd0}}) ;

                // Write to buffer
                buf_nxt[adr_ctr_ff[$clog2(CACHE_LINE/4)-1:0]] = i_wb_ack ?
                                                                i_wb_dat :
                                                                buf_ff[adr_ctr_ff[$clog2(CACHE_LINE/4)-1:0]];

                // Manipulate buffer as needed
                if ( wr )
                begin
                        a = address[$clog2(CACHE_LINE/4)+1:2]; // Use value of X/4.

                        buf_nxt[a][7:0]   = ben[0] ? din[7:0]   : buf_nxt[a][7:0];
                        buf_nxt[a][15:8]  = ben[1] ? din[15:8]  : buf_nxt[a][15:8];
                        buf_nxt[a][23:16] = ben[2] ? din[23:16] : buf_nxt[a][23:16];
                        buf_nxt[a][31:24] = ben[3] ? din[31:24] : buf_nxt[a][31:24];
                end

                if ( {{ADR_PAD{1'd0}}, adr_ctr_nxt} <= (CACHE_LINE/4) - 1 )
                begin

                        // Fetch line from memory
                        wb_prpr_read(
                                     {phy_addr[31:$clog2(CACHE_LINE)], {$clog2(CACHE_LINE){1'd0}}} + (adr_ctr_nxt * (32/8)),
                                     ({{ADR_PAD{1'd0}}, adr_ctr_nxt} != CACHE_LINE/4 - 1) ? CTI_BURST : CTI_EOB);
                end
                else
                begin:blk12
                        // Update cache with previous buffers. Here _nxt refers to _ff except for the last one.

                        o_cache_line = 0;

                        for(int i=0;i<CACHE_LINE/4;i++)
                        begin
                                o_cache_line = o_cache_line |
                                               ({{LINE_PAD{1'd0}},buf_nxt[i][31:0]} << (32 * i));
                        end

                        o_cache_line_ben  = {CACHE_LINE{1'd1}};

                        // Update tag. Remove dirty and set valid
                        o_cache_tag_wr_en                       = 1'd1; // Implicitly sets valid.
                        o_cache_tag[`ZAP_CACHE_TAG__TAG]        = address[`ZAP_VA__CACHE_TAG];
                        o_cache_tag[`ZAP_CACHE_TAG__PA]         = phy_addr[31:$clog2(CACHE_LINE)];
                        o_cache_tag_dirty                       = !wr ? 1'd0 : 1'd1; // BUG FIX.

                        // Move to idle state
                        kill_access ();
                        state_nxt = IDLE;
                end
        end

        INVALIDATE: // Invalidate the cache - Almost Single Cycle
        begin
                cache_inv_req_nxt = 1'd1;
                cache_clean_req_nxt = 1'd0;

                if ( i_cache_inv_done )
                begin
                        cache_inv_req_nxt    = 1'd0;
                        state_nxt            = IDLE;
                        o_cache_inv_done     = 1'd1;
                end
        end

        CLEAN:  // Force cache to clean itself
        begin
                cache_clean_req_nxt = 1'd1;
                cache_inv_req_nxt   = 1'd0;

                if ( i_cache_clean_done )
                begin
                        cache_clean_req_nxt  = 1'd0;
                        state_nxt            = IDLE;
                        o_cache_clean_done   = 1'd1;
                end
        end

        default:
        begin
                a                       = 'x; //
                state_nxt               = 'x; //
                adr_ctr_nxt             = 'x; //
                o_wb_cyc_nxt            = 'x; //
                o_wb_stb_nxt            = 'x; //
                o_wb_adr_nxt            = 'x; //
                o_wb_dat_nxt            = 'x; //
                o_wb_cti_nxt            = 'x; //
                o_wb_wen_nxt            = 'x; //
                o_wb_sel_nxt            = 'x; //
                cache_clean_req_nxt     = 'x; //
                cache_inv_req_nxt       = 'x; //
                o_fsr                   = 'x; //
                o_far                   = 'x; //
                o_cache_tag             = 'x; //
                o_cache_inv_done        = 'x; //
                o_cache_clean_done      = 'x; //
                o_cache_tag_dirty       = 'x; //
                o_cache_tag_wr_en       = 'x; //
                o_cache_line            = 'x; //
                o_cache_line_ben        = 'x; //
                o_hold                  = 'x; //
                o_dat                   = 'x; //
                o_ack                   = 'x; //
                o_err                   = 'x; //
                o_err2                  = 'x; //
                o_address               = 'x; //

                for(int i=0;i<CACHE_LINE/4;i++)
                begin
                        buf_nxt[i] = 'x;
                end

                rhit                     = 'x;
                whit                     = 'x;
        end

        endcase
end

// ----------------------------------------------------------------------------
// Tasks and functions.
// ----------------------------------------------------------------------------

function automatic [31:0] adapt_cache_data (
        input [$clog2(CACHE_LINE) - 3:0] shift,
        input [CACHE_LINE*8-1:0]         data
);
localparam [31:0] W = $clog2(CACHE_LINE) + 3;
logic [LINE_PAD-1:0] dummy;
logic [W-1:0]        shamt;
begin
        shamt                     = {shift, 5'd0};
        {dummy, adapt_cache_data} =  data >> shamt;
        UNUSED_1B                 = |{dummy};
end
endfunction

function automatic [CACHE_LINE-1:0] ben_comp (
        input [$clog2(CACHE_LINE) - 3:0] shift,
        input [3:0]                      bv
);
localparam [31:0] W = $clog2(CACHE_LINE);
logic [W-1:0] shamt;
begin
        shamt    = {shift, 2'd0};
        ben_comp = {{(CACHE_LINE - 32'd4){1'd0}}, bv} << shamt;
end
endfunction

function automatic [31:0] clean_single_d (
        input [CACHE_LINE*8-1:0]        cl,
        input [$clog2(CACHE_LINE/4):0]  sh
);
logic [$clog2(CACHE_LINE/4) + 5:0] shamt;
logic [CACHE_LINE*8-32-1:0] dummy;
begin
        shamt                   = {sh, 5'd0};
        {dummy, clean_single_d} = cl >> shamt; // Select specific 32-bit.
        UNUSED_2B               = |{dummy};
end
endfunction

// Task to generate Wishbone read signals.
function automatic void wb_prpr_read (
        input [31:0] Address,
        input [2:0]  cti
);
begin
        o_wb_cyc_nxt = 1'd1;
        o_wb_stb_nxt = 1'd1;
        o_wb_wen_nxt = 1'd0;
        o_wb_sel_nxt = 4'b1111;
        o_wb_adr_nxt = Address;
        o_wb_cti_nxt = cti;
        o_wb_dat_nxt = 0;
end
endfunction

// Function to generate Wishbone write signals
function automatic void wb_prpr_write (
        input   [31:0]  data,
        input   [31:0]  Address,
        input   [2:0]   cti,
        input   [3:0]   Ben
);
begin
        o_wb_cyc_nxt = 1'd1;
        o_wb_stb_nxt = 1'd1;
        o_wb_wen_nxt = 1'd1;
        o_wb_sel_nxt = Ben;
        o_wb_adr_nxt = Address;
        o_wb_cti_nxt = cti;
        o_wb_dat_nxt = data;
end
endfunction

// Disables Wishbone
function automatic void kill_access ();
begin
        o_wb_cyc_nxt = 0;
        o_wb_stb_nxt = 0;
        o_wb_wen_nxt = 0;
        o_wb_adr_nxt = 0;
        o_wb_dat_nxt = 0;
        o_wb_sel_nxt = 0;
        o_wb_cti_nxt = CTI_EOB;
end
endfunction

endmodule // zap_cache_fsm



// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
