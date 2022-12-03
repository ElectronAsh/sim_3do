// ------------------------------------------------------------------------------
// --                                                                          --
// --                   (C) 2016-2018 Revanth Kamaraj.                         --
// --                                                                          -- 
// -- ---------------------------------------------------------------------------
// --                                                                          --
// -- This program is free software; you can redistribute it and/or            --
// -- modify it under the terms of the GNU General Public License              --
// -- as published by the Free Software Foundation; either version 2           --
// -- of the License, or (at your option) any later version.                   --
// --                                                                          --
// -- This program is distributed in the hope that it will be useful,          --
// -- but WITHOUT ANY WARRANTY; without even the implied warranty of           --
// -- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            --
// -- GNU General Public License for more details.                             --
// --                                                                          --
// -- You should have received a copy of the GNU General Public License        --
// -- along with this program; if not, write to the Free Software              --
// -- Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA            --
// -- 02110-1301, USA.                                                         --
// --                                                                          --
// ------------------------------------------------------------------------------
// --                                                                          --          
// --  This stage merely acts as a buffer in between the ALU stage and the reg.-- 
// --  file (i.e., writeback stage). 32-bit data received from the cache is    -- 
// --  is rotated appropriately here in case of byte reads or halfword reads.  --
// --  Otherwise, this stage is simply a buffer.                               -- 
// --                                                                          -- 
// ------------------------------------------------------------------------------

