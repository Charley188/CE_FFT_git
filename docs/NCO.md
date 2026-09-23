# NCO 操作（继承主版本功能）

以下原始验证记录属于迁移前版本。本轮验证单独见 VALIDATION.md；本目录未复制历史报告目录。

# 双通道 Fine NCO + VIO 调频

工作副本：D:\CE\CE_FFT_git。板级工程：adda/project/ce_fft_adda.xpr。

## 已接入

- 实际工程 BD 和 board_sources/design_1/design_1.bd 均已修改。
- ADC Tile0 两路（01、23）和 DAC Tile0 两路（00、02）均为 Fine。
- ADC/DAC 采样率仍为 4.8 GS/s，抽取/插值仍为 2，FFT 数据接口保持原配置。
- 两个 VIO：vio_adc_freq、vio_dac_freq；两个控制器均使用 RFDC s_axi_aclk 的 100 MHz 时钟及对应同步复位，无新增跨时钟频率总线。
- ADC 与 DAC 分别提交更新，不保证二者同拍生效；这不是相干同步跳频实现。
- 只更新频率，不写相位/相位复位。频率在完整 busy 握手期间锁存。

## 启动默认值

原 Coarse 时的频率枚举由本机 RFDC component.xml 核对。Fine 默认值保持实际工程原有的 +/-Fs/4 数字混频偏移，而不是沿用原先未生效的 NCO 字段。

| 通道 | ADC NCO | DAC NCO |
|---|---:|---:|
| 第一通道：ADC01 / DAC00 | +1.2 GHz，400000000000 | -1.2 GHz，C00000000000 |
| 第二通道：ADC23 / DAC02 | -1.2 GHz，C00000000000 | +1.2 GHz，400000000000 |

已核对生成的 RFDC 初始化 ROM 与上表一致。Fine 和 Coarse 的实际幅度/相位表现仍需板上测量。

## PS 为什么有少量改动

main.c 在原 RFDC 启动流程之后、ce_coeff_run 之前调用 ce_nco_vio_init()。
该函数只设置 NCO Update Mode 的事件源并读回确认；每次调频不经过 PS。
设置规则：(原寄存器值 & ~7) | 2，即只把低三位设为 Tile，保留其余位。

相对 RFDC 基地址的寄存器偏移：

- ADC 两路包含四个内部切片：0x1608C、0x1648C、0x1688C、0x16C8C。
- DAC 两路：0x0608C、0x0688C。

使用 16 位读写，与本机官方 xrfdc 驱动一致。依据 rfdc_v12_0/src/xrfdc_hw.h：
ADC/DAC Tile0 DRP 基址 0x16000/0x6000，物理切片步长 0x400，NCO_UPDT 偏移 0x08C，事件掩码 7，Tile 值 2。
本机生成的 ADC/DAC NCO 状态机会写 DRP 0x72E 来发出 Tile 更新事件。
生成初始化 ROM 未发现显式设置该事件寄存器的条目；本轮未上板读取原硬件默认值，因此不声称原值必定不是 2。
这里显式设置已知值以避免依赖未验证的上电状态。如果后续 PS 再重启/复位 RFDC，也须重新调用初始化。

## 使用步骤

1. 在上述 Vivado 工程重新综合、实现并生成 bitstream。当前旧 bit 不含本功能。
2. 导出新 XSA，在 Vitis Classic 更新平台并重新编译 app_seu。Debug 内旧 makefile 的绝对路径不是本轮构建入口。
3. 下载新 bit 和匹配的 probes 文件，运行应用。等待串口提示 Fine NCO VIO ready 及系数加载成功。
4. Hardware Manager 打开 vio_adc_freq 或 vio_dac_freq，将频率输出显示进制设为 Hex。
5. 先写 probe_out0 / probe_out1 的 12 位十六进制频率字，再设 probe_out2 掩码。
6. 确认 probe_in0 的 bit0/bit1 均为 0，再翻转 probe_out3（0→1 或 1→0 均可）提交一次。
7. 等待 probe_in1 完成计数增加、probe_in0 bit0 回到 0。下一次再翻转提交位。

| VIO probe | 位宽 | 含义 |
|---|---:|---|
| probe_out0 | 48 | 第一通道的 NCO 频率字 |
| probe_out1 | 48 | 第二通道的 NCO 频率字 |
| probe_out2 | 2 | 更新掩码：1=第一路，2=第二路，3=两路，0=不提交 |
| probe_out3 | 1 | 提交翻转位，默认 0 |
| probe_in0 | 4 | bit0=控制器忙；bit1=RFDC busy；bit2=超时；bit3=观察到 busy 应答 |
| probe_in1 | 16 | 已完成事务计数（复位清零，溢出回绕） |
| probe_in2 / 3 | 48 | 最近锁存的请求频率，不是 RFDC 寄存器读回 |

超时约 0.168 s（2^24 个 100 MHz 周期）；超时会继续保持负载并等待，不会误报成功。
忙碌期间提交会忽略，不排队；完成后重新翻转提交位。超时标志在下一次接受新事务时清除。

## 频率字

word = round(f_NCO / Fs * 2^48)，负数按 48 位补码编码。此接口范围为 [-Fs/2, Fs/2)。
Fs 使用 ADC/DAC 原始采样率 4800 MHz，不是抽取后的 2400 MHz，也不是 PL 的 300 MHz。

示例：+1200 MHz → 400000000000；-1200 MHz → C00000000000；0 → 000000000000。
任意频点可用可选工具 docs/maintenance/nco_word.ps1 -FrequencyMHz 1000 换算；上板操作只需 VIO，无需运行脚本。
这里输入的是带符号的 NCO 数字偏移；模拟中心频率还取决于 ADC/DAC 方向、Nyquist 区和频谱镜像，不能把 RF 频率直接不加判断地填入。

## 第二路 FFT 开关与切频影响

rtl/ce_config.vh 的 CE_ENABLE_SECOND_PATH 仍为原值 0。本功能已给两路 RFDC 加入调频接口；若要第二路也有完整 ADC→FFT→DAC 信号链，将该宏改成 1 后重新综合。宏为 0 时第二路 DAC 数字数据恒为零。
切频不是无缝整链切换：FFT/OLS 及 FIFO 中存在旧频率数据。观察稳定输出前需留出管线过渡时间；校准频点改变后，原补偿系数也不自动变成新频点的校准结果。

## 验证与边界

- Vivado 2023.2 BD 校验及输出生成通过。
- ADC/DAC 控制器行为仿真通过：锁存、写掩码、单周期请求、等待 busy、忽略忙时提交、超时保持、复位。
- 与本机实际生成的 DAC NCO FSM 集成仿真通过：两路频率寄存器覆盖、第二路单独更新、延迟启动、Tile 更新事件。DRP 寄存器总线使用测试模型；不是模拟 RF 输出验证。
- 控制器单独综合通过。100 MHz 综合时序估计 WNS +8.956 ns；不是整板实现时序结论。
- PS main.c 用本机 ARM GCC 和副本内 BSP 编译通过；3 个未使用变量告警来自原文件。
- 复制工程原有的 ce_fft_ip stale 锁定已刷新；升级前后全部 CONFIG 参数逐项一致，IP 版本仍为 9.1 Rev.10。见 ip_status_after_refresh.rpt。
- 未重跑整板布局布线、未生成新 bit/XSA、未上板验证。

报告及修改前备份：verification_fine_vio。源码：rtl/ce_nco_vio_ctrl.v、ps/src/ce_nco.h。
官方接口说明：https://docs.amd.com/r/en-US/pg269-rf-data-converter/Single-Converter-Mode
