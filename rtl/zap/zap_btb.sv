//
// (C) 2016-2022 Revanth Kamaraj (krevanth)
//
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
// This RTL describe a classic direct mapped branch target buffer.
//

module zap_btb #(
        //
        // Entries in the branch predictor RAM. Only half are available
        // in 32-bit state.
        //
        parameter logic [31:0] BP_ENTRIES = 32'd1024,

        //
        // Address breakup. We use direct mapped addressing. We have a
        // 1-bit offset since address LSB = 0. Index is used to index
        // into the SRAM and tag will be compared to check if it is
        // the actual entry or not.
        //
        localparam type t_address = struct packed {
        logic [TAG_WDT-1:0]            tag;
        logic [$clog2(BP_ENTRIES)-1:0] index;
        logic                          offset;
        }
) (
        // Clock and reset.
        input logic         i_clk,
        input logic         i_reset,

        ////////////////////////////
        // Pipeline sync controls
        ////////////////////////////

        input logic         i_stall,
        input logic         i_clear,

        //////////////////////////
        // Feedback path.
        //////////////////////////

        // Feedback status.
        input logic         i_fb_ok,
        input logic         i_fb_nok,

        // Branch source address.
        input t_address     i_fb_branch_src_address,

        // Branch predicted state. This should be changed.
        input logic [1:0]   i_fb_current_branch_state,

        // Branch target address. This is the correct destination address.
        input t_address     i_fb_branch_dest_address,

        /////////////////////////
        // Live read path.
        /////////////////////////

        // Read addresses from SRAM.
        input t_address     i_rd_addr,
        input t_address     i_rd_addr_del,

        ////////////////////////
        // Control path
        ////////////////////////

        // BTB control path change.
        output logic        o_clear_from_btb,
        output logic [31:0] o_pc_from_btb,

        /////////////////////////
        // Branch state.
        /////////////////////////

        output logic [1:0]  o_branch_state
);

`include "zap_localparams.svh"
`include "zap_functions.svh"

localparam [31:0] TAG_WDT = 32 - $clog2(BP_ENTRIES) - 1;
localparam [31:0] MAX_WDT = 32 + 2 + TAG_WDT;

logic unused;

assign unused = |{i_rd_addr[0],
                  i_rd_addr    [31:$clog2(BP_ENTRIES)+1],
                  i_rd_addr_del[$clog2(BP_ENTRIES):0],
                  i_fb_branch_src_address[0]};

logic [BP_ENTRIES-1:0] dav;
logic                  bp_dav;
logic                  mem_wr_en;
logic                  mem_rd_en;

logic [$clog2(BP_ENTRIES)-1:0] mem_wr_addr;
logic [$clog2(BP_ENTRIES)-1:0] mem_rd_addr;

struct packed {
        logic [31:0]        target;
        logic [TAG_WDT-1:0] tag;
        logic [1:0]         state; // LSB
} mem_wr_data, mem_rd_data;

// Update memory on any kind of feedback.
assign mem_wr_en   = i_fb_ok | i_fb_nok;

// Read memory when no pipeline stall.
assign mem_rd_en = ~i_stall;

// Memory addresses are driven by index.
assign mem_wr_addr = i_fb_branch_src_address.index;
assign mem_rd_addr = i_rd_addr.index;

// Memory write data. Compute the new state based on feedback.
assign mem_wr_data.state   = compute(i_fb_current_branch_state,i_fb_nok);
assign mem_wr_data.tag     = i_fb_branch_src_address.tag;
assign mem_wr_data.target  = i_fb_branch_dest_address;

// BTB RAM.
zap_ram_simple_nopipe #(.DEPTH(BP_ENTRIES), .WIDTH(MAX_WDT)) u_br_ram
(
        .i_clk    (i_clk),
        .i_wr_en  (mem_wr_en),
        .i_wr_addr(mem_wr_addr),
        .i_rd_addr(mem_rd_addr),
        .i_wr_data(mem_wr_data),
        .i_rd_en  (!i_stall),
        .o_rd_data(mem_rd_data)
);

// Writing branch state. When clear, set DAV to 0.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                dav    <= '0;
        end
        else if ( i_clear )
        begin
                dav    <= '0;
        end
        else
        begin
                dav[i_fb_branch_src_address.index] <= mem_wr_en;
        end
end

// Clocked out in parallel with the RAM.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                bp_dav <= 1'd0;
        end
        else if ( i_clear )
        begin
                bp_dav <= 1'd0;
        end
        else if ( mem_rd_en )
        begin
                bp_dav <= dav[i_rd_addr.index];
        end
end

logic mem_rd_taken;
logic mem_rd_tag_match;

// Memory read data state read as taken.
assign mem_rd_taken = (mem_rd_data.state == WT || mem_rd_data.state == ST);

// Memory read address tag match with tag in memory read data.
assign mem_rd_tag_match = i_rd_addr_del.tag == mem_rd_data.tag;

//
// Tag check and clear generation logic. Use RAM data. This is produced
// 1 cycle after the memory is read.
//
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                o_clear_from_btb <= 1'd0;
                o_pc_from_btb    <= {32{1'dx}};
                o_branch_state   <= {2{1'dx}};
        end
        else if ( !i_stall )
        begin
                o_branch_state <= mem_rd_data.state;

                //
                // If the tag matches and prediction is taken, resync
                // the pipeline to the predicted address.
                //
                if ( mem_rd_tag_match & bp_dav & mem_rd_taken )
                begin
                        o_clear_from_btb <= 1'd1;
                        o_pc_from_btb    <= mem_rd_data.target;
                end
                else
                begin
                        o_clear_from_btb <= 1'd0;
                end
        end
end

//
// Function for branch prediction.
//
function automatic [1:0] compute ( input [1:0] pred, input nok );
begin
                // Branch was predicted incorrectly. Go to opposite state.
                if ( nok )
                begin
                        case ( pred )
                        SNT: return WNT; // May be not so strongly not taken.
                        WNT: return WT;  // Perhaps it is taken.
                        WT:  return WNT; // Perhaps it is not taken.
                        ST:  return WT;  // May be not so strongy taken.
                   default:  return 'x;  // Propagate X.
                        endcase
                end
                else // Confirm that branch was correctly predicted.
                begin
                        case ( pred )
                        SNT: return SNT; // Reinforce.
                        WNT: return SNT; // Reinforce.
                        WT:  return ST;  // Reinforce.
                        ST:  return ST;  // Reinforce.
                   default:  return 'x;  // Propagate X.
                        endcase
                end
end
endfunction

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
