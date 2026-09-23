`timescale 1ns/1ps
module ce_fft_engine #(parameter integer OVERLAP=256, DATA_WIDTH=32, parameter bit COEFF_WRITABLE=0,
 parameter H_RE="h_re.mem", H_IM="h_im.mem")(
 input wire clk,rst_n,
 input wire coeff_we, input wire [10:0] coeff_addr,
 input wire [17:0] coeff_re,coeff_im, output wire coeff_match,
 input wire wr_en, input wire [8:0] wr_addr, input wire [255:0] wr_data,
 input wire launch, input wire launch_page, input wire zero_prefix,
 input wire out_page, input wire [7:0] out_word,
 output wire [255:0] out_data, output reg [1:0] done_toggle,
 output wire configured, output wire fault
);
 // Two full block snapshots. A 256-bit write stores 8 consecutive complex points.
 (* ram_style="block" *) reg [255:0] input_ram[0:511];
 reg [255:0] rd_word;
 reg active,page,first;
 reg [10:0] issue;
 reg [2:0] lane;
 reg v,last,zero;
 reg schedule_fault;
 wire sr;
 wire ce=!v || sr;
 wire [31:0] sample=rd_word[lane*32+:32];
 wire signed [31:0] xr=$signed(sample[15:0]);
 wire signed [31:0] xi=$signed(sample[31:16]);
 // Keep four input guard bits at every supported width.
 localparam integer INPUT_SHIFT=DATA_WIDTH-20;
 localparam integer OUTPUT_SHIFT=INPUT_SHIFT-11;
 wire [63:0] sd=zero ? 64'b0 : { (xi<<<INPUT_SHIFT), (xr<<<INPUT_SHIFT) };
 always @(posedge clk) begin
   if(wr_en) input_ram[wr_addr]<=wr_data;
   if(ce && active) rd_word<=input_ram[{page,issue[10:3]}];
 end
 always @(posedge clk) begin
   if(!rst_n) begin active<=0; issue<=0; v<=0; last<=0; zero<=0; lane<=0; page<=0; first<=0; schedule_fault<=0; end
   else begin
     if(ce) begin
       v<=active;
       if(active) begin
         lane<=issue[2:0]; last<=issue==2047; zero<=first && issue<OVERLAP;
         if(issue==2047) active<=0;
         issue<=issue+1'b1;
       end
     end
     if(launch) begin
       if(active || v) schedule_fault<=1;
       active<=1; issue<=0; page<=launch_page; first<=zero_prefix;
     end
   end
 end
 wire [63:0] fd,gd,yd;
 wire fv,fr,fl,gv,gr,gl,yv,yl;
 wire fc,ic,ff,gf,ifault;
 ce_fft_core #(.DATA_WIDTH(DATA_WIDTH)) fft(.clk(clk),.rst_n(rst_n),.s_data(sd),.s_valid(v),.s_ready(sr),.s_last(last),
   .m_data(fd),.m_valid(fv),.m_ready(fr),.m_last(fl),.configured(fc),.fault(ff));
 ce_complex_gain #(.COEFF_WRITABLE(COEFF_WRITABLE),.DATA_WIDTH(DATA_WIDTH),.H_RE(H_RE),.H_IM(H_IM)) gain(.clk(clk),.rst_n(rst_n),
   .coeff_we(coeff_we),.coeff_addr(coeff_addr),.coeff_re(coeff_re),.coeff_im(coeff_im),.coeff_match(coeff_match),
   .s_data(fd),.s_valid(fv),.s_ready(fr),.s_last(fl),.m_data(gd),.m_valid(gv),.m_ready(gr),.m_last(gl),.fault(gf));
 ce_fft_core #(.INVERSE(1),.DATA_WIDTH(DATA_WIDTH)) ifft(.clk(clk),.rst_n(rst_n),.s_data(gd),.s_valid(gv),.s_ready(gr),.s_last(gl),
   .m_data(yd),.m_valid(yv),.m_ready(1'b1),.m_last(yl),.configured(ic),.fault(ifault));
 assign configured=fc && ic;
 reg [10:0] yi;
 reg yp;
 reg format_fault,clip;
 wire [10:0] dst=yi-OVERLAP;
 // Ideal gain before this quantizer: 2**(INPUT_SHIFT-11).
 function automatic signed [63:0] normalized(input signed [31:0] a);
   reg signed [63:0] t;
   begin
     t=a;
     if(OUTPUT_SHIFT>0) t=(t+(64'sd1<<<(OUTPUT_SHIFT-1)))>>>OUTPUT_SHIFT;
     else if(OUTPUT_SHIFT<0) t=t<<<(-OUTPUT_SHIFT);
     normalized=t;
   end
 endfunction
 function automatic [15:0] sat16(input signed [31:0] a);
   reg signed [63:0] t;
   begin t=normalized(a);
     if(t>32767) sat16=16'h7fff;
     else if(t< -32768) sat16=16'h8000;
     else sat16=t[15:0];
   end
 endfunction
 wire [31:0] y16={sat16($signed(yd[63:32])),sat16($signed(yd[31:0]))};
 for(genvar b=0;b<8;b=b+1) begin: banks
   (* ram_style="block" *) reg [31:0] mem[0:511];
   reg [31:0] q;
   always @(posedge clk) begin
     if(yv && yi>=OVERLAP && dst[2:0]==b) mem[{yp,dst[10:3]}]<=y16;
     q<=mem[{out_page,out_word}];
   end
   assign out_data[b*32+:32]=q;
 end
 always @(posedge clk) begin
   if(!rst_n) begin yi<=0; yp<=0; done_toggle<=0; format_fault<=0; clip<=0; end
   else if(yv) begin
     if(yl!=(yi==2047)) format_fault<=1;
     if(yi>=OVERLAP && (normalized($signed(yd[31:0]))>32767 || normalized($signed(yd[31:0]))< -32768 ||
                       normalized($signed(yd[63:32]))>32767 || normalized($signed(yd[63:32]))< -32768)) clip<=1;
     yi<=yi+1'b1;
     if(yi==2047) begin done_toggle[yp]<=~done_toggle[yp]; yp<=~yp; end
   end
 end
 assign fault=schedule_fault|format_fault|clip|ff|gf|ifault;
endmodule

