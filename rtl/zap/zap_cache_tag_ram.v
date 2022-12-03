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
// -- This is the tag RAM and data RAM unit. The tag RAM holds both the       --
// -- virtual tag and the physical address. The physical address is used to   --  
// -- avoid translation during clean operations. The cache data RAM is also   --
// -- present in this unit. This unit has a dedicated memory interface        -- 
// -- because it can perform global clean and flush by itself without         --
// -- depending on the cache controller.                                      --
// --                                                                         --
// -----------------------------------------------------------------------------

`default_nettype none
`include "zap_defines.vh"

module zap_cache_tag_ram #( 

parameter CACHE_SIZE = 1024 // Bytes.

)(

input   wire                            i_clk,
input   wire                            i_reset,
input   wire    [31:0]                  i_address_nxt,
input   wire    [31:0]                  i_address,
input   wire                            i_cache_en,
input   wire    [127:0]                 i_cache_line,
input   wire    [15:0]                  i_cache_line_ben,
output  reg     [127:0]                 o_cache_line,
input   wire                            i_cache_tag_wr_en,
input   wire    [`CACHE_TAG_WDT-1:0]    i_cache_tag,
input   wire                            i_cache_tag_dirty,

output  reg     [`CACHE_TAG_WDT-1:0]    o_cache_tag,
output  reg                             o_cache_tag_valid,
output  reg                             o_cache_tag_dirty,
input   wire                            i_cache_clean_req,
output  reg                             o_cache_clean_done,
input   wire                            i_cache_inv_req,
output  reg                             o_cache_inv_done,

/* 
 * Cache clean operations occur through these ports.
 * Memory access ports, both NXT and FF. Usually you'll be connecting NXT ports 
 */
output  reg                             o_wb_cyc_ff, o_wb_cyc_nxt,
output  reg                             o_wb_stb_ff, o_wb_stb_nxt,
output  reg     [31:0]                  o_wb_adr_ff, o_wb_adr_nxt,
output  reg     [31:0]                  o_wb_dat_ff, o_wb_dat_nxt,
output  reg     [3:0]                   o_wb_sel_ff, o_wb_sel_nxt,
output  reg                             o_wb_wen_ff, o_wb_wen_nxt,
output  reg     [2:0]                   o_wb_cti_ff, o_wb_cti_nxt, /* Cycle Type Indicator - 010, 111 */
input wire      [31:0]                  i_wb_dat,
input wire                              i_wb_ack

);

// ----------------------------------------------------------------------------

`include "zap_localparams.vh"

localparam NUMBER_OF_DIRTY_BLOCKS = ((CACHE_SIZE/16)/16); // Keep cache size > 16 bytes.

// States.
localparam IDLE                         = 0;
localparam CACHE_CLEAN_GET_ADDRESS      = 1;
localparam CACHE_CLEAN_WRITE            = 2;
localparam CACHE_INV                    = 3;


// ----------------------------------------------------------------------------

reg [(CACHE_SIZE/16)-1:0]       dirty;
reg [(CACHE_SIZE/16)-1:0]       valid; 
reg [`CACHE_TAG_WDT-1:0]        tag_ram [(CACHE_SIZE/16)-1:0];
reg [127:0]                     dat_ram [(CACHE_SIZE/16)-1:0];

// ----------------------------------------------------------------------------

