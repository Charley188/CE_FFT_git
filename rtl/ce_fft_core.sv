`timescale 1ns/1ps
// Vivado 2023.2 XFFT: fixed 2048, configurable data width, scaled, natural order, non-realtime.
module ce_fft_core #(parameter bit INVERSE=0, parameter integer DATA_WIDTH=32)(
 input wire clk, input wire rst_n,
 input wire [63:0] s_data, input wire s_valid, output wire s_ready, input wire s_last,
 output wire [63:0] m_data, output wire m_valid, input wire m_ready, output wire m_last,
 output wire configured, output reg fault
);
 // Simulator-only acceleration: after >=16 reset edges, suppress idle XFFT
 // clock events while reset remains asserted. Controller/RAM clocks are untouched.
 // Synthesis always uses the original clock. +FULL_RESET_CLOCKS disables this.
 wire fft_clock;
`ifdef SYNTHESIS
 assign fft_clock=clk;
`else
`ifdef CE_SIM_FAST_RESET
 reg sim_clock_enable=1'b1;
 integer sim_reset_edges=0;
 reg sim_full_reset_clocks;
 initial sim_full_reset_clocks=$test$plusargs("FULL_RESET_CLOCKS");
 always @(negedge clk) begin
   if(rst_n || sim_full_reset_clocks) begin
     sim_reset_edges=0;sim_clock_enable=1'b1;
   end else if(sim_reset_edges<16) begin
     sim_reset_edges=sim_reset_edges+1;sim_clock_enable=1'b1;
   end else sim_clock_enable=1'b0;
 end
 assign fft_clock=clk && sim_clock_enable;
`else
 assign fft_clock=clk;
`endif
`endif
 localparam integer AXIS_COMPONENT_WIDTH=((DATA_WIDTH+7)/8)*8;
 wire [2*AXIS_COMPONENT_WIDTH-1:0] ip_out;
 wire [2*AXIS_COMPONENT_WIDTH-1:0] ip_in={s_data[32+:AXIS_COMPONENT_WIDTH],s_data[0+:AXIS_COMPONENT_WIDTH]};
 assign m_data[31:0]=$signed(ip_out[0+:DATA_WIDTH]);
 assign m_data[63:32]=$signed(ip_out[AXIS_COMPONENT_WIDTH+:DATA_WIDTH]);
 initial if(DATA_WIDTH<24 || DATA_WIDTH>32) $fatal(1,"Unsupported FFT width");
 // Generated XFFT input_width MUST equal DATA_WIDTH; keep Vivado IP customization and top DATA_WIDTH consistent.
 reg cfg_sent;
 wire cfg_ready, raw_ready, unexpected, missing, overflow;
 wire [15:0] cfg_data = INVERSE ? 16'h0d54 : 16'h0d55;
 assign configured=cfg_sent;
 assign s_ready=cfg_sent && raw_ready;
 always @(posedge fft_clock) begin
   if (!rst_n) begin cfg_sent<=0; fault<=0; end
   else begin
     if (cfg_ready) cfg_sent<=1;
     if (unexpected || missing || overflow) fault<=1;
   end
 end
 ce_fft_ip ip(
   .aclk(fft_clock), .aresetn(rst_n),
   .s_axis_config_tdata(cfg_data), .s_axis_config_tvalid(!cfg_sent), .s_axis_config_tready(cfg_ready),
   .s_axis_data_tdata(ip_in), .s_axis_data_tvalid(s_valid && cfg_sent),
   .s_axis_data_tready(raw_ready), .s_axis_data_tlast(s_last),
   .m_axis_data_tdata(ip_out), .m_axis_data_tvalid(m_valid), .m_axis_data_tready(m_ready), .m_axis_data_tlast(m_last),
   .m_axis_status_tready(1'b1), .event_tlast_unexpected(unexpected), .event_tlast_missing(missing), .event_fft_overflow(overflow)
 );
endmodule



