#!/bin/sh
#
# GMT script to plot weather station data und update web page
# Label time axis with local time (EST=GMT-5, EDT=GMT-4)
# Requires GMT <http://www.soest.hawaii.edu/gmt>
# and sitecopy <http://www.manyfish.co.uk/sitecopy>

# Kelsey Jordahl
# Time-stamp: <Fri Aug  6 16:05:06 EDT 2010>

# make sure GMT tools are in current path, even running as cron job
GMTHOME=/usr/lib/gmt
export GMTHOME
PATH=$GMTHOME/bin:$PATH
export PATH

DAYS=4		     # number of days to plot (will be rounded up)

# set GMT defaults
gmtset TIME_UNIT c     # Tell GMT to use Unix time in seconds since 1970
gmtset CHAR_ENCODING ISOLatin1+
gmtset PLOT_DATE_FORMAT dd-o
gmtset PLOT_CLOCK_FORMAT hh:mm
gmtset ANNOT_FONT_SIZE_PRIMARY +9p
gmtset BASEMAP_AXES WESn
gmtset D_FORMAT %.12g

# Handle DST - doesn't really handle time zones, assume Eastern
TZ=`date '+%Z'`	       # name of current time zone
TZ_OFFSET=`date '+%::z'` # current time zone offset
#gmtset TIME_EPOCH 1970-01-01T00:00:00    # UTC
if [ $TZ = "EDT" ]; then
    gmtset TIME_EPOCH 1969-12-31T20:00:00 # shift to Unix epoch -4h (EDT)
else
    if [ $TZ != "EST" ]; then
	echo "Don't know time zone $TZ; assuming EST (-0400)"
	TZ="EST"
    fi
    gmtset TIME_EPOCH 1969-12-31T19:00:00 # shift to Unix epoch -5h (EST)
fi

