% load and plot weather station data
!grep -a "DATA: T=" /tmp/serial.log | awk '{print $6, $9}' | sort -u > /tmp/temp.dat
!grep -a "DATA: H=" /tmp/serial.log | awk '{print $6, $9}' | sort -u > /tmp/hygro.dat
!grep -a INDOOR2 /tmp/serial.log | grep -v packet | awk '{print $6,$8}' > /tmp/in1.dat
%load weather
load /tmp/temp.dat
t1=(temp(:,1)/86400-5/24) + datenum('1 jan 1970');
T=temp(:,2);
load /tmp/hygro.dat
t2=(hygro(:,1)/86400-5/24) + datenum('1 jan 1970');
h=hygro(:,2);
load /tmp/in1.dat
t3=(in1(:,1)/86400-5/24) + datenum('1 jan 1970');
ITF=in1(:,2)*9/5+32;

% plot results
figure(1)
TF=T*9/5+32;
%TF=despike(TF);                         % if despike function is available
h(h<20)=20;                             % can't register h<20%)
h(h>100)=NaN;
% noon each day for past week
%dt=datenum([datestr(now,1) ' 12:00'])+[-7:1:0];
subplot(311)
% plot temperature
h1=plot(t1,TF);
set(h1,'linewidth',2)
datetick('x',6)
axis tight
title('Weather Station Data')
ylabel('Temperature (^\circ F)')
subplot 312
% plot humidity
h2=plot(t2,h);
set(h2,'linewidth',2)
datetick('x',6)
axis tight
ylabel('Relative humidity (%)')
% indoor temperature
subplot 313
h3=plot(t3,ITF);
set(h3,'linewidth',2)
datetick('x',6)
axis tight
ylabel('Indoor T (^\circ C)')
orient tall
% for PNG output
%print -dpng -r150 plot.png

% print stats
Tmax=max(TF(t1>(datenum(now)-1)));
Tmin=min(TF(t1>(datenum(now)-1)));
fprintf('24 hour high %4.1f degF, low %4.1f degF\n',Tmax,Tmin);
fprintf('Current T = %4.1f degF, h = %d\n',TF(length(TF)),h(length(h)));
