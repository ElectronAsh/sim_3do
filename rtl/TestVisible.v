module TestVisible (
	// This only works for the upper 16-bit INTEGER part of the coords.
	input signed [15:0] xpoint0,
	input signed [15:0] xpoint1,
	input signed [15:0] xpoint2,
	input signed [15:0] xpoint3,
	input signed [15:0] clipx,
	
	input signed [15:0] ypoint0,
	input signed [15:0] ypoint1,
	input signed [15:0] ypoint2,
	input signed [15:0] ypoint3,
	input signed [15:0] clipy,
	
	input is_packed,
	
	output visible
);

wire x01_less_zero = (xpoint0<0) && (xpoint1<0);
wire x01_more_clip = (xpoint0>clipx) && (xpoint1>clipx);

wire x23_less_zero = (xpoint2<0) && (xpoint3<0);
wire x23_more_clip = (xpoint2>clipx) && (xpoint3>clipx);

wire y01_less_zero = (ypoint0<0) && (ypoint1<0);
wire y01_more_clip = (ypoint0>clipy) && (ypoint1>clipy);

wire y23_less_zero = (ypoint2<0) && (ypoint3<0);
wire y23_more_clip = (ypoint2>clipy) && (ypoint3>clipy);


wire x01_not_visible = (x01_less_zero && x01_more_clip);
wire x23_not_visible = (x23_less_zero && x23_more_clip);

wire y01_not_visible = (y01_less_zero && y01_more_clip);
wire y23_not_visible = (y23_less_zero && y23_more_clip);


assign visible = (is_packed) ? !(x01_not_visible && y01_not_visible) :
							   !(x01_not_visible && y01_not_visible && x23_not_visible && y23_not_visible);

endmodule
