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
// -- Merges two Wishbone busses onto a single bus. One side can from the     --
// -- instruction cache while the other from data cache. This module can      --
// -- be used to connect I and D caches to a common interface.                --
// --                                                                         --
// -----------------------------------------------------------------------------

module zap_wb_merger #(parameter ONLY_CORE = 1'd0) (

// Clock and reset       
input logic i_clk,   
input logic i_reset,

// Wishbone bus 1
input logic i_c_wb_stb,
input logic i_c_wb_cyc,
input logic i_c_wb_wen,
input logic [3:0] i_c_wb_sel,
input logic [31:0] i_c_wb_dat,
input logic [31:0] i_c_wb_adr,
input logic [2:0] i_c_wb_cti,
output logic o_c_wb_ack,

// Wishbone bus 2
input logic i_d_wb_stb,
input logic i_d_wb_cyc,
input logic i_d_wb_wen,
input logic [3:0] i_d_wb_sel,
input logic [31:0] i_d_wb_dat,
input logic [31:0] i_d_wb_adr,
input logic [2:0] i_d_wb_cti,
output logic o_d_wb_ack,

// Common bus
output logic o_wb_cyc,
output logic o_wb_stb,
output logic o_wb_wen,
output logic [3:0] o_wb_sel,
output logic [31:0] o_wb_dat,
output logic [31:0] o_wb_adr,
output logic [2:0] o_wb_cti,
input logic i_wb_ack

);

`include "zap_defines.svh"
`include "zap_localparams.svh"

localparam CODE = 1'd0;
localparam DATA = 1'd1;

logic sel_ff, sel_nxt;

always_ff @ (posedge i_clk)
begin
        if ( i_reset )
                sel_ff <= CODE;
        else
                sel_ff <= sel_nxt;
end

always_comb
begin
        if ( sel_ff == CODE )
        begin
                o_c_wb_ack = i_wb_ack;
                o_d_wb_ack = 1'd0;
        end
        else
        begin
                o_d_wb_ack = i_wb_ack;
                o_c_wb_ack = 1'd0;
        end
end

always_comb
begin
        sel_nxt = sel_ff;

        case(sel_ff)
        CODE:
        begin
                if ( i_wb_ack && (o_wb_cti == CTI_CLASSIC || o_wb_cti == CTI_EOB) && i_d_wb_stb )
                        sel_nxt = DATA;
                else if ( !i_c_wb_stb && i_d_wb_stb )
                        sel_nxt = DATA;
                else
                        sel_nxt = sel_ff;
        end

        DATA:
        begin
                if ( i_wb_ack && (o_wb_cti == CTI_CLASSIC || o_wb_cti == CTI_EOB) && i_c_wb_stb )
                        sel_nxt = CODE;
                else if ( i_c_wb_stb && !i_d_wb_stb )
                        sel_nxt = CODE;
                else
                        sel_nxt = sel_ff;
        end
        endcase
end

generate if ( !ONLY_CORE )
begin: genblk1
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
                        o_wb_cti <= 0;
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
end: genblk1
else
begin: genblk2
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
end: genblk2 
endgenerate

endmodule



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
