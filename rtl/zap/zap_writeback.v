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

`default_nettype none

module zap_writeback #(
        parameter FLAG_WDT = 32, // Flags width a.k.a CPSR.
        parameter PHY_REGS = 46  // Number of physical registers.
)
(
        // Decompile.
        input   wire    [64*8-1:0]           i_decompile,
        output  reg     [64*8-1:0]           o_decompile,

        // Shelve output.
        output wire                          o_shelve,

        // Clock and reset.
        input wire                           i_clk, 
        input wire                           i_reset,   

        // Inputs from memory unit valid signal.
        input wire                           i_valid,

        // The PC can either be frozen in place or changed based on signals
        // from other units. If a unit clears the PC, it must provide the
        // appropriate new value.
        input wire                           i_code_stall,
        input wire                           i_data_stall,
        input wire                           i_clear_from_alu,
        input wire      [31:0]               i_pc_from_alu,
        input wire                           i_stall_from_decode,
        input wire                           i_stall_from_issue,
        input wire                           i_stall_from_shifter,
        input wire                           i_clear_from_decode,
        input wire      [31:0]               i_pc_from_decode,

        // 4 read ports for high performance.
        input wire   [$clog2(PHY_REGS)-1:0] i_rd_index_0, 
        input wire   [$clog2(PHY_REGS)-1:0] i_rd_index_1, 
        input wire   [$clog2(PHY_REGS)-1:0] i_rd_index_2, 
        input wire   [$clog2(PHY_REGS)-1:0] i_rd_index_3,

        // Memory load indicator.
        input wire                          i_mem_load_ff,

        // Write index and data and flag updates.
        input   wire [$clog2(PHY_REGS)-1:0] i_wr_index,
        input   wire [31:0]                 i_wr_data,
        input   wire [FLAG_WDT-1:0]         i_flags,
        input   wire                        i_thumb,
        input   wire [$clog2(PHY_REGS)-1:0] i_wr_index_1,
        input   wire [31:0]                 i_wr_data_1,

        // Interrupt indicators.
        input   wire                         i_irq,
        input   wire                         i_fiq,
        input   wire                         i_instr_abt,
        input   wire                         i_data_abt,
        input   wire                         i_swi,    
        input   wire                         i_und,

        // Program counter, PC + 8. This value is captured in the fetch
        // stage and is buffered all the way through.
        input   wire    [31:0]               i_pc_buf_ff,

        // Coprocessor.
        input wire                              i_copro_reg_en,
        input wire      [$clog2(PHY_REGS)-1:0]  i_copro_reg_wr_index,
        input wire      [$clog2(PHY_REGS)-1:0]  i_copro_reg_rd_index,
        input wire      [31:0]                  i_copro_reg_wr_data,
        output reg      [31:0]                  o_copro_reg_rd_data_ff,

        // Read data from the register file.
        output wire     [31:0]               o_rd_data_0,         
        output wire     [31:0]               o_rd_data_1,         
        output wire     [31:0]               o_rd_data_2,         
        output wire     [31:0]               o_rd_data_3,

        // Program counter (dedicated port).
        output wire     [31:0]               o_pc,
        output wire     [31:0]               o_pc_nxt,

        // CPSR output
        output wire      [31:0]              o_cpsr_nxt,

        // Clear from writeback
        output reg                           o_clear_from_writeback,

        // Hijack I/F
        output reg    [31:0]                  o_hijack_op1,
        output reg    [31:0]                  o_hijack_op2,
        output reg                            o_hijack_cin,
        output reg                            o_hijack,
        input wire     [31:0]                 i_hijack_sum
);

`include "zap_defines.vh"
`include "zap_localparams.vh"
`include "zap_functions.vh"

// ----------------------------------------------
// Localparams
// ----------------------------------------------

