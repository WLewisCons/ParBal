function [C,hdr,varnames]=read_ceres(ceres_dir,gldas_matdates,tz,var)
% function to read ceres to go with gldas data
% input
% ceres dir, where the ceres CDF files live
% gldas matdates from output of stackGLDAS, length t
% tz offset (- west/+ east) in fractions of 24
% available every 3 hr starting at 01:30, i.e.
% 1:30,4:30,7:30,10:30,13:30,16:30,19:30,22:30
% so nearest values will be picked.
% var, variables names to retrieve, as a cell e.g.
% {'sfc_comp_sw-down_all_3h','sfc_comp_lw-down_all_3h',...
% 'aux_surfpress_3h'}; for incoming sw,incoming lw,and surface pressure as 3
% as 3hr averages

% output
% C, struct containing ceres info
% hdr, coordinate info
% varnames, names of variables specified by numbers
matdates=gldas_matdates;
%check if all dates are least 3 hr apart and throw error if not

assert(all(diff(matdates)>=3/24),'dates must be 3 hr apart')
    
d=dir(fullfile(ceres_dir,'*.nc'));
C.datevalsLocal=zeros(1,length(matdates));
C.datevalsUTC=zeros(1,length(matdates));
varnames=cell(size(var));
hdr.gridtype='geographic';
for h=1:length(matdates)
    match=false;
    i=1;
    %calculate all ceres times 1 day before and after for buffer
    ceres_times=((floor(matdates(h))-1):3/24:(ceil(matdates(h))+1))+1.5/24;
    %search for closest time to specified times
    [~,idx]=min(abs(ceres_times-matdates(h)));
    while ~match && i <=length(d)
          fname=fullfile(ceres_dir,d(i).name);
          ncid = netcdf.open(fname);
          daterange=netcdf.getVar(ncid,2);
          daterange=datenum(double(daterange)+datenum([2000 3 1]));
        if any(ceres_times(idx)==daterange)
            match=true;
            %zero based indexing for netCDF
            start=find(ceres_times(idx)==daterange)-1;
        elseif i == length(d)
            error('no file matching %s',datestr(matdates(h),'yyyymmdd HH:MM'));
        end
        i=i+1;
        netcdf.close(ncid);
    end
    C.datevalsUTC(h)=ceres_times(idx);
    C.datevalsLocal(h)=ceres_times(idx)+tz;
    for i=1:length(var)
        ncid = netcdf.open(fname);
        var_id=netcdf.inqVarID(ncid,var{i});
        [~,~,dimids,~]  = netcdf.inqVar(ncid,var_id); 
%         varnames{i}=varname;
        %no dashes in struct field names
        varname=strrep(var{i},'-','_');
        varnames{i}=varname;
        sz=zeros(size(dimids));
        for j=1:length(dimids)
            [~, sz(j)] = netcdf.inqDim(ncid,dimids(j));
        end
        if h==1 % allocate for first run
            C.(varname)=zeros([sz(2) sz(1) h]);
            %get grid
            lon=double(netcdf.getVar(ncid,0));
            lat=double(netcdf.getVar(ncid,1));
            % change 0-360 lon to standard conv., i.e. -180 (dateline) to 179
            lon=lon-180;
            hdr.RefMatrix=makerefmat(lon(1),lat(end),lon(2)-lon(1),...
                -(lat(end)-lat(end-1)));
            hdr.RasterReference=refmatToGeoRasterReference(hdr.RefMatrix,[sz(2)...
                sz(1)]);
        end
        %note start is zero based
        x=netcdf.getVar(ncid,var_id,[0 0 start],[sz(1) sz(2) 1]);
        x(x<0)=NaN;
        x=flipud(x');
        %shift PM to dateline
        x=circshift(x,-sz(1)/2,2);
        C.(varname)(:,:,h)=x;
        netcdf.close(ncid);
    end
end
end