% load raw data on serrano
%!grep -a RAW serial.log | awk '{print $6,$8}' > raw.dat
% load raw data on poblano
%!grep -a RAW /Volumes/kels/lacrosse/serial.log.1 | awk '{print $6,$8}' | tail --line=+4 >> raw.dat
!grep -a RAW /Volumes/kels/lacrosse/serial.log | awk '{print $6,$8}' > raw.dat
!grep -a INDOOR2 /Volumes/kels/lacrosse/serial.log | awk '{print $6,$8}' > /tmp/in1.dat
pktstart=hex2bin('0A');                 % start of packet binary string
fid=fopen('raw.dat');
%clear T h
load weather
prev=length(t);
lastt=t(prev);
j=prev+1;

data=textscan(fid,'%d %s');
%ts=data{1};
%t=[t; datenum('1 jan 1970')+double(data{1})/86400-5/24];
tmp=datenum('1 jan 1970')+double(data{1})/86400-5/24;
hex=data{2};

idx=find(tmp>lastt)';
rd=0;

for k = (idx),
  T(j)=NaN; h(j)=NaN; t(j)=tmp(k);
%  fprintf('%s %s\n',datestr(t(j)),hex{j});
  % binary equivalent
  binstr=hex2bin(cell2mat(hex(k)));
  b=logical(str2num(binstr'))';
  i=1;
  while (i < (length(b)-44)),
    if(strcmp(binstr(i:i+7),pktstart)),
      % possible packet start
      pkt=binstr(i:i+43);
      npkt=bin2dec(reshape(pkt,4,11)');    % nibbles to numeric values
      hpkt=dec2hex(npkt)';
%      fprintf('Packet start: %s ',hpkt);
      chk=mod(sum(npkt(2:10)),16);
      if (chk==npkt(11)),
        if (npkt(3)==0),                        % temperature data
 %         fprintf('T data\n');
          if (npkt(6)==npkt(9) & npkt(7)==npkt(10)),
            T(j)=npkt(6)*10-50+npkt(7)+npkt(8)/10;
            i=i+41;
            rd=1;
          else                          % digits don't match
            i=i+1;
          end
        elseif (npkt(3)==14),                        % hygro data
%          fprintf('H data\n');
          if (npkt(6)==npkt(9) & npkt(7)==npkt(10)),
            h(j)=npkt(6)*10+npkt(7);
            i=i+41;
            rd=1;
          else
            i=i+1;
          end
        else
          fprintf('no data\n');
          i=i+1;
        end
      else                              % checksum fail
%        disp('Checksum fail');
        i=i+1;
      end
    else                                % no match at beginning
      i=i+1;
    end
  end
  if (rd),                              % only incremnt if a value
    j=j+1;                              % was read
    rd=0;
  end
end


% plot results
figure(1)
idx1=~isnan(T);
idx2=~isnan(h);
idx1(T<-40)=0;
TF=T(idx1)*9/5+32;
idx2(h<20)=0;
t1=t(idx1);
t2=t(idx2);
% noon each day for past week
dt=datenum([datestr(now,1) ' 12:00'])+[-7:1:0];
iw1=t1>(datenum(now)-7);                    % last week
iw2=t2>(datenum(now)-7);                    % last week
figure(1)
subplot(211)
% plot temperature
h1=plot(t1(iw1),TF(iw1));
set(h1,'linewidth',2)
% plot dewpoint
%plot(t(id),TF(id),'.',t(id),dew(id),'.')
datetick('x','dd mmm')
xlim=get(gca,'xlim');
%dt=dt(dt>min(xlim));
set(gca,'xtick',dt)
set(gca,'xlim',[min(t) max(t)])
axis tight
title('Weather Station Data')
ylabel('Temperature (^\circ F)')
subplot 212
% plot humidity
hp=h(idx2);                              % data values only
h2=plot(t2(iw2),hp(iw2));
set(h2,'linewidth',2)
axis tight
datetick('x','dd mmm')
set(gca,'xtick',dt)
set(gca,'xlim',[min(t) max(t)])
axis tight
ylabel('Relative humidity (%)')
relabel
orient tall
%print -dpng -r150 plot.png

% indoor temperature
figure(2)
load /tmp/in1.dat
plot(in1(:,1)/86400-5/24,in1(:,2))
datetick('x',6)

% print stats
Tmax=max(TF(t1>(datenum(now)-1)));
Tmin=min(TF(t1>(datenum(now)-1)));
fprintf('24 hour high %4.1f degF, low %4.1f degF\n',Tmax,Tmin);
fprintf('Current T = %4.1f degF, h = %d\n',TF(length(TF)),h(length(h)));
