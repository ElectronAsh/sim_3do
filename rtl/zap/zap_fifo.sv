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
// This RTL describes the FIFO stage of the pipeline. It essentially
// consists of an async FIFO wrapped around with some control logic.
//

module zap_fifo #(parameter [31:0] WDT = 32, DEPTH = 8) (

// Clock and reset.
input logic             i_clk,
input logic             i_reset,

// Pipeline synchronization controls.
input logic             i_write_inhibit,
input logic             i_clear_from_writeback,
input logic             i_data_stall,
input logic             i_clear_from_alu,
input logic             i_stall_from_shifter,
input logic             i_stall_from_issue,
input logic             i_stall_from_decode,
input logic             i_clear_from_decode,

// Payload and valid. o_full blocks writes.
input logic [WDT-1:0]   i_instr,
input logic             i_valid,
output logic            o_full,

// Payload out.
output logic  [WDT-1:0] o_instr,
output logic            o_valid

);

logic           clear;
logic           rd_en;
logic [WDT-1:0] instr;
logic           valid;

// Priority encoder to determine if to clear the FIFO.
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

// Priority encoder to determine if to read out the FIFO.
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

// The core queue of the pipeline stage.
zap_sync_fifo #(.WIDTH(WDT), .DEPTH(DEPTH)) u_zap_sync_fifo (
        .i_clk          (i_clk),
        .i_reset        (i_reset),
        .i_clear        (clear),
        .i_ack          ( rd_en  ),
        .i_wr_en        ( i_valid && !i_write_inhibit ),
        .i_data         (i_instr),
        .o_data         (instr),
        .o_empty_n      (valid),
        .o_full         (o_full),
        /* verilator lint_off PINCONNECTEMPTY */
        .o_full_n       (),
        .o_empty        ()
        /* verilator lint_on PINCONNECTEMPTY */
);

//
// Pipeline register. Since the FIFO read data is through a MUX, having a pipe
// register here helps break timing paths.
//
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

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
