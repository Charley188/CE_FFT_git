function result=ce_main(mode,cfg)
if ~isfolder(cfg.input_dir),mkdir(cfg.input_dir);end
if ~isfolder(cfg.output_dir),mkdir(cfg.output_dir);end
if mode==1
 assert(cfg.blocks>=1 && cfg.blocks==fix(cfg.blocks) && cfg.blocks*1792<=262144);
 rng(cfg.seed);M=1792*cfg.blocks;
 x=randi([-2000,2000],M,1)+1j*randi([-2000,2000],M,1);
 switch string(cfg.test_case)
 case "identity",H=ones(2048,1);
 case "three_tap",h=zeros(2048,1);h(1)=0.5;h(8)=0.25j;h(257)=-0.125;H=fft(h);
 case "deployed"
  hr=read_mem(fullfile(cfg.coeff_dir,'h_re.mem'),18,2048);hi=read_mem(fullfile(cfg.coeff_dir,'h_im.mem'),18,2048);H=(hr+1j*hi)/65536;
 otherwise,error('Unknown test case');
 end
 hr=round(real(H)*65536);hi=round(imag(H)*65536);
 assert(all(hr>=-131072 & hr<=131071 & hi>=-131072 & hi<=131071));
 write_mem(fullfile(cfg.input_dir,'h_re.mem'),hr,18);write_mem(fullfile(cfg.input_dir,'h_im.mem'),hi,18);
 packed=mod(real(x),65536)+65536*mod(imag(x),65536);
 write_mem(fullfile(cfg.input_dir,'input_iq.mem'),packed,32);
 f=fopen(fullfile(cfg.input_dir,'config.txt'),'w');assert(f>=0);fprintf(f,'%d\n',M);fclose(f);
 writematrix([real(x),imag(x)],fullfile(cfg.input_dir,'input_iq.csv'));
 save(fullfile(cfg.input_dir,'input.mat'),'x','hr','hi','cfg');
 result=struct('samples',M,'test_case',cfg.test_case);
 fprintf('生成完成：%d 点。请在 Vivado 打开 tb/ce_fft_tb.xpr，点击 Run Behavioral Simulation。\n',M);
elseif mode==2
 % No run IDs, fingerprints, or automatic same-dataset checks.
 u=read_mem(fullfile(cfg.input_dir,'input_iq.mem'),32,sscanf(fileread(fullfile(cfg.input_dir,'config.txt')),'%d',1));
 u=mod(u,2^32);ri=mod(u,65536);rq=floor(u/65536);ri(ri>=32768)=ri(ri>=32768)-65536;rq(rq>=32768)=rq(rq>=32768)-65536;x=ri+1j*rq;
 hr=read_mem(fullfile(cfg.input_dir,'h_re.mem'),18,2048);hi=read_mem(fullfile(cfg.input_dir,'h_im.mem'),18,2048);
 [fixed,floating]=ce_fixed(x,hr,hi);
 outputs=dir(fullfile(cfg.output_dir,'rtl_ch*.csv'));assert(~isempty(outputs),'No FPGA output CSV found');
 result=struct([]);
 for k=1:numel(outputs)
  t=readtable(fullfile(outputs(k).folder,outputs(k).name));
  assert(all(ismember({'sample','cycle','i','q','fault'},t.Properties.VariableNames)),'CSV columns invalid');
  M=numel(x);assert(height(t)==M,'Sample count mismatch: expected %d, got %d',M,height(t));
  assert(all(t.sample==(0:M-1)'),'Sample indices missing/reordered');
  assert(all(t.fault==0),'RTL reported fault');
  assert(all(isfinite(t.i) & isfinite(t.q)) && all(t.i==fix(t.i) & t.q==fix(t.q)),'Invalid integer output');
  assert(all(t.i>=-32768 & t.i<=32767 & t.q>=-32768 & t.q<=32767));
  expected_cycle=t.cycle(1)+floor((0:M-1)'/8);assert(isequal(t.cycle,expected_cycle),'Output continuity violation');
  rtl=t.i+1j*t.q;e=rtl-fixed;ef=rtl-floating;
  result(k).file=outputs(k).name;result(k).pass=all(e==0);
  result(k).max_component_error=max([abs(real(e));abs(imag(e))]);
  result(k).rms_complex_error=sqrt(mean(abs(e).^2));
  result(k).float_evm=sqrt(sum(abs(ef).^2)/max(sum(abs(floating).^2),eps));
  first=find(e~=0,1);if isempty(first),first=NaN;else,first=first-1;end
  result(k).first_mismatch=first;
  if cfg.plots
   figure('Name',['主干比对 ' outputs(k).name]);tiledlayout(2,2);
   nexttile;plot([real(fixed),real(rtl)]);title('I：定点模型 / RTL');legend('MATLAB','RTL');
   nexttile;plot([imag(fixed),imag(rtl)]);title('Q：定点模型 / RTL');
   nexttile;plot([real(e),imag(e)]);title('逐点误差（LSB）');
   nexttile;f=(-M/2:M/2-1)'*2.4e9/M;plot(f/1e6,20*log10(max(abs(fftshift(fft([floating,rtl]))),1e-12)));title('浮点 / RTL 频谱');xlabel('MHz');
  end
 end
 save(fullfile(cfg.output_dir,'comparison.mat'),'fixed','floating','result');
 writetable(struct2table(result),fullfile(cfg.output_dir,'comparison.csv'));disp(struct2table(result));
 if all([result.pass]),fprintf('PASS：MATLAB 官方位精确模型与 RTL 逐样点一致。\n');else,warning('数值比对不通过，见 comparison.csv。');end
else,error('MODE must be 1 or 2');end
end
