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
// --                                                                        -- 
// --  This is the top module of the ZAP processor. It contains instances of --
// --  processor core and the memory management units. I and D WB busses     --
// --  are provided.                                                         --
// --                                                                        --
// ----------------------------------------------------------------------------

module zap_top #(

// -----------------------------------
// Only core. When 1, cache and MMU
// are not present.
// -----------------------------------

parameter    [0:0]      ONLY_CORE          = 1'd1,			// for 3DO.

// -----------------------------------
// Set reset vector here
// -----------------------------------

parameter   [31:0]       RESET_VECTOR      = 32'h03000000,	// for 3DO.

// -----------------------------------
// Set initial value of CPSR here.
// -----------------------------------

parameter [31:0]        CPSR_INIT          = {24'd0, 1'd0,1'd0,1'd0,5'b10011},	// Bit[7]=IRQ mask. Bit[6]=FIQ mask. bit[5]=Thumb. bits[4:0]=Mode.

// -----------------------------------
// Enable BE-32
// -----------------------------------

parameter   [0:0]       BE_32_ENABLE       = 1'd1,	// for 3DO.

// -----------------------------------
// BP entries, FIFO depths
// -----------------------------------

parameter  [31:0]       BP_ENTRIES         = 32'd1024, // Predictor depth.
parameter  [31:0]       FIFO_DEPTH         = 32'd16,   // FIFO depth.
parameter  [31:0]       STORE_BUFFER_DEPTH = 32'd16,   // Depth of the store buffer.
parameter  [31:0]       RAS_DEPTH          = 32'd4,    // Depth of RAS.

// ----------------------------------
// Data MMU/Cache configuration.
// ----------------------------------
parameter [31:0] DATA_SECTION_TLB_ENTRIES =  32'd128,  // Section TLB entries.
parameter [31:0] DATA_LPAGE_TLB_ENTRIES   =  32'd128,  // Large page TLB entries.
parameter [31:0] DATA_SPAGE_TLB_ENTRIES   =  32'd128,  // Small page TLB entries.
parameter [31:0] DATA_FPAGE_TLB_ENTRIES   =  32'd128,  // Tiny page TLB entries.
parameter [31:0] DATA_CACHE_SIZE          =  32'd16384,// Cache size in bytes.
parameter [31:0] DATA_CACHE_LINE          =  32'd64,   // Cache line size in bytes.

// ----------------------------------
// Code MMU/Cache configuration.
// ----------------------------------
parameter [31:0] CODE_SECTION_TLB_ENTRIES =  32'd128,  // Section TLB entries.
parameter [31:0] CODE_LPAGE_TLB_ENTRIES   =  32'd128,  // Large page TLB entries.
parameter [31:0] CODE_SPAGE_TLB_ENTRIES   =  32'd128,  // Small page TLB entries.
parameter [31:0] CODE_FPAGE_TLB_ENTRIES   =  32'd128,  // Fine page TLB entries.
parameter [31:0] CODE_CACHE_SIZE          =  32'd16384,// Cache size in bytes.
parameter [31:0] CODE_CACHE_LINE          =  32'd64    // Ccahe line size in bytes.

)(
        // --------------------------------------
        // Trace. Only for DV. Leave open.
        // --------------------------------------

        output  logic  [2047:0]    o_trace,
        output  logic              o_trace_trigger,

        // --------------------------------------
        // Clock and reset
        // --------------------------------------

        input   logic            i_clk,
        input   logic            i_reset,

        // ---------------------------------------
        // Interrupts. 
        // Both of them are active high and level 
        // trigerred.
        // ---------------------------------------

        input   logic            i_irq,
        input   logic            i_fiq,

        // ---------------------
        // Wishbone interface.
        // ---------------------

        output  logic            o_wb_cyc,
        output  logic            o_wb_stb,
        output  logic [31:0]     o_wb_adr,
        output  logic            o_wb_we,
        output logic  [31:0]     o_wb_dat,
        output  logic [3:0]      o_wb_sel,
        output logic [2:0]       o_wb_cti,
        output logic [1:0]       o_wb_bte,
        input   logic            i_wb_ack,
        input   logic [31:0]     i_wb_dat
);

always_comb o_wb_bte = 2'b00; // Linear Burst.

