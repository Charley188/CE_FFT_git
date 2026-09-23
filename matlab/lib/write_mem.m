function write_mem(path,v,bits)
assert(all(isfinite(v)) && all(v==fix(v)));
f=fopen(path,'w');assert(f>=0);c=onCleanup(@()fclose(f));
fmt=sprintf('%%0%dX\n',ceil(bits/4));fprintf(f,fmt,mod(v,2^bits));
end
