function [xtable,ytable,utable,vtable,typevector] = FFT_multi (image1,image2,interrogationarea,step,...
        subpixfinder,mask_input,roi_input,passes,int2,int3,int4,imdeform,repeat,mask_auto,do_pad)
% the interrogation algorithm based on FFT

warning off
% numel: Number of elements in an array or subscripted array expression
if numel(roi_input)>0 % roi has been given
    xroi=roi_input(1);
    yroi=roi_input(2);
    widthroi=roi_input(3);
    heightroi=roi_input(4);
    image1_roi=double(image1(yroi:yroi+heightroi,xroi:xroi+widthroi));
    image2_roi=double(image2(yroi:yroi+heightroi,xroi:xroi+widthroi));
else % default roi
    xroi=0;
    yroi=0;
    image1_roi=double(image1);
    image2_roi=double(image2);
end
gen_image1_roi = image1_roi;
gen_image2_roi = image2_roi;

if numel(mask_input)>0 % mask has been given
    cellmask=mask_input;
    mask=zeros(size(image1_roi));
    for i=1:size(cellmask,1)
        masklayerx=cellmask{i,1};
        masklayery=cellmask{i,2};
        % poly2mask: onvert region-of-interest polygon to mask
        % BW = poly2mask(xi,yi,m,n)
        mask = mask + poly2mask(masklayerx-xroi,masklayery-yroi,size(image1_roi,1),size(image1_roi,2)); % smaller image and mask shifted
    end
else % no mask by default
    mask=zeros(size(image1_roi));
end
mask(mask>1)=1;
gen_mask = mask;

% limit the range of movement of the center of the interrogation area
miniy=1+(ceil(interrogationarea/2));
minix=1+(ceil(interrogationarea/2));
maxiy=step*(floor(size(image1_roi,1)/step))+1+(ceil(interrogationarea/2))-interrogationarea;
maxix=step*(floor(size(image1_roi,2)/step))+1+(ceil(interrogationarea/2))-interrogationarea;

numelementsy=floor((maxiy-miniy)/step+1);
numelementsx=floor((maxix-minix)/step+1);

LAy=miniy;
LAx=minix;
LUy=size(image1_roi,1)-maxiy;
LUx=size(image1_roi,2)-maxix;
shift4centery=round((LUy-LAy)/2);
shift4centerx=round((LUx-LAx)/2);
% shift4center will be negative if in the unshifted case the left border is bigger than the right border. 
% the vectormatrix is hence not centered on the image. the matrix cannot be shifted more towards the left border 
% because then image2_crop would have a negative index. The only way to center the matrix would be 
% to remove a column of vectors on the right side. but then we weould have less data....((LUx-LAx)/2);
if shift4centery<0 
    shift4centery=0;
end
if shift4centerx<0 
    shift4centerx=0;
end
miniy=miniy+shift4centery;
minix=minix+shift4centerx;
maxix=maxix+shift4centerx;
maxiy=maxiy+shift4centery;

% B = padarray(A,padsize,padval) pads array A where padval specifies a constant value 
% to use for padded elements or a method to replicate array elements
image1_roi=padarray(image1_roi,[ceil(interrogationarea/2) ceil(interrogationarea/2)], min(min(image1_roi)));
image2_roi=padarray(image2_roi,[ceil(interrogationarea/2) ceil(interrogationarea/2)], min(min(image1_roi)));
mask=padarray(mask,[ceil(interrogationarea/2) ceil(interrogationarea/2)],0);

% r = rem(a,b) returns the remainder after division of a by b, where a is the dividend and b is the divisor
if (rem(interrogationarea,2) == 0) % for the subpixel displacement measurement
    SubPixOffset=1;
else
    SubPixOffset=0.5;
end

typevector=ones(numelementsy,numelementsx);


%% MAINLOOP
try % check if used from GUI
    handles=guihandles(getappdata(0,'hgui'));
    GUI_avail=1;
catch %#ok<CTCH>
    GUI_avail=0;
end

% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% divide images by small pictures, new index for image1_roi and image2_roi
% B = repmat(A,r1,...,rN) specifies a list of scalars, r1,..,rN, that describes how copies of A are arranged in each dimension
s0 = (repmat((miniy:step:maxiy)'-1,1,numelementsx) + repmat(((minix:step:maxix)-1)*size(image1_roi,1),numelementsy,1))';
% B = permute(A,order) rearranges the dimensions of A so that they are in the order specified by the vector order
s0 = permute(s0(:), [2 3 1]);
s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi,1),interrogationarea,1);
ss1 = repmat(s1,[1,1,size(s0,3)]) + repmat(s0,[interrogationarea,interrogationarea,1]);
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

image1_cut = image1_roi(ss1);
image2_cut = image2_roi(ss1);

