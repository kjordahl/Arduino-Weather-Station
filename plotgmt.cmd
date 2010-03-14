#!/bin/sh
#
# GMT script to plot weather station data und update web page
# Label time axis with local time (EST=GMT-5, EDT=GMT-4)
# Requires GMT <http://www.soest.hawaii.edu/gmt>
# and sitecopy <http://www.manyfish.co.uk/sitecopy>

# Kelsey Jordahl
# Time-stamp: <Sun Mar 14 19:37:50 EDT 2010>

# make sure GMT tools are in current path, even running as cron job
GMTHOME=/usr/lib/gmt
export GMTHOME
PATH=$GMTHOME/bin:$PATH
export PATH
DAYS=4		     # number of days to plot (will be rounded up)
# Tell GMT to use Unix time in seconds since 1970
gmtset TIME_UNIT c
#gmtset TIME_EPOCH 1970-01-01T00:00:00    # UTC
#gmtset TIME_EPOCH 1969-12-31T19:00:00 # shift to Unix epoch -5h (EST)
gmtset TIME_EPOCH 1969-12-31T20:00:00 # shift to Unix epoch -4h (EDT)
gmtset CHAR_ENCODING ISOLatin1+
gmtset PLOT_DATE_FORMAT dd-o
gmtset PLOT_CLOCK_FORMAT hh:mm
gmtset ANNOT_FONT_SIZE_PRIMARY +9p
gmtset BASEMAP_AXES WESn
SERIALLOG=/home/kels/lacrosse/serial.log # file to read weather data from
LOGFILE=/tmp/plotgmt.log		 # log output of script
DIR=/home/kels/html/weather
PSFILE=$DIR/plot.ps
MINT=-5
MAXT=25
DATE=`grep -a "DATA: T=" $SERIALLOG | tail -1 | awk '{print $1, $2, $3, $4, $5}'`
TEMPF=`grep -a "DATA: T=" $SERIALLOG | tail -1 | awk '{print $11}'`
HUMID=`grep -a "DATA: H=" $SERIALLOG | tail -1 | awk '{print $9}'`
DEWPOINT=`grep -a "DEWPOINT" $SERIALLOG | tail -1 | awk '{print $10}'`
echo $DATE > $LOGFILE
echo $PWD >> $LOGFILE
echo $PATH >> $LOGFILE
sed s/TEMPF/$TEMPF/ $DIR/template.html | sed s/HUMID/$HUMID/ | sed "s/DATE/$DATE/" | sed s/DEWPOINT/$DEWPOINT/ > $DIR/weather.html
STARTTIME=`date -u +%s -d now-${DAYS}days`
R=`grep -a "DATA: T=" $SERIALLOG | awk '{print $6, $9}' | gmtselect -R${STARTTIME}/1e10/$MINT/$MAXT | minmax -I86400/1 -C | awk '{print "-R" $1+17280 "/" $2+17280 "/" $3 "/" $4+1}'`
echo $R
# Fahrenheit axis options
RF=`echo $R | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/" $3*9/5+32 "/" $4*9/5+32}'`
echo $RF
RH=`echo $R | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/0/100"}'`
echo $RH
gmtset BASEMAP_AXES EN
psbasemap -Y4.5 $RF -JX6t/3 -Bp12Hf1H/5f1:,"\260 F": -P -K -V > $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES WS
grep -a "DATA: T=" $SERIALLOG | awk '{print $6, $9}' | psxy $R -JX6t/3 -ft -P -V -Bp12Hf1H/5:"Outdoor temperature"::,"\260 C": -Bs1D -W10/blue -O -K -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES EN
psbasemap -Y-3.60 $RH -JX6t/3 -Bp12Hf1H/10f1:,"%": -K -O -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES WS
grep -a "DATA: H=" $SERIALLOG | awk '{print $6, $9}' | gmtselect -R0/1e10/19.999/99.999 | psxy $RH -JX6t/3 -ft -P -V -Bp12Hf1H:"Local time (EDT)":/10:"Relative humidity"::,"%": -Bs1D -W10/blue -O >> $PSFILE 2>> $LOGFILE
ps2raster $PSFILE -V -Tg -E100 -D$DIR 2>> $LOGFILE
ps2raster $PSFILE -V -Tf -D$DIR 2>> $LOGFILE
#gv $PSFILE &     # view postscript file
# update remote website (requires that .sitecopyrc is already set up)
sitecopy -u weather
