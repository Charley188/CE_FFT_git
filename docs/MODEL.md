# MATLAB 定点模型

FFT 使用本机 Vivado 2023.2 的 `xfft_v9_1_bitacc_cmodel_nt64.zip` 中官方 C 模型及 MATLAB MEX 接口。
`matlab/vendor` 保留原厂版权声明和本机生成的 MEX。模型运行不需要调用 Python 或 Vivado。
已用 Vivado 内置 MinGW 9.3 和 MATLAB R2025b 的 R2017b 兼容复数 API 编译，官方 smoke test 通过。

配置逐项对应 ce_fft_ip：2048、pipelined streaming、28 位数据、20 位 twiddle、scaled、convergent rounding、natural order。
配置字 0x0d55/0x0d54 对应正/逆方向，缩放顺序为 [2 2 2 2 2 1]。
输入整数左移 8；复乘系数 Q16，floor((sum+32768)/65536)，ties 向正无穷并饱和至 28 位；逆变换后输出左移 3 并饱和至 16 位。
乘积和加减在 double 整数精确范围内（不超过 47 个有符号位）。发生 FFT 溢出、复乘饱和或 DAC 削顶时报告错误，与 RTL 的 fault 策略对应。

模型按 OLS 每块 2048、丢前 256、输出 1792 点；首块前缀为零。浮点参考使用同一量化 H 的 OLS，不用另一组系数。
位精确模型比对要求最大分量误差为 0；浮点参考用于显示定点误差，不用它替代整数一致性判据。

TB 以 RFDC 数字 I/Q 接口为起点，以 DAC 前数字接口为终点。使用实际 AXI 系数加载控制器、XPM FIFO、完整 10 引擎/通路和真实 XFFT IP。
不仿真 ADC/DAC 模拟电路、PS CPU、HMC7044 模拟时钟行为或 VNA 测量。TB 的 AXI master 代替 PS 发起正常加载流程。
只通过 online.live_q 选择真实算法输出（不把启动静默零当作信号）；不跳过任何真实有效输出样点，不自动调整增益/相位或进行互相关平移。

本机 MEX 是平台相关产物。换 MATLAB/操作系统时需由维护者重新编译官方接口，保留原厂声明；不允许悄悄退回浮点近似 FFT。

## 仅仿真复位期加速

CE_SIM_FAST_RESET 仅在 TB 的 simulation fileset 定义。ce_fft_core 在复位至少16个时钟后暂停 IP 及配置状态机时钟；解除复位后的首个正常下降沿重新开钟，不产生窄脉冲。系数 RAM、控制器和数据链复位逻辑不暂停。SYNTHESIS 分支始终将 fft_clock 接原 clk。加速测试验证运行期的数据行为，不作为完整复位期逐周期等价证明；FULL_RESET_CLOCKS 可关闭加速。
