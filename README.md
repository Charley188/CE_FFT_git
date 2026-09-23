# CE FFT：共享 RTL、手动仿真与在线系数加载

主工程来源：`CE_0922/CE_FFT_mod_fre`。此目录是新的独立工作副本；原目录未修改。

## 日常只用这三个入口

|入口|用途|
|---|---|
|`adda/project/ce_fft_adda.xpr`|实际 ADDA 板级 Vivado 工程，保留在线系数加载和 NCO/VIO 调频|
|`tb/ce_fft_tb.xpr`|实际数字数据链主干 TB，使用真实 AMD FFT IP|
|`matlab/MAIN.m`、`matlab/VNA_MAIN.m`|MATLAB 点击 Run 的主干比对和单路 VNA 校准|

用户无需执行 Python、PowerShell、Tcl 或命令行。`docs/maintenance` 只用于维护工程，不是日常操作入口。

## 仿真顺序（路径已相互对应）

1. 在 MATLAB 打开 `matlab/MAIN.m`，设置 `MODE=1`，点击 Run。
   - `TEST_CASE="identity"`：H=1；`"three_tap"`：已知复数三 tap；`"deployed"`：读取 `coeff/h_re.mem`、`h_im.mem`。
   - 生成 `data/input/input_iq.mem`、`h_re.mem`、`h_im.mem`、`config.txt`。默认 12 块、21,504 个复数样点。
   - `input_iq.csv`、`input.mat` 是方便查看的副本；实际 MATLAB 模型与 TB 都读取 MEM。
2. 在 Vivado 2023.2 打开 `tb/ce_fft_tb.xpr`，点击 Run Simulation → Run Behavioral Simulation。
   - 如果上次仿真还开着，先关闭，再重新 Run Behavioral Simulation，重新读取输入文件。
   - 工程已设置运行到结束。看到 `PASS MAIN` 表示系数加载、数据记录和连续性检查完成。
   - 输出自动写到 `data/output/rtl_ch1.csv`；双路开启时还写 `rtl_ch2.csv`。
3. 返回 MATLAB，把 `MAIN.m` 的 `MODE` 改为 2，点击 Run。
   - 从 `data/input` 读取输入信号和系数，执行官方 FFT 位精确模型与 RTL 配套整数运算。
   - 从 `data/output` 读取 RTL CSV，按样点序号对齐，逐点比较，并画波形、误差和频谱。
   - 数值指标保存到 `data/output/comparison.csv`；中间模型数据在 `comparison.mat`。
   - 不使用数据批次编号、哈希或“同一组数据”识别；数据选择由使用者确认。
   - 程序保留格式、数量、样点顺序、连续性和 fault 检查，不进行自动增益/相位拟合或任意平移。

## 目录职责

- `rtl/`：唯一生产 RTL，算法、异步 FIFO、在线加载控制器、NCO 控制器、板级顶层及所需网表。
- `ip/`：ADDA 与 TB 共用 FFT XCI；同时保存板级辅助 IP。生成产物不作为源码历史。
- `coeff/`：PL 初始 MEM；也是 MAIN 的 deployed 系数来源。主干 TB 运行时由 AXI 加载 data/input 系数。
- `adda/`：板级工程、BD、约束；不保存另一套手写 RTL。
- `tb/`：一个主干 TB 工程，无快速 FFT 模型、位宽扫描、独立小模块测试入口。
- `matlab/`：一个主干两模式入口、一个单路 VNA 两模式入口，以及内部函数/官方数值模型。
- `ps/src/`：原 PS 应用源码与四份系数文件；从新 XSA 创建/更新本机 Vitis 平台后使用。
- `data/`：MATLAB→TB→MATLAB 交换区。
- `docs/`：操作说明、迁移清单和本轮验证情况。

## 单路 / 双路

唯一开关是 `rtl/ce_config.vh` 中的 `CE_ENABLE_SECOND_PATH`：0 单路，1 双路。ADDA 和 TB 共用该文件。
默认保持原主工程的 0。更改后重新启动 TB 仿真；硬件需重新综合、实现、生成 bit 并导出匹配 XSA。
TB 双路时向两路加载同一份测试系数和输入，分别输出与比对；实际 PS 仍可加载两路不同系数。
固定配置：N=2048、overlap=256、8 complex samples/clk、FFT 28 位、twiddle 20 位、系数 signed18/Q16。
MAIN 的模式选择是数据生成/比对，不是硬件单/双路开关。

## VNA：单路两个模式

打开 `matlab/VNA_MAIN.m`，设置 MODE 后点击 Run：

- MODE=1：在 `matlab/vna/output/bypass/` 生成 H=1 的 `h_re.mem`、`h_im.mem`。
- MODE=2：读取 bypass 测量的复数 S21，做有限长度、正则化补偿设计，并在 `matlab/vna/output/compensated/` 输出新 MEM 和预测结果。
- 数据格式：MAT 包含 `freq_axis`（Hz）、`vna_data`（复数）；CSV 为 Hz、实部、虚部三列，不是 dB/相位列。
- `CENTER_HZ` 要设置为实际 RF 中心频率；程序使用 `f_baseband=f_measured-CENTER_HZ`。频谱方向应由实际 RFDC 混频配置确认，不自动猜测共轭/翻转。
- 测量需覆盖设定通带（默认中心 ±1 GHz）；默认 257 tap、128 样点目标延时。补偿目标幅度取 bypass 通带幅度中位数，不是无条件拉到绝对 0 dB。
- 定量输出为设计预测，量化产生的 OLS 尾部误差另外报告；补偿效果要由重新测量确认。
- 手动把两份 MEM 放入 `ps/src/coeff` 对应通路：第一路原名，第二路改为 `h_re_2.mem`/`h_im_2.mem`。
- 在 Vitis Classic 中 Clean → Build → Run，让新 MEM 进入 ELF，再在线加载。不重新生成 PL bit。
- PS 仍要求四份 MEM；只更新一路时保留另一路文件。MATLAB 不自动复制文件、不启动 PS。

## PS 与板级构建

新工程没有复用旧 bit/XSA/ELF。用 ADDA 重新生成 bit，Export Hardware（包含 bit），在 Vitis Classic 2023.2 创建/更新 A53 standalone 平台并导入 `ps/src`。保留 src/coeff 相对层次。
NCO/VIO 操作见 `docs/NCO.md`。任何板级实现/时序和上板结论以 `docs/VALIDATION.md` 为准。

## 版本管理

此目录使用本地 Git。源文件、XPR、BD/XCI、MEM、文档进入版本管理；Vivado 缓存和仿真输出不进入。
完成一个改动就提交；可复现版本打标签，不再复制日期版工程目录。外部备份/远端尚未配置。
项目移动后，MATLAB 路径自动相对入口定位；Vivado Simulation Settings → xsim.more_options 的 INPUT_DIR/OUTPUT_DIR 需更新为新位置。
