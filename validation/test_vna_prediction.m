function test_vna_prediction(scratch)
% No board files are changed; all generated data live in scratch.
root=fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(root,'matlab','lib'));
if ~isfolder(scratch),mkdir(scratch);end
Fs=2.4e9;f=linspace(-1.2e9,1.2e9,2001)';
freq_axis=f+1.2e9;
vna_data=0.4*(1+0.12*sin(2*pi*f/Fs)).*exp(0.4j+0.1j*cos(2*pi*f/Fs));
file=fullfile(scratch,'measurement.mat');save(file,'freq_axis','vna_data');
cfg=struct('center_hz',1.2e9,'passband_hz',1e9,'stopband_hz',1.1e9,...
 'tap_count',257,'delay_samples',128,'regularization',1e-4,'max_gain_db',6,...
 'file',file,'output_dir',fullfile(scratch,'new'),'plots',false);
r=ce_vna(2,cfg);
assert(isequal(r.h_hw,conj(r.h_design)) && isequal(r.h,r.h_hw));
assert(r.hardware_conjugated && any(abs(imag(r.h_design))>1e-6));
H=fft(r.h_hw,2048);q=round([real(H),imag(H)]*65536);
assert(isequal(r.Hq,complex(q(:,1),q(:,2))/65536));
assert(isequal(read_mem(fullfile(cfg.output_dir,'compensated','h_re.mem')),mod(q(:,1),2^18)));
assert(isequal(read_mem(fullfile(cfg.output_dir,'compensated','h_im.mem')),mod(q(:,2),2^18)));
pass=abs(f)<=cfg.passband_hz;fp=f(pass);gp=vna_data(pass)/r.target_gain;
D=exp(-2j*pi*(fp/Fs)*(0:cfg.tap_count-1));target=exp(-2j*pi*fp/Fs*cfg.delay_samples);
e=gp.*(D*r.h_design)./target;
assert(abs(r.predicted_ripple_db-range(20*log10(abs(e))))<1e-10);
assert(abs(r.predicted_phase_error_deg-max(abs(angle(e)*180/pi)))<1e-10);
assert(r.predicted_ripple_db<0.2 && r.predicted_phase_error_deg<5);
wrong=gp.*(D*r.h_hw)./target;
assert(max(abs(angle(wrong)*180/pi))>20,'Fixture must detect mixed conventions');
s=load(fullfile(cfg.output_dir,'compensated','calibration.mat'));
assert(isequal(s.result.h_hw,r.h_hw) && isequal(s.result.h_design,r.h_design));
r2=ce_vna(2,cfg);assert(isequal(r.Hq,r2.Hq));
ce_vna(1,cfg);
assert(all(read_mem(fullfile(cfg.output_dir,'bypass','h_re.mem'))==65536));
assert(all(read_mem(fullfile(cfg.output_dir,'bypass','h_im.mem'))==0));
fprintf('PASS: VNA prediction ripple %.6g dB, phase %.6g deg; hardware exports, saved fields, repeated export and bypass checked.\n',r.predicted_ripple_db,r.predicted_phase_error_deg);
end
function q=read_mem(path)
rows=strip(readlines(path));rows=rows(strlength(rows)>0);
assert(numel(rows)==2048 && all(strlength(rows)==5));q=hex2dec(rows);
end
