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
// This is a pipelined memory macro for high performance. Very similar
// to zap_ram_simple but has byte enables. Please use that file to
// follow code comments.
//
// The key difference in the hazard detection logic is that it is byte
// wise. For example, a 32-bit read could have each of its 4 bytes
// modified over 3 cycles, the final data should reflect that.
//
// This memory has a read latency of 3 cycles.
//
// We cannot generalize this memory to every case because we may need
// memories whose widths are less than a byte. Although it is possible
// to merge multiple rows of such memories into a single column, we choose
// to have a separate memory system with byte enables not present.
//

module zap_ram_simple_ben #(
        parameter logic [31:0] WIDTH = 32'd32,
        parameter logic [31:0] DEPTH = 32'd32
)
(
        // Clock and reset.
        input logic                          i_clk,

        // Clock enable/read enable.
        input logic                          i_clken,

        // Write enable. Needs i_clken=1 to actually write.
        input logic [WIDTH/8-1:0]            i_wr_en,

        // Write data and address.
        input logic [WIDTH-1:0]              i_wr_data,
        input logic[$clog2(DEPTH)-1:0]       i_wr_addr,

        // Read address and data.
        input logic [$clog2(DEPTH)-1:0]      i_rd_addr,

        // 2 cycle delayed read data.
        output logic [WIDTH-1:0]             o_rd_data_pre,

        // 3 cycle delayed read data.
        output logic [WIDTH-1:0]             o_rd_data
);

initial
begin
        assert ( WIDTH % 8 == 0 ) else
        $fatal(2, "RAM width not a multiple of bytes.");
end

// Note that the sel_* signals are bytewise, simply because writes can only
// target a byte.

logic [WIDTH-1:0] mem [DEPTH-1:0];
logic [WIDTH-1:0]         mem_data_st1, mem_data_st2;
logic [WIDTH-1:0]         buffer_st1, buffer_st2, buffer_st2_x;
logic [WIDTH/8-1:0][1:0]  sel_st1;
logic [WIDTH/8-1:0][2:0]  sel_st2;
logic [$clog2(DEPTH)-1:0] rd_addr_st1, rd_addr_st2;

// ----------------------------------------------------------------------------
// High speed RAM logic
// ----------------------------------------------------------------------------

// Write logic.
always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                for(int i=0;i<WIDTH/8;i++)
                begin
                        if ( i_wr_en[i] )
                        begin
                                mem [ i_wr_addr ][ i*8 +: 8 ] <=
                                i_wr_data [i*8 +: 8];
                        end
                end
        end
end

// ----------------------------------------------------------------------------
// Stage 1
// ----------------------------------------------------------------------------

// RAM Read logic.
always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                mem_data_st1 <= mem [ i_rd_addr ];
        end
end

// Hazard Detection Logic
always_ff @ ( posedge i_clk ) if ( i_clken )
begin
        for(int i=0;i<WIDTH/8;i++)
        begin
                if ( i_wr_addr == i_rd_addr && i_wr_en[i] )
                begin
                        sel_st1[i] <= 2'd2;
                end
                else
                begin
                        sel_st1[i] <= 2'd1;
                end
        end
end

// Buffer update logic.
always_ff @ ( posedge i_clk ) if ( i_clken )
begin
        buffer_st1  <= i_wr_data;
        rd_addr_st1 <= i_rd_addr;
end

// ----------------------------------------------------------------------------
// Stage 2
// ----------------------------------------------------------------------------

// RAM Read logic.
always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                mem_data_st2 <= mem_data_st1;
        end
end

always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                for(int i=0;i<WIDTH/8;i++)
                begin
                        if ( i_wr_addr == rd_addr_st1 && i_wr_en[i] )
                        begin
                                sel_st2[i] <= {1'd1, 2'd0};
                        end
                        else
                        begin
                                sel_st2[i] <= {1'd0, sel_st1[i]};
                        end
                end
        end
end

always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                buffer_st2   <= i_wr_data;
                buffer_st2_x <= buffer_st1;
                rd_addr_st2  <= rd_addr_st1;
        end
end

always_comb
begin
        for(int i=0;i<WIDTH/8;i++)
        begin
                casez ( sel_st2[i] )
                3'b100 : o_rd_data_pre[i*8 +: 8] = buffer_st2   [i*8 +: 8];
                3'b010 : o_rd_data_pre[i*8 +: 8] = buffer_st2_x [i*8 +: 8];
                3'b001 : o_rd_data_pre[i*8 +: 8] = mem_data_st2 [i*8 +: 8];

                // Synth will OPTIMIZE. OK to do for FPGA synthesis.
                default: o_rd_data_pre[i*8 +: 8] = {8{1'dx}};
                endcase
        end
end

// ----------------------------------------------------------------------------
// Stage 3
// ----------------------------------------------------------------------------

always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                for(int i=0;i<WIDTH/8;i++)
                begin
                        if ( i_wr_addr == rd_addr_st2 && i_wr_en[i] )
                        begin
                                o_rd_data[i*8 +: 8] <= i_wr_data[i*8 +: 8];
                        end
                        else
                        begin
                                o_rd_data[i*8 +: 8] <= o_rd_data_pre[i*8 +: 8];
                        end
                end
        end
end

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