`include "zap_defines.svh"
`include "zap_localparams.svh"
`include "zap_functions.svh"

logic            wb_cyc, wb_stb, wb_we;
logic [3:0]      wb_sel;
logic [31:0]     wb_dat, wb_idat;
logic [31:0]     wb_adr;
logic [2:0]      wb_cti;
logic            wb_ack;
logic            cpu_mmu_en;
logic [`ZAP_CPSR_MODE] cpu_cpsr;
logic            cpu_mem_translate;
logic [31:0]     cpu_daddr, cpu_daddr_nxt, cpu_daddr_check;
logic [31:0]     cpu_iaddr, cpu_iaddr_nxt, cpu_iaddr_check;
logic [7:0]      dc_fsr;
logic [31:0]     dc_far;
logic            cpu_dc_en, cpu_ic_en;
logic [1:0]      cpu_sr;
logic [7:0]      cpu_pid;
logic [31:0]     cpu_baddr, cpu_dac_reg;
logic            cpu_dc_inv, cpu_ic_inv;
logic            cpu_dc_clean, cpu_ic_clean;
logic            dc_inv_done, ic_inv_done, dc_clean_done, ic_clean_done;
logic            cpu_dtlb_inv, cpu_itlb_inv;
logic            data_ack, data_err, instr_ack, instr_err;
logic [31:0]     ic_data, dc_data, cpu_dc_dat;
logic            cpu_instr_stb;
logic            cpu_dc_we, cpu_dc_stb;
logic [3:0]      cpu_dc_sel;
logic            c_wb_stb;
logic            c_wb_cyc;
logic            c_wb_wen;
logic [3:0]      c_wb_sel;
logic [31:0]     c_wb_dat;
logic [31:0]     c_wb_adr;
logic [2:0]      c_wb_cti;
logic            c_wb_ack;
logic            d_wb_stb;
logic            d_wb_cyc;
logic            d_wb_wen;
logic [3:0]      d_wb_sel;
logic [31:0]     d_wb_dat;
logic [31:0]     d_wb_adr;
logic [2:0]      d_wb_cti;
logic            d_wb_ack;
logic [63:0]     dc_rreg_idx, dc_wreg_idx;
logic [63:0]     dc_lock;
logic [31:0]     dc_reg_data;
logic            icache_err2, dcache_err2;
logic            cpu_dwe_check, cpu_dre_check;
logic            s_reset, s_fiq, s_irq;
logic            code_stall;

assign          s_reset = i_reset;

zap_dual_rank_synchronizer #(.WIDTH(2)) u_sync (
        .i_clk(i_clk),
        .i_reset(i_reset),
        .in( {i_fiq, i_irq}),
        .out({s_fiq, s_irq})
);