reg [`CACHE_TAG_WDT-1:0]        tag_ram_wr_data;
reg                             tag_ram_wr_en;
reg [$clog2(CACHE_SIZE/16)-1:0] tag_ram_wr_addr, tag_ram_rd_addr;
reg                             tag_ram_clear;
reg                             tag_ram_clean;

// ----------------------------------------------------------------------------

reg [1:0] state_ff, state_nxt;

// ----------------------------------------------------------------------------

reg [$clog2(NUMBER_OF_DIRTY_BLOCKS)-1:0] blk_ctr_ff, blk_ctr_nxt;
reg [2:0]                                adr_ctr_ff, adr_ctr_nxt;

// ----------------------------------------------------------------------------

initial
begin: blk1
        // FPGA anyway initializes to 0 on start.
        integer i;

        for(i=0;i<CACHE_SIZE/16;i=i+1)
                dat_ram[i] = 0;                

        for(i=0;i<CACHE_SIZE/16;i=i+1)
                tag_ram[i] = 0;
end

always @ (posedge i_clk)
begin
        o_cache_line    <=      dat_ram [ tag_ram_rd_addr ];
end

always @ (posedge i_clk)
begin
        if ( i_cache_line_ben[0]  )   dat_ram [tag_ram_wr_addr][7:0]       <=      i_cache_line[7:0];
        if ( i_cache_line_ben[1]  )   dat_ram [tag_ram_wr_addr][15:8]      <=      i_cache_line[15:8];
        if ( i_cache_line_ben[2]  )   dat_ram [tag_ram_wr_addr][23:16]     <=      i_cache_line[23:16];
        if ( i_cache_line_ben[3]  )   dat_ram [tag_ram_wr_addr][31:24]     <=      i_cache_line[31:24];
        if ( i_cache_line_ben[4]  )   dat_ram [tag_ram_wr_addr][39:32]     <=      i_cache_line[39:32];
        if ( i_cache_line_ben[5]  )   dat_ram [tag_ram_wr_addr][47:40]     <=      i_cache_line[47:40];
        if ( i_cache_line_ben[6]  )   dat_ram [tag_ram_wr_addr][55:48]     <=      i_cache_line[55:48];
        if ( i_cache_line_ben[7]  )   dat_ram [tag_ram_wr_addr][63:56]     <=      i_cache_line[63:56];
        if ( i_cache_line_ben[8]  )   dat_ram [tag_ram_wr_addr][71:64]     <=      i_cache_line[71:64];
        if ( i_cache_line_ben[9]  )   dat_ram [tag_ram_wr_addr][79:72]     <=      i_cache_line[79:72];
        if ( i_cache_line_ben[10] )   dat_ram [tag_ram_wr_addr][87:80]     <=      i_cache_line[87:80];
        if ( i_cache_line_ben[11] )   dat_ram [tag_ram_wr_addr][95:88]     <=      i_cache_line[95:88];
        if ( i_cache_line_ben[12] )   dat_ram [tag_ram_wr_addr][103:96]    <=      i_cache_line[103:96];
        if ( i_cache_line_ben[13] )   dat_ram [tag_ram_wr_addr][111:104]   <=      i_cache_line[111:104];
        if ( i_cache_line_ben[14] )   dat_ram [tag_ram_wr_addr][119:112]   <=      i_cache_line[119:112];
        if ( i_cache_line_ben[15] )   dat_ram [tag_ram_wr_addr][127:120]   <=      i_cache_line[127:120];
end

// ----------------------------------------------------------------------------

always @ (posedge i_clk)
begin
        if ( tag_ram_wr_en )
                tag_ram [ tag_ram_wr_addr ] <= tag_ram_wr_data;
end

always @ (posedge i_clk)
begin
                o_cache_tag                 <= tag_ram [ tag_ram_rd_addr ];
end

// ----------------------------------------------------------------------------

always @ (posedge i_clk)
begin
        o_cache_tag_dirty                   <= dirty [ tag_ram_rd_addr ];

        if ( i_reset )
                dirty <= 0;
        else if ( tag_ram_wr_en )
                dirty [ tag_ram_wr_addr ]   <= i_cache_tag_dirty;
        else if ( tag_ram_clean )
                dirty[tag_ram_rd_addr] <= 1'd0;// BUG FIX dirty_nxt;
end

always @ (posedge i_clk)
begin
        o_cache_tag_valid                   <= valid [ tag_ram_rd_addr ];

        if ( tag_ram_clear | !i_cache_en )
                valid <= 0;
        else if ( tag_ram_wr_en )
                valid [ tag_ram_wr_addr ]   <= 1'd1;
end

// ----------------------------------------------------------------------------

always @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                o_wb_cyc_ff             <= 0;
                o_wb_stb_ff             <= 0;
                o_wb_wen_ff             <= 0;
                o_wb_sel_ff             <= 0;
                o_wb_dat_ff             <= 0;
                o_wb_cti_ff             <= CTI_CLASSIC;
                o_wb_adr_ff             <= 0;
                adr_ctr_ff              <= 0;
                blk_ctr_ff              <= 0;
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
                adr_ctr_ff              <= adr_ctr_nxt;
                blk_ctr_ff              <= blk_ctr_nxt;
                state_ff                <= state_nxt;
        end
end

// ----------------------------------------------------------------------------

always @*
begin

        // Defaults.
        state_nxt = state_ff;
        tag_ram_rd_addr         = 0;//i_address_nxt [`VA__CACHE_INDEX];
        tag_ram_wr_addr         = i_address     [`VA__CACHE_INDEX];
        tag_ram_wr_en           = 0; //i_cache_tag_wr_en;
        tag_ram_clear           = 0;
        tag_ram_clean           = 0;
        adr_ctr_nxt             = adr_ctr_ff;
        blk_ctr_nxt             = blk_ctr_ff;
        o_cache_clean_done      = 0;
        o_cache_inv_done        = 0;

        o_wb_cyc_nxt = o_wb_cyc_ff;
        o_wb_stb_nxt = o_wb_stb_ff;
        o_wb_adr_nxt = o_wb_adr_ff;
        o_wb_dat_nxt = o_wb_dat_ff;
        o_wb_sel_nxt = o_wb_sel_ff;
        o_wb_wen_nxt = o_wb_wen_ff;
        o_wb_cti_nxt = o_wb_cti_ff;

        tag_ram_wr_data = 0;

        case ( state_ff )

        IDLE:
        begin: blp9
                integer i;

                kill_access;

                tag_ram_rd_addr = i_address_nxt [`VA__CACHE_INDEX];
                tag_ram_wr_addr = i_address     [`VA__CACHE_INDEX];
                tag_ram_wr_en   = i_cache_tag_wr_en;
                tag_ram_wr_data = i_cache_tag;

                if ( i_cache_clean_req )
                begin
                        tag_ram_wr_en = 0;
                        blk_ctr_nxt = 0;

                // assertions_start

                        $display($time, " - %m :: Cache clean requested...");

                        for(i=0;i<CACHE_SIZE/16;i=i+1)
                        begin
                                $display($time, " - %m :: Line %d : %x %d", i, dat_ram[i], dirty[i]);
                        end

                // assertions_end


                        state_nxt = CACHE_CLEAN_GET_ADDRESS;
                end
                else if ( i_cache_inv_req )
                begin
                        tag_ram_wr_en = 0;
                        state_nxt = CACHE_INV;
                end
        end        

        CACHE_CLEAN_GET_ADDRESS:
        begin
                tag_ram_rd_addr = get_tag_ram_rd_addr (blk_ctr_ff , dirty);

                if ( baggage(dirty, blk_ctr_ff) == 5'b11111)
                begin
                        // Move to next block.
                        blk_ctr_nxt = blk_ctr_ff + 1;

                        if ( blk_ctr_ff == NUMBER_OF_DIRTY_BLOCKS - 1 )
                        begin
                                state_nxt = IDLE;
                                o_cache_clean_done = 1'd1;
                        end
                end
                else
                begin

                        // Go to state.
                        state_nxt = CACHE_CLEAN_WRITE;
                end

                adr_ctr_nxt     = 0; // Initialize address counter.
        end

        CACHE_CLEAN_WRITE:
        begin
                tag_ram_rd_addr = get_tag_ram_rd_addr (blk_ctr_ff , dirty);
                adr_ctr_nxt = adr_ctr_ff + (i_wb_ack && o_wb_stb_ff);

                if ( adr_ctr_nxt > 3 )
                begin
                        // Remove dirty marking. BUG FIX.
                        tag_ram_clean = 1;

                        // Kill access.
                        kill_access;

                        // Go to new state.
                        state_nxt = CACHE_CLEAN_GET_ADDRESS;
                end
                else
                begin: blk1111
                        reg [31:0] shamt;
                        reg [31:0] data;
                        reg [31:0] pa;

                        shamt = adr_ctr_nxt << 5;
                        data  = o_cache_line >> shamt;
                        pa = {o_cache_tag[`CACHE_TAG__PA], 4'd0};

                        // Perform a Wishbone write using Physical Address.
                        wb_prpr_write(  data, pa + (adr_ctr_nxt << 2), adr_ctr_nxt != 3 ? CTI_BURST : CTI_EOB, 4'b1111 
                        );
                end
        end

        CACHE_INV:
        begin
                tag_ram_clear = 1'd1;
                state_nxt     = IDLE;
                o_cache_inv_done = 1'd1;
        end
        
        endcase                
