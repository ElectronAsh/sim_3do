module matrix_engine (
	input clock,
	
	input [31:0] MI00_in,
	input [31:0] MI01_in,
	input [31:0] MI02_in,
	input [31:0] MI03_in,
	input [31:0] MI10_in,
	input [31:0] MI11_in,
	input [31:0] MI12_in,
	input [31:0] MI13_in,
	input [31:0] MI20_in,
	input [31:0] MI21_in,
	input [31:0] MI22_in,
	input [31:0] MI23_in,
	input [31:0] MI30_in,
	input [31:0] MI31_in,
	input [31:0] MI32_in,
	input [31:0] MI33_in,

	input [31:0] MV0_in,
	input [31:0] MV1_in,
	input [31:0] MV2_in,
	input [31:0] MV3_in
);

reg signed [31:0] mregs [0:4095];


wire signed [63:0] MI00 = { {32{MI00_in[31]}}, MI00_in };
wire signed [63:0] MI01 = { {32{MI01_in[31]}}, MI01_in };
wire signed [63:0] MI02 = { {32{MI02_in[31]}}, MI02_in };
wire signed [63:0] MI03 = { {32{MI03_in[31]}}, MI03_in };
wire signed [63:0] MI10 = { {32{MI10_in[31]}}, MI10_in };
wire signed [63:0] MI11 = { {32{MI11_in[31]}}, MI11_in };
wire signed [63:0] MI12 = { {32{MI12_in[31]}}, MI12_in };
wire signed [63:0] MI13 = { {32{MI13_in[31]}}, MI13_in };
wire signed [63:0] MI20 = { {32{MI20_in[31]}}, MI20_in };
wire signed [63:0] MI21 = { {32{MI21_in[31]}}, MI21_in };
wire signed [63:0] MI22 = { {32{MI22_in[31]}}, MI22_in };
wire signed [63:0] MI23 = { {32{MI23_in[31]}}, MI23_in };
wire signed [63:0] MI30 = { {32{MI30_in[31]}}, MI30_in };
wire signed [63:0] MI31 = { {32{MI31_in[31]}}, MI31_in };
wire signed [63:0] MI32 = { {32{MI32_in[31]}}, MI32_in };
wire signed [63:0] MI33 = { {32{MI33_in[31]}}, MI33_in };

// vector
wire signed [63:0] MV0 = { {32{MV0_in[31]}}, MV0_in }; 
wire signed [63:0] MV1 = { {32{MV1_in[31]}}, MV1_in };
wire signed [63:0] MV2 = { {32{MV2_in[31]}}, MV2_in };
wire signed [63:0] MV3 = { {32{MV3_in[31]}}, MV3_in };


// input
/*
wire signed [63:0] MI00 = { {32{mregs[12'h600][31]}}, mregs[12'h600] };
wire signed [63:0] MI01 = { {32{mregs[12'h604][31]}}, mregs[12'h604] };
wire signed [63:0] MI02 = { {32{mregs[12'h608][31]}}, mregs[12'h608] };
wire signed [63:0] MI03 = { {32{mregs[12'h60C][31]}}, mregs[12'h60C] };
wire signed [63:0] MI10 = { {32{mregs[12'h610][31]}}, mregs[12'h610] };
wire signed [63:0] MI11 = { {32{mregs[12'h614][31]}}, mregs[12'h614] };
wire signed [63:0] MI12 = { {32{mregs[12'h618][31]}}, mregs[12'h618] };
wire signed [63:0] MI13 = { {32{mregs[12'h61C][31]}}, mregs[12'h61C] };
wire signed [63:0] MI20 = { {32{mregs[12'h620][31]}}, mregs[12'h620] };
wire signed [63:0] MI21 = { {32{mregs[12'h624][31]}}, mregs[12'h624] };
wire signed [63:0] MI22 = { {32{mregs[12'h628][31]}}, mregs[12'h628] };
wire signed [63:0] MI23 = { {32{mregs[12'h62C][31]}}, mregs[12'h62C] };
wire signed [63:0] MI30 = { {32{mregs[12'h630][31]}}, mregs[12'h630] };
wire signed [63:0] MI31 = { {32{mregs[12'h634][31]}}, mregs[12'h634] };
wire signed [63:0] MI32 = { {32{mregs[12'h638][31]}}, mregs[12'h638] };
wire signed [63:0] MI33 = { {32{mregs[12'h63C][31]}}, mregs[12'h63C] };

// vector
wire signed [63:0] MV0 = { {32{mregs[12'h640][31]}}, mregs[12'h640] }; 
wire signed [63:0] MV1 = { {32{mregs[12'h644][31]}}, mregs[12'h644] };
wire signed [63:0] MV2 = { {32{mregs[12'h648][31]}}, mregs[12'h648] };
wire signed [63:0] MV3 = { {32{mregs[12'h64C][31]}}, mregs[12'h64C] };
*/

// output
reg signed [31:0] MO0 /*= mregs[12'h660]*/;
reg signed [31:0] MO1 /*= mregs[12'h664]*/;
reg signed [31:0] MO2 /*= mregs[12'h668]*/;
reg signed [31:0] MO3 /*= mregs[12'h66C]*/;

// temp
reg signed [63:0] tmpMO0;
reg signed [63:0] tmpMO1;
reg signed [63:0] tmpMO2;
reg signed [63:0] tmpMO3;

wire signed [63:0] Nfrac_top = { {32{mregs[12'h680][31]}}, mregs[12'h680] };

wire signed [63:0] Nfrac16 = {Nfrac_top, mregs[12'h684]};

/*
madam_matrix_copy(void)
{
  MO0 = tmpMO0;
  MO1 = tmpMO1;
  MO2 = tmpMO2;
  MO3 = tmpMO3;
}


void madam_matrix_mul3x3(void)
{
  madam_matrix_copy();

  tmpMO0 = (((MI00 * MV0) +
             (MI01 * MV1) +
             (MI02 * MV2)) >> 16);
  tmpMO1 = (((MI10 * MV0) +
             (MI11 * MV1) +
             (MI12 * MV2)) >> 16);
  tmpMO2 = (((MI20 * MV0) +
             (MI21 * MV1) +
             (MI22 * MV2)) >> 16);
}
*/

/*
  multiply a 3x3 matrix of 16.16 values by a vector of 16.16 values
*/
always @(posedge clock) begin
	tmpMO0 <= (((MI00 * MV0) +
				(MI01 * MV1) +
				(MI02 * MV2)) >> 16);
				
	tmpMO1 <= (((MI10 * MV0) +
				(MI11 * MV1) +
				(MI12 * MV2)) >> 16);
				
	tmpMO2 <= (((MI20 * MV0) +
				(MI21 * MV1) +
				(MI22 * MV2)) >> 16);
end

endmodule
