# VNA预测与FPGA导出约定

VNA/MATLAB与FPGA的频率方向适配只发生在硬件系数生成边界：
- h_design：VNA坐标下求解的浮点抽头，用于补偿预测、幅度纹波和相位误差。
- h_hw = conj(h_design)：FPGA约定下的抽头；H = fft(h_hw,2048)后量化、导出MEM。
- Hq：实际硬件频域量化系数。范围、峰值增益和量化OLS误差检查仍针对硬件系数执行。

calibration.mat中的result.h保留原有硬件抽头语义，并增加h_design、h_hw、hardware_conjugated和prediction_domain字段。预测曲线是设计坐标下的浮点预测，不是RFDC完整模型或上板实测保证。
TB与MATLAB定点仿真使用同一份已导出的Hq，不再次共轭、不交换I/Q、不翻转频率。
MODE=1仍输出H=1。PS手动复制流程不变。

验证入口：validation/test_vna_prediction.m，参数为工程外的临时输出目录。

验证记录（2026-09-25，MATLAB R2025b）：合成复数通道回归通过；设计坐标预测纹波0.0715845 dB、相位误差0.000356293度。与提交b3d01e3的原函数对比，两份导出MEM逐字节一致，Hq、量化误差界、峰值增益及最终正则化一致。原混用坐标的预测为4.1896 dB、57.2955度。以上为合成测试，不代表板上实测效果。
