`timescale 1ns/1ps
module ce_async_fifo(
 input wire rst,wr_clk,rd_clk,
 input wire [255:0] s_data,input wire s_valid,output wire s_ready,
 output wire [255:0] m_data,output wire m_valid,input wire m_ready,
 output wire [8:0] rd_count
);
 wire full,empty,wb,rb;
 assign s_ready=!rst && !full && !wb;
 assign m_valid=!empty && !rb;
 xpm_fifo_async #(.FIFO_MEMORY_TYPE("block"),.FIFO_WRITE_DEPTH(256),
   .WRITE_DATA_WIDTH(256),.READ_DATA_WIDTH(256),.READ_MODE("fwft"),.FIFO_READ_LATENCY(0),
   .WR_DATA_COUNT_WIDTH(9),.RD_DATA_COUNT_WIDTH(9),.USE_ADV_FEATURES("0707"),
   .CDC_SYNC_STAGES(3),.PROG_FULL_THRESH(240),.PROG_EMPTY_THRESH(16),.SIM_ASSERT_CHK(1)
 ) fifo(.rst(rst),.wr_clk(wr_clk),.rd_clk(rd_clk),.din(s_data),.wr_en(s_valid && s_ready),
   .dout(m_data),.rd_en(m_valid && m_ready),.full(full),.empty(empty),
   .wr_rst_busy(wb),.rd_rst_busy(rb),.rd_data_count(rd_count),
   .sleep(1'b0),.injectsbiterr(1'b0),.injectdbiterr(1'b0));
endmodule
