function result=ce_vna(mode,cfg)
N=2048;O=256;Fs=2.4e9;
assert(ismember(mode,[1 2]),'MODE must be 1 or 2');
if mode==1
 hr=65536*ones(N,1);hi=zeros(N,1);result=struct('mode',1,'description','H=1 bypass');
 out=fullfile(cfg.output_dir,'bypass');
else
 if strlength(string(cfg.file))==0
  [f,p]=uigetfile({'*.mat;*.csv','VNA complex response (.mat/.csv)'});assert(~isequal(f,0),'No VNA file selected');cfg.file=fullfile(p,f);
 end
 [~,~,ext]=fileparts(cfg.file);
 if strcmpi(ext,'.mat')
  s=load(cfg.file);assert(isfield(s,'freq_axis') && isfield(s,'vna_data'),'MAT needs freq_axis and complex vna_data');f=s.freq_axis(:);g=s.vna_data(:);
 elseif strcmpi(ext,'.csv')
  a=readmatrix(cfg.file);assert(size(a,2)==3,'CSV needs Hz, real S21, imag S21');f=a(:,1);g=a(:,2)+1j*a(:,3);
 else,error('Supported files: MAT or CSV');end
 f=f-cfg.center_hz;assert(numel(f)==numel(g) && all(isfinite(f)) && all(isfinite(g)) && all(diff(f)>0),'Invalid complex frequency data');
 assert(cfg.passband_hz>0 && cfg.passband_hz<cfg.stopband_hz && cfg.stopband_hz<Fs/2);
 assert(f(1)<=-cfg.passband_hz && f(end)>=cfg.passband_hz,'Measurement must cover the requested baseband');
 assert(cfg.tap_count>=1 && cfg.tap_count<=O+1 && cfg.tap_count==fix(cfg.tap_count));
 assert(cfg.delay_samples>=0 && cfg.delay_samples<cfg.tap_count && cfg.delay_samples==fix(cfg.delay_samples));
 pass=abs(f)<=cfg.passband_hz;fp=f(pass);gp=g(pass);assert(numel(fp)>cfg.tap_count && all(abs(gp)>1e-10),'Insufficient points / deep null');
 target_gain=median(abs(gp));gp=gp/target_gain;
 ix=unique(round(linspace(1,numel(fp),min(4097,numel(fp)))));fw=fp(ix);gw=gp(ix);
 A=exp(-2j*pi*(fw/Fs)*(0:cfg.tap_count-1));B=gw.*A;
 desired=exp(-2j*pi*fw/Fs*cfg.delay_samples);
 guardf=[linspace(-Fs/2,-cfg.stopband_hz,128),linspace(cfg.stopband_hz,Fs/2,128)]';
 C=exp(-2j*pi*(guardf/Fs)*(0:cfg.tap_count-1));
 assert(cfg.regularization>0 && isfinite(cfg.regularization));
 lambda=cfg.regularization*numel(fw);
 for attempt=1:8
  h_design=[B;0.25*C;sqrt(lambda)*eye(cfg.tap_count)]\[desired;zeros(numel(guardf)+cfg.tap_count,1)];
  % Conjugate only for the board convention; keep VNA-domain taps for prediction.
  h_hw=conj(h_design);
  H=fft(h_hw,N);hr=round(real(H)*65536);hi=round(imag(H)*65536);
  fits=all(hr>=-131072 & hr<=131071 & hi>=-131072 & hi<=131071);
  Hq=(hr+1j*hi)/65536;tail_error=sum(abs(ifft(Hq)-[h_hw;zeros(N-numel(h_hw),1)]));
  peak=20*log10(max(abs(fft(h_hw,32768)))+tail_error);
  if fits && peak<=cfg.max_gain_db,break;end
  lambda=lambda*10;
 end
 assert(fits && peak<=cfg.max_gain_db,'Cannot fit MEM range/gain limit; inspect measurement and settings');
 predicted=gp.*(exp(-2j*pi*(fp/Fs)*(0:cfg.tap_count-1))*h_design);
 desired_full=exp(-2j*pi*fp/Fs*cfg.delay_samples);e=predicted./desired_full;
 result=struct('mode',2,'cfg',cfg,'h',h_hw,'h_design',h_design,'h_hw',h_hw,'Hq',Hq,...
  'hardware_conjugated',true,'prediction_domain','VNA design (floating-point)','regularization_used',lambda/numel(fw),...
  'target_gain',target_gain,'predicted_ripple_db',range(20*log10(abs(e))),...
  'predicted_phase_error_deg',max(abs(angle(e)*180/pi)),'quantized_error_l1',tail_error,'peak_gain_db',peak);
 out=fullfile(cfg.output_dir,'compensated');
 if cfg.plots
  figure('Name','单路 VNA 补偿预测（设计坐标，浮点）');tiledlayout(2,1);
  nexttile;plot(fp/1e6,20*log10(abs(gp)),fp/1e6,20*log10(abs(predicted)));legend('bypass','补偿预测');ylabel('相对幅度 dB');
  nexttile;plot(fp/1e6,unwrap(angle(gp))*180/pi,fp/1e6,angle(e)*180/pi);legend('bypass 相位','补偿后相对目标延时的残余相位');xlabel('MHz');ylabel('degree');
 end
 fprintf('VNA设计坐标浮点预测 ripple %.4f dB；量化 OLS 误差界系数 %.6g。实际效果请重新测量。\n',result.predicted_ripple_db,tail_error);
end
if ~isfolder(out),mkdir(out);end
write_mem(fullfile(out,'h_re.mem'),hr,18);write_mem(fullfile(out,'h_im.mem'),hi,18);
save(fullfile(out,'calibration.mat'),'result');
fprintf('单路 MEM 已生成：%s\n手动复制到 PS，Clean → Build → Run。\n',out);
end
