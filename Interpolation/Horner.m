function y = Horner(poly, x)
% Efficient polynomial evaluation method.
y=zeros(size(x));
for i=length(poly):-1:1
    y=poly(i)+y.*x;
end
end