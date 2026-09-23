# Maintainer-only: rebuild the official MATLAB MEX on this workstation.
$ErrorActionPreference = 'Stop'
$root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$vendor = Join-Path $root 'matlab/vendor'
$compiler = 'D:/Xilinx/Vivado/2023.2/tps/mingw/9.3.0/win64.o/nt/bin/g++.exe'
$matlabRoot = 'D:/Program Files/MATLAB/R2025b'
& $compiler -shared -O2 -DWIN64 -DNT -DMATLAB_MEX_FILE -DMATLAB_MEXCMD_RELEASE=R2017b "-I$matlabRoot/extern/include" "$vendor/xfft_v9_1_bitacc_mex.cpp" "-L$vendor" -lIp_xfft_v9_1_bitacc_cmodel -lgmp "-L$matlabRoot/extern/lib/win64/mingw64" -lmex -lmx -lmat -static-libgcc -static-libstdc++ -o "$vendor/xfft_v9_1_bitacc_mex.mexw64"
if ($LASTEXITCODE -ne 0) { throw 'MEX compilation failed' }