`ifndef ARM_MODE
        `define ARM_MODE (cpsr_ff[T] == 1'd0)
`endif

localparam RST_VECTOR   = 32'h00000000;
localparam UND_VECTOR   = 32'h00000004;
localparam SWI_VECTOR   = 32'h00000008;
localparam PABT_VECTOR  = 32'h0000000C;
localparam DABT_VECTOR  = 32'h00000010;
localparam IRQ_VECTOR   = 32'h00000018;
localparam FIQ_VECTOR   = 32'h0000001C;

// ----------------------------------------------
// Variables
// ----------------------------------------------

// assertions_start
        reg fiq_ack;
        reg irq_ack;
        reg und_ack;
        reg dabt_ack;
        reg iabt_ack;
        reg swi_ack;
        integer irq_addr = 0;
        reg temp_set = 0;
        reg error = 0;
// assertions_end

reg     [31:0]                  cpsr_ff, cpsr_nxt;
reg     [31:0]                  pc_ff, pc_nxt;
reg [$clog2(PHY_REGS)-1:0]      wa1, wa2;
reg [31:0]                      wdata1, wdata2;
reg                             wen;
reg [31:0]                      pc_shelve_ff, pc_shelve_nxt;
reg                             shelve_ff, shelve_nxt;

assign  o_shelve        = shelve_ff; // Shelve the PC until it is needed.
assign  o_pc            = pc_ff;
assign  o_pc_nxt        = pc_nxt & 32'hfffffffe;
assign  o_cpsr_nxt      = cpsr_nxt;

// ----------------------------------------------
// Register file
// ----------------------------------------------

zap_register_file u_zap_register_file
(
.i_clk(i_clk),
 .i_reset        (       i_reset         ),       

 .i_wr_addr_a    (       wa1             ),
 .i_wr_addr_b    (       wa2             ),

 .i_wr_data_a    (       wdata1          ),
 .i_wr_data_b    (       wdata2          ),

 .i_wen          (       wen             ),        

 .i_rd_addr_a    ( i_copro_reg_en ? i_copro_reg_rd_index : i_rd_index_0 ),
 .i_rd_addr_b    (       i_rd_index_1    ),
 .i_rd_addr_c    (       i_rd_index_2    ),
 .i_rd_addr_d    (       i_rd_index_3    ),

 .o_rd_data_a    (       o_rd_data_0     ),
 .o_rd_data_b    (       o_rd_data_1     ),
 .o_rd_data_c    (       o_rd_data_2     ),
 .o_rd_data_d    (       o_rd_data_3     )
);

// ---------------------------------------------
// Combinational Logic
// ---------------------------------------------

always @ (*)
begin: blk1

        integer i;

        shelve_nxt    = shelve_ff;
        pc_shelve_nxt = pc_shelve_ff;

        // assertions_start
                fiq_ack  = 0;
                irq_ack  = 0;
                und_ack  = 0;
                dabt_ack = 0;
                iabt_ack = 0;
                swi_ack  = 0;
        // assertions_end

        o_hijack     = 0;
        o_hijack_op1 = 0;
        o_hijack_op2 = 0;
        o_hijack_cin = 0;

        wen     = 1'd0;
        wa1     = PHY_RAZ_REGISTER;
        wa2     = PHY_RAZ_REGISTER;
        wdata1  = 32'd0;
        wdata2  = 32'd0;

        o_clear_from_writeback = 0;

        pc_nxt   = pc_ff;
        cpsr_nxt = cpsr_ff;


        // Low priority PC control tree.

        if ( i_clear_from_alu )
        begin
                pc_shelve(i_pc_from_alu);
        end

        else if ( i_clear_from_decode )
        begin
                pc_shelve(i_pc_from_decode);
        end

        else if ( i_code_stall )
        begin
                pc_nxt = pc_ff;
        end
        else if ( shelve_ff )
        begin

                pc_nxt     = pc_shelve_ff;
                shelve_nxt = 1'd0;
        end
        else
        begin
                pc_nxt = pc_ff + (i_thumb ? 32'd2 : 32'd4);
        end


        // The stuff below has more priority than the above. This means even in
        // a global stall, interrupts can overtake execution. Further, writes to 
        // PC that reach writeback can cancel a global stall. On interrupts or 
        // jumps, all units are flushed effectively clearing any global stalls.

        if ( i_data_abt         || 
                i_fiq           || 
                i_irq           || 
                i_instr_abt     || 
                i_swi           ||
                i_und )
        begin
                o_clear_from_writeback  = 1'd1;
                cpsr_nxt[I]      = 1'd1; // Mask interrupts.
                cpsr_nxt[T]      = 1'd0; // Go to ARM mode.
        end
                
        if ( i_data_abt )
        begin
                o_hijack    =  1'd1;
                o_hijack_op1 = i_pc_buf_ff;
                o_hijack_op2 = 32'd4;
                o_hijack_cin = 1'd0;

                // Returns do LR - 8 to get back to the same instruction.
                pc_shelve( DABT_VECTOR ); 

                wen                     = 1;
                wdata1                  = `ARM_MODE ? i_pc_buf_ff : i_hijack_sum[31:0];
                wa1                     = PHY_ABT_R14;
                wa2                     = PHY_ABT_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]    = ABT;

                // assertions_start
                        dabt_ack = 1'd1;
                // assertions_end

        end
        else if ( i_fiq )
        begin
                $display($time, " - %m :: FIQ detected.");

                // Returns do LR - 4 to get back to the same instruction.
                pc_shelve ( FIQ_VECTOR ); 

                wen                     = 1;
                wdata1                  = `ARM_MODE ? i_wr_data : i_pc_buf_ff ;
                wa1                     = PHY_FIQ_R14;
                wa2                     = PHY_FIQ_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]    = FIQ;
                cpsr_nxt[F]             = 1'd1;

                // assertions_start
                        fiq_ack = 1'd1;
                // assertions_end
        end
        else if ( i_irq )
        begin
                $display($time, " - %m :: IRQ detected.");

                pc_shelve (IRQ_VECTOR); 

                wen                     = 1;
                wdata1                  = `ARM_MODE ? i_wr_data : i_pc_buf_ff ;
                wa1                     = PHY_IRQ_R14;
                wa2                     = PHY_IRQ_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]    = IRQ;
                // Returns do LR - 4 to get back to the same instruction.

                // assertions_start
                        irq_addr = wdata1;
                        irq_ack  = 1'd1;
                // assertions_end
        end
        else if ( i_instr_abt )
        begin
                // Returns do LR - 4 to get back to the same instruction.
                pc_shelve (PABT_VECTOR); 

                wen    = 1;
                wdata1 = `ARM_MODE ? i_wr_data : i_pc_buf_ff ;
                wa1    = PHY_ABT_R14;
                wa2    = PHY_ABT_SPSR;
                wdata2 = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]  = ABT;

                // assertions_start
                        iabt_ack = 1'd1;
                // assertions_end
        end
        else if ( i_swi )
        begin
                // Returns do LR to return to the next instruction.
                pc_shelve(SWI_VECTOR); 

                wen                     = 1;
                wdata1                  = `ARM_MODE ? i_wr_data : i_pc_buf_ff ;
                wa1                     = PHY_SVC_R14;
                wa2                     = PHY_SVC_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]    = SVC;

                // assertions_start
                        swi_ack = 1'd1;
                // assertions_end
        end
        else if ( i_und )
        begin
                // Returns do LR to return to the next instruction.
                pc_shelve(UND_VECTOR); 

                wen                     = 1;
                wdata1                  = `ARM_MODE ? i_wr_data : i_pc_buf_ff ;
                wa1                     = PHY_UND_R14;
                wa2                     = PHY_UND_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`CPSR_MODE]    = UND;

                // assertions_start
                        und_ack = 1'd1;
                // assertions_end
        end
        else if ( i_copro_reg_en )
        begin
               // Write to register (Coprocessor command).
               wen      = 1;
               wa1      = i_copro_reg_wr_index;
               wdata1   = i_copro_reg_wr_data;
        end
        else if ( i_valid ) // If valid,
        begin
                // Only then execute the instruction at hand...
                cpsr_nxt                =   i_flags;

                // Dual write port.
                wen    = 1;

                // Port from arithmetic side
                wa1    = i_wr_index;
                wdata1 = i_wr_data;

                // Port from memory side.
                wa2    = i_mem_load_ff ? i_wr_index_1 : PHY_RAZ_REGISTER;
                wdata2 = i_wr_data_1;

                // Load to PC will trigger from writeback.
                if ( i_mem_load_ff && i_wr_index_1 == ARCH_PC)
                begin
                        $display($time, " - %m :: Detected load to PC. Trigger a writeback.");

                        pc_shelve (i_wr_data_1);
                        o_clear_from_writeback  = 1'd1;
                end
        end

        // Ensure lower 2 bits of PC are always tied to VSS.
        pc_nxt = pc_nxt & 32'hffff_fffe;
