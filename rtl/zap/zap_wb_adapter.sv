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
// --  Implements store FIFO. Serves as a bridge between the processor core & --
// --  the memory interface.                                                  --
// --                                                                         --
// -----------------------------------------------------------------------------



module zap_wb_adapter #(
        parameter DEPTH     = 32,
        parameter BURST_LEN = 4
) (

// Clock.
input logic                   i_clk,
input logic                   i_reset,

// Processor Wishbone interface. These come from the Wishbone registered
// interface.
input logic                   I_WB_CYC,
input logic                   I_WB_STB,   
input logic [3:0]             I_WB_SEL,     
input logic [2:0]             I_WB_CTI,   
input logic [31:0]            I_WB_ADR,    
input logic [31:0]            I_WB_DAT,    
input logic                   I_WB_WE,
output logic [31:0]           O_WB_DAT,    
output logic                  O_WB_ACK,     

// Wishbone interface.
output logic                  o_wb_cyc,
output logic                  o_wb_stb,
output logic     [31:0]       o_wb_dat,
output logic     [31:0]       o_wb_adr,
output logic     [3:0]        o_wb_sel,
output logic     [2:0]        o_wb_cti,
output logic                  o_wb_we,
input logic      [31:0]       i_wb_dat,
input logic                   i_wb_ack
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

logic           fsm_write_en;
logic  [69:0]   fsm_write_data;
logic           w_eob;
logic           w_full;
logic           w_emp;
logic  [31:0]   ctr_nxt, ctr_ff;
logic  [31:0]   dff, dnxt;
logic  [31:0]   adr_buf_nxt, adr_buf_ff;
logic           ack;        // ACK write channel.
logic           ack_ff;     // Read channel.

localparam IDLE             = 0;
localparam PRPR_RD_SINGLE   = 1;
localparam PRPR_RD_BURST    = 2;
localparam WRITE            = 3;
localparam WAIT1            = 4;
localparam WAIT2            = 5;
localparam NUMBER_OF_STATES = 6;

logic [$clog2(NUMBER_OF_STATES)-1:0] state_ff, state_nxt;

zap_sync_fifo #(.WIDTH(32'd70), .DEPTH(DEPTH), .FWFT(32'd1)) U_STORE_FIFO (
.i_clk          (i_clk),
.i_reset        (i_reset),
.i_ack          (i_wb_ack && !w_emp),
.i_wr_en        (fsm_write_en && !w_full),
.i_data         (fsm_write_data),
.o_data         ({o_wb_sel, o_wb_dat, o_wb_adr, w_eob, o_wb_we}),
.o_empty        (w_emp),
.o_full         (w_full),

/* verilator lint_off PINCONNECTEMPTY */
.o_empty_n      (),
.o_full_n       (),
.o_full_n_nxt   ()
/* verilator lint_on PINCONNECTEMPTY */
);

// FIFO output is basically registered.
always_comb
begin
        o_wb_stb = !w_emp;
        o_wb_cyc = !w_emp;
        o_wb_cti = w_eob ? CTI_EOB : CTI_BURST;
end

// Flip flop clocking block.
always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                state_ff <= IDLE;
                ctr_ff   <= 0;
                dff      <= 0;
                adr_buf_ff<= 32'd0;
        end
        else
        begin
                state_ff <= state_nxt;
                ctr_ff   <= ctr_nxt;
                dff      <= dnxt;
                adr_buf_ff<=adr_buf_nxt;
        end
end

// Reads from the Wishbone bus are flopped.
always_ff @ (posedge i_clk)
begin
        if ( i_reset )
        begin
                ack_ff   <= 1'd0;
                O_WB_DAT <= 32'd0;
        end
        else if ( !o_wb_we && o_wb_cyc && o_wb_stb && i_wb_ack ) // Read on wishbone.
        begin
                // Send ACK on next cycle.
                ack_ff   <= 1'd1;
                O_WB_DAT <= i_wb_dat;
        end
        else
        begin
                ack_ff <= 1'd0;
        end
