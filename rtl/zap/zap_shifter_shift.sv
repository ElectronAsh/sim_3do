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



module zap_shifter_shift
#(
        parameter SHIFT_OPS = 5
)
(
        // Source value.
        input  logic [31:0]                      i_source,

        // Shift amount.
        input  logic [7:0]                       i_amount, 

        // Carry in.
        input  logic                             i_carry,

        // Shift type.
        input  logic [$clog2(SHIFT_OPS)-1:0]     i_shift_type,

        // Output result and output carry.
        output logic [31:0]                       o_result,
        output logic                              o_carry,
        output logic                              o_sat
);

`include "zap_defines.svh"
`include "zap_localparams.svh"

///////////////////////////////////////////////////////////////////////////////

always_comb
begin:blk1
        logic signed [32:0] res, res1;

        res  = 0;
        res1 = 0;

        // Prevent latch inference.
        o_result        = i_source;
        o_carry         = 0;
        o_sat           = 0;

        case ( i_shift_type )

                // Logical shift left, logical shift right and 
                // arithmetic shift right.
                {1'd0, LSL}:    {o_carry, o_result} = {i_carry, i_source} << i_amount;
                {1'd0, LSR}:    {o_result, o_carry} = {i_source, i_carry} >> i_amount;
                {1'd0, ASR}:    
                begin
                        res = {i_source, i_carry};
                        res1 = $signed(res) >>> i_amount;
                        {o_result, o_carry} = res1;
                end

                {1'd0, ROR}: // Rotate right.
                begin
                        o_result = ( i_source >> i_amount[4:0] )  | 
                                   ( i_source << (32 - i_amount[4:0] ) );                               
                        o_carry  = ( i_amount[7:0] == 0) ? 
                                     i_carry  : ( (i_amount[4:0] == 0) ? 
                                     i_source[31] : o_result[31] ); 
                end

                RORI, ROR_1:
                begin
                        // ROR #n (ROR_1)
                        o_result = ( i_source >> i_amount[4:0] )  | 
                                   (i_source << (32 - i_amount[4:0] ) );
                        o_carry  = (|i_amount) ? o_result[31] : i_carry; 
                end

                // ROR #0 becomes this.
                RRC:    {o_result, o_carry}        = {i_carry, i_source}; 

                // LSL_SAT. Always #1 in length.
                LSL_SAT: 
                begin

                        o_result = i_source << 1;

                        if ( o_result[31] != i_source[31] )
                        begin
                                o_sat = 1'd1;
                        end

                        if ( o_sat == 1'd1 )
                        begin
                                if ( i_source[31] == 1'd0 )
                                        o_result = {1'd0, {31{1'd1}}}; // Max positive.
                                else
                                        o_result = {1'd1, {31{1'd0}}}; // Max negative.
                        end
                end

                default: // For lint.
                begin
                end
        endcase
end

///////////////////////////////////////////////////////////////////////////////

endmodule // zap_shift_shifter.v



// ----------------------------------------------------------------------------
// EOF
// ----------------------------------------------------------------------------
