function [x, w] = Fejer(a, b, n)
% Returns abscissas and weights for the corresponding Fejer
% n-point quadrature over the interval [a, b].
th=((1:n)-1/2)*pi/n;
x=(b-a)/2*cos(th)+(a+b)/2;
d=1./(1-(0:2:n-2).^2);
d(1)=sqrt(2)/2;
w=idct(d)*(b-a)/sqrt(n);
w=[w, fliplr(w)];
end