end

// ACK from read | ACK from write.
always_comb O_WB_ACK = ack_ff | ack;

// State machine.
always_comb
begin:blk1
        state_nxt      = state_ff;
        ctr_nxt        = ctr_ff;
        ack            = 1'd0;
        dnxt           = dff;
        fsm_write_en   = 1'd0;
        fsm_write_data = 70'd0;
        adr_buf_nxt    = adr_buf_ff;

        case ( state_ff )

        IDLE:
        begin
                ctr_nxt = 32'd0;
                dnxt    = 32'd0;

                if ( I_WB_STB && I_WB_CYC && I_WB_WE && !o_wb_stb ) // Wishbone write request 
                begin
                        // Simply buffer stores into the FIFO.
                        state_nxt = WRITE;
                end   
                else if ( I_WB_STB && I_WB_CYC && !I_WB_WE && !o_wb_stb ) // Wishbone read request
                begin
                        // Write a set of reads into the FIFO.
                        if ( I_WB_CTI == CTI_BURST ) // Burst of BURST_LEN words. Each word is 4 byte.
                        begin
                                state_nxt   = PRPR_RD_BURST;
                                adr_buf_nxt = I_WB_ADR;
                        end
                        else // Single.
                        begin
                                state_nxt = PRPR_RD_SINGLE; 
                        end
                end
        end

        PRPR_RD_SINGLE: // Write a single read token into the FIFO.
        begin
                if ( !w_full )
                begin
                        state_nxt      = WAIT1;
                        fsm_write_en   = 1'd1;
                        fsm_write_data = {      
                                                I_WB_SEL, 
                                                I_WB_DAT, 
                                                I_WB_ADR & ~32'h3, 
                                                I_WB_CTI != CTI_BURST ? 1'd1 : 1'd0, 
                                                1'd0
                                         };
                end
        end

        PRPR_RD_BURST: // Write burst read requests into the FIFO.
        begin
                if ( O_WB_ACK )
                        dnxt = dff + 32'd1;
                else
                        dnxt = dff;

                if ( ctr_ff == BURST_LEN )
                begin
                        ctr_nxt   = 0;
                        state_nxt = WAIT2; // FIFO prep done.
                end
                else if ( !w_full )
                begin
                        fsm_write_en   = 1'd1;
                        fsm_write_data = 
                        {I_WB_SEL, 
                         32'd0,    
                         (adr_buf_ff & ~32'h3) + (ctr_ff << 32'd2),
                         ctr_ff == BURST_LEN - 1 ? 1'd1 : 1'd0, 
                         1'd0};

                        ctr_nxt = ctr_ff + 32'd1;
                end                
        end

        WRITE:
        begin
                // As long as write burst requests exist, write them out to the FIFO.
                if ( I_WB_STB && I_WB_WE )
                begin
                        if ( !w_full )
                        begin
                                fsm_write_en    = 1'd1;
                                fsm_write_data  =  
                                {I_WB_SEL, 
                                 I_WB_DAT, 
                                 I_WB_ADR & ~32'h3, 
                                 I_WB_CTI != CTI_BURST ? 1'd1 : 1'd0, 
                                 1'd1};
                                ack = 1'd1;
                        end
                end
                else // Writes done!
                begin
                        state_nxt = IDLE;
                end
        end

        WAIT1: // Wait for single read to complete.
        begin
                if ( O_WB_ACK )
                        state_nxt = IDLE;
                else
                        state_nxt = state_ff;
        end

        WAIT2: // Wait for burst reads to complete.
        begin
                if ( O_WB_ACK )
                        dnxt = dff + 1;
                else
                        dnxt = dff;

                if ( dff == BURST_LEN && !o_wb_stb )
                        state_nxt = IDLE;
                else
                        state_nxt = state_ff;
        end

        endcase
end

endmodule



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