if do_pad==1 && passes == 1 % only on first pass
    % subtract mean to avoid high frequencies at border of correlation:
    image1_cut=image1_cut-mean(mean(image1_cut));
    image2_cut=image2_cut-mean(mean(image2_cut));
    % padding (faster than padarray) to get the linear correlation:
    image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
        zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
    image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
        zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
end
% do fft2:
% Y = fft2(X) returns the two-dimensional Fourier transform of a matrix using a fast Fourier transform algorithm
% ZC = conj(Z) returns the complex conjugate of the elements of Z
% X = ifft2(Y) returns the two-dimensional discrete inverse Fourier transform of a matrix using a fast Fourier transform algorithm
% X = real(Z) returns the real part of the elements of the complex array Z
% fftshift: Shift zero-frequency component to center of spectrum; Y = fftshift(X,dim) operates along the dimension dim of X
% For example, if X is a matrix whose rows represent multiple 1-D transforms, then fftshift(X,2) swaps the halves of each row of X
result_conv = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))),1),2);
if do_pad==1 && passes == 1
    % cropping of correlation matrix:
    result_conv =result_conv((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
end

%% repeated  Correlation in the first pass (might make sense to repeat more often to make it even more robust...)

if repeat == 1 && passes == 1
    ms=round(step/4); % multishift parameter as large as quarter in window (one-quarter rule)
    % Shift left bot
    s0B = (repmat((miniy+ms:step:maxiy+ms)'-1, 1,numelementsx) + repmat(((minix-ms:step:maxix-ms)-1)*size(image1_roi, 1), numelementsy,1))';
    s0B = permute(s0B(:), [2 3 1]);
    s1B = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
    ss1B = repmat(s1B, [1, 1, size(s0B,3)])+repmat(s0B, [interrogationarea, interrogationarea, 1]);
    image1_cutB = image1_roi(ss1B);
    image2_cutB = image2_roi(ss1B);
    if do_pad==1 && passes == 1
        % subtract mean to avoid high frequencies at border of correlation:
        image1_cutB=image1_cutB-mean(mean(image1_cutB));
        image2_cutB=image2_cutB-mean(mean(image2_cutB));
        % padding (faster than padarray) to get the linear correlation:
        image1_cutB=[image1_cutB zeros(interrogationarea,interrogationarea-1,size(image1_cutB,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cutB,3))];
        image2_cutB=[image2_cutB zeros(interrogationarea,interrogationarea-1,size(image2_cutB,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cutB,3))];
    end
    result_convB = fftshift(fftshift(real(ifft2(conj(fft2(image1_cutB)).*fft2(image2_cutB))),1),2);
    if do_pad==1 && passes == 1
        % cropping of correlation matrix:
        result_convB =result_convB((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
    end
    
    % Shift right bot
    s0C = (repmat((miniy+ms:step:maxiy+ms)'-1,1,numelementsx) + repmat(((minix+ms:step:maxix+ms)-1)*size(image1_roi,1),numelementsy,1))';
    s0C = permute(s0C(:), [2 3 1]);
    s1C = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
    ss1C = repmat(s1C, [1, 1, size(s0C,3)])+repmat(s0C, [interrogationarea, interrogationarea, 1]);
    image1_cutC = image1_roi(ss1C);
    image2_cutC = image2_roi(ss1C);
    if do_pad==1 && passes == 1
        % subtract mean to avoid high frequencies at border of correlation:
        image1_cutC=image1_cutC-mean(mean(image1_cutC));
        image2_cutC=image2_cutC-mean(mean(image2_cutC));
        % padding (faster than padarray) to get the linear correlation:
        image1_cutC=[image1_cutC zeros(interrogationarea,interrogationarea-1,size(image1_cutC,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cutC,3))];
        image2_cutC=[image2_cutC zeros(interrogationarea,interrogationarea-1,size(image2_cutC,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cutC,3))];
    end
    result_convC = fftshift(fftshift(real(ifft2(conj(fft2(image1_cutC)).*fft2(image2_cutC))),1),2);
    if do_pad==1 && passes == 1
        % cropping of correlation matrix:
        result_convC =result_convC((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
    end
    
    % Shift left top
    s0D = (repmat((miniy-ms:step:maxiy-ms)'-1,1,numelementsx) + repmat(((minix-ms:step:maxix-ms)-1)*size(image1_roi, 1),numelementsy,1))';
    s0D = permute(s0D(:), [2 3 1]);
    s1D = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi,1),interrogationarea,1);
    ss1D = repmat(s1D,[1,1,size(s0D,3)]) + repmat(s0D,[interrogationarea,interrogationarea,1]);
    image1_cutD = image1_roi(ss1D);
    image2_cutD = image2_roi(ss1D);
    
    if do_pad==1 && passes == 1
        % subtract mean to avoid high frequencies at border of correlation:
        image1_cutD=image1_cutD-mean(mean(image1_cutD));
        image2_cutD=image2_cutD-mean(mean(image2_cutD));
        % padding (faster than padarray) to get the linear correlation:
        image1_cutD=[image1_cutD zeros(interrogationarea,interrogationarea-1,size(image1_cutD,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cutD,3))];
        image2_cutD=[image2_cutD zeros(interrogationarea,interrogationarea-1,size(image2_cutD,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cutD,3))];
    end
    result_convD = fftshift(fftshift(real(ifft2(conj(fft2(image1_cutD)).*fft2(image2_cutD))), 1), 2);
    if do_pad==1 && passes == 1
        % cropping of correlation matrix:
        result_convD =result_convD((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
    end
    
    % Shift right top
    s0E = (repmat((miniy-ms:step:maxiy-ms)'-1,1,numelementsx) + repmat(((minix+ms:step:maxix+ms)-1)*size(image1_roi,1),numelementsy,1))';
    s0E = permute(s0E(:),[2 3 1]);
    s1E = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
    ss1E = repmat(s1E,[1,1,size(s0E,3)]) + repmat(s0E,[interrogationarea,interrogationarea,1]);
    image1_cutE = image1_roi(ss1E);
    image2_cutE = image2_roi(ss1E);
    if do_pad==1 && passes == 1
        % subtract mean to avoid high frequencies at border of correlation:
        image1_cutE=image1_cutE-mean(mean(image1_cutE));
        image2_cutE=image2_cutE-mean(mean(image2_cutE));
        % padding (faster than padarray) to get the linear correlation:
        image1_cutE=[image1_cutE zeros(interrogationarea,interrogationarea-1,size(image1_cutE,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cutE,3))];
        image2_cutE=[image2_cutE zeros(interrogationarea,interrogationarea-1,size(image2_cutE,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cutE,3))];
    end
    result_convE = fftshift(fftshift(real(ifft2(conj(fft2(image1_cutE)).*fft2(image2_cutE))),1),2);
    if do_pad==1 && passes == 1
        % cropping of correlation matrix:
        result_convE =result_convE((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
    end
    result_conv=result_conv.*result_convB.*result_convC.*result_convD.*result_convE;
end

if mask_auto == 1
    % replace the center of the 3x3 matrix with the mean = no autocorrelation
    % MARKER
    h = fspecial('gaussian',3,1.5);
    h=h/h(2,2);
    h=1-h;
    h=repmat(h,1,1,size(result_conv,3));
    h=h.*result_conv((interrogationarea/2)+SubPixOffset-1:(interrogationarea/2)+SubPixOffset+1,...
        (interrogationarea/2)+SubPixOffset-1:(interrogationarea/2)+SubPixOffset+1,:);
    result_conv((interrogationarea/2)+SubPixOffset-1:(interrogationarea/2)+SubPixOffset+1,...
        (interrogationarea/2)+SubPixOffset-1:(interrogationarea/2)+SubPixOffset+1,:)=h;
end

minres = permute(repmat(squeeze(min(min(result_conv))),[1,size(result_conv,1),size(result_conv,2)]),[2 3 1]);
deltares = permute(repmat(squeeze(max(max(result_conv))-min(min(result_conv))),[1,size(result_conv,1),size(result_conv,2)]),[2 3 1]);
result_conv = ((result_conv-minres)./deltares)*255;



%apply mask
ii = mask(ss1(round(interrogationarea/2+1),round(interrogationarea/2+1), :)) ~= 0;
jj = mask((miniy:step:maxiy)+round(interrogationarea/2),(minix:step:maxix)+round(interrogationarea/2)) ~= 0;
typevector(jj) = 0;
result_conv(:,:, ii) = 0;

% [I,J] = ind2sub(siz,IND) returns the matrices I and J containing the equivalent row and column subscripts 
% corresponding to each linear index in the matrix IND for a matrix of size siz
[y, x, z] = ind2sub(size(result_conv),find(result_conv==255));

% we need only one peak from each couple pictures
[z1, zi] = sort(z);
dz1 = [z1(1); diff(z1)];
i0 = find(dz1~=0);
x1 = x(zi(i0));
y1 = y(zi(i0));
z1 = z(zi(i0));

xtable = repmat((minix:step:maxix)+interrogationarea/2,length(miniy:step:maxiy),1);
ytable = repmat(((miniy:step:maxiy)+interrogationarea/2)',1,length(minix:step:maxix));

if subpixfinder==1
    [vector] = SUBPIXGAUSS (result_conv,interrogationarea,x1,y1,z1,SubPixOffset);
elseif subpixfinder==2
    [vector] = SUBPIX2DGAUSS (result_conv,interrogationarea,x1,y1,z1,SubPixOffset);
end
vector = permute(reshape(vector,[size(xtable') 2]),[2 1 3]);

utable = vector(:,:,1);
vtable = vector(:,:,2);


% multipass
% determine how many passes, if interrogationarea = 0 then no pass.
for multipass=1:passes-1
    
    if GUI_avail==1
        set(handles.progress, 'string' , ['Frame progress: ' ...
            int2str(1i/maxiy*100/passes+((multipass-1)*(100/passes))) '%' newline 'Validating velocity field']);drawnow;
    else
        fprintf('.');
    end
    % multipass validation, smoothing
    % stdev test
    utable_orig=utable;
    vtable_orig=vtable;
    stdthresh=4;
    meanu=nanmean(nanmean(utable));
    meanv=nanmean(nanmean(vtable));
    std2u=nanstd(reshape(utable,size(utable,1)*size(utable,2),1));
    std2v=nanstd(reshape(vtable,size(vtable,1)*size(vtable,2),1));
    minvalu=meanu-stdthresh*std2u;
    maxvalu=meanu+stdthresh*std2u;
    minvalv=meanv-stdthresh*std2v;
    maxvalv=meanv+stdthresh*std2v;
    utable(utable<minvalu)=NaN;
    utable(utable>maxvalu)=NaN;
    vtable(vtable<minvalv)=NaN;
    vtable(vtable>maxvalv)=NaN;
    
    % median test
    % info1=[];
    epsilon=0.02;
    thresh=2;
    [J,I]=size(utable);
    % medianres=zeros(J,I);
    normfluct=zeros(J,I,2);
    b=1;
    % eps=0.1;
    for c=1:2
        if c==1
            velcomp=utable;
        else
            velcomp=vtable;
        end
        
        clear neigh
        for ii = -b:b
            for jj = -b:b
                neigh(:, :, ii+2*b, jj+2*b)=velcomp((1+b:end-b)+ii, (1+b:end-b)+jj); %#ok<*AGROW>
            end
        end
        
        neighcol = reshape(neigh, size(neigh,1), size(neigh,2), (2*b+1)^2);
        neighcol2= neighcol(:,:, [(1:(2*b+1)*b+b) ((2*b+1)*b+b+2:(2*b+1)^2)]);
        neighcol2 = permute(neighcol2, [3, 1, 2]);
        med=median(neighcol2);
        velcomp = velcomp((1+b:end-b), (1+b:end-b));
        fluct=velcomp-permute(med, [2 3 1]);
        res=neighcol2-repmat(med, [(2*b+1)^2-1, 1,1]);
        medianres=permute(median(abs(res)), [2 3 1]);
        normfluct((1+b:end-b), (1+b:end-b), c)=abs(fluct./(medianres+epsilon));
    end
    
    
    info1=(sqrt(normfluct(:,:,1).^2+normfluct(:,:,2).^2)>thresh);
    utable(info1==1)=NaN;
    vtable(info1==1)=NaN;
    
    if GUI_avail==1
        if verLessThan('matlab','8.4')
            delete (findobj(getappdata(0,'hgui'),'type', 'hggroup'))
        else
            delete (findobj(getappdata(0,'hgui'),'type', 'quiver'))
        end
        hold on;
        vecscale=str2double(get(handles.vectorscale,'string'));
        % Problem: if colorbar, this also counts as axes...
        colorbar('off')
        quiver ((findobj(getappdata(0,'hgui'),'type', 'axes')),xtable(isnan(utable)==0)+xroi-interrogationarea/2,...
            ytable(isnan(utable)==0)+yroi-interrogationarea/2,utable_orig(isnan(utable)==0)*vecscale,vtable_orig(isnan(utable)==0)*vecscale,...
            'Color', [0.15 0.7 0.15],'autoscale','off')
        quiver ((findobj(getappdata(0,'hgui'),'type', 'axes')),xtable(isnan(utable)==1)+xroi-interrogationarea/2,...
            ytable(isnan(utable)==1)+yroi-interrogationarea/2,utable_orig(isnan(utable)==1)*vecscale,vtable_orig(isnan(utable)==1)*vecscale,...
            'Color',[0.7 0.15 0.15], 'autoscale','off')
        drawnow
        hold off
    end
    
    % replace nans
    utable=inpaint_nans(utable,4);
    vtable=inpaint_nans(vtable,4);
    % smooth predictor
    try
        if multipass<passes-1
            utable = smoothn(utable,0.6); % stronger smoothing for first passes
            vtable = smoothn(vtable,0.6);
        else
            utable = smoothn(utable); % weaker smoothing for last pass
            vtable = smoothn(vtable);
        end
    catch
        
        % old matlab versions: gaussian kernel
        h=fspecial('gaussian',5,1);
        utable=imfilter(utable,h,'replicate');
        vtable=imfilter(vtable,h,'replicate');
    end
    
    if multipass==1
        interrogationarea=round(int2/2)*2;
    end
    if multipass==2
        interrogationarea=round(int3/2)*2;
    end
    if multipass==3
        interrogationarea=round(int4/2)*2;
    end
    step=interrogationarea/2;    
    
    image1_roi = gen_image1_roi;
    image2_roi = gen_image2_roi;
    mask = gen_mask;
    
    
    miniy=1+(ceil(interrogationarea/2));
    minix=1+(ceil(interrogationarea/2));
    maxiy=step*(floor(size(image1_roi,1)/step))-(interrogationarea-1)+(ceil(interrogationarea/2));
    maxix=step*(floor(size(image1_roi,2)/step))-(interrogationarea-1)+(ceil(interrogationarea/2));
    
    numelementsy=floor((maxiy-miniy)/step+1);
    numelementsx=floor((maxix-minix)/step+1);
    
    LAy=miniy;
    LAx=minix;
    LUy=size(image1_roi,1)-maxiy;
    LUx=size(image1_roi,2)-maxix;
    shift4centery=round((LUy-LAy)/2);
    shift4centerx=round((LUx-LAx)/2);
    if shift4centery<0 
        shift4centery=0;
    end
    if shift4centerx<0 
        shift4centerx=0;
    end
    miniy=miniy+shift4centery;
    minix=minix+shift4centerx;
    maxix=maxix+shift4centerx;
    maxiy=maxiy+shift4centery;
    
    image1_roi=padarray(image1_roi,[ceil(interrogationarea/2) ceil(interrogationarea/2)], min(min(image1_roi)));
    image2_roi=padarray(image2_roi,[ceil(interrogationarea/2) ceil(interrogationarea/2)], min(min(image1_roi)));
    mask=padarray(mask,[ceil(interrogationarea/2) ceil(interrogationarea/2)],0);
    if (rem(interrogationarea,2) == 0) % for the subpixel displacement measurement
        SubPixOffset=1;
    else
        SubPixOffset=0.5;
    end
    
    xtable_old=xtable;
    ytable_old=ytable;
    typevector=ones(numelementsy,numelementsx);
    xtable = repmat((minix:step:maxix), numelementsy, 1) + interrogationarea/2;
    ytable = repmat((miniy:step:maxiy)', 1, numelementsx) + interrogationarea/2;
    
    % xtable old and new give coordinates where the vectors come from
    if GUI_avail==1
        set(handles.progress, 'string' , ['Frame progress: ' int2str(1i/maxiy*100/passes+((multipass-1)*(100/passes))) ...
            '%' newline 'Interpolating velocity field']);drawnow;
    else
        fprintf('.');
    end
    
    utable=interp2(xtable_old,ytable_old,utable,xtable,ytable,'*spline');
    vtable=interp2(xtable_old,ytable_old,vtable,xtable,ytable,'*spline');
    
    utable_1= padarray(utable, [1,1], 'replicate');
    vtable_1= padarray(vtable, [1,1], 'replicate');
    
    % add 1 line around image for border regions... linear extrap    
    firstlinex=xtable(1,:);
    firstlinex_intp=interp1(1:1:size(firstlinex,2),firstlinex,0:1:size(firstlinex,2)+1,'linear','extrap');
    xtable_1=repmat(firstlinex_intp,size(xtable,1)+2,1);
    
    firstliney=ytable(:,1);
    firstliney_intp=interp1(1:1:size(firstliney,1),firstliney,0:1:size(firstliney,1)+1,'linear','extrap')';
    ytable_1=repmat(firstliney_intp,1,size(ytable,2)+2);
    
    X=xtable_1; % original locations of vectors in whole image
    Y=ytable_1;
    U=utable_1; % interesting portion of u
    V=vtable_1; % "" of v
    
    X1=X(1,1):1:X(1,end)-1;
    Y1=(Y(1,1):1:Y(end,1)-1)';
    X1=repmat(X1,size(Y1, 1),1);
    Y1=repmat(Y1,1,size(X1, 2));
    
    U1 = interp2(X,Y,U,X1,Y1,'*linear');
    V1 = interp2(X,Y,V,X1,Y1,'*linear');
    % linear is 3x faster and looks ok...
    image2_crop_i1 = interp2(1:size(image2_roi,2),(1:size(image2_roi,1))',double(image2_roi),X1+U1,Y1+V1,imdeform); 
    
    xb = find(X1(1,:) == xtable_1(1,1));
    yb = find(Y1(:,1) == ytable_1(1,1));
    
    % divide images by small pictures
    % new index for image1_roi
    s0 = (repmat((miniy:step:maxiy)'-1, 1,numelementsx) + repmat(((minix:step:maxix)-1)*size(image1_roi, 1), numelementsy,1))';
    s0 = permute(s0(:), [2 3 1]);
    s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
    ss1 = repmat(s1, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
    % new index for image2_crop_i1
    s0 = (repmat(yb-step+step*(1:numelementsy)'-1, 1,numelementsx) + repmat((xb-step+step*(1:numelementsx)-1)*size(image2_crop_i1, 1), numelementsy,1))';
    s0 = permute(s0(:), [2 3 1]) - s0(1);
    s2 = repmat((1:2*step)',1,2*step) + repmat(((1:2*step)-1)*size(image2_crop_i1, 1),2*step,1);
    ss2 = repmat(s2, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
    
    
    image1_cut = image1_roi(ss1);
    image2_cut = image2_crop_i1(ss2);
    if do_pad==1 && multipass==passes-1
        % subtract mean to avoid high frequencies at border of correlation:
        image1_cut=image1_cut-mean(mean(image1_cut));
        image2_cut=image2_cut-mean(mean(image2_cut));
        % padding (faster than padarray) to get the linear correlation:
        image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
        image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
            zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
    end
    % do fft2:
    result_conv = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))), 1), 2);
    if do_pad==1 && multipass==passes-1
        % cropping of correlation matrix:
        result_conv =result_conv((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
    end
    
    %% repeated correlation
    if repeat == 1 && multipass==passes-1
        ms=round(step/4); % one-quarter rule
        
        % Shift left bot
        % linear is 3x faster and looks ok...
        image2_crop_i1 = interp2(1:size(image2_roi,2),(1:size(image2_roi,1))',double(image2_roi),X1+U1-ms,Y1+V1+ms,imdeform); 
        xb = find(X1(1,:) == xtable_1(1,1));
        yb = find(Y1(:,1) == ytable_1(1,1));
        s0 = (repmat((miniy+ms:step:maxiy+ms)'-1, 1,numelementsx) + repmat(((minix-ms:step:maxix-ms)-1)*size(image1_roi, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]);
        s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
        ss1 = repmat(s1, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        s0 = (repmat(yb-step+step*(1:numelementsy)'-1,1,numelementsx) + ...
            repmat((xb-step+step*(1:numelementsx)-1)*size(image2_crop_i1, 1),numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]) - s0(1);
        s2 = repmat((1:2*step)',1,2*step) + repmat(((1:2*step)-1)*size(image2_crop_i1, 1),2*step,1);
        ss2 = repmat(s2, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        image1_cut = image1_roi(ss1);
        image2_cut = image2_crop_i1(ss2);
        if do_pad==1 && multipass==passes-1
            % subtract mean to avoid high frequencies at border of correlation:
            image1_cut=image1_cut-mean(mean(image1_cut));
            image2_cut=image2_cut-mean(mean(image2_cut));
            % padding (faster than padarray) to get the linear correlation:
            image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
            image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
        end
        result_convB = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))), 1), 2);
        if do_pad==1 && multipass==passes-1
            %cropping of correlation matrix:
            result_convB =result_convB((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
        end       
        
        % Shift right bot
        image2_crop_i1 = interp2(1:size(image2_roi,2),(1:size(image2_roi,1))',double(image2_roi),X1+U1+ms,Y1+V1+ms,imdeform);
        xb = find(X1(1,:) == xtable_1(1,1));
        yb = find(Y1(:,1) == ytable_1(1,1));
        s0 = (repmat((miniy+ms:step:maxiy+ms)'-1, 1,numelementsx) + repmat(((minix+ms:step:maxix+ms)-1)*size(image1_roi, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]);
        s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
        ss1 = repmat(s1, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        s0 = (repmat(yb-step+step*(1:numelementsy)'-1, 1,numelementsx) + ...
            repmat((xb-step+step*(1:numelementsx)-1)*size(image2_crop_i1, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]) - s0(1);
        s2 = repmat((1:2*step)',1,2*step) + repmat(((1:2*step)-1)*size(image2_crop_i1, 1),2*step,1);
        ss2 = repmat(s2, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        image1_cut = image1_roi(ss1);
        image2_cut = image2_crop_i1(ss2);
        if do_pad==1 && multipass==passes-1
            % subtract mean to avoid high frequencies at border of correlation:
            image1_cut=image1_cut-mean(mean(image1_cut));
            image2_cut=image2_cut-mean(mean(image2_cut));
            % padding (faster than padarray) to get the linear correlation:
            image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
            image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
        end
        result_convC = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))), 1), 2);
        if do_pad==1 && multipass==passes-1
            % cropping of correlation matrix:
            result_convC =result_convC((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
        end
        % Shift left top
        image2_crop_i1 = interp2(1:size(image2_roi,2),(1:size(image2_roi,1))',double(image2_roi),X1+U1-ms,Y1+V1-ms,imdeform); 
        xb = find(X1(1,:) == xtable_1(1,1));
        yb = find(Y1(:,1) == ytable_1(1,1));
        s0 = (repmat((miniy-ms:step:maxiy-ms)'-1, 1,numelementsx) + repmat(((minix-ms:step:maxix-ms)-1)*size(image1_roi, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]);
        s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
        ss1 = repmat(s1, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        s0 = (repmat(yb-step+step*(1:numelementsy)'-1, 1,numelementsx) + ...
            repmat((xb-step+step*(1:numelementsx)-1)*size(image2_crop_i1, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]) - s0(1);
        s2 = repmat((1:2*step)',1,2*step) + repmat(((1:2*step)-1)*size(image2_crop_i1, 1),2*step,1);
        ss2 = repmat(s2, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        image1_cut = image1_roi(ss1);
        image2_cut = image2_crop_i1(ss2);
        if do_pad==1 && multipass==passes-1
            % subtract mean to avoid high frequencies at border of correlation:
            image1_cut=image1_cut-mean(mean(image1_cut));
            image2_cut=image2_cut-mean(mean(image2_cut));
            % padding (faster than padarray) to get the linear correlation:
            image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
            image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
        end
        result_convD = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))), 1), 2);
        if do_pad==1 && multipass==passes-1
            %cropping of correlation matrix:
            result_convD =result_convD((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
        end
        %Shift right top
        image2_crop_i1 = interp2(1:size(image2_roi,2),(1:size(image2_roi,1))',double(image2_roi),X1+U1+ms,Y1+V1-ms,imdeform); 
        xb = find(X1(1,:) == xtable_1(1,1));
        yb = find(Y1(:,1) == ytable_1(1,1));
        s0 = (repmat((miniy-ms:step:maxiy-ms)'-1, 1,numelementsx) + repmat(((minix+ms:step:maxix+ms)-1)*size(image1_roi, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]);
        s1 = repmat((1:interrogationarea)',1,interrogationarea) + repmat(((1:interrogationarea)-1)*size(image1_roi, 1),interrogationarea,1);
        ss1 = repmat(s1, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        s0 = (repmat(yb-step+step*(1:numelementsy)'-1, 1,numelementsx) + ...
            repmat((xb-step+step*(1:numelementsx)-1)*size(image2_crop_i1, 1), numelementsy,1))';
        s0 = permute(s0(:), [2 3 1]) - s0(1);
        s2 = repmat((1:2*step)',1,2*step) + repmat(((1:2*step)-1)*size(image2_crop_i1, 1),2*step,1);
        ss2 = repmat(s2, [1, 1, size(s0,3)]) + repmat(s0, [interrogationarea, interrogationarea, 1]);
        image1_cut = image1_roi(ss1);
        image2_cut = image2_crop_i1(ss2);
        if do_pad==1 && multipass==passes-1
            % subtract mean to avoid high frequencies at border of correlation:
            image1_cut=image1_cut-mean(mean(image1_cut));
            image2_cut=image2_cut-mean(mean(image2_cut));
            % padding (faster than padarray) to get the linear correlation:
            image1_cut=[image1_cut zeros(interrogationarea,interrogationarea-1,size(image1_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image1_cut,3))];
            image2_cut=[image2_cut zeros(interrogationarea,interrogationarea-1,size(image2_cut,3)); ...
                zeros(interrogationarea-1,2*interrogationarea-1,size(image2_cut,3))];
        end
        result_convE = fftshift(fftshift(real(ifft2(conj(fft2(image1_cut)).*fft2(image2_cut))), 1), 2);
        if do_pad==1 && multipass==passes-1
            % cropping of correlation matrix:
            result_convE =result_convE((interrogationarea/2):(3*interrogationarea/2)-1,(interrogationarea/2):(3*interrogationarea/2)-1,:);
        end
        result_conv=result_conv.*result_convB.*result_convC.*result_convD.*result_convE;
    end    
    
    if mask_auto == 1
        % limit peak search arena....
        emptymatrix=zeros(size(result_conv,1),size(result_conv,2),size(result_conv,3));
        % emptymatrix=emptymatrix+0.1;
        sizeones=4;
        
        % h = fspecial('gaussian', sizeones*2+1,1);
        h=fspecial('disk',4);
        
        
        h=h/max(max(h));
        h=repmat(h,1,1,size(result_conv,3));
        emptymatrix((interrogationarea/2)+SubPixOffset-sizeones:(interrogationarea/2)+SubPixOffset+sizeones,...
            (interrogationarea/2)+SubPixOffset-sizeones:(interrogationarea/2)+SubPixOffset+sizeones,:)=h;
        result_conv = result_conv .* emptymatrix;
    end
    %do fft2
    
    minres = permute(repmat(squeeze(min(min(result_conv))), [1, size(result_conv, 1), size(result_conv, 2)]), [2 3 1]);
    deltares = permute(repmat(squeeze(max(max(result_conv))-min(min(result_conv))), [1, size(result_conv, 1), size(result_conv, 2)]), [2 3 1]);
    result_conv = ((result_conv-minres)./deltares)*255;
    
    %apply mask
    ii = mask(ss1(round(interrogationarea/2+1), round(interrogationarea/2+1), :))~=0;
    jj = mask((miniy:step:maxiy)+round(interrogationarea/2), (minix:step:maxix)+round(interrogationarea/2))~=0;
    typevector(jj) = 0;
    result_conv(:,:, ii) = 0;
    
    [y, x, z] = ind2sub(size(result_conv), find(result_conv==255));
    [z1, zi] = sort(z);
    % we need only one peak from each couple pictures
    dz1 = [z1(1); diff(z1)];
    i0 = find(dz1~=0);
    x1 = x(zi(i0));
    y1 = y(zi(i0));
    z1 = z(zi(i0));
    
    % new xtable and ytable
    xtable = repmat((minix:step:maxix)+interrogationarea/2, length(miniy:step:maxiy), 1);
    ytable = repmat(((miniy:step:maxiy)+interrogationarea/2)', 1, length(minix:step:maxix));
    
    if subpixfinder==1
        [vector] = SUBPIXGAUSS (result_conv,interrogationarea, x1, y1, z1,SubPixOffset);
    elseif subpixfinder==2
        [vector] = SUBPIX2DGAUSS (result_conv,interrogationarea, x1, y1, z1,SubPixOffset);
    end
    vector = permute(reshape(vector, [size(xtable') 2]), [2 1 3]);
    
    utable = utable+vector(:,:,1);
    vtable = vtable+vector(:,:,2);
    
end

xtable=xtable-ceil(interrogationarea/2);
ytable=ytable-ceil(interrogationarea/2);

xtable=xtable+xroi;
ytable=ytable+yroi;

function [vector] = SUBPIXGAUSS(result_conv, interrogationarea, x, y, z, SubPixOffset)

xi = find(~((x <= (size(result_conv,2)-1)) & (y <= (size(result_conv,1)-1)) & (x >= 2) & (y >= 2)));
x(xi) = [];
y(xi) = [];
z(xi) = [];
xmax = size(result_conv, 2);
vector = NaN(size(result_conv,3), 2);
if(numel(x)~=0)
    ip = sub2ind(size(result_conv), y, x, z);
    % the following 8 lines are copyright (c) 1998, Uri Shavit, Roi Gurka, Alex Liberzon
    % http://urapiv.wordpress.com
    f0 = log(result_conv(ip));
    f1 = log(result_conv(ip-1));
    f2 = log(result_conv(ip+1));
    peaky = y + (f1-f2)./(2*f1-4*f0+2*f2);
    f0 = log(result_conv(ip));
    f1 = log(result_conv(ip-xmax));
    f2 = log(result_conv(ip+xmax));
    peakx = x + (f1-f2)./(2*f1-4*f0+2*f2);
    
    SubpixelX=peakx-(interrogationarea/2)-SubPixOffset;
    SubpixelY=peaky-(interrogationarea/2)-SubPixOffset;
    vector(z, :) = [SubpixelX, SubpixelY];
end

function [vector] = SUBPIX2DGAUSS(result_conv, interrogationarea, x, y, z, SubPixOffset)
xi = find(~((x <= (size(result_conv,2)-1)) & (y <= (size(result_conv,1)-1)) & (x >= 2) & (y >= 2)));
x(xi) = [];
y(xi) = [];
z(xi) = [];
xmax = size(result_conv, 2);
vector = NaN(size(result_conv,3), 2);
if(numel(x)~=0)
    c10 = zeros(3,3, length(z));
    c01 = c10;
    c11 = c10;
    c20 = c10;
    c02 = c10;
    ip = sub2ind(size(result_conv), y, x, z);
    
    for i = -1:1
        for j = -1:1
            % following 15 lines based on
            % H. Nobach & M. Honkanen (2005)
            % Two-dimensional Gaussian regression for sub-pixel displacement estimation in particle image velocimetry
            c10(j+2,i+2, :) = i*log(result_conv(ip+xmax*i+j));
            c01(j+2,i+2, :) = j*log(result_conv(ip+xmax*i+j));
            c11(j+2,i+2, :) = i*j*log(result_conv(ip+xmax*i+j));
            c20(j+2,i+2, :) = (3*i^2-2)*log(result_conv(ip+xmax*i+j));
            c02(j+2,i+2, :) = (3*j^2-2)*log(result_conv(ip+xmax*i+j));
            %c00(j+2,i+2)=(5-3*i^2-3*j^2)*log(result_conv_norm(maxY+j, maxX+i));
        end
    end
    c10 = (1/6)*sum(sum(c10));
    c01 = (1/6)*sum(sum(c01));
    c11 = (1/4)*sum(sum(c11));
    c20 = (1/6)*sum(sum(c20));
    c02 = (1/6)*sum(sum(c02));
    %c00=(1/9)*sum(sum(c00));
    
    deltax = squeeze((c11.*c01-2*c10.*c02)./(4*c20.*c02-c11.^2));
    deltay = squeeze((c11.*c10-2*c01.*c20)./(4*c20.*c02-c11.^2));
    peakx = x+deltax;
    peaky = y+deltay;
    
    SubpixelX = peakx-(interrogationarea/2)-SubPixOffset;
    SubpixelY = peaky-(interrogationarea/2)-SubPixOffset;
    
    vector(z, :) = [SubpixelX, SubpixelY];
end
