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
// Merges two Wishbone busses onto a single bus. One side can from the
// instruction cache while the other from data cache. This module can
// be used to connect I and D caches to a common interface. Take note of
// special interface requirements based on ONLY_CORE parameter.
//

module zap_wb_merger #(

        // If ONLY_CORE=0, use NXT ports from cache, else use FF ports from CPU.
        parameter logic ONLY_CORE = 1'd0
)
(

// Clock and reset
input logic i_clk,
input logic i_reset,

// Wishbone bus 1
input logic             i_c_wb_stb,
input logic             i_c_wb_cyc,
input logic             i_c_wb_wen,
input logic [3:0]       i_c_wb_sel,
input logic [31:0]      i_c_wb_dat,
input logic [31:0]      i_c_wb_adr,
input logic [2:0]       i_c_wb_cti,
output logic            o_c_wb_ack,
output logic            o_c_wb_err,

// Wishbone bus 2
input logic             i_d_wb_stb,
input logic             i_d_wb_cyc,
input logic             i_d_wb_wen,
input logic [3:0]       i_d_wb_sel,
input logic [31:0]      i_d_wb_dat,
input logic [31:0]      i_d_wb_adr,
input logic [2:0]       i_d_wb_cti,
output logic            o_d_wb_ack,
output logic            o_d_wb_err,

// Common bus
output logic            o_wb_cyc,
output logic            o_wb_stb,
output logic            o_wb_wen,
output logic [3:0]      o_wb_sel,
output logic [31:0]     o_wb_dat,
output logic [31:0]     o_wb_adr,
output logic [2:0]      o_wb_cti,
input logic             i_wb_ack,
input logic             i_wb_err

);

`include "zap_defines.svh"
`include "zap_localparams.svh"

localparam logic CODE = 1'd0;
localparam logic DATA = 1'd1;

////////////////////////////////////
// FSM
////////////////////////////////////

//
// Channel select state machine. This will select either instruction or
// data in a round robin fashion. It will not interrupt a burst.
//

// State variable.
logic sel_ff, sel_nxt;

always_comb
begin
        sel_nxt = sel_ff;

        case(sel_ff)

        CODE:
        begin
                // Switch over if EOB and data STB exists.
                if ( (i_wb_ack|i_wb_err) && (o_wb_cti == CTI_EOB) && i_d_wb_stb )
                begin
                        sel_nxt = DATA;
                end
                // Switch over if code STB == 0 and data STB exists.
                else if ( !i_c_wb_stb && i_d_wb_stb )
                begin
                        sel_nxt = DATA;
                end
                else
                begin
                        sel_nxt = sel_ff;
                end
        end

        DATA:
        begin
                // Switch over if EOB and code STB exists.
                if ( (i_wb_ack|i_wb_err) && (o_wb_cti == CTI_EOB) && i_c_wb_stb )
                begin
                        sel_nxt = CODE;
                end
                // Switch over if data STB == 0 and code STB exists.
                else if ( i_c_wb_stb && !i_d_wb_stb )
                begin
                        sel_nxt = CODE;
                end
                else
                begin
                        sel_nxt = sel_ff;
                end
        end

        default: // Propagate X.
        begin
                sel_nxt = 'x;
        end

        endcase
end

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                sel_ff <= CODE;
        end
        else
        begin
                sel_ff <= sel_nxt;
        end
end

////////////////////////////////////
// ACK towards CPU
////////////////////////////////////

// Based on the current selection, redirect ACK to code or data.
assign o_c_wb_ack = (sel_ff == CODE) & (i_wb_err | i_wb_ack);
assign o_d_wb_ack = (sel_ff == DATA) & (i_wb_err | i_wb_ack);
assign o_c_wb_err = (sel_ff == CODE) & i_wb_err;
assign o_d_wb_err = (sel_ff == DATA) & i_wb_err;

/////////////////////////////////////
// WB output generation logic.
/////////////////////////////////////

if ( !ONLY_CORE )
begin: l_genblk1

        //
        // We can flop these, because we're using NXT ports.
        // Use sel_nxt since we are using wishbone NXT ports.
        //
        always_ff @ (posedge i_clk)
        begin
                if ( i_reset )
                begin
                        o_wb_cyc <= 0;
                        o_wb_stb <= 0;
                        o_wb_wen <= 0;
                        o_wb_sel <= 0;
                        o_wb_dat <= 0;
                        o_wb_adr <= 0;
                        o_wb_cti <= CTI_EOB;
                end
                else if ( sel_nxt == CODE )
                begin
                        o_wb_cyc <= i_c_wb_cyc;
                        o_wb_stb <= i_c_wb_stb;
                        o_wb_wen <= i_c_wb_wen;
                        o_wb_sel <= i_c_wb_sel;
                        o_wb_dat <= i_c_wb_dat;
                        o_wb_adr <= i_c_wb_adr;
                        o_wb_cti <= i_c_wb_cti;
                end
                else
                begin
                        o_wb_cyc <= i_d_wb_cyc;
                        o_wb_stb <= i_d_wb_stb;
                        o_wb_wen <= i_d_wb_wen;
                        o_wb_sel <= i_d_wb_sel;
                        o_wb_dat <= i_d_wb_dat;
                        o_wb_adr <= i_d_wb_adr;
                        o_wb_cti <= i_d_wb_cti;
                end
        end

end: l_genblk1
else
begin: l_genblk2

        //
        // Not required to flop these since the sources are flops themselves.
        // Just a 2:1 MUX on the path - very little delay - won't affect timing.
        // Here, we use all FF versions.
        //
        always_comb
        begin
                if ( sel_ff == CODE )
                begin
                        o_wb_cyc = i_c_wb_cyc;
                        o_wb_stb = i_c_wb_stb;
                        o_wb_wen = i_c_wb_wen;
                        o_wb_sel = i_c_wb_sel;
                        o_wb_dat = i_c_wb_dat;
                        o_wb_adr = i_c_wb_adr;
                        o_wb_cti = i_c_wb_cti;
                end
                else
                begin
                        o_wb_cyc = i_d_wb_cyc;
                        o_wb_stb = i_d_wb_stb;
                        o_wb_wen = i_d_wb_wen;
                        o_wb_sel = i_d_wb_sel;
                        o_wb_dat = i_d_wb_dat;
                        o_wb_adr = i_d_wb_adr;
                        o_wb_cti = i_d_wb_cti;
                end
        end
end: l_genblk2

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
