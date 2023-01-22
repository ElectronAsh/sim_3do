//
// (C) 2016-2022 Revanth Kamaraj (krevanth)
//
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
// This is a pipelined memory macro for high performance. This memory
// has a 3 cycle read latency, but can operate at high speeds. The core
// SRAM inferred is a read-first memory. Match logic is provided to ensure
// the latest write data to a colliding address is picked up onto the
// output.
//

module zap_ram_simple #(
        parameter logic [31:0] WIDTH = 32'd32,
        parameter logic [31:0] DEPTH = 32'd32
)
(
        // Clock.
        input logic                          i_clk,

        // SRAM clock enable/read enable.
        input logic                          i_clken,

        // Write enable. Needs i_clken=1 to actually write.
        input logic                          i_wr_en,

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

// ----------------------------------------------------------------------------
// Stage 1
// ----------------------------------------------------------------------------

logic [WIDTH-1:0]         mem [DEPTH-1:0];
logic [WIDTH-1:0]         mem_data_st1, mem_data_st2;
logic [WIDTH-1:0]         buffer_st1, buffer_st2, buffer_st2_x;
logic [1:0]               sel_st1;
logic [2:0]               sel_st2;
logic [$clog2(DEPTH)-1:0] rd_addr_st1, rd_addr_st2;

// ----------------------------------------------------------------------------
// Write RAM
// ----------------------------------------------------------------------------

always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                if ( i_wr_en )
                begin
                        mem [ i_wr_addr ] <= i_wr_data;
                end
        end
end

// ----------------------------------------------------------------------------
// Stage 1
// ----------------------------------------------------------------------------

// Memory read. Direct output from block RAM.
always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                mem_data_st1 <= mem [ i_rd_addr ];
        end
end

//
// Hazard Detection Logic. If the read data from this stage should be modified
// mark it as such. This happens when write address collides with read
// address.
//
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                //
                // If 2, then collision occured, else it did not.
                // We encode as 1-hot.
                //
                if ( i_wr_addr == i_rd_addr && i_wr_en )
                begin
                        sel_st1 <= 2'b10;
                end
                else
                begin
                        sel_st1 <= 2'b01;
                end
        end
end

// Buffer update logic.
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                // Take a copy of the write data. We will need it if sel = 1.
                buffer_st1  <= i_wr_data;

                // Keep pumping address down.
                rd_addr_st1 <= i_rd_addr;
        end
end

// ----------------------------------------------------------------------------
// Stage 2
// ----------------------------------------------------------------------------

// Delay the memory read for another cycle to deal with slow SRAMs.
always_ff @ (posedge i_clk)
begin
        if ( i_clken )
        begin
                mem_data_st2 <= mem_data_st1;
        end
end

//
// Hazard detection logic. If the data in this stage needs to be modified
// with current write data mark it as such. Else, Pass the previous
// stage modifier signal too.
//
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                //
                // If a collision occured here, give priority to this
                // replacement for the address - even if the address
                // is associated with a data replacement in the previous
                // stages. Think about writes to the same address happening
                // over 3 cycles :
                // W1    W2     W3 (Write to same address)
                // <-- Read Lat.--> Read trig. at W1 reads W3
                //
                if ( i_wr_addr == rd_addr_st1 && i_wr_en )
                begin
                        sel_st2       <= 3'b100;
                end
                else
                begin
                        sel_st2       <= {1'd0, sel_st1};
                end
        end
end

// Keep passing the address down.
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                rd_addr_st2 <= rd_addr_st1;
        end
end

// Take a copy of the write data and pass the buffer down.
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                buffer_st2   <= i_wr_data;
                buffer_st2_x <= buffer_st1;
        end
end

//
// If the read data should be overriden in st2, then do that. Is fast to do
// as the encoding is 1-hot. Default case is assigned X for synthesis to
// OPTIMIZE. This is OK for FPGA synthesis.
//
always_comb
begin
        case (sel_st2)
        3'b100  : o_rd_data_pre = buffer_st2;
        3'b010  : o_rd_data_pre = buffer_st2_x;
        3'b001  : o_rd_data_pre = mem_data_st2;
        default : o_rd_data_pre = {WIDTH{1'dx}}; // Synthesis will OPTIMIZE.
                                                 // OK for FPGA synthesis.
        endcase
end

// ----------------------------------------------------------------------------
// Stage 3
// ----------------------------------------------------------------------------

//
// We want a purely registered output. Once again check for collisions. This
// will override any replacements done in the previous stages for this
// read packet.
//
always_ff @ ( posedge i_clk )
begin
        if ( i_clken )
        begin
                if ( i_wr_addr == rd_addr_st2 && i_wr_en )
                begin
                        o_rd_data <= i_wr_data;
                end
                else
                begin
                        o_rd_data <= o_rd_data_pre;
                end
        end
end

endmodule

// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
