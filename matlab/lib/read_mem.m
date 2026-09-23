function v=read_mem(path,bits,count)
s=strip(readlines(path));s(s=="")=[];
assert(numel(s)==count,'MEM must contain %d values: %s',count,path);
assert(all(~cellfun('isempty',regexp(cellstr(s),'^[0-9a-fA-F]+$','once'))),'Invalid MEM token');
u=hex2dec(s);assert(all(u<2^bits),'MEM value exceeds bit width');
v=u;v(u>=2^(bits-1))=u(u>=2^(bits-1))-2^bits;
end