zap_core #(
        .BP_ENTRIES(BP_ENTRIES),
        .FIFO_DEPTH(FIFO_DEPTH),
        .RAS_DEPTH(RAS_DEPTH),
        .BE_32_ENABLE(BE_32_ENABLE),
        .RESET_VECTOR(RESET_VECTOR),
        .CPSR_INIT(CPSR_INIT)
) u_zap_core
(
// Trace
.o_trace                (o_trace),
.o_trace_trigger        (o_trace_trigger),

// Clock and reset.
.i_clk                  (i_clk),
.i_reset                (s_reset),

// Code related.
.o_instr_wb_adr         (cpu_iaddr),
.o_instr_wb_stb         (cpu_instr_stb),
/* verilator lint_off PINCONNECTEMPTY */
.o_instr_wb_cyc         (),
.o_instr_wb_we          (),
.o_instr_wb_sel         (),
/* verilator lint_on PINCONNECTEMPTY */
.o_code_stall           (code_stall),
.i_instr_wb_dat         (!ONLY_CORE ? ic_data   : i_wb_dat),
.i_instr_wb_ack         (instr_ack),
.i_instr_wb_err         (!ONLY_CORE ? instr_err : 1'd0),

// Data related.
.o_data_wb_we           (cpu_dc_we),
.o_data_wb_adr          (cpu_daddr),
.o_data_wb_sel          (cpu_dc_sel),
.o_data_wb_dat          (cpu_dc_dat),
/* verilator lint_off PINCONNECTEMPTY */
.o_data_wb_cyc          (),
/* verilator lint_on PINCONNECTEMPTY */
.o_data_wb_stb          (cpu_dc_stb),
.i_data_wb_dat          (!ONLY_CORE ? dc_data : 
                         BE_32_ENABLE ? be_32(i_wb_dat, o_wb_sel) : i_wb_dat), 
                        // Swap data into CPU based on current o_wb_sel.
.i_data_wb_ack          (data_ack),
.i_data_wb_err          (data_err),

// Interrupts.
.i_fiq                  (s_fiq),
.i_irq                  (s_irq),

// MMU/cache is present.
.i_fsr                  (!ONLY_CORE ? {24'd0,dc_fsr} : '0),
.i_far                  (!ONLY_CORE ? dc_far : '0),

.o_mem_translate        (cpu_mem_translate),
.o_dac                  (cpu_dac_reg),
.o_baddr                (cpu_baddr),
.o_mmu_en               (cpu_mmu_en),
.o_sr                   (cpu_sr),
.o_pid                  (cpu_pid),
.o_dcache_inv           (cpu_dc_inv),
.o_icache_inv           (cpu_ic_inv),
.o_dcache_clean         (cpu_dc_clean),
.o_icache_clean         (cpu_ic_clean),
.o_dtlb_inv             (cpu_dtlb_inv),
.o_itlb_inv             (cpu_itlb_inv),
.o_dcache_en            (cpu_dc_en),
.o_icache_en            (cpu_ic_en),
.o_data_wb_adr_nxt      (cpu_daddr_nxt), // Data addr nxt. Used to drive address of data tag RAM.
.o_data_wb_adr_check    (cpu_daddr_check),
.o_data_wb_we_check     (cpu_dwe_check),
.o_data_wb_re_check     (cpu_dre_check),
.o_instr_wb_adr_nxt     (cpu_iaddr_nxt), // PC addr nxt. Drives read address of code tag RAM.
.o_instr_wb_adr_check   (cpu_iaddr_check),
.o_cpsr                 (cpu_cpsr[`ZAP_CPSR_MODE]),
.o_dc_reg_idx           (dc_rreg_idx),

.i_dc_reg_idx           (!ONLY_CORE ? dc_wreg_idx : '0),
.i_dc_lock              (!ONLY_CORE ? dc_lock : '0),
.i_dc_reg_dat           (!ONLY_CORE ? dc_reg_data : '0), 
.i_dcache_inv_done      (!ONLY_CORE ? dc_inv_done : '0),
.i_icache_inv_done      (!ONLY_CORE ? ic_inv_done : '0),
.i_dcache_clean_done    (!ONLY_CORE ? dc_clean_done : '0),
.i_icache_clean_done    (!ONLY_CORE ? ic_clean_done : '0),
.i_icache_err2          (!ONLY_CORE ? icache_err2 : '0),
.i_dcache_err2          (!ONLY_CORE ? dcache_err2 : '0)
);

generate
        if ( !ONLY_CORE )
        begin
                // Normal case.
        end
        else
        begin
                assign dc_wreg_idx     = '0;
                assign dc_lock         = '0;
                assign dc_reg_data     = '0;
                assign dc_inv_done     = '0;
                assign ic_inv_done     = '0;
                assign dc_clean_done   = '0;
                assign ic_clean_done   = '0;
                assign icache_err2     = '0;
                assign dcache_err2     = '0;
                assign dc_fsr          = '0;
                assign dc_far          = '0;
                assign instr_err       = '0;
                assign dc_data         = '0;
                assign ic_data         = '0;
                assign data_err        = '0;
                assign c_wb_ack        = '0;
                assign d_wb_ack        = '0;
                assign wb_cyc          = '0;
                assign wb_stb          = '0;
                assign wb_we           = '0;
                assign wb_sel          = '0;
                assign wb_idat         = '0;
                assign wb_adr          = '0;
                assign wb_cti          = '0;
                assign wb_ack          = '0;
                assign c_wb_stb        = '0;
                assign c_wb_cyc        = '0;
                assign c_wb_wen        = '0;
                assign c_wb_sel        = '0;
                assign c_wb_dat        = '0;
                assign c_wb_adr        = '0;
                assign c_wb_cti        = '0; 
                assign d_wb_stb        = '0;
                assign d_wb_cyc        = '0;
                assign d_wb_wen        = '0;
                assign d_wb_sel        = '0;
                assign d_wb_dat        = '0;
                assign d_wb_adr        = '0;
                assign d_wb_cti        = '0; 
                assign wb_dat          = '0;

                wire unused =
                   (    |dc_wreg_idx       )
                 | (    |dc_lock           ) 
                 | (    |dc_reg_data       ) 
                 | (    |dc_inv_done       ) 
                 | (    |ic_inv_done       ) 
                 | (    |dc_clean_done     ) 
                 | (    |ic_clean_done     ) 
                 | (    |icache_err2       ) 
                 | (    |dcache_err2       ) 
                 | (    |dc_fsr            ) 
                 | (    |dc_far            ) 
                 | (    |instr_err         ) 
                 | (    |dc_data           ) 
                 | (    |ic_data           ) 
                 | (    |data_err          ) 
                 | (    |c_wb_ack          ) 
                 | (    |d_wb_ack          ) 
                 | (    |wb_cyc            ) 
                 | (    |wb_stb            ) 
                 | (    |wb_we             ) 
                 | (    |wb_sel            ) 
                 | (    |wb_idat           ) 
                 | (    |wb_adr            ) 
                 | (    |wb_cti            ) 
                 | (    |wb_ack            ) 
                 | (    |c_wb_stb          ) 
                 | (    |c_wb_cyc          ) 
                 | (    |c_wb_wen          ) 
                 | (    |c_wb_sel          ) 
                 | (    |c_wb_dat          ) 
                 | (    |c_wb_adr          ) 
                 | (    |c_wb_cti          )  
                 | (    |d_wb_stb          ) 
                 | (    |d_wb_cyc          ) 
                 | (    |d_wb_wen          ) 
                 | (    |d_wb_sel          ) 
                 | (    |d_wb_dat          ) 
                 | (    |d_wb_adr          ) 
                 | (    |d_wb_cti          )
                 | (    |wb_dat            )
                 | (    |cpu_mmu_en        )            
                 | (    |cpu_cpsr          )
                 | (    |cpu_mem_translate )
                 | (    |cpu_daddr_nxt     )
                 | (    |cpu_daddr_check   )     
                 | (    |cpu_iaddr_nxt     )
                 | (    |cpu_iaddr_check   )
                 | (    |cpu_dc_en         )
                 | (    |cpu_ic_en         )
                 | (    |cpu_sr            )
                 | (    |cpu_pid           )
                 | (    |cpu_baddr         )
                 | (    |cpu_dac_reg       )
                 | (    |cpu_dc_inv        )
                 | (    |cpu_ic_inv        )
                 | (    |cpu_dc_clean      )
                 | (    |cpu_ic_clean      )
                 | (    |cpu_dtlb_inv      )
                 | (    |cpu_itlb_inv      )
                 | (    |dc_rreg_idx       )
                 | (    |cpu_dwe_check     )
                 | (    |cpu_dre_check     )
                 | (    |code_stall        )
                 ;

        end
endgenerate

generate 
if ( !ONLY_CORE )
        zap_wb_merger #(.ONLY_CORE(1'd0)) u_zap_wb_merger (
        
        .i_clk(i_clk),
        .i_reset(s_reset),
        
        .i_c_wb_stb(c_wb_stb ),
        .i_c_wb_cyc(c_wb_cyc ),
        .i_c_wb_wen(c_wb_wen ), 
        .i_c_wb_sel(c_wb_sel ),
        .i_c_wb_dat(c_wb_dat ),
        .i_c_wb_adr(c_wb_adr ),
        .i_c_wb_cti(c_wb_cti ),
        .o_c_wb_ack(c_wb_ack ),
        
        .i_d_wb_stb(d_wb_stb ),
        .i_d_wb_cyc(d_wb_cyc ),
        .i_d_wb_wen(d_wb_wen ),
        .i_d_wb_sel(d_wb_sel ),
        .i_d_wb_dat(d_wb_dat ),
        .i_d_wb_adr(d_wb_adr ),
        .i_d_wb_cti(d_wb_cti ),
        .o_d_wb_ack(d_wb_ack ),
        
        .o_wb_cyc  (wb_cyc   ),
        .o_wb_stb  (wb_stb   ),
        .o_wb_wen  (wb_we    ),
        .o_wb_sel  (wb_sel   ),
        .o_wb_dat  (wb_idat  ),
        .o_wb_adr  (wb_adr   ),
        .o_wb_cti  (wb_cti   ),
        .i_wb_ack  (wb_ack   )
        
        );
else // if ( ONLY_CORE )
        zap_wb_merger #(.ONLY_CORE(1'd1)) u_zap_wb_merger (
        
        .i_clk(i_clk),
        .i_reset(s_reset),
        
        .i_c_wb_stb(cpu_instr_stb),
        .i_c_wb_cyc(cpu_instr_stb),
        .i_c_wb_wen(1'h0),
        .i_c_wb_sel(4'hF),
        .i_c_wb_dat(32'd0),
        .i_c_wb_adr(cpu_iaddr),
        .i_c_wb_cti(3'b111),
        .o_c_wb_ack(instr_ack),
        
        .i_d_wb_stb(cpu_dc_stb),
        .i_d_wb_cyc(cpu_dc_stb),
        .i_d_wb_wen(cpu_dc_we),
        .i_d_wb_sel(BE_32_ENABLE ? be_sel_32(cpu_dc_sel) : cpu_dc_sel), // Swap sel from CPU.
        .i_d_wb_dat(cpu_dc_dat),
        .i_d_wb_adr(cpu_daddr),
        .i_d_wb_cti(3'b111),
        .o_d_wb_ack(data_ack),
        
        .o_wb_cyc  (o_wb_cyc ),
        .o_wb_stb  (o_wb_stb ),
        .o_wb_wen  (o_wb_we  ),
        .o_wb_sel  (o_wb_sel ),
        .o_wb_dat  (o_wb_dat ),
        .o_wb_adr  (o_wb_adr ),
        .o_wb_cti  (o_wb_cti ),
        .i_wb_ack  (i_wb_ack )
        
        );

endgenerate

/////////////////////////////////////////////////////////////////////////////////////////////////////////////
// Put cache and MMU only if ONLY_CORE == 0
/////////////////////////////////////////////////////////////////////////////////////////////////////////////

generate 
if ( !ONLY_CORE ) 
begin: genblk1

zap_dcache #(
        .CACHE_SIZE(DATA_CACHE_SIZE), 
        .SPAGE_TLB_ENTRIES(DATA_SPAGE_TLB_ENTRIES), 
        .LPAGE_TLB_ENTRIES(DATA_LPAGE_TLB_ENTRIES), 
        .SECTION_TLB_ENTRIES(DATA_SECTION_TLB_ENTRIES),
        .FPAGE_TLB_ENTRIES(DATA_FPAGE_TLB_ENTRIES),
        .CACHE_LINE(CODE_CACHE_LINE),
        .BE_32_ENABLE(BE_32_ENABLE)
)
u_data_cache (
.i_clk                  (i_clk),
.i_stall                (1'd0), // For timing.
.i_reset                (s_reset),
.i_address              (cpu_daddr     + ({24'd0, cpu_pid[7:0]} << 32'd25)),
.i_address_nxt          (cpu_daddr_nxt + ({24'd0, cpu_pid[7:0]} << 32'd25)),
.i_address_check        (cpu_daddr_check + ({24'd0, cpu_pid[7:0]} << 32'd25)),
.i_wr_check             (cpu_dwe_check),
.i_rd_check             (cpu_dre_check),
.i_rd                   (!cpu_dc_we && cpu_dc_stb),
.i_wr                   ( cpu_dc_we && cpu_dc_stb),
.i_ben                  (cpu_dc_sel),
.i_dat                  (cpu_dc_dat),
.i_reg_idx              (dc_rreg_idx),

.o_dat                  (dc_data),
.o_ack                  (data_ack),
.o_err                  (data_err),
.o_lock                 (dc_lock),
.o_reg_dat              (dc_reg_data),
.o_reg_idx              (dc_wreg_idx),
.o_fsr                  (dc_fsr),
.o_far                  (dc_far),
.o_cache_inv_done       (dc_inv_done),
.o_cache_clean_done     (dc_clean_done),

.i_mmu_en               (cpu_mmu_en),
.i_cache_en             (cpu_dc_en),
.i_cache_inv_req        (cpu_dc_inv),
.i_cache_clean_req      (cpu_dc_clean),
.i_cpsr                 (cpu_mem_translate ? USR : cpu_cpsr[`ZAP_CPSR_MODE]),
.i_sr                   (cpu_sr),
.i_baddr                (cpu_baddr),
.i_dac_reg              (cpu_dac_reg),
.i_tlb_inv              (cpu_dtlb_inv),

.o_err2                 (dcache_err2),

/* verilator lint_off PINCONNECTEMPTY */
.o_wb_stb               (),
.o_wb_cyc               (),
.o_wb_wen               (),
.o_wb_sel               (),
.o_wb_dat               (),
.o_wb_adr               (),
.o_wb_cti               (),
/* verilator lint_on PINCONNECTEMPTY */

.i_wb_dat               (wb_dat),
.i_wb_ack               (d_wb_ack),

.o_wb_stb_nxt           (d_wb_stb),
.o_wb_cyc_nxt           (d_wb_cyc),
.o_wb_wen_nxt           (d_wb_wen),
.o_wb_sel_nxt           (d_wb_sel),
.o_wb_dat_nxt           (d_wb_dat),
.o_wb_adr_nxt           (d_wb_adr),
.o_wb_cti_nxt           (d_wb_cti)
);

zap_cache #(
.CACHE_SIZE(CODE_CACHE_SIZE), 
.SPAGE_TLB_ENTRIES(CODE_SPAGE_TLB_ENTRIES), 
.LPAGE_TLB_ENTRIES(CODE_LPAGE_TLB_ENTRIES), 
.SECTION_TLB_ENTRIES(CODE_SECTION_TLB_ENTRIES),
.FPAGE_TLB_ENTRIES(CODE_FPAGE_TLB_ENTRIES),
.CACHE_LINE(DATA_CACHE_LINE)
) 
u_code_cache (
.i_clk              (i_clk),
.i_stall            (code_stall),
.i_reset            (s_reset),
.i_address          ((cpu_iaddr     & 32'hFFFF_FFFC) + ({24'd0, cpu_pid[7:0]} << 32'd25)), // Cut off lower 2 bits.
.i_address_nxt      ((cpu_iaddr_nxt & 32'hFFFF_FFFC) + ({24'd0, cpu_pid[7:0]} << 32'd25)), // Cut off lower 2 bits.

.i_address_check    ((cpu_iaddr_check & 32'hFFFF_FFFC) + ({24'd0, cpu_pid[7:0]} << 32'd25)),
.i_wr_check         (1'd0),
.i_rd_check         (1'd1),

.i_rd              (cpu_instr_stb),
.i_wr              (1'd0),
.i_ben             (4'b1111),
.i_dat             (32'd0),
.o_dat             (ic_data),
.o_ack             (instr_ack),
.o_err             (instr_err),

/* verilator lint_off PINCONNECTEMPTY */
.o_fsr             (), 
.o_far             (), 
/* verilator lint_on PINCONNECTEMPTY */

.i_mmu_en          (cpu_mmu_en),
.i_cache_en        (cpu_ic_en),
.i_cache_inv_req   (cpu_ic_inv),
.i_cache_clean_req (cpu_ic_clean),
.o_cache_inv_done  (ic_inv_done),
.o_cache_clean_done(ic_clean_done),
.i_cpsr         (cpu_mem_translate ? USR : cpu_cpsr[`ZAP_CPSR_MODE]),
.i_sr           (cpu_sr),
.i_baddr        (cpu_baddr),
.i_dac_reg      (cpu_dac_reg),
.i_tlb_inv      (cpu_itlb_inv),

.o_err2         (icache_err2),

/* verilator lint_off PINCONNECTEMPTY */
.o_wb_stb       (),
.o_wb_cyc       (),
.o_wb_wen       (),
.o_wb_sel       (),
.o_wb_dat       (),
.o_wb_adr       (),
.o_wb_cti       (),
/* verilator lint_on PINCONNECTEMPTY */

.i_wb_dat       (wb_dat),
.i_wb_ack       (c_wb_ack),

.o_wb_stb_nxt   (c_wb_stb),
.o_wb_cyc_nxt   (c_wb_cyc),
.o_wb_wen_nxt   (c_wb_wen),
.o_wb_sel_nxt   (c_wb_sel),
.o_wb_dat_nxt   (c_wb_dat),
.o_wb_adr_nxt   (c_wb_adr),
.o_wb_cti_nxt   (c_wb_cti)
);

zap_wb_adapter 
#(.DEPTH(STORE_BUFFER_DEPTH), .BURST_LEN(CODE_CACHE_LINE < DATA_CACHE_LINE ? 
        CODE_CACHE_LINE/4 : 
        DATA_CACHE_LINE/4))
u_zap_wb_adapter (
.i_clk(i_clk),
.i_reset(s_reset),

.I_WB_CYC(wb_cyc),
.I_WB_STB(wb_stb),
.I_WB_WE(wb_we),
.I_WB_DAT(wb_idat),
.I_WB_SEL(wb_sel),
.I_WB_CTI(wb_cti),
.O_WB_ACK(wb_ack),
.O_WB_DAT(wb_dat),
.I_WB_ADR(wb_adr),

.o_wb_cyc(o_wb_cyc),
.o_wb_stb(o_wb_stb),
.o_wb_we(o_wb_we),
.o_wb_sel(o_wb_sel),
.o_wb_dat(o_wb_dat),
.o_wb_adr(o_wb_adr),
.o_wb_cti(o_wb_cti),
.i_wb_dat(i_wb_dat),
.i_wb_ack(i_wb_ack)

);

end:genblk1
endgenerate

endmodule // zap_top.v