end

// -----------------------------------------------------------------------------

// Priority encoder.
function  [4:0] pri_enc1 ( input [15:0] in );
begin: priEncFn
                casez ( in )
                16'b0000_0000_0000_0001: pri_enc1 = 4'd0;
                16'b0000_0000_0000_001?: pri_enc1 = 4'd1;
                16'b0000_0000_0000_01??: pri_enc1 = 4'd2;
                16'b0000_0000_0000_1???: pri_enc1 = 4'd3;
                16'b0000_0000_0001_????: pri_enc1 = 4'd4;
                16'b0000_0000_001?_????: pri_enc1 = 4'd5;
                16'b0000_0000_01??_????: pri_enc1 = 4'd6;
                16'b0000_0000_1???_????: pri_enc1 = 4'd7;
                16'b0000_0001_????_????: pri_enc1 = 4'd8;
                16'b0000_001?_????_????: pri_enc1 = 4'd9;
                16'b0000_01??_????_????: pri_enc1 = 4'hA;
                16'b0000_1???_????_????: pri_enc1 = 4'hB;
                16'b0001_????_????_????: pri_enc1 = 4'hC;
                16'b001?_????_????_????: pri_enc1 = 4'hD;
                16'b01??_????_????_????: pri_enc1 = 4'hE;
                16'b1???_????_????_????: pri_enc1 = 4'hF;
                default:                 pri_enc1 = 5'b11111;
                endcase
