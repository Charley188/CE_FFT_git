`timescale 1ns/1ps
`include "ce_config.vh"
module tb_main;
 localparam DATA_WIDTH=28, ENABLE_SECOND_PATH=`CE_ENABLE_SECOND_PATH;
 localparam CHANNELS=ENABLE_SECOND_PATH ? 2 : 1;
 reg axi_clk=0,alg_clk=0,adc_clk=0,dac_clk=0;
 always #5 axi_clk=~axi_clk;
 always #1.667 alg_clk=~alg_clk;
 initial begin #0.4;forever #1.667 adc_clk=~adc_clk;end
 initial begin #0.9;forever #1.667 dac_clk=~dac_clk;end
 reg rst_n=0;
 reg [39:0] awaddr=0,araddr=0;reg awvalid=0,wvalid=0,arvalid=0,bready=0,rready=0;
 reg [31:0] wdata=0;reg [3:0] wstrb=15;
 wire awready,wready,arready,bvalid,rvalid;wire [1:0] bresp,rresp;wire [31:0] rdata;
 wire hold_core,cwe,cch;wire [10:0] ca;wire [17:0] cre,cim;
 wire [1:0] matched,quiet,running,fault;

 ce_coeff_control #(.WAIT_CYCLES(3000000)) ctl(
  .axi_clk(axi_clk),.alg_clk(alg_clk),.arst_n(rst_n),
  .s_awaddr(awaddr),.s_awvalid(awvalid),.s_awready(awready),.s_wdata(wdata),.s_wstrb(wstrb),.s_wvalid(wvalid),.s_wready(wready),
  .s_bresp(bresp),.s_bvalid(bvalid),.s_bready(bready),.s_araddr(araddr),.s_arvalid(arvalid),.s_arready(arready),
  .s_rdata(rdata),.s_rresp(rresp),.s_rvalid(rvalid),.s_rready(rready),
  .update_hold(hold_core),.coeff_we(cwe),.coeff_channel(cch),.coeff_addr(ca),.coeff_re(cre),.coeff_im(cim),
  .coeff_match(matched),.load_quiet(quiet),.path_running(running),.path_fault(fault));

 string input_dir,output_dir;
 integer samples,config_fd,read_count,fd[0:1],status_fd;
 reg [31:0] input_words[0:262143];
 reg [17:0] h_re[0:2047],h_im[0:2047];
 reg [127:0] stim_i[0:1],stim_q[0:1];
 wire [255:0] data[0:1];wire [1:0] valid,overflow,underflow;
 integer sent[0:1],received[0:1],dac_cycle=0,last_cycle[0:1];
 reg [1:0] done=0;reg files_ready=0;
 initial begin
   if(!$value$plusargs("INPUT_DIR=%s",input_dir))$fatal(1,"INPUT_DIR missing");
   if(!$value$plusargs("OUTPUT_DIR=%s",output_dir))$fatal(1,"OUTPUT_DIR missing");
   config_fd=$fopen({input_dir,"/config.txt"},"r");
   if(!config_fd)$fatal(1,"Run MATLAB mode 1 first");
   read_count=$fscanf(config_fd,"%d",samples);$fclose(config_fd);
   if(read_count!=1 || samples<1792 || samples>262144 || samples%1792)$fatal(1,"Invalid configuration");
   $readmemh({input_dir,"/input_iq.mem"},input_words,0,samples-1);
   $readmemh({input_dir,"/h_re.mem"},h_re);$readmemh({input_dir,"/h_im.mem"},h_im);
   for(integer k=0;k<samples;k++)if($isunknown(input_words[k]))$fatal(1,"Incomplete input");
   for(integer k=0;k<2048;k++)if($isunknown({h_re[k],h_im[k]}))$fatal(1,"Incomplete coefficients");
   status_fd=$fopen({output_dir,"/tb_status.txt"},"w");if(!status_fd)$fatal(1,"Output directory missing");
   $fdisplay(status_fd,"RUNNING %0d %0d",samples,CHANNELS);$fclose(status_fd);
   for(integer c=0;c<CHANNELS;c++)begin
     fd[c]=$fopen($sformatf("%s/rtl_ch%0d.csv",output_dir,c+1),"w");if(!fd[c])$fatal(1,"Output open failed");
     $fdisplay(fd[c],"sample,cycle,i,q,fault");
   end
   files_ready=1;
 end
 for(genvar ch=0;ch<2;ch++)begin: paths
 if(ch==0 || ENABLE_SECOND_PATH)begin: enabled
   adda_fft_path #(.ONLINE_UPDATE(1),.DATA_WIDTH(DATA_WIDTH)) path(
    .clk_adc0(adc_clk),.clk_300m(alg_clk),.clk_dac0(dac_clk),.pl_rstn(rst_n),.rf_adc_axis_rstn(rst_n),.rf_dac_axis_rstn(rst_n),
    .update_hold(hold_core),.coeff_we(cwe && cch==ch),.coeff_addr(ca),.coeff_re(cre),.coeff_im(cim),
    .coeff_match(matched[ch]),.load_quiet(quiet[ch]),.path_running(running[ch]),
    .m00_axis_tdata(stim_i[ch]),.m01_axis_tdata(stim_q[ch]),.m00_axis_tvalid(1'b1),.m01_axis_tvalid(1'b1),.m00_axis_tready(),.m01_axis_tready(),
    .s00_axis_tdata(data[ch]),.s00_axis_tvalid(valid[ch]),.s00_axis_tready(1'b1),.fifo_overflow(overflow[ch]),.fifo_underflow(underflow[ch]));
   assign fault[ch]=overflow[ch]|underflow[ch];
   initial begin sent[ch]=0;received[ch]=0;last_cycle[ch]=-1;stim_i[ch]=0;stim_q[ch]=0;end
   always @(negedge adc_clk)for(integer l=0;l<8;l++)begin
     if(files_ready && sent[ch]+l<samples)begin
       stim_i[ch][l*16+:16]=input_words[sent[ch]+l][15:0];stim_q[ch][l*16+:16]=input_words[sent[ch]+l][31:16];
     end else begin stim_i[ch][l*16+:16]=0;stim_q[ch][l*16+:16]=0;end
   end
   always @(posedge adc_clk)begin
     if(!path.adc_rst_n)sent[ch]=0;else if(path.awr)sent[ch]=sent[ch]+8;
   end
   always @(posedge dac_clk)begin
     if(rst_n && fault[ch]!==0)$fatal(1,"Path fault ch=%0d",ch);
     if(rst_n && !done[ch] && valid[ch] && path.online.live_q)begin
       if($isunknown(data[ch]))$fatal(1,"Unknown DAC data");
       if(last_cycle[ch]>=0 && dac_cycle!=last_cycle[ch]+1)$fatal(1,"DAC discontinuity");
       last_cycle[ch]=dac_cycle;
       for(integer l=0;l<8;l++)if(received[ch]<samples)begin
         $fdisplay(fd[ch],"%0d,%0d,%0d,%0d,%0d",received[ch],dac_cycle,$signed(data[ch][l*32+:16]),$signed(data[ch][l*32+16+:16]),fault[ch]);received[ch]++;
       end
       if(received[ch]==samples)begin $fclose(fd[ch]);done[ch]=1;end
     end
   end
 end else begin: disabled
   ce_disabled_fft_path inactive(.clk_dac0(dac_clk),.arst_n(rst_n),.m00_axis_tready(),.m01_axis_tready(),
     .s00_axis_tdata(data[ch]),.s00_axis_tvalid(valid[ch]),.coeff_match(matched[ch]),.load_quiet(quiet[ch]),.path_running(running[ch]),.fifo_overflow(overflow[ch]),.fifo_underflow(underflow[ch]));
   assign fault[ch]=overflow[ch]|underflow[ch];
   always @(posedge dac_clk)if(rst_n && data[ch]!==0)$fatal(1,"Inactive path not zero");
 end
 end
 always @(posedge dac_clk)dac_cycle<=dac_cycle+1;
 integer writes=0;
 task automatic aw(input [15:0] off);
   @(negedge axi_clk);awaddr=40'h80010000+off;awvalid=1;
   do @(posedge axi_clk);while(!awready);
   @(negedge axi_clk);awvalid=0;
 endtask
 task automatic wd(input [31:0] value);
   @(negedge axi_clk);wdata=value;wvalid=1;
   do @(posedge axi_clk);while(!wready);
   @(negedge axi_clk);wvalid=0;
 endtask
 task automatic put(input [15:0] off,input [31:0] value,input bit reject=0);
   writes++;
   // Alternate W-before-AW and AW-before-W; B is deliberately backpressured.
   if(writes%2) begin wd(value);aw(off);end else begin aw(off);wd(value);end
   wait(bvalid);
   repeat(2) @(negedge axi_clk);
   if(bresp!=(reject ? 2 : 0)) $fatal(1,"AXI write response off=%h resp=%d",off,bresp);
   bready=1;@(negedge axi_clk);bready=0;
 endtask
 task automatic get(input [15:0] off,output [31:0] value);
   @(negedge axi_clk);araddr=40'h80010000+off;arvalid=1;
   do @(posedge axi_clk);while(!arready);
   @(negedge axi_clk);arvalid=0;
   wait(rvalid);repeat(2) @(negedge axi_clk);
   value=rdata;if(rresp!=0)$fatal(1,"AXI read error");
   rready=1;@(negedge axi_clk);rready=0;
 endtask
 task automatic idle(output [31:0] status);
   integer n;n=0;
   do begin get(8,status);n++;if(n>10000)$fatal(1,"Command stuck busy");end while(status[0]);
 endtask
 task automatic command(input integer op,input integer err=0);
   reg [31:0] st,e;put(4,op);idle(st);get(12,e);
   if(e[7:0]!=err)$fatal(1,"Command %d error expected %d got %h",op,err,e);
 endtask
 function automatic [31:0] crcword(input [31:0] c,input [31:0] w);
   reg [31:0] t,v;begin t=c;v=w;
   for(integer b=0;b<4;b++)begin t=t^v[7:0];v=v>>8;for(integer k=0;k<8;k++)t=t[0]?(t>>1)^32'hedb88320:t>>1;end
   crcword=t;end
 endfunction

 reg [31:0] expected[0:1],st,crc;
 initial begin
   wait(files_ready);repeat(30)@(negedge axi_clk);rst_n=1;
   repeat(50)@(negedge axi_clk);get(0,st);if(st!='h43454631)$fatal(1,"Wrong controller ID");
   command(1);
   for(integer c=0;c<2;c++)begin
     put('h10,c);put('h14,0);crc='hffffffff;
     for(integer k=0;k<2048;k++)begin
       put('h18,{14'b0,h_re[k]});put('h1c,{14'b0,h_im[k]});put('h20,1);idle(st);
       if(st[5])$fatal(1,"Coefficient load error");
       crc=crcword(crcword(crc,{14'b0,h_re[k]}),{14'b0,h_im[k]});
     end
     expected[c]=~crc;
     get(c?'h28:'h24,st);if(st!=2048)$fatal(1,"Coefficient count mismatch");
     get(c?'h30:'h2c,st);if(st!=expected[c])$fatal(1,"Coefficient CRC mismatch");
   end
   put('h34,expected[0]);put('h38,expected[1]);command(3);command(4);
   wait(done[0] && (!ENABLE_SECOND_PATH || done[1]));
   status_fd=$fopen({output_dir,"/tb_status.txt"},"w");$fdisplay(status_fd,"PASS %0d %0d",samples,CHANNELS);$fclose(status_fd);
   $display("PASS MAIN samples=%0d channels=%0d",samples,CHANNELS);$finish;
 end
 initial begin #20000000;$fatal(1,"TB timeout");end
endmodule
