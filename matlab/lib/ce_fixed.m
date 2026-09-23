function [y,yfloat]=ce_fixed(x,hr,hi)
% FFT uses AMD bit-accurate C model. All other arithmetic follows shared RTL.
root=fileparts(fileparts(fileparts(mfilename('fullpath'))));
vendor=fullfile(root,'matlab','vendor');addpath(vendor);
setenv('PATH',[vendor pathsep getenv('PATH')]);
assert(exist('xfft_v9_1_bitacc_mex','file')==3,'Official FFT MEX is missing; see docs/MODEL.md');
g=struct('C_NFFT_MAX',11,'C_ARCH',3,'C_HAS_NFFT',0,'C_USE_FLT_PT',0,...
 'C_INPUT_WIDTH',28,'C_TWIDDLE_WIDTH',20,'C_HAS_SCALING',1,'C_HAS_BFP',0,'C_HAS_ROUNDING',1);
N=2048;O=256;L=N-O;W=28;scale=2^(W-1);schedule=[2 2 2 2 2 1];
x=x(:);M=numel(x);blocks=ceil(M/L);padded=[zeros(O,1);x;zeros(blocks*L-M,1)];
y=zeros(blocks*L,1);yfloat=y;H=(hr+1j*hi)/65536;
for b=0:blocks-1
 frame=padded(b*L+(1:N));
 [F,~,ov]=xfft_v9_1_bitacc_mex(g,11,(frame*256/scale).',schedule,1);
 assert(~ov,'Forward FFT overflow');F=round(real(F(:))*scale)+1j*round(imag(F(:))*scale);
 % Exact double integer products: maximum sum uses <=47 signed bits.
 pr=real(F).*hr-imag(F).*hi;pi=real(F).*hi+imag(F).*hr;
 qr=floor((pr+32768)/65536);qi=floor((pi+32768)/65536);
 assert(all(qr>=-scale & qr<scale & qi>=-scale & qi<scale),'Complex gain saturation / RTL fault');
 qr=min(max(qr,-scale),scale-1);qi=min(max(qi,-scale),scale-1);
 [Y,~,ov]=xfft_v9_1_bitacc_mex(g,11,((qr+1j*qi)/scale).',schedule,0);
 assert(~ov,'Inverse FFT overflow');Y=round(real(Y(:))*scale)+1j*round(imag(Y(:))*scale);
 raw=Y(O+1:end)*8;
 assert(all(real(raw)>=-32768 & real(raw)<=32767 & imag(raw)>=-32768 & imag(raw)<=32767),'DAC clipping / RTL fault');
 y(b*L+(1:L))=min(max(real(raw),-32768),32767)+1j*min(max(imag(raw),-32768),32767);
 z=ifft(fft(frame).*H);yfloat(b*L+(1:L))=z(O+1:end);
end
y=y(1:M);yfloat=yfloat(1:M);
end