# concatenate two most recent logfiles
cat /home/kels/lacrosse/serial.log.0 /home/kels/lacrosse/serial.log > /tmp/serial.log
SERIALLOG=/tmp/serial.log # file to read weather data from
#SERIALLOG=/home/kels/lacrosse/serial.log # file to read weather data from
LOGFILE=/tmp/plotgmt.log		 # log output of script
DIR=/home/kels/html/weather
#DIR=/home/kels/lacrosse
PSFILE=$DIR/plot.ps
MINT=-40
MAXT=40
MINP=1002
MAXP=1022
DATE=`grep -a "DATA: T=" $SERIALLOG | tail -1 | awk '{print $1, $2, $3, $4, $5}'`
TEMPF=`grep -a "DATA: T=" $SERIALLOG | tail -1 | awk '{print $11}'`
HUMID=`grep -a "DATA: H=" $SERIALLOG | tail -1 | awk '{print $9}'`
DEWPOINT=`grep -a "DEWPOINT" $SERIALLOG | tail -1 | awk '{print $10}'`
PRESS=`grep -a "DATA: P= [0-9]\{5,\} " $SERIALLOG | tail -1 | awk '{print $9}' | gmtmath STDIN 1 139 44330 DIV SUB 5.255 POW DIV 100 DIV = | awk '{printf "%6.1f", $1}'`
echo $PRESS
YDAY=`date -u +%s -d now-24hours`
grep -a "DATA: T=" $SERIALLOG | awk '{print $6, $9}' | gmtselect -R$YDAY/1e10/-40/40 | minmax -C > /tmp/minmax.tmp
LOW=`awk '{print $3}' /tmp/minmax.tmp`
# bc truncates instead of rounding; this was the simplest way I found to round
LOW=`echo "scale=1; ($LOW*90/5+320.5)/10" | bc` # Fahrenheit
echo $LOW
HIGH=`awk '{print $4}' /tmp/minmax.tmp`
HIGH=`echo "scale=1; ($HIGH*90/5+320.5)/10" | bc` # Fahrenheit
echo $HIGH
echo $DATE > $LOGFILE
echo $PWD >> $LOGFILE
echo $PATH >> $LOGFILE
sed s/TEMPF/$TEMPF/ $DIR/template.html | sed s/HUMID/$HUMID/ | sed "s/DATE/$DATE/" | sed s/DEWPOINT/$DEWPOINT/ | sed s/PRESS/$PRESS/ | sed s/LOW/$LOW/ | sed s/HIGH/$HIGH/ > $DIR/current.html
STARTTIME=`date -u +%s -d now-${DAYS}days`
R=`grep -a "DATA: T=" $SERIALLOG | awk '{print $6, $9}' | gmtselect -R${STARTTIME}/1e10/$MINT/$MAXT | minmax -I86400/1 -C | awk '{print "-R" $1+17280 "/" $2+17280 "/" $3 "/" $4+1}'`
echo $R
# Fahrenheit axis options
RF=`echo $R | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/" $3*9/5+32 "/" $4*9/5+32}'`
echo $RF
RH=`echo $R | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/0/100"}'`
echo $RH
# pressure axis
RP=`echo $R/$MINP/$MAXP | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/" $5 "/" $6}'`
echo $RP
# in Hg units
RI=`echo $R/$MINP/$MAXP | awk 'BEGIN{FS="/"}{print $1 "/" $2 "/" $5*0.02954 "/" $6*0.02954}'`
echo $RI
gmtset BASEMAP_AXES EN
psbasemap -Y7.5 $RF -JX6t/2.5 -Bp12Hf1H/5f1:,"\260 F": -P -K -V > $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES WS
grep -a "DATA: T=" $SERIALLOG | awk '{print $6, $9}' | psxy $R -JX6t/2.5 -ft -P -V -Bp12Hf1H/5:"Outdoor temperature"::,"\260 C": -Bs1D -W10/blue -O -K -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES EN
psbasemap -Y-3.10 $RH -JX6t/2.5 -Bp12Hf1H/10f1:,"%": -K -O -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES WS
grep -a "DATA: H=" $SERIALLOG | awk '{print $6, $9}' | gmtselect -R0/1e10/19.999/99.999 | psxy $RH -JX6t/2.5 -ft -P -V -Bp12Hf1H/10:"Relative humidity"::,"%": -Bs1D -W10/blue -O -K -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES EN
psbasemap -Y-3.10 $RI -JX6t/2.5 -Bp12Hf1H/0.05f0.01:,"in": -K -O -V >> $PSFILE 2>> $LOGFILE
gmtset BASEMAP_AXES WS
# reduce to sea level and filter with 5 min Gaussian filter
grep -a "DATA: P= [0-9]\{5,\} " $SERIALLOG | awk '{print $6, $9}' | gmtmath -N0/0 STDIN 1 139 44330 DIV SUB 5.255 POW DIV 100 DIV = | filter1d -FG600 | psxy $RP -JX6t/2.5 -ft -P -V -Bp12Hf1H:"Local time ($TZ)":/2f1:"Barometric Pressure"::,"mbar": -Bs1D -W10/blue -O -V >> $PSFILE 2>> $LOGFILE
#grep -a "DATA: P= [0-9]\{5,\} " $SERIALLOG | awk '{print $6, $9}' | gmtmath -N0/0 STDIN 1 139 44330 DIV SUB 5.255 POW DIV 100 DIV = | psxy $RP -JX6t/2.5 -ft -P -V -Bp12Hf1H:"Local time (EDT)":/1f1:"Barometric Pressure"::,"mbar": -Bs1D -W10/blue -O -V >> $PSFILE 2>> $LOGFILE
ps2raster $PSFILE -V -Tg -E100 -D$DIR 2>> $LOGFILE
ps2raster $PSFILE -V -Tf -D$DIR 2>> $LOGFILE
gv $PSFILE &     # view postscript file
# update remote website (requires that .sitecopyrc is already set up)
sitecopy -u weather
