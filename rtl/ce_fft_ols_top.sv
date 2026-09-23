`timescale 1ns/1ps
// Each lane is {Q[15:0],I[15:0]}; lane 0 is the earliest sample.
// Optional runtime writes are allowed only while the entire core is reset.
module ce_fft_ols_top #(
 parameter integer OVERLAP=256, ENGINES=10, STARTUP_GUARD=224, DATA_WIDTH=32,
 parameter bit COEFF_WRITABLE=0,
 parameter H_RE="h_re.mem", H_IM="h_im.mem"
)(
 input wire clk, rst_n,
 input wire coeff_we, input wire [10:0] coeff_addr,
 input wire [17:0] coeff_re,coeff_im, output wire coeff_match,

 input wire [255:0] s_data, input wire s_valid, output wire s_ready,
 output reg [255:0] m_data, output reg m_valid,
 output wire fault
);
 localparam integer WORDS=(2048-OVERLAP)/8, OW=OVERLAP/8;
 localparam integer EW=$clog2(ENGINES);
 initial begin
   if(OVERLAP<8 || OVERLAP>1024 || OVERLAP%8!=0) $fatal(1,"This implementation requires overlap multiple of 8 in [8,1024]");
   if(ENGINES*WORDS<2052) $fatal(1,"Insufficient FFT capacity / serializer margin");
 end
 reg [EW-1:0] in_engine;
 wire [EW-1:0] next_engine=(in_engine==ENGINES-1)?0:in_engine+1'b1;
 reg [7:0] in_word;
 reg in_page, first_block, started, input_fault;
 wire [ENGINES-1:0] configured, engine_fault, coeff_matches;
 assign coeff_match=&coeff_matches;
 assign s_ready=&configured;
 wire take=s_valid && s_ready;
 reg [EW-1:0] out_engine, mux_engine;
 reg out_page, running, read_valid, output_fault;
 reg [7:0] out_word;
 wire [255:0] result[0:ENGINES-1];
 wire [1:0] done[0:ENGINES-1];
 reg [1:0] seen[0:ENGINES-1];
 wire available=done[out_engine][out_page]!=seen[out_engine][out_page];
 localparam integer GW=(STARTUP_GUARD<1)?1:$clog2(STARTUP_GUARD+1);
 reg [GW-1:0] guard_count;
 wire read_now=running || (available && guard_count==STARTUP_GUARD);
 for(genvar e=0;e<ENGINES;e=e+1) begin: engines
   wire own=in_engine==e;
   wire prefix=next_engine==e && in_word>=WORDS-OW;
   wire wp=own ? in_page : ((in_engine==ENGINES-1)?~in_page:in_page);
   wire [7:0] wa=own ? in_word+OW : in_word-(WORDS-OW);
   ce_fft_engine #(.COEFF_WRITABLE(COEFF_WRITABLE),.DATA_WIDTH(DATA_WIDTH),.OVERLAP(OVERLAP),.H_RE(H_RE),.H_IM(H_IM)) engine(
     .coeff_we(coeff_we),.coeff_addr(coeff_addr),.coeff_re(coeff_re),.coeff_im(coeff_im),.coeff_match(coeff_matches[e]),
     .clk(clk),.rst_n(rst_n),.wr_en(take && (own || prefix)),.wr_addr({wp,wa}),.wr_data(s_data),
     .launch(take && own && in_word==WORDS-1),.launch_page(in_page),.zero_prefix(first_block),
     .out_page(out_page),.out_word(out_word),.out_data(result[e]),.done_toggle(done[e]),
     .configured(configured[e]),.fault(engine_fault[e]));
 end
 integer j;
 always @(posedge clk) begin
   if(!rst_n) begin
     in_engine<=0; in_word<=0; in_page<=0; first_block<=1; started<=0; input_fault<=0;
     out_engine<=0; out_page<=0; out_word<=0; running<=0; read_valid<=0;
     guard_count<=0; m_valid<=0; m_data<=0; mux_engine<=0; output_fault<=0;
     for(j=0;j<ENGINES;j=j+1) seen[j]<=0;
   end else begin
     if(!running && available && guard_count<STARTUP_GUARD) guard_count<=guard_count+1'b1;
     if(started && !take) input_fault<=1;
     if(take) begin
       started<=1;
       if(in_word==WORDS-1) begin
         in_word<=0; in_engine<=next_engine; first_block<=0;
         if(in_engine==ENGINES-1) in_page<=~in_page;
       end else in_word<=in_word+1'b1;
     end
     read_valid<=read_now; mux_engine<=out_engine;
     m_valid<=read_valid;
     if(read_valid) m_data<=result[mux_engine];
     if(read_now) begin
       running<=1;
       if(out_word==0 && !available) output_fault<=1;
       if(out_word==WORDS-1) begin
         seen[out_engine][out_page]<=done[out_engine][out_page];
         out_word<=0;
         if(out_engine==ENGINES-1) begin out_engine<=0; out_page<=~out_page; end
         else out_engine<=out_engine+1'b1;
       end else out_word<=out_word+1'b1;
     end
   end
 end
 assign fault=input_fault|output_fault|(|engine_fault);
endmodule