`default_nettype none
module zap_memory_main
#(
        // Width of CPSR.
        parameter FLAG_WDT = 32,

        // Number of physical registers.
        parameter PHY_REGS = 46
)
(
        // Debug
        input   wire    [64*8-1:0]          i_decompile,
        output  reg     [64*8-1:0]          o_decompile,

        // Clock and reset.
        input wire                          i_clk,
        input wire                          i_reset,

        // Pipeline control signals.
        input wire                          i_clear_from_writeback,
        input wire                          i_data_stall,

        // Memory stuff.
        input   wire                        i_mem_load_ff,
        input   wire [31:0]                  i_mem_address_ff, // Access Address.

        // Data read from memory.
        input   wire [31:0]                 i_mem_rd_data,

        // Memory fault transfer. i_mem_fault comes from the cache unit.
        input   wire                        i_mem_fault,      // Fault in.
        output  reg                         o_mem_fault,      // Fault out.

        // Data valid and buffered PC.
        input wire                          i_dav_ff,
        input wire [31:0]                   i_pc_plus_8_ff,

        // ALU value, flags,and where to write the value.
        input wire [31:0]                   i_alu_result_ff,
        input wire  [FLAG_WDT-1:0]          i_flags_ff,
        input wire [$clog2(PHY_REGS)-1:0]   i_destination_index_ff,

        // Interrupts.
        input   wire                        i_irq_ff,
        input   wire                        i_fiq_ff,
        input   wire                        i_instr_abort_ff,
        input   wire                        i_swi_ff,

        // Memory SRCDEST index. For loads, this tells the register file where
        // to put the read data. Set to point to RAZ if invalid.
        input wire [$clog2(PHY_REGS)-1:0]   i_mem_srcdest_index_ff,

        // SRCDEST value.
        input wire [31:0]                   i_mem_srcdest_value_ff,

        // Memory size and type.
        input wire                          i_sbyte_ff, 
                                            i_ubyte_ff, 
                                            i_shalf_ff, 
                                            i_uhalf_ff,

        // Undefined instr.
        input wire                         i_und_ff,
        output reg                         o_und_ff,

        // ALU result and flags.
        output reg  [31:0]                   o_alu_result_ff,
        output reg  [FLAG_WDT-1:0]           o_flags_ff,

        // Where to write ALU and memory read target register.
        output reg [$clog2(PHY_REGS)-1:0]    o_destination_index_ff,

        // Set to point to the RAZ register if invalid.
        output reg [$clog2(PHY_REGS)-1:0]    o_mem_srcdest_index_ff, 

        // Outputs valid and PC buffer.
        output reg                           o_dav_ff,
        output reg [31:0]                    o_pc_plus_8_ff,

        // The whole interrupt signaling scheme.
        output reg                           o_irq_ff,
        output reg                           o_fiq_ff,
        output reg                           o_swi_ff,
        output reg                           o_instr_abort_ff,

        // Memory load information is passed down.
        output reg                           o_mem_load_ff,
        output reg  [31:0]                   o_mem_rd_data
);

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

reg                             i_mem_load_ff2          ;
reg [31:0]                      i_mem_srcdest_value_ff2 ;
reg [31:0]                      i_mem_address_ff2       ;
reg                             i_sbyte_ff2             ;
reg                             i_ubyte_ff2             ;
reg                             i_shalf_ff2             ;
reg                             i_uhalf_ff2             ;
reg [31:0]                      mem_rd_data             ;

// Invalidates the outptus of this stage.
task clear;
begin
        // Invalidate stage.
        o_dav_ff                  <= 0;

        // Clear interrupts.
        o_irq_ff                  <= 0;
        o_fiq_ff                  <= 0;
        o_swi_ff                  <= 0;
        o_instr_abort_ff          <= 0;
        o_und_ff                  <= 0;
        o_mem_fault               <= 0;
end
endtask

// On reset or on a clear from WB, we will disable the vectors
// in this unit. Else, we will just flop everything out.
always @ (posedge i_clk)
if ( i_reset )
begin
        clear;
end
else if ( i_clear_from_writeback )
begin
        clear;
end
else if ( i_data_stall )
begin
        // Stall unit. Outputs do not change.
        o_dav_ff <= 1'd0;
end
else
begin
        // Just flop everything out.
        o_alu_result_ff       <= i_alu_result_ff;
        o_flags_ff            <= i_flags_ff;
        o_mem_srcdest_index_ff<= i_mem_srcdest_index_ff;
        o_dav_ff              <= i_dav_ff;
        o_destination_index_ff<= i_destination_index_ff;
        o_pc_plus_8_ff        <= i_pc_plus_8_ff;
        o_irq_ff              <= i_irq_ff;
        o_fiq_ff              <= i_fiq_ff;
        o_swi_ff              <= i_swi_ff;
        o_instr_abort_ff      <= i_instr_abort_ff;
        o_mem_load_ff         <= i_mem_load_ff; 
        o_und_ff              <= i_und_ff;
        o_mem_fault           <= i_mem_fault;
        mem_rd_data           <= i_mem_rd_data;

        // Debug.
        o_decompile           <= i_decompile;
end

// Manual Pipeline Retiming.
always @ (posedge i_clk)
begin
        if ( !i_data_stall )
        begin
                i_mem_load_ff2          <= i_mem_load_ff;
                i_mem_srcdest_value_ff2 <= i_mem_srcdest_value_ff;
                i_mem_address_ff2       <= i_mem_address_ff;
                i_sbyte_ff2             <= i_sbyte_ff;
                i_ubyte_ff2             <= i_ubyte_ff;
                i_shalf_ff2             <= i_shalf_ff;
                i_uhalf_ff2             <= i_uhalf_ff;
        end
end

always @*
o_mem_rd_data         = transform((i_mem_load_ff2 ? mem_rd_data : 
                        i_mem_srcdest_value_ff2), i_mem_address_ff2[1:0], 
                        i_sbyte_ff2, i_ubyte_ff2, i_shalf_ff2, i_uhalf_ff2, 
                        i_mem_load_ff2);

// Memory always loads 32-bit to processor. 
// We will rotate that here as we wish.

function [31:0] transform ( 

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
        reg [31:0] d; // Data shorthand.

        transform = 32'd0;
        d         = data;

        // Unsigned byte. Take only lower byte.
        if ( ubyte == 1'd1 )
        begin
                case ( address[1:0] )
                0: transform = (d >> 24) & 32'h000000ff;	// 3DO ARM60 Endianess kludge. ElectronAsh.
                1: transform = (d >> 16) & 32'h000000ff;
                2: transform = (d >> 8)  & 32'h000000ff;
                3: transform = (d >> 0)  & 32'h000000ff;
                endcase
        end
        // Signed byte. Sign extend lower byte.
        else if ( sbyte == 1'd1 )
        begin
                // Take lower byte.
                case ( address[1:0] )
                0: transform = (d >> 24) & 32'h000000ff;	// 3DO ARM60 Endianess kludge. ElectronAsh.
                1: transform = (d >> 16) & 32'h000000ff;
                2: transform = (d >> 8)  & 32'h000000ff;
                3: transform = (d >> 0)  & 32'h000000ff;
                endcase

                // Sign extend.
                transform = $signed(transform[7:0]);
        end
        // Signed half word. Sign extend lower 16-bit.
        else if ( shalf == 1'd1 )
        begin
                case ( address[1] )
                0: transform = (d >>  0) & 32'h0000ffff;
                1: transform = (d >> 16) & 32'h0000ffff;
                endcase

                transform = $signed(transform[15:0]);
        end
        // Unsigned half word. Take only lower 16-bit.
        else if ( uhalf == 1'd1 )
        begin
                case ( address[1] )
                0: transform = (d >>  0) & 32'h0000ffff;
                1: transform = (d >> 16) & 32'h0000ffff;
                endcase
        end
        else // Default. Typically, a word.
        begin
                transform = data;
        end

        // Override above computation if not a memory load.
        if ( !mem_load_ff ) 
        begin
                transform = data; // No memory load means pass data on.
        end
end
endfunction

endmodule
`default_nettype wire
