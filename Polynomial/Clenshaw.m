function [y]=Clenshaw(A, B, C, a, x)
% Evaluates the recursion P_n(x)=(A_n*x+B_n)*P_{n-1}(x)+C_n*P_{n-2}(x)
% Assumes P_0(x)=1 and P_1(x)=x
n=length(a);
A(1:n)=A; B(1:n)=B; C(1:n)=C;
b=zeros(size(x)); bb=b;
for k=n:-1:2
    temp=b;
    b=a(k)+(A(k)*x+B(k)).*b+C(k)*bb;
    bb=temp;
end
y=a(1)+x.*b+C(1)*bb;
end

