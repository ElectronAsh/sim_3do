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
// This stage merely acts as a buffer in between the ALU stage and the reg.
// file (i.e., writeback stage). 32-bit data received from the cache is
// is rotated appropriately here in case of byte reads or halfword reads.
// Otherwise, this stage is simply a buffer.
//

module zap_memory_main
#(
        // Width of CPSR.
        parameter [31:0] FLAG_WDT = 32,

        // Number of physical registers.
        parameter [31:0] PHY_REGS = 46
)
(
        // Debug
        input   logic    [64*8-1:0]          i_decompile,
        input   logic                        i_decompile_valid,
        output  logic    [64*8-1:0]          o_decompile,
        output  logic                        o_decompile_valid,
        input   logic                        i_uop_last,
        output  logic                        o_uop_last,

        // Clock and reset.
        input logic                          i_clk,
        input logic                          i_reset,

        // Pipeline control signals.
        input logic                          i_clear_from_writeback,
        input logic                          i_data_stall,

        // Memory stuff.
        input   logic                        i_mem_load_ff,
        input   logic [1:0]                  i_mem_address_ff, // Access Address.

        // Data read from memory.
        input   logic [31:0]                 i_mem_rd_data,

        // Memory fault transfer. i_mem_fault comes from the cache unit.
        input   logic  [1:0]                 i_mem_fault,      // Fault in.
        output  logic   [1:0]                 o_mem_fault,     // Fault out.

        // Data valid and buffered PC.
        input logic                          i_dav_ff,
        input logic [31:0]                   i_pc_plus_8_ff,

        // ALU value, flags,and where to write the value.
        input logic [31:0]                   i_alu_result_ff,
        input logic  [FLAG_WDT-1:0]          i_flags_ff,
        input logic [$clog2(PHY_REGS)-1:0]   i_destination_index_ff,

        // Interrupts.
        input   logic                        i_irq_ff,
        input   logic                        i_fiq_ff,
        input   logic                        i_instr_abort_ff,
        input   logic                        i_swi_ff,

        // Memory SRCDEST index. For loads, this tells the register file where
        // to put the read data. Set to point to RAZ if invalid.
        input logic [$clog2(PHY_REGS)-1:0]   i_mem_srcdest_index_ff,

        // SRCDEST value.
        input logic [31:0]                   i_mem_srcdest_value_ff,

        // Memory size and type.
        input logic                          i_sbyte_ff,
                                             i_ubyte_ff,
                                             i_shalf_ff,
                                             i_uhalf_ff,

        // Undefined instr.
        input logic                          i_und_ff,
        output logic                         o_und_ff,

        // ALU result and flags.
        output logic  [31:0]                 o_alu_result_ff,
        output logic  [FLAG_WDT-1:0]         o_flags_ff,

        // Where to write ALU and memory read target register.
        output logic [$clog2(PHY_REGS)-1:0]  o_destination_index_ff,

        // Set to point to the RAZ register if invalid.
        output logic [$clog2(PHY_REGS)-1:0]  o_mem_srcdest_index_ff,

        // Outputs valid and PC buffer.
        output logic                         o_dav_ff,
        output logic [31:0]                  o_pc_plus_8_ff,

        // The whole interrupt signaling scheme.
        output logic                         o_irq_ff,
        output logic                         o_fiq_ff,
        output logic                         o_swi_ff,
        output logic                         o_instr_abort_ff,

        // Memory load information is passed down.
        output logic                         o_mem_load_ff,
        output logic  [31:0]                 o_mem_rd_data
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

logic                             mem_load_ff2          ;
logic [31:0]                      mem_srcdest_value_ff2 ;
logic [1:0]                       mem_address_ff2       ;
logic                             sbyte_ff2             ;
logic                             ubyte_ff2             ;
logic                             shalf_ff2             ;
logic                             uhalf_ff2             ;
logic [31:0]                      mem_rd_data           ;

// On reset or on a clear from WB, we will disable the vectors
// in this unit. Else, we will just flop everything out.
always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                o_dav_ff                  <= 0;
                o_decompile_valid         <= 0;
                o_uop_last                <= 0;
                o_irq_ff                  <= 0;
                o_fiq_ff                  <= 0;
                o_swi_ff                  <= 0;
                o_instr_abort_ff          <= 0;
                o_und_ff                  <= 0;
                o_mem_fault               <= 0;
                o_alu_result_ff           <= 'x;
                o_flags_ff                <= 0;
                o_mem_srcdest_index_ff    <= 'x;
                o_destination_index_ff    <= 'x;
                o_pc_plus_8_ff            <= 'x;
                o_instr_abort_ff          <= 0;
                o_mem_load_ff             <= 'x;
                mem_rd_data               <= 'x;
                o_decompile               <= 0;
        end
        else if ( i_clear_from_writeback )
        begin
                o_dav_ff                  <= 0;
                o_decompile_valid         <= 0;
                o_uop_last                <= 0;
                o_irq_ff                  <= 0;
                o_fiq_ff                  <= 0;
                o_swi_ff                  <= 0;
                o_instr_abort_ff          <= 0;
                o_und_ff                  <= 0;
                o_mem_fault               <= 0;
                o_alu_result_ff           <= 'x;
                o_flags_ff                <= 0;
                o_mem_srcdest_index_ff    <= 'x;
                o_destination_index_ff    <= 'x;
                o_pc_plus_8_ff            <= 'x;
                o_instr_abort_ff          <= 0;
                o_mem_load_ff             <= 'x;
                mem_rd_data               <= 'x;
                o_decompile               <= 0;
        end
        else if ( i_data_stall )
        begin
                // Invalidate when data stall.
                o_decompile_valid <= 1'd0;
                o_uop_last        <= 1'd0;
                o_und_ff          <= 1'd0;
                o_irq_ff          <= 1'd0;
                o_fiq_ff          <= 1'd0;
                o_swi_ff          <= 1'd0;
                o_instr_abort_ff  <= 1'd0;
                o_dav_ff          <= 1'd0;
        end
        else
        begin
                // Just flop everything out.
                o_alu_result_ff       <= i_alu_result_ff;
                o_flags_ff            <= i_flags_ff;
                o_mem_srcdest_index_ff<= i_mem_srcdest_index_ff;
                o_destination_index_ff<= i_destination_index_ff;
                o_pc_plus_8_ff        <= i_pc_plus_8_ff;

                casez    ({i_und_ff, i_fiq_ff, i_irq_ff, i_swi_ff, i_instr_abort_ff})
                5'b1????: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b10000;
                5'b01???: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b01000;
                5'b001??: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b00100;
                5'b0001?: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b00010;
                5'b00001: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b00001;
                5'b00000: {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= 5'b00000;
                // Synthesis will OPTIMIZE. OK to do for FPGA synthesis.
                default : {o_und_ff, o_fiq_ff, o_irq_ff, o_swi_ff, o_instr_abort_ff} <= {5{1'bx}};
                endcase

                o_dav_ff              <= i_und_ff         ? 1'd0 :
                                         i_fiq_ff         ? 1'd0 :
                                         i_irq_ff         ? 1'd0 :
                                         i_swi_ff         ? 1'd0 :
                                         i_instr_abort_ff ? 1'd0 :
                                         i_dav_ff;

                o_mem_load_ff         <= i_mem_load_ff;
                o_mem_fault           <= i_mem_fault;
                mem_rd_data           <= i_mem_rd_data;

                // Debug.
                o_decompile           <= i_decompile;
                o_decompile_valid     <= i_decompile_valid;
                o_uop_last            <= i_uop_last;
        end
end

// Manual Pipeline Retiming.
always_ff @ (posedge i_clk)
begin
        if ( !i_data_stall )
        begin
                mem_load_ff2          <= i_mem_load_ff;
                mem_srcdest_value_ff2 <= i_mem_srcdest_value_ff;
                mem_address_ff2       <= i_mem_address_ff[1:0];
                sbyte_ff2             <= i_sbyte_ff;
                ubyte_ff2             <= i_ubyte_ff;
                shalf_ff2             <= i_shalf_ff;
                uhalf_ff2             <= i_uhalf_ff;
        end
end

always_comb
        o_mem_rd_data         = transform
                                (
                                        (
                                                mem_load_ff2 ?
                                                mem_rd_data    :
                                                mem_srcdest_value_ff2
                                        ),

                                        mem_address_ff2[1:0],
                                        sbyte_ff2,
                                        ubyte_ff2,
                                        shalf_ff2,
                                        uhalf_ff2,
                                        mem_load_ff2
                                );

//
// Memory always loads 32-bit to processor.
// We will rotate that here as we wish.
//
function automatic [31:0] transform (

        // Data and address.
        input [31:0]    data,
        input [1:0]     address,

        // Memory access data type.
        input           sbyte,
        input           ubyte,
        input           shalf,
        input           uhalf,

        // Memory load.
        input           mem_load_ff
);
begin: transform_function
        logic [31:0] d; // Data shorthand.

        transform = 32'd0;
        d         = data;

        // If it's a store, don't bother with the output of this.
        if ( mem_load_ff == 1'd0 )
        begin
                transform = data;
        end
        // Unsigned byte. Take only lower byte.
        else if ( ubyte == 1'd1 )
        begin
                case ( address[1:0] )
                2'd0: transform = {24'd0, d[7:0]};
                2'd1: transform = {24'd0, d[15:8]};
                2'd2: transform = {24'd0, d[23:16]};
                2'd3: transform = {24'd0, d[31: 24]};
            default : transform = 'x;
                endcase
        end
        // Signed byte. Sign extend lower byte.
        else if ( sbyte == 1'd1 )
        begin
                // Take lower byte and sign extend it.
                case ( address[1:0] )
                2'd0: transform = {{24{d[7] }},d[7:0]};
                2'd1: transform = {{24{d[15]}},d[15:8]};
                2'd2: transform = {{24{d[23]}},d[23:16]};
                2'd3: transform = {{24{d[31]}},d[31:24]};
             default: transform = 'x;
                endcase
        end
        // Signed half word. Sign extend lower 16-bit.
        else if ( shalf == 1'd1 )
        begin
                case ( address[1] )
                1'd0: transform = {{16{d[15]}},d[15:0]};
                1'd1: transform = {{16{d[31]}},d[31:16]};
             default: transform = 'x;
                endcase

                if ( o_dav_ff && mem_load_ff2 )
                begin
                        assert ( address[0] == 1'd0 ) else
                        $info("Warning: Address bit 0 is 1, leads to halfword load as UNPREDICTABLE.");
                end
        end
        // Unsigned half word. Take only lower 16-bit.
        else if ( uhalf == 1'd1 )
        begin
                case ( address[1] )
                1'd0: transform = {16'd0, d[15:0]};
                1'd1: transform = {16'd0, d[31:16]}; // address[1] = 1'd1
             default: transform = 'x;
                endcase

                if ( o_dav_ff && mem_load_ff2 )
                begin
                        assert ( address[0] == 1'd0 ) else
                        $info("Warning: Address bit 0 is 1, leads to halfword load as UNPREDICTABLE.");
                end
        end
        // Default. Typically, a word.
        else
        begin
                // Rotate data based on byte targetted.
                case ( address[1:0] )
                2'b00: transform = {             data [31:0]};
                2'b01: transform = {data  [7:0], data [31:8]};
                2'b10: transform = {data [15:0], data[31:16]};
                2'b11: transform = {data [23:0], data[31:24]};
              default: transform = 'x;
                endcase
        end
end
endfunction

endmodule

