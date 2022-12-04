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



module zap_fifo #(parameter WDT = 32, DEPTH = 8) (

input logic            i_clk,
input logic            i_reset,

input logic            i_write_inhibit,

input logic            i_clear_from_writeback,
input logic            i_data_stall,
input logic            i_clear_from_alu,
input logic            i_stall_from_shifter,
input logic            i_stall_from_issue,
input logic            i_stall_from_decode,
input logic            i_clear_from_decode,

input logic [WDT-1:0] i_instr, // Instruction + other bits.
input logic           i_valid, // Above is valid. Write enable basically.

output logic  [WDT-1:0] o_instr, // Instruction output.
output logic            o_valid, // Output valid.
output logic            o_full   // FIFO full.
);

logic clear, rd_en; 
logic [WDT-1:0] instr;
logic valid;

always_comb
begin
        if      ( i_clear_from_writeback ) clear = 1'd1;
        else if ( i_data_stall )           clear = 1'd0;
        else if ( i_clear_from_alu )       clear = 1'd1;
        else if ( i_stall_from_shifter )   clear = 1'd0;
        else if ( i_stall_from_issue )     clear = 1'd0;
        else if ( i_stall_from_decode )    clear = 1'd0;
        else if ( i_clear_from_decode )    clear = 1'd1;
        else                               clear = 1'd0;
end

always_comb
begin
        if      ( i_clear_from_writeback)  rd_en = 1'd0;
        else if ( i_data_stall )           rd_en = 1'd0;
        else if ( i_clear_from_alu )       rd_en = 1'd0;
        else if ( i_stall_from_shifter )   rd_en = 1'd0;
        else if ( i_stall_from_issue )     rd_en = 1'd0;
        else if ( i_stall_from_decode )    rd_en = 1'd0;
        else if ( i_clear_from_decode )    rd_en = 1'd0;
        else                               rd_en = 1'd1;
end

zap_sync_fifo #(.WIDTH(WDT), .DEPTH(DEPTH), .FWFT(32'd1)) USF (
        .i_clk          (i_clk),
        .i_reset        (i_reset || clear),
        .i_ack          ( rd_en  ),
        .i_wr_en        ( i_valid && !i_write_inhibit ),
        .i_data         (i_instr),
        .o_data         (instr),
        .o_empty_n      (valid),
        .o_full         (o_full),
        /* verilator lint_off PINCONNECTEMPTY */
        .o_full_n       (),
        .o_full_n_nxt   (),
        .o_empty        ()
        /* verilator lint_on PINCONNECTEMPTY */
);

// Pipeline register.
always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin   
                o_valid <= 1'd0;
        end
        else if ( clear )
        begin
                o_valid <= 1'd0;
        end
        else if ( rd_en )
        begin
                o_valid <= valid;
                o_instr <= instr;
        end
end

endmodule

