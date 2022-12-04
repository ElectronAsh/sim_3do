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

module zap_writeback #(
        parameter BP_ENTRIES = 1024,
        parameter FLAG_WDT = 32, // Flags width a.k.a CPSR.
        parameter PHY_REGS = 46  // Number of physical registers.
)
(
        // Decompile.
        input   logic    [64*8-1:0]           i_decompile,
        output  logic    [64*8-1:0]           o_decompile,

        // Shelve output.
        output logic                          o_shelve,

        // Clear BTB
        input   logic                         i_clear_btb,

        // Clock and reset.
        input logic                           i_clk, 
        input logic                           i_reset,   

        // Inputs from memory unit valid signal.
        input logic                           i_valid,

        // The PC can either be frozen in place or changed based on signals
        // from other units. If a unit clears the PC, it must provide the
        // appropriate new value.
        input logic                           i_code_stall,
        input logic                           i_clear_from_alu,
        input logic      [31:0]               i_pc_from_alu,
        input logic                           i_clear_from_decode,
        input logic      [31:0]               i_pc_from_decode,
        input logic                           i_clear_from_icache,
        input logic                           i_confirm_from_alu, // Added
        input logic [31:0]                    i_alu_pc_ff, // Added
        input logic [1:0]                     i_taken,            // Added

        // 4 read ports for high performance.
        input logic   [$clog2(PHY_REGS)-1:0] i_rd_index_0, 
        input logic   [$clog2(PHY_REGS)-1:0] i_rd_index_1, 
        input logic   [$clog2(PHY_REGS)-1:0] i_rd_index_2, 
        input logic   [$clog2(PHY_REGS)-1:0] i_rd_index_3,

        // Memory load indicator.
        input logic                          i_mem_load_ff,

        // Write index and data and flag updates.
        input   logic [$clog2(PHY_REGS)-1:0] i_wr_index,
        input   logic [31:0]                 i_wr_data,
        input   logic [FLAG_WDT-1:0]         i_flags,
        input   logic                        i_thumb,
        input   logic [$clog2(PHY_REGS)-1:0] i_wr_index_1,
        input   logic [31:0]                 i_wr_data_1,
        input   logic [PHY_REGS-1:0]         i_wr_index_2,
        input   logic [31:0]                 i_wr_data_2,

        // Interrupt indicators.
        input   logic                         i_irq,
        input   logic                         i_fiq,
        input   logic                         i_instr_abt,
        input   logic [1:0]                   i_data_abt,
        input   logic                         i_swi,    
        input   logic                         i_und,

        // Program counter, PC + 8. This value is captured in the fetch
        // stage and is buffered all the way through.
        input   logic    [31:0]               i_pc_plus_8_buf_ff,

        // Coprocessor.
        input logic                              i_copro_reg_en,
        input logic      [$clog2(PHY_REGS)-1:0]  i_copro_reg_wr_index,
        input logic      [$clog2(PHY_REGS)-1:0]  i_copro_reg_rd_index,
        input logic      [31:0]                  i_copro_reg_wr_data,
        output logic      [31:0]                 o_copro_reg_rd_data_ff,

        // Read data from the register file.
        output logic     [31:0]               o_rd_data_0,         
        output logic     [31:0]               o_rd_data_1,         
        output logic     [31:0]               o_rd_data_2,         
        output logic     [31:0]               o_rd_data_3,

        // Program counter (dedicated port).
        output logic     [31:0]               o_pc,
        output logic     [31:0]               o_pc_check,
        output logic     [31:0]               o_pc_nxt,

        // Predict.
        output logic     [32:0]               o_pred,

        // CPSR output
        output logic      [31:0]              o_cpsr_nxt,

        // Clear from writeback
        output logic                         o_clear_from_writeback,

        // STB and CYC
        output logic                         o_wb_stb,
        output logic                         o_wb_cyc
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

// ----------------------------------------------------------------------------
// Variables
// ----------------------------------------------------------------------------

logic     [31:0]                  cpsr_ff, cpsr_nxt;
logic [$clog2(PHY_REGS)-1:0]      wa1, wa2;
logic [31:0]                      wdata1, wdata2;
logic                             wen;

logic                             shelve_ff, shelve_nxt;
logic [31:0]                      pc_shelve_ff, pc_shelve_nxt;
logic [32:0]                      pc_ff, pc_nxt;
logic [32:0]                      pc_del_ff, pc_del_nxt;
logic [32:0]                      pc_del2_ff, pc_del2_nxt;
logic [32:0]                      pc_del3_ff, pc_del3_nxt;

logic                             arm_mode;
logic                             clear_from_btb;
logic [31:0]                      pc_from_btb;

always_comb  arm_mode     = (cpsr_ff[T] == 1'd0) ? 1'd1 : 1'd0;
always_comb  o_shelve     = shelve_ff; // Shelve the PC until it is needed.
always_comb  o_pc         = pc_del3_ff[31:0];
always_comb  o_pc_check   = pc_del2_ff[31:0];
always_comb  o_pc_nxt     = pc_ff[31:0];
always_comb  o_cpsr_nxt   = cpsr_nxt;
always_comb  o_wb_stb     = pc_del3_ff[32];
always_comb  o_wb_cyc     = pc_del3_ff[32];

// ----------------------------------------------------------------------------
// Register file
// ----------------------------------------------------------------------------

zap_register_file u_zap_register_file
(
.i_clk(i_clk),
 .i_reset        (       i_reset         ),       

 .i_wr_addr_a    (       wa1             ),
 .i_wr_addr_b    (       wa2             ),
 .i_wr_addr_c    (     i_wr_index_2      ),

 .i_wr_data_a    (       wdata1          ),
 .i_wr_data_b    (       wdata2          ),
 .i_wr_data_c    (     i_wr_data_2       ),

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

// ----------------------------------------------------------------------------
// Combinational Logic
// ----------------------------------------------------------------------------

always_comb
begin: blk1
        shelve_nxt               = shelve_ff;
        pc_shelve_nxt            = pc_shelve_ff;
        wen                      = 1'd0;
        wa1                      = PHY_RAZ_REGISTER;
        wa2                      = PHY_RAZ_REGISTER;
        wdata1                   = 32'd0;
        wdata2                   = 32'd0;
        o_clear_from_writeback   = 0;

        cpsr_nxt                 = cpsr_ff;
        o_pred                   = 33'd0;

        pc_nxt                   = pc_ff;
        pc_del_nxt               = pc_del_ff;
        pc_del2_nxt              = pc_del2_ff;
        pc_del3_nxt              = pc_del3_ff;

        // ------------------- Low priority PC control tree -------------------------------
        // Keep looking further down for more high priority logic that can modify the PC.
        // Grep for High priority PC control tree.
        // --------------------------------------------------------------------------------

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
                pc_nxt      = pc_ff;
                pc_del_nxt  = pc_del_ff;
                pc_del2_nxt = pc_del2_ff;
                pc_del3_nxt = pc_del3_ff;
        end
        else if ( shelve_ff )
        begin
                pc_nxt      = {1'd1, pc_shelve_ff[31:0]};
                pc_del_nxt  = 33'd0;
                pc_del2_nxt = 33'd0;
                pc_del3_nxt = 33'd0;
                shelve_nxt  = 1'd0;
        end
        else if ( i_clear_from_icache ) // Lowest priority.
        begin
                pc_shelve (pc_del3_ff[31:0]);
        end
        else if ( clear_from_btb && pc_del3_ff[32] ) // Lowest priority now.
        begin
                pc_shelve (pc_from_btb);
                o_pred = {1'd1, pc_from_btb};
        end
        else
        begin
                pc_nxt[31:0] = pc_ff[31:0] + (i_thumb ? 32'd2 : 32'd4);
                pc_del_nxt   = pc_ff;
                pc_del2_nxt  = pc_del_ff;
                pc_del3_nxt  = pc_del2_ff;
        end

        // -------------- High priority PC control tree -------------------------
        // The stuff below has more priority than the above. This means even in
        // a global stall, interrupts can overtake execution. Further, writes to 
        // PC that reach writeback can cancel a global stall. On interrupts or 
        // jumps, all units are flushed effectively clearing any global stalls.
        // -----------------------------------------------------------------------
             
        if ( i_data_abt[1] )
        begin
                pc_shelve ( arm_mode ? i_pc_plus_8_buf_ff - 8 : i_pc_plus_8_buf_ff - 4 );
                o_clear_from_writeback = 1'd1;
        end   
        else if ( i_data_abt[0] )
        begin
                // Returns do LR - 8 to get back to the same instruction.
                pc_shelve( DABT_VECTOR ); 

                wen                     = 1;
                wdata1                  = arm_mode ? i_pc_plus_8_buf_ff : i_pc_plus_8_buf_ff + 4;
                wa1                     = PHY_ABT_R14;
                wa2                     = PHY_ABT_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE] = ABT;

                chmod ();
        end
        else if ( i_fiq )
        begin
                // Returns do LR - 4 to get back to the same instruction.
                pc_shelve ( FIQ_VECTOR ); 

                wen                     = 1;
                wdata1                  = arm_mode ? i_wr_data : i_pc_plus_8_buf_ff ;
                wa1                     = PHY_FIQ_R14;
                wa2                     = PHY_FIQ_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE] = FIQ;
                cpsr_nxt[F]             = 1'd1;

                chmod ();
        end
        else if ( i_irq )
        begin
                pc_shelve (IRQ_VECTOR); 

                wen                     = 1;
                wdata1                  = arm_mode ? i_wr_data : i_pc_plus_8_buf_ff ;
                wa1                     = PHY_IRQ_R14;
                wa2                     = PHY_IRQ_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE] = IRQ;
                // Returns do LR - 4 to get back to the same instruction.

                chmod ();
        end
        else if ( i_instr_abt )
        begin
                // Returns do LR - 4 to get back to the same instruction.
                pc_shelve (PABT_VECTOR); 

                wen    = 1;
                wdata1 = arm_mode ? i_wr_data : i_pc_plus_8_buf_ff ;
                wa1    = PHY_ABT_R14;
                wa2    = PHY_ABT_SPSR;
                wdata2 = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE]  = ABT;

                chmod ();
        end
        else if ( i_swi )
        begin
                // Returns do LR to return to the next instruction.
                pc_shelve(SWI_VECTOR); 

                wen                     = 1;
                wdata1                  = arm_mode ? i_wr_data : i_pc_plus_8_buf_ff ;
                wa1                     = PHY_SVC_R14;
                wa2                     = PHY_SVC_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE] = SVC;

                chmod ();
        end
        else if ( i_und )
        begin
                // Returns do LR to return to the next instruction.
                pc_shelve(UND_VECTOR); 

                wen                     = 1;
                wdata1                  = arm_mode ? i_wr_data : i_pc_plus_8_buf_ff ;
                wa1                     = PHY_UND_R14;
                wa2                     = PHY_UND_SPSR;
                wdata2                  = cpsr_ff;
                cpsr_nxt[`ZAP_CPSR_MODE] = UND;

                chmod ();
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
                if ( i_mem_load_ff && i_wr_index_1 == {2'd0, ARCH_PC})
                begin
                        pc_shelve (i_wr_data_1);
                        o_clear_from_writeback  = 1'd1;
                        cpsr_nxt[T]             = i_wr_data_1[0]; // Switch A/T state.
                end
        end

        // lower bit of pc = 0.
        pc_nxt[0] = 1'd0;
end

// ----------------------------------------------------------------------------
// Sequential Logic
// ----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_reset )
        begin
                // On reset, the CPU starts at 0 in
                // supervisor mode.
                shelve_ff                  <= 1'd0;

                pc_ff                      <= {1'd1, 32'd0};
                pc_del_ff                  <= 33'd0;
                pc_del2_ff                 <= 33'd0;
                pc_del3_ff                 <= 33'd0;

                // CPSR reset logic.
                cpsr_ff                    <= 32'd0;
                cpsr_ff[`ZAP_CPSR_MODE]    <= SVC;
                cpsr_ff[I]                 <= 1'd1; // Mask IRQ.
                cpsr_ff[F]                 <= 1'd1; // Mask FIQ.
                cpsr_ff[T]                 <= 1'd0; // Start CPU in ARM mode.
        end
        else
        begin
                shelve_ff                 <= shelve_nxt;
                pc_shelve_ff              <= pc_shelve_nxt;

                pc_ff                     <= pc_nxt;
                pc_del_ff                 <= pc_del_nxt;
                pc_del2_ff                <= pc_del2_nxt;
                pc_del3_ff                <= pc_del3_nxt;

                cpsr_ff                   <= cpsr_nxt;
                o_decompile               <= i_decompile;
                o_copro_reg_rd_data_ff    <= o_rd_data_0;
        end