end
endfunction

// -----------------------------------------------------------------------------

function [31:0] get_tag_ram_rd_addr (
input [31:0] blk_ctr,
input [CACHE_SIZE/16-1:0] dirty
);
reg [CACHE_SIZE/16-1:0] dirty_new;
reg [3:0] enc;
reg [31:0] shamt;
begin
        shamt = blk_ctr_ff << 4;
        dirty_new = dirty >> shamt;
        enc = pri_enc1(dirty_new);        
        get_tag_ram_rd_addr = shamt + enc;
end
endfunction

// ----------------------------------------------------------------------------

/* Function to generate Wishbone read signals. */
task  wb_prpr_read;
input [31:0] i_address;
input [2:0]  i_cti;
begin
        $display($time, " - %m :: Reading from address %x", i_address);

        o_wb_cyc_nxt = 1'd1;
        o_wb_stb_nxt = 1'd1;
        o_wb_wen_nxt = 1'd0;
        o_wb_sel_nxt = 4'b1111;
        o_wb_adr_nxt = i_address;
        o_wb_cti_nxt = i_cti;
        o_wb_dat_nxt = 0;
end
endtask

// ----------------------------------------------------------------------------

/* Function to generate Wishbone write signals */
task  wb_prpr_write;
input   [31:0]  i_data;
input   [31:0]  i_address;
input   [2:0]   i_cti;
input   [3:0]   i_ben;
begin
        o_wb_cyc_nxt = 1'd1;
        o_wb_stb_nxt = 1'd1;
        o_wb_wen_nxt = 1'd1;
        o_wb_sel_nxt = i_ben;
        o_wb_adr_nxt = i_address;
        o_wb_cti_nxt = i_cti;
        o_wb_dat_nxt = i_data;
end
endtask

// ----------------------------------------------------------------------------

/* Disables Wishbone */
task  kill_access;
begin
        o_wb_cyc_nxt = 0;
        o_wb_stb_nxt = 0;
        o_wb_wen_nxt = 0;
        o_wb_adr_nxt = 0;
        o_wb_dat_nxt = 0;
        o_wb_sel_nxt = 0;
        o_wb_cti_nxt = CTI_CLASSIC;
end
endtask

// ----------------------------------------------------------------------------

function [4:0] baggage ( input [CACHE_SIZE/16-1:0] dirty, input [31:0] blk_ctr_ff );
reg [31:0] shamt;
integer i;
begin
        shamt = blk_ctr_ff << 4;
        baggage = pri_enc1(dirty >> shamt);
end
endfunction

endmodule // zap_cache_tag_ram.v
`default_nettype wire
