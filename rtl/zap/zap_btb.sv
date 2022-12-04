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

module zap_btb #(parameter BP_ENTRIES=1024) ( 
        input logic         i_clk,
        input logic         i_reset,
        input logic         i_stall,
        input logic         i_clear,

        // Feedback path.
        input logic         i_fb_ok,
        input logic         i_fb_nok,              
        input logic [31:0]  i_fb_branch_src_address,
        input logic [1:0]   i_fb_current_branch_state,
        input logic [31:0]  i_fb_branch_dest_address,   
        
        // Live read path.
        input logic [31:0]  i_rd_addr,
        input logic [31:0]  i_rd_addr_del,
        output logic        o_clear_from_btb,
        output logic [31:0] o_pc_from_btb
);        

`include "zap_localparams.svh"
`include "zap_functions.svh"

localparam TAG_WDT    =  32 - $clog2(BP_ENTRIES) - 1;
localparam MAX_WDT    =  32 + 2 + TAG_WDT;

logic unused;

always_comb
begin
        unused = |{i_rd_addr[0],  
                   i_rd_addr    [31:$clog2(BP_ENTRIES)+1], 
                   i_rd_addr_del[$clog2(BP_ENTRIES):0],
                   i_fb_branch_src_address[0]};
end

// RAM read data.
logic [MAX_WDT-1:0]    rd_data;
logic [BP_ENTRIES-1:0] dav;
logic                  bp_dav;

// BTB RAM. {target, tag, state}
zap_ram_simple_nopipe #(.DEPTH(BP_ENTRIES), .WIDTH(MAX_WDT)) u_br_ram
(
        .i_clk    (i_clk),
        .i_wr_en  (i_fb_ok || i_fb_nok),
        .i_wr_addr(i_fb_branch_src_address[$clog2(BP_ENTRIES):1]),
        .i_rd_addr(i_rd_addr[$clog2(BP_ENTRIES):1]),

        //{target, tag, state}
        .i_wr_data({i_fb_branch_dest_address, 
                    i_fb_branch_src_address[$clog2(BP_ENTRIES)+1+TAG_WDT-1:$clog2(BP_ENTRIES)+1], 
                    compute(i_fb_current_branch_state, i_fb_nok)}),

        .i_rd_en  (!i_stall),

        //{target, tag, state}
        .o_rd_data(rd_data)
);

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                bp_dav <= 1'd0;
                dav    <= 0;
        end
        else
        begin
                if (!i_stall )
                begin
                        bp_dav <= dav[i_rd_addr[$clog2(BP_ENTRIES):1]];
                end
                else if ( i_clear )
                begin
                        bp_dav <= 1'd0;
                        dav    <= 0;
                end

                if ( (i_fb_ok || i_fb_nok) && !i_clear )
                begin
                        dav[i_fb_branch_src_address[$clog2(BP_ENTRIES):1]] <= 1'd1;
                end
        end
end

// Tag check and clear generation logic. Use RAM data.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )  
        begin
                o_clear_from_btb <= 1'd0;
                o_pc_from_btb    <= 32'd0;
        end
        else if ( !i_stall )
        begin
                if ( (
                        i_rd_addr_del[$clog2(BP_ENTRIES)+1+TAG_WDT-1:$clog2(BP_ENTRIES)+1] == 
                        rd_data[TAG_WDT + 1 : 2]) 
                        && 
                        bp_dav                                                                                          
                        && 
                        (rd_data[1:0] == WT || rd_data[1:0] == ST) 
                )
                begin
                        o_clear_from_btb <= 1'd1;
                        o_pc_from_btb    <= rd_data[MAX_WDT - 1 : 2 + (31 - $clog2(BP_ENTRIES)) ];
                end
                else
                begin
                        o_clear_from_btb <= 1'd0;
                end
        end
end

endmodule
