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

`ifndef __ZAP_DECOMPILE_SVH__
`define __ZAP_DECOMPILE_SVH__
`define ZAP_DECOMPILE_CCC            cond_code(i_instruction[31:28])
`define ZAP_DECOMPILE_CRB            arch_reg_num({i_instruction[ZAP_DP_RB_EXTEND], i_instruction[`ZAP_DP_RB]})
`define ZAP_DECOMPILE_CRD            arch_reg_num({i_instruction[ZAP_DP_RD_EXTEND], i_instruction[`ZAP_DP_RD]})
`define ZAP_DECOMPILE_CRD1           arch_reg_num({i_instruction[ZAP_SRCDEST_EXTEND], i_instruction[`ZAP_SRCDEST]})
`define ZAP_DECOMPILE_CRN            arch_reg_num({i_instruction[ZAP_DP_RA_EXTEND], i_instruction[`ZAP_DP_RA]})
`define ZAP_DECOMPILE_CRN1           arch_reg_num({i_instruction[ZAP_BASE_EXTEND], i_instruction[`ZAP_BASE]})
`define ZAP_DECOMPILE_CRM            arch_reg_num({i_instruction[ZAP_DP_RB_EXTEND], i_instruction[`ZAP_DP_RB]});
`define ZAP_DECOMPILE_COPCODE        get_opcode({i_instruction[ZAP_OPCODE_EXTEND], i_instruction[24:21]})
`define ZAP_DECOMPILE_CSHTYPE        get_shtype(i_instruction[6:5])
`define ZAP_DECOMPILE_CRS            arch_reg_num(i_instruction[11:8]);
`define ZAP_DECOMPILE_XUMULL         3'b100
`define ZAP_DECOMPILE_XUMLAL         3'b101
`define ZAP_DECOMPILE_XSMULL         3'b110
`define ZAP_DECOMPILE_XSMLAL         3'b111
`endif

