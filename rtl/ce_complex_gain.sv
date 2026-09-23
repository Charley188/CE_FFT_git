`timescale 1ns/1ps
module ce_complex_gain #(
 parameter integer DATA_WIDTH=32, parameter bit COEFF_WRITABLE=0,
 parameter H_RE="h_re.mem", H_IM="h_im.mem"
)(
 input wire clk, rst_n,
 input wire coeff_we, input wire [10:0] coeff_addr,
 input wire [17:0] coeff_re,coeff_im, output wire coeff_match,
 input wire [63:0] s_data, input wire s_valid, output wire s_ready, input wire s_last,
 output wire [63:0] m_data, output wire m_valid, input wire m_ready, output wire m_last,
 output reg fault
);
 (* ram_style="block" *) reg signed [17:0] hr[0:2047], hi[0:2047];
 initial begin $readmemh(H_RE,hr); $readmemh(H_IM,hi); end
 // Port B writes only while the signal-processing state is held in reset.
 // Reset never clears coefficients. Port A is reused for update readback.
 always @(posedge clk) if(COEFF_WRITABLE && coeff_we && !rst_n) begin
   hr[coeff_addr]<=coeff_re; hi[coeff_addr]<=coeff_im;
 end
 localparam integer PW=DATA_WIDTH+18, SW=PW+1;
 localparam signed [63:0] MAX_VALUE=(64'sd1<<<(DATA_WIDTH-1))-1;
 localparam signed [63:0] MIN_VALUE=-(64'sd1<<<(DATA_WIDTH-1));
 reg [10:0] bin;
 reg [3:0] valid,last;
 reg signed [DATA_WIDTH-1:0] ar,ai;
 reg signed [17:0] br,bi;
 (* use_dsp="yes" *) reg signed [PW-1:0] rr,ii,ri,ir;
 reg signed [SW-1:0] sumr,sumi;
 reg signed [31:0] outr,outi;
 wire ce=!valid[3] || m_ready;
 assign coeff_match=(br==coeff_re) && (bi==coeff_im);
 wire [10:0] coeff_read_addr=(COEFF_WRITABLE && !rst_n) ? coeff_addr : bin;
 wire coeff_read_enable=(COEFF_WRITABLE && !rst_n) || (rst_n && ce && s_valid);
 always @(posedge clk) if(coeff_read_enable) begin
   br<=hr[coeff_read_addr]; bi<=hi[coeff_read_addr];
 end
 assign s_ready=ce;
 assign m_valid=valid[3]; assign m_last=last[3]; assign m_data={outi,outr};
 // Q16 coefficient; round toward nearest, exact ties toward +infinity.
 function automatic signed [31:0] quant(input signed [SW-1:0] a);
   reg signed [63:0] t;
   begin
     t=a; t=(t+64'sd32768)>>>16;
     if(t>MAX_VALUE) quant=MAX_VALUE;
     else if(t<MIN_VALUE) quant=MIN_VALUE;
     else quant=t[31:0];
   end
 endfunction
 always @(posedge clk) begin
   if(!rst_n) begin bin<=0; valid<=0; last<=0; fault<=0; end
   else if(ce) begin
     valid<={valid[2:0],s_valid}; last<={last[2:0],s_last};
     if(s_valid) begin
       ar<=$signed(s_data[31:0]); ai<=$signed(s_data[63:32]);
       if(s_last != (bin==2047)) fault<=1;
       bin<=bin+1'b1;
     end
     rr<=ar*br; ii<=ai*bi; ri<=ar*bi; ir<=ai*br;
     sumr<=$signed({rr[PW-1],rr})-$signed({ii[PW-1],ii});
     sumi<=$signed({ri[PW-1],ri})+$signed({ir[PW-1],ir});
     outr<=quant(sumr); outi<=quant(sumi);
     if(valid[2] && ((($signed(sumr)+64'sd32768)>>>16)>MAX_VALUE || (($signed(sumr)+64'sd32768)>>>16)<MIN_VALUE ||
                    (($signed(sumi)+64'sd32768)>>>16)>MAX_VALUE || (($signed(sumi)+64'sd32768)>>>16)<MIN_VALUE)) fault<=1;
   end
 end
endmodule
