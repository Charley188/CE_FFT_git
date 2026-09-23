%% 单路 VNA 校准：修改 MODE，然后点击 Run
MODE = 1; % 1：生成 H=1 bypass MEM；2：用 bypass 测量优化补偿 MEM
CENTER_HZ = 0; % VNA 的 RF 中心频率；f_baseband = f_measured - CENTER_HZ
BYPASS_FILE = ""; % 模式2留空时弹窗选 MAT 或 CSV
% MAT: freq_axis (Hz), vna_data (complex S21)
% CSV: frequency_Hz, real_S21, imag_S21；不是 dB/degree 列
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'matlab','lib'));
cfg=struct('center_hz',CENTER_HZ,'passband_hz',1e9,'stopband_hz',1.1e9,...
 'tap_count',257,'delay_samples',128,'regularization',1e-4,'max_gain_db',6,...
 'file',BYPASS_FILE,'output_dir',fullfile(root,'matlab','vna','output'),'plots',true);
result=ce_vna(MODE,cfg);
% 手动把输出 h_re.mem/h_im.mem 放入 PS 所需通路。不自动复制或运行 PS。