end

// ----------------------------------------------
// Sequential Logic
// ----------------------------------------------

always @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                // On reset, the CPU starts at 0 in
                // supervisor mode.
                shelve_ff                  <= 1'd0;
                pc_ff                      <= 32'd0;
                cpsr_ff                    <= SVC;
                cpsr_ff[I]                 <= 1'd1; // Mask IRQ.
                cpsr_ff[F]                 <= 1'd1; // Mask FIQ.
                cpsr_ff[T]                 <= 1'd0; // Start CPU in ARM mode.
        end
        else
        begin
                shelve_ff                 <= shelve_nxt;
                pc_shelve_ff              <= pc_shelve_nxt;
                pc_ff                     <= pc_nxt;
                cpsr_ff                   <= cpsr_nxt;
                o_decompile               <= i_decompile;
                o_copro_reg_rd_data_ff    <= o_rd_data_0;
        end
end

// ----------------------------------------------
// Tasks
// ----------------------------------------------

task pc_shelve (input [31:0] new_pc);
begin
        if (!i_code_stall )
        begin
                pc_nxt = new_pc;
                shelve_nxt = 1'd0; // BUG FIX.
        end
        else
        begin 
                shelve_nxt = 1'd1;
                pc_shelve_nxt = new_pc;
                pc_nxt = pc_ff;
        end
end
endtask

// assertions_start 

        always @ (*)
        if ( cpsr_nxt[`CPSR_MODE] != USR && cpsr_ff[`CPSR_MODE] == USR )
        begin
                if ( 
                        i_data_abt      || 
                        i_fiq           || 
                        i_irq           || 
                        i_instr_abt     || 
                        i_swi           ||
                        i_und
                 )
                begin
                        // OKAY...
                end
                else
                begin
                        $display($time, "Error : %m CPU is changing out of USR mode without an exception...");
                        $stop;
                end
        end

// assertions_end

endmodule // zap_register_file.v
`default_nettype wire
