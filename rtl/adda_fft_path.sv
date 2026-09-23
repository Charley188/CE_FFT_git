`timescale 1ns/1ps
// ADC/DAC AXIS and processing clock must have the same sustained 300 MHz rate.
// CDC FIFOs absorb phase difference; they cannot correct permanent rate error.
module adda_fft_path #(
 parameter integer DATA_WIDTH=32,
 parameter bit ONLINE_UPDATE=0,
 parameter H_RE="h_re.mem", H_IM="h_im.mem"
)(
 input wire clk_adc0,clk_300m,clk_dac0,
 input wire pl_rstn,rf_adc_axis_rstn,rf_dac_axis_rstn,
 input wire update_hold,coeff_we, input wire [10:0] coeff_addr,
 input wire [17:0] coeff_re,coeff_im,
 output wire coeff_match,load_quiet,path_running,
 input wire [127:0] m00_axis_tdata,m01_axis_tdata,
 input wire m00_axis_tvalid,m01_axis_tvalid,
 output wire m00_axis_tready,m01_axis_tready,
 output wire [255:0] s00_axis_tdata,
 output wire s00_axis_tvalid,input wire s00_axis_tready,
 output wire fifo_overflow,fifo_underflow
);
 wire base_arst_n=pl_rstn && rf_adc_axis_rstn && rf_dac_axis_rstn;
 wire hold_core=ONLINE_UPDATE && update_hold;
 wire arst_n=base_arst_n && !hold_core;
 wire adc_rst_n,alg_rst_n,dac_rst_n;
 ce_reset_sync a(.clk(clk_adc0),.arst_n(arst_n),.rst_n(adc_rst_n));
 ce_reset_sync p(.clk(clk_300m),.arst_n(arst_n),.rst_n(alg_rst_n));
 ce_reset_sync d(.clk(clk_dac0),.arst_n(arst_n),.rst_n(dac_rst_n));
 wire [255:0] packed_iq,fi,fo;
 for(genvar l=0;l<8;l=l+1) begin: lanes
   assign packed_iq[l*32+:32]={m01_axis_tdata[l*16+:16],m00_axis_tdata[l*16+:16]};
 end
 wire pair=m00_axis_tvalid && m01_axis_tvalid;
 wire awr,fiv,core_ready,fov,dwr,dvalid;
 wire [8:0] acount,dcount;
 reg astarted,dstarted;
 wire core_fault;
 reg adc_error,alg_error,dac_error,adc_armed;
 assign m00_axis_tready=(ONLINE_UPDATE && !adc_rst_n) ? 1'b1 : awr && m01_axis_tvalid;
 assign m01_axis_tready=(ONLINE_UPDATE && !adc_rst_n) ? 1'b1 : awr && m00_axis_tvalid;
 ce_async_fifo input_cdc(.rst(!adc_rst_n),.wr_clk(clk_adc0),.rd_clk(clk_300m),
   .s_data(packed_iq),.s_valid(pair),.s_ready(awr),.m_data(fi),.m_valid(fiv),
   .m_ready(astarted && core_ready),.rd_count(acount));
 always @(posedge clk_300m) begin
   if(!alg_rst_n) begin astarted<=0; alg_error<=0; end
   else begin
     if(core_ready && acount>=32) astarted<=1;
     if((astarted && !fiv) || (fov && !dwr)) alg_error<=1;
   end
 end
 always @(posedge clk_adc0) begin
   if(!adc_rst_n) begin adc_error<=0;adc_armed<=0;end
   else begin
     // RFDC may already be producing data while XPM finishes reset. Start
     // overflow monitoring only after the FIFO can accept its first word.
     if(awr) adc_armed<=1;
     if((!ONLINE_UPDATE || adc_armed) && ((pair && !awr) || (m00_axis_tvalid ^ m01_axis_tvalid))) adc_error<=1;
   end
 end
 ce_fft_ols_top #(.COEFF_WRITABLE(ONLINE_UPDATE),.DATA_WIDTH(DATA_WIDTH),.H_RE(H_RE),.H_IM(H_IM))
 core(.clk(clk_300m),.rst_n(alg_rst_n),
   .coeff_we(coeff_we && hold_core),.coeff_addr(coeff_addr),.coeff_re(coeff_re),.coeff_im(coeff_im),.coeff_match(coeff_match),.s_data(fi),
   .s_valid(astarted && fiv),.s_ready(core_ready),.m_data(fo),.m_valid(fov),.fault(core_fault));
 wire [255:0] dac_fifo_data;
 wire dac_fifo_ready;
 ce_async_fifo output_cdc(.rst(!alg_rst_n),.wr_clk(clk_300m),.rd_clk(clk_dac0),
   .s_data(fo),.s_valid(fov),.s_ready(dwr),.m_data(dac_fifo_data),.m_valid(dvalid),
   .m_ready(dac_fifo_ready),.rd_count(dcount));
 always @(posedge clk_dac0) begin
   if(!dac_rst_n) begin dstarted<=0; dac_error<=0; end
   else begin
     if(dcount>=32) dstarted<=1;
     if(dstarted && (!dvalid || !s00_axis_tready)) dac_error<=1;
   end
 end
 generate if(ONLINE_UPDATE) begin: online
   wire base_dac_rst_n;
   ce_reset_sync base_d(.clk(clk_dac0),.arst_n(base_arst_n),.rst_n(base_dac_rst_n));
   reg [255:0] data_q;
   reg valid_q,live_q,live_accepted,adc_quiet_q;
   wire slot_free=!valid_q || s00_axis_tready;
   wire take_live=dac_rst_n && dstarted && dvalid;
   assign dac_fifo_ready=slot_free && dac_rst_n && dstarted;
   assign s00_axis_tdata=data_q;
   assign s00_axis_tvalid=valid_q;
   // Keep AXIS payload stable under backpressure, including a mute request.
   // Zero insertion continues through local reset and startup.
   always @(posedge clk_dac0) begin
     if(!base_dac_rst_n) begin data_q<=0; valid_q<=0; live_q<=0; live_accepted<=0; end
     else begin
       if(slot_free) begin
         valid_q<=1; live_q<=take_live;
         data_q<=take_live ? dac_fifo_data : 256'b0;
       end
       if(!dac_rst_n) live_accepted<=0;
       else if(valid_q && s00_axis_tready && live_q) live_accepted<=1;
     end
   end
   always @(posedge clk_adc0) adc_quiet_q<=!adc_rst_n;
   wire adc_quiet_alg,dac_quiet_alg,live_alg;
   wire dac_quiet=!dac_rst_n && base_dac_rst_n && valid_q && !live_q;
   xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.SIM_ASSERT_CHK(1)) aq(
     .src_clk(clk_adc0),.src_in(adc_quiet_q),.dest_clk(clk_300m),.dest_out(adc_quiet_alg));
   xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(1),.SIM_ASSERT_CHK(1)) dq(
     .src_clk(clk_dac0),.src_in(dac_quiet),.dest_clk(clk_300m),.dest_out(dac_quiet_alg));
   xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.SIM_ASSERT_CHK(1)) lr(
     .src_clk(clk_dac0),.src_in(live_accepted),.dest_clk(clk_300m),.dest_out(live_alg));
   assign load_quiet=hold_core && !alg_rst_n && adc_quiet_alg && dac_quiet_alg;
   assign path_running=!hold_core && alg_rst_n && live_alg;
 end else begin: legacy
   assign dac_fifo_ready=dstarted && s00_axis_tready;
   assign s00_axis_tdata=dac_fifo_data;
   assign s00_axis_tvalid=dstarted && dvalid;
   assign load_quiet=1'b0;
   assign path_running=dstarted && dvalid;
 end endgenerate
 // Online controller receives only algorithm-domain diagnostic signals.
 generate if(ONLINE_UPDATE) begin: diagnostic_cdc
   wire adc_error_alg,dac_error_alg;
   xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.SIM_ASSERT_CHK(1)) ae(
     .src_clk(clk_adc0),.src_in(adc_error),.dest_clk(clk_300m),.dest_out(adc_error_alg));
   xpm_cdc_single #(.DEST_SYNC_FF(3),.SRC_INPUT_REG(0),.SIM_ASSERT_CHK(1)) de(
     .src_clk(clk_dac0),.src_in(dac_error),.dest_clk(clk_300m),.dest_out(dac_error_alg));
   assign fifo_overflow=adc_error_alg|alg_error|core_fault;
   assign fifo_underflow=dac_error_alg|alg_error|core_fault;
 end else begin: diagnostic_legacy
   assign fifo_overflow=adc_error|alg_error|core_fault;
   assign fifo_underflow=dac_error|alg_error|core_fault;
 end endgenerate
endmodule
module ce_reset_sync(input wire clk,arst_n,output wire rst_n);
 (* ASYNC_REG="TRUE" *) reg [3:0] ff;
 always @(posedge clk or negedge arst_n)
   if(!arst_n) ff<=0; else ff<={ff[2:0],1'b1};
 assign rst_n=ff[3];
endmodule

// Inactive channel for temporary single-path builds. No FFT, coefficient RAM,
// or data FIFO is instantiated. The PS still sends both coefficient images:
// the controller checks the discarded channel's count/CRC, not a RAM readback.
// Constant acknowledgements exclude this inactive path from collective waits.
module ce_disabled_fft_path(
 input wire clk_dac0,arst_n,
 output wire m00_axis_tready,m01_axis_tready,
 output wire [255:0] s00_axis_tdata,
 output reg s00_axis_tvalid,
 output wire coeff_match,load_quiet,path_running,
 output wire fifo_overflow,fifo_underflow
);
 wire dac_rst_n;
 ce_reset_sync reset_d(.clk(clk_dac0),.arst_n(arst_n),.rst_n(dac_rst_n));
 assign m00_axis_tready=1'b1;
 assign m01_axis_tready=1'b1;
 assign s00_axis_tdata=256'b0;
 always @(posedge clk_dac0)
   if(!dac_rst_n) s00_axis_tvalid<=1'b0;
   else s00_axis_tvalid<=1'b1;
 assign coeff_match=1'b1;
 assign load_quiet=1'b1;
 assign path_running=1'b1;
 assign fifo_overflow=1'b0;
 assign fifo_underflow=1'b0;
endmodule