%% 主干仿真：修改 MODE 后，点击 MATLAB Run
% MODE=1：生成同一份整数输入与测试系数，之后去 Vivado 点击 Run Simulation。
% MODE=2：MATLAB 位精确定点仿真，并读取指定的 FPGA TB 输出进行比对。
MODE = 1;
TEST_CASE = "identity"; % identity / three_tap / deployed
BLOCKS = 12;            % 每块输出 1792 点；12 块覆盖 10 个引擎及复用
SEED = 27;
PLOT_RESULTS = true;
root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'matlab','lib'));
cfg = struct('test_case',TEST_CASE,'blocks',BLOCKS,'seed',SEED,'plots',PLOT_RESULTS);
cfg.input_dir = fullfile(root,'data','input');
cfg.output_dir = fullfile(root,'data','output');
cfg.coeff_dir = fullfile(root,'coeff');
% 如需比对别处输出，修改 output_dir；程序不检查数据批次/哈希，由你确认。
result = ce_main(MODE,cfg);