end

// ----------------------------------------------------------------------------
// Instantiationss
// ----------------------------------------------------------------------------

zap_btb #(.BP_ENTRIES(BP_ENTRIES)) u_zap_btb (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .i_stall(i_code_stall),
        .i_clear(i_clear_btb),
        .i_fb_ok(i_confirm_from_alu),
        .i_fb_nok(i_clear_from_alu),
        .i_fb_branch_src_address(i_alu_pc_ff),
        .i_fb_branch_dest_address(i_pc_from_alu),
        .i_fb_current_branch_state(i_taken),
        .i_rd_addr(pc_del_ff[31:0]),
        .i_rd_addr_del(pc_del2_ff[31:0]),
        .o_clear_from_btb(clear_from_btb),
        .o_pc_from_btb(pc_from_btb)
);

// ----------------------------------------------------------------------------
// Tasks
// ----------------------------------------------------------------------------

function void pc_shelve (input [31:0] new_pc);
begin
        if (!i_code_stall )
        begin
                // Jump instruction basically.
                pc_nxt        = {1'd1, new_pc};
                pc_del_nxt    = {1'd0, pc_ff[31:0]};
                pc_del2_nxt   = {1'd0, pc_del_ff[31:0]};
                pc_del3_nxt   = {1'd0, pc_del2_ff[31:0]};
                shelve_nxt    = 1'd0;
        end
        else
        begin
                shelve_nxt    = 1'd1;
                pc_shelve_nxt = new_pc;

                pc_nxt        = pc_ff;
                pc_del_nxt    = pc_del_ff;
                pc_del2_nxt   = pc_del2_ff;
                pc_del3_nxt   = pc_del3_ff;
        end
end
endfunction

function void chmod;
begin
        o_clear_from_writeback  = 1'd1;
        cpsr_nxt[I]             = 1'd1; // Mask interrupts.
        cpsr_nxt[T]             = 1'd0; // Go to ARM mode.
end
endfunction

endmodule // zap_register_file.v


// ----------------------------------------------------------------------------
// END OF FILE
// ----------------------------------------------------------------------------
