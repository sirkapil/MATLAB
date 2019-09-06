function [relres,it,resvec] = adf2(n,ne,nu,opts)
if(nargin==3)
    opts=ones(1,4);
end
opts=[opts(:)',ones(1,4-numel(opts))];
no=opts(1);
ifras=logical(opts(2));
ifneu=logical(opts(3));
ifcrs=logical(opts(4));
ifsweep=no<0;
no=min(max(0,no),1);

% GMRES settings
maxit=50;
tol=1e-10;

% Problem settings
if(nu<0), nu=1./abs(nu); end

UDATA=@(x,y) x.*(1-exp((y-1)/nu))./(1-exp(-2/nu)); FDATA=0; bcbox=[1,1,1,1];
%UDATA=0; FDATA=1; bcbox=[1,0,1,0];
ux=@(x,y,z) 0+0*y.*(1-x.^2);
uy=@(x,y,z) 1-0*x.*(1-y.^2);
uz=@(x,y,z) 0+0*x+0*y;

% Stabilization CFL
CFL=1.0E-2;
%CFL=inf;

function [u]=vel(x,y,z,ijac)
    u=ijac(:,:,:,:,1).*ux(x,y,z)+ijac(:,:,:,:,2).*uy(x,y,z)+ijac(:,:,:,:,3).*uz(x,y,z);
end


ns=n+2*no;
ndim=2;
nfaces=2*ndim;

nex=ne(1);
ney=ne(end);
nel=nex*ney;

[Dhat,zhat,what]=legD(n);
Jfem=[1-zhat, 1+zhat]/2;
F=bubfilt(zhat);

xc=linspace(-1,1,nex+1);
yc=linspace(-1,1,ney+1);
hx=diff(xc)/2;
hy=diff(yc)/2;

x1=zhat*hx+repmat(conv(xc,[1,1]/2,'valid'),n,1);
y1=zhat*hy+repmat(conv(yc,[1,1]/2,'valid'),n,1);
[x,y]=ndgrid(x1,y1);
x=semreshape(x,n,nex,ney);
y=semreshape(y,n,nex,ney);

dx=min(diff(zhat))*min([hx(:);hy(:)]);
dt=CFL*dx;

[hx,hy]=ndgrid(hx,hy);
hx=hx(:);
hy=hy(:);

xm=conv(xc,[1,1]/2,'valid');
ym=conv(yc,[1,1]/2,'valid');
[xm,ym]=ndgrid(xm,ym);
zm=zeros(size(xm));
vx=ux(xm(:),ym(:),zm(:));
vy=uy(xm(:),ym(:),zm(:));


%--------------------------------------------------------------------------
%  Boundary conditions
%--------------------------------------------------------------------------

bc=zeros(nfaces,nel);
bc(:)=2; % Overlap
depth=1:nel;

if(ifsweep)
    dex=repmat((1:nex)',1,ney);
    dey=repmat((1:ney) ,nex,1);
    depth=inf(size(dex));
    ex=[]; ey=[];
    if(vx(1)>=0 && vy(1)==0)
        %depth=dex;
        ex=1;
        ey=(ney)/2;
    elseif(vx(1)==0 && vy(1)>=0)
        %depth=dey;
        ex=(nex)/2;
        ey=1;
    elseif(vx(1)>=0 && vy(1)>=0)
        ex=1;
        ey=1;
    end
    
    for k=1:length(ex)
        depth=min(depth,1+ceil(abs(dex-ex(k))+abs(dey-ey(k))));
    end
    
    bc=reshape(bc,[],nex,ney);
    bc(1,2:end  ,:)=1+(depth(2:end  ,:)<=depth(1:end-1,:)); 
    bc(2,1:end-1,:)=1+(depth(1:end-1,:)<=depth(2:end  ,:)); 
    bc(3,:,2:end  )=1+(depth(:,2:end  )<=depth(:,1:end-1)); 
    bc(4,:,1:end-1)=1+(depth(:,1:end-1)<=depth(:,2:end  )); 
    bc=reshape(bc,[],nel);
    depth=reshape(depth,1,[]);
end

% Override with problem boundaries
bc=reshape(bc,nfaces,nex,ney);
bc(1,  1,:)=bcbox(1); % Left
bc(2,end,:)=bcbox(2); % Right
bc(3,:,1  )=bcbox(3); % Bottom
bc(4,:,end)=bcbox(4); % Top
bc=reshape(bc,nfaces,nel);

% Mask
mask=ones(n*nex,n*ney);
mask(1  ,:)=mask(1  ,:)*(1-bcbox(1));
mask(end,:)=mask(end,:)*(1-bcbox(2));
mask(:,1  )=mask(:,1  )*(1-bcbox(3));
mask(:,end)=mask(:,end)*(1-bcbox(4));
mask=semreshape(mask,n,nex,ney);


%--------------------------------------------------------------------------
%  Coarse grid
%--------------------------------------------------------------------------

cmask=ones(2,2,nex,ney);
cbnd=false(nex+1,ney+1);
if(bcbox(1)==1)
    cmask(1,:,1,:)=0;
    cbnd(1,:)=true;
end
if(bcbox(2)==1)
    cmask(end,:,end,:)=0;
    cbnd(end,:)=true;
end
if(bcbox(3)==1)
    cmask(:,1,:,1)=0;
    cbnd(:,1)=true;
end
if(bcbox(4)==1)
    cmask(:,end,:,end)=0;
    cbnd(:,end)=true;
end
cbnd=cbnd(:);

gidx=repmat((1:2)',1,nex)+repmat(0:nex-1,2,1);
gidy=repmat((1:2)',1,ney)+repmat(0:ney-1,2,1);
[gx,gy]=ndgrid(gidx(:),gidy(:));
gid=gx+((2-1)*nex+1)*(gy-1);
cid=reshape(permute(reshape(gid,2,nex,2,ney),[1,3,2,4]),2,2,nel);

[Acrs,supg] = crs2(cid,hx,hy,nu,vx,vy);
ibnd=(size(Acrs,1)+1)*(find(cbnd)-1)+1;
Acrs(cbnd,:)=0;
Acrs(:,cbnd)=0;
Acrs(ibnd)=1;

%--------------------------------------------------------------------------
%  Forward operator
%--------------------------------------------------------------------------

nxd=ceil(3*n/2); %nxd=n;
nyd=nxd; nzd=1;
if(nxd==n)
    [xq,wq]=deal(zhat,what);
    J=eye(n);
else
    [xq,wq]=gauleg(-1,1,nxd);
    J=legC(zhat,xq);
end
D=J*Dhat;
wq=reshape(kron(wq,wq),[nxd,nxd]);

kx=repmat(1:length(xc),2,1);
ky=repmat(1:length(yc),2,1);
kx=kx(2:end-1);
ky=ky(2:end-1);
[xxc,yyc]=ndgrid(xc(kx),yc(ky),1);
pts=reshape(permute(reshape(xxc+1i*yyc,[2,nex,2,ney]),[1,3,2,4]),[4,nex*ney]);

function [map]=mymap(e,x,y,z)
    rad=[inf;inf;inf;inf];
    w=crvquad(pts([4,3,2,1],e),rad);
    map=[real(w(x,y)); imag(w(x,y)); z];
end

xd=zeros(nxd,nyd,nzd,nel);
yd=zeros(nxd,nyd,nzd,nel);
zd=zeros(nxd,nyd,nzd,nel);
bm1=zeros(nxd,nyd,nzd,nel);
G=zeros(nxd,nyd,nzd,6,nel);
C=zeros(nxd,nyd,nzd,3,nel);
for e=1:nel
% Equation coefficients
coord=@(x,y,z) mymap(e,x,y,z);
[xd(:,:,:,e),yd(:,:,:,e),zd(:,:,:,e),ijac,bm1(:,:,:,e),G(:,:,:,:,e)]=gmfact(ndim,coord,xq,wq);
ud=vel(xd(:,:,:,e),yd(:,:,:,e),zd(:,:,:,e),ijac);
C(:,:,:,1,e)=bm1(:,:,:,e).*ud(:,:,:,1);
C(:,:,:,2,e)=bm1(:,:,:,e).*ud(:,:,:,2);
C(:,:,:,3,e)=bm1(:,:,:,e).*ud(:,:,:,3);
end
G=nu.*G;

mult=1./dssum(ones(n,n,nel));

function [u]=dssum(u)
    sz=size(u);
    u=reshape(u,size(u,1),size(u,2),nex,ney);
    s=u(1,:,2:end,:)+u(end,:,1:end-1,:);
    u(1,:,2:end,:)=s;
    u(end,:,1:end-1,:)=s;
    s=u(:,1,:,2:end)+u(:,end,:,1:end-1);
    u(:,1,:,2:end)=s;
    u(:,end,:,1:end-1)=s;
    u=reshape(u,sz);
end


function [bx]=bfun(x,elems)
    if(nargin==1)
        elems=1:nel;
    end
    bx=reshape(x,n,n,nel);
    for ie=elems
        bx(:,:,ie)=J'*(bm1(:,:,:,ie).*(J*bx(:,:,ie)*J'))*J;
    end
    bx=dssum(bx);
    bx=reshape(bx,size(x));
end

function [au]=afun(u,elems)
    if(nargin==1)
        elems=1:nel;
    end
    sz=size(u);
    u=reshape(u,n,n,nel);
    au=zeros(size(u));
    for ie=elems
        fu=F*u(:,:,ie)*F';
        u_x=D*u(:,:,ie)*J';
        u_y=J*u(:,:,ie)*D';
        au(:,:,ie) = D'*(G(:,:,:,1,ie).*u_x + G(:,:,:,4,ie).*u_y)*J + ...
                     J'*(G(:,:,:,4,ie).*u_x + G(:,:,:,2,ie).*u_y)*D + ...
                     J'*(C(:,:,:,1,ie).*u_x + C(:,:,:,2,ie).*u_y + ...
                     (1/dt)*bm1(:,:,:,ie).*(J*(u(:,:,ie)-fu)*J'))*J;
    end
    au=dssum(au);
    au(:)=mask(:).*au(:);
    au=reshape(au,sz);
end


%--------------------------------------------------------------------------
%  Preconditioner
%--------------------------------------------------------------------------
[A,B]=schwarz2d(n,no,hx,hy,nu,vx,vy,dt,bc,ifneu);

% Schwarz weight
if(ifras)
    wt=ones(n,n,nel);
elseif(no==0)
    wt=ones(n,n,nel);
elseif(no==1)
    wt1=ones(ns,ns,nel);
    wt2=ones(ns,ns,nel);
    wt1=extrude(wt1,0,0.0,wt2,0,1.0);
    wt2=dssum(wt2);
    wt2=extrude(wt2,0,1.0,wt1,0,-1.0);
    wt2=extrude(wt2,2,1.0,wt2,0,1.0);
    wt=wt2(2:end-1,2:end-1,:);
end
wt=dssum(wt);
wt(:)=1./wt(:);
if(ifsweep)
    wt(1,:,bc(1,:)==1)=0;
    wt(n,:,bc(2,:)==1)=0;
    wt(:,1,bc(3,:)==1)=0;
    wt(:,n,bc(4,:)==1)=0;
else
    % Upwinding
    unx=zeros(n,n); unx(1,:)=-1; unx(end,:)=1;
    uny=zeros(n,n); uny(:,1)=-1; uny(:,end)=1;
    for e=1:nel
        wt(:,:,e)=wt(:,:,e).*(1+sign(vx(e)*unx+vy(e)*uny));
    end
end
wt=wt./dssum(wt); % ensure partition of unity
wt(mask==0)=0;

function [v1]=extrude(v1,l1,f1,v2,l2,f2)
    k1=[1+l1,size(v1,1)-l1];
    k2=[1+l2,size(v2,1)-l2];
    v1(k1,2:end-1,:)=f1*v1(k1,2:end-1,:)+f2*v2(k2,2:end-1,:);
    k1=[1+l1,size(v1,2)-l1];
    k2=[1+l2,size(v2,2)-l2];
    v1(2:end-1,k1,:)=f1*v1(2:end-1,k1,:)+f2*v2(2:end-1,k2,:);
end

function [u]=psweep(r)
    visit=zeros(nex,ney);
    im=zeros(length(xc),length(yc));
    figure(2); hv=pcolor(xc,yc,im');
    colormap(gray(2));
    caxis('manual'); caxis([0,1]);
    set(gca,'YDir','normal');
    title('Sweeping');
    
    u=zeros(size(r));
    w=zeros(size(r));
    for is=1:max(depth(:))
        ie=find(depth==is);
        w(:,:,ie)=r(:,:,ie)-w(:,:,ie);
        z=pschwarz(w,ie);
        u(:,:,ie)=u(:,:,ie)+z(:,:,ie);
        u=wt.*u;
        u=dssum(u);

        if(is<max(depth(:)))
            je=find(depth==is|depth==is+1|depth==is+2);
            w=afun(u,je);
        end
        
        visit(ie)=visit(ie)+1;
        im(1:nex,1:ney)=visit;
        set(hv,'CData',im'); drawnow;        
    end
end

function [u]=pschwarz(r,elems)
    if(nargin==1)
        elems=1:size(r,3);
    end
    u=reshape(r,size(A,1),size(B,1),[]);
    for ie=elems
        LA=A(:,:,2,ie)\A(:,:,1,ie);
        LB=B(:,:,2,ie)\B(:,:,1,ie);
        LR=A(:,:,2,ie)\u(:,:,ie)/B(:,:,2,ie)';
        u(:,:,ie)=sylvester(LA,LB',LR);
%         K=kron(B(:,:,2,ie),A(:,:,1,ie))+kron(B(:,:,1,ie),A(:,:,2,ie))+...
%           kron(B(:,:,3,ie),A(:,:,3,ie));        
%         u(:,:,ie)=reshape(K\reshape(u(:,:,ie),[],1),size(u(:,:,ie)));
    end
    u=reshape(u,size(r));
end

function [u]=psmooth(r)
    if(ifsweep)
    u=psweep(reshape(r,n,n,[]));
    elseif(no==0)
    u=pschwarz(reshape(r,n,n,[]));
    elseif(no==1)
    % go to exteded array
    w1=zeros(ns,ns,nel);
    w1(2:end-1,2:end-1,:)=reshape(r,n,n,[]);
    % exchange interior nodes
    w1=extrude(w1,0,0.0,w1,2,1.0);
    w1=dssum(w1);
    w1=extrude(w1,0,1.0,w1,2,-1.0);
    % do the local solves
    w2=pschwarz(w1); 
    if(~ifras)
    % sum overlap region
    w1=extrude(w1,0,0.0,w2,0,1.0);
    w2=dssum(w2);
    w2=extrude(w2,0,1.0,w1,0,-1.0);
    w2=extrude(w2,2,1.0,w2,0,1.0);
    end
    % go back to regular size array
    u=w2(2:end-1,2:end-1,:);
    end
    % sum border nodes    
    u(:)=wt(:).*u(:);
    u=dssum(u);
    u=reshape(u,size(r));
end

function [u]=pcoarse(r)
    sz=size(r);
    r=reshape(r(:).*mult(:),n,n,[]);
    rc=zeros(2,2,size(r,3));
    for ie=1:size(r,3)
        rc(:,:,ie)=Jfem'*r(:,:,ie)*Jfem;
    end
    rc(:)=cmask(:).*rc(:);
    uc=supg(Acrs,rc);
    uc(:)=cmask(:).*uc(:);
    
    u=zeros(size(r));
    for ie=1:size(r,3)
        u(:,:,ie)=Jfem*uc(:,:,ie)*Jfem';
    end
    u=reshape(u,sz);
end


function [u]=pfun(r)
    u=psmooth(r);
    if(ifcrs)
        u=u+pcoarse(r-afun(u));
    end
end

%--------------------------------------------------------------------------

ub=zeros(n,n,nel);
f=zeros(n,n,nel);
if(isfloat(UDATA))
    ub(x==1)=UDATA;
else
    ub(mask==0)=UDATA(x(mask==0),y(mask==0));
end
if(isfloat(FDATA))
    f(:)=FDATA;
else
    f=FDATA(x(mask==0),y(mask==0));
end
b=bfun(f)-afun(ub);

u0=pcoarse(b(:));
u0(:)=0;

restart=maxit;
[u,flag,relres,it,resvec]=gmres(@afun,b(:),restart,tol,1,[],@pfun,u0(:));
% relres=0; resvec=0; u=pfun(b);
it=length(resvec)-1;

for k=1:0
u0=u0+pfun(b(:)-afun(u0));
end
%u=u0;


u=reshape(u,size(ub));
u=u+ub;
%u=UDATA(x,y)-reshape(u,size(x));


figure(2);
semilogy(0:it,resvec*relres/resvec(end),'.-b');
ylim([tol/100,1]);
drawnow;

%return;
figure(1);
semplot2(x,y,u); 
%shading interp; camlight;
%view(2);
colormap(jet(256));
colorbar;
end


function [x]=semreshape(x,n,nex,ney)
    x=permute(reshape(x,n,nex,n,ney),[1,3,2,4]);
end

function []=semplot2(x,y,u)
u=reshape(u,size(u,1),size(u,2),[]);
x=reshape(x,size(u));
y=reshape(y,size(u));
nel = size(u,3);
for e=1:nel
    surf(x(:,:,e),y(:,:,e),u(:,:,e)); hold on; %drawnow;
end
hold off; 
end