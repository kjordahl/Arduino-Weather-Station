#!/usr/bin/env python
# -*- coding: iso-8859-15 -*-
"""
Parse serial log file from Arduino weather station and produce a graph
for static HTML page.  Plots temperature, relative humidity, and
barometric pressure.

Takes command line flags for number of days to plot,
allow display of graph if called from command line,
will upload HTML to live site if requested.

Examples:

To plot the default number of days (4) and upload to live website, use:
% plotweather.py -u

To plot 7 days and display the resulting graph (but not upload HTML), use:
% plotweather.py -d 7 -p

To see all input options, use "plotweather.py -h"

See http://mysite.verizon.net/kajordahl/weather.html
or http://github.com/kjordahl/Arduino-Weather-Station

Author: Kelsey Jordahl
Copyright: Kelsey Jordahl 2010-2011
License: GPLv3
Time-stamp: <Sun Mar  4 22:01:53 EST 2012>

    This program is free software: you can redistribute it and/or
    modify it under the terms of the GNU General Public License as
    published by the Free Software Foundation, either version 3 of the
    License, or (at your option) any later version.  A copy of the GPL
    version 3 license can be found in the file COPYING or at
    <http://www.gnu.org/licenses/>.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

"""

import os, sys
import re
import argparse
from datetime import datetime, date, time, tzinfo
#from time import timezone
import time
import numpy as np
from matplotlib import dates, pyplot
from matplotlib.figure import Figure
from matplotlib.backends.backend_agg import FigureCanvasAgg
import tempfile


class Weather(object):
    """Class to hold weather data.
    """

    def __init__(self):
        self.temp = None
        self.time = None
        self.humid = None
        self.pressure = None
        self.max = None
        self.min = None
        self.MINTEMP = -40.0       # minimum valid temperature (deg C)
        # only honors current timezone (plot will not be correct across a DST change)
        self.timezone = time.timezone
        self.TZ = time.strftime('%Z', time.localtime())

    @property
    def dewpoint(self):
        """Simplified dewpoint formula from Lawrence (2005),
        doi:10.1175/BAMS-86-2-225
        """
        if self.humid and self.temp:
            dp = self.temp - (100 - self.humid)*((self.temp + 273.15)/300)**2 / 5 - 0.00135*(self.humid - 84)**2 + 0.35
            return dp
        else:
            return None

    @property
    def fahrenheit(self):
        """Convert to degrees Fahrenheit"""
        if self.temp:
            return c2f(self.temp)

    def report(self):
        """print current weather conditions"""
        #        print 'time', datetime.isoformat(self.time)
        print self.time.strftime("%a %d %b %Y %H:%M:%S"), self.TZ
        print 'Temperature: %4.1f deg C, %4.1f deg F' % (self.temp, self.fahrenheit)
        print 'Pressure:', self.pressure, 'mbar'
        print 'Humidity:', self.humid, '% humidity'
        print 'Dewpoint: %4.1f deg C, %4.1f deg F' % (self.dewpoint, c2f(self.dewpoint))

    def save_html(self):
        """Update static HTML file with current weather data"""
        templatefile = os.path.join(args.outdir,'template_py.html')
        outfile = os.path.join(args.outdir,'current.html')
        html = open(templatefile,'r')
        lines = html.read()
        # print lines
        out = open(outfile,'w')
        try:
            out.write(lines % (self.time.strftime("%a %d %b %Y %H:%M:%S " + self.TZ), self.fahrenheit, c2f(self.max), c2f(self.min), self.humid, c2f(self.dewpoint), self.pressure))
        except:
            exceptionType, exceptionValue, exceptionTraceback = sys.exc_info()
            print exceptionType
            print exceptionValue
        out.close()


def datelabels(ax):
    ax.xaxis.set_major_locator(
        dates.DayLocator()
        )
    ax.xaxis.set_major_formatter(
        dates.DateFormatter('%d %b')
        )


def c2f(tempC):
    """Celcius to Fahrenheit degrees conversion"""
    return tempC * 9/5 + 32

def sealevel(P,h):
    """Calculate pressure at sea level given altitude of sensor in meters
    From the BMP085 pressure sensor datasheet
    http://www.bosch-sensortec.com/content/language1/downloads/BST-BMP085-DS000-05.pdf"""
    return P / (1 - h/44330.0)**5.255

def main(args):
    logfilename = os.path.join(args.logdir,'serial.log')
    oldlogfilename = os.path.join(args.logdir,'serial.log.0')
    current = Weather()
    h = 139                             # elevation in meters
    if args.days > 7:
        print "WARNING: %s days requested; log may contain 7-14 days of data" % args.days

    # copy DATA lines to temporary file, concatenating current and former logfiles
    t = tempfile.TemporaryFile()
    # to have a named file for testing:
    # t = tempfile.NamedTemporaryFile(delete=False)
    logfile = open(oldlogfilename,'r')
    for line in logfile:
        if re.match("(.*)DATA(.*)", line):
            t.write(line)
    logfile.close()
    logfile = open(logfilename,'r')
    for line in logfile:
        if re.match("(.*)DATA(.*)", line):
            t.write(line)
    logfile.close()

    # read from tempfile into numpy array for each parameter
    t.seek(0)
    temptemp = np.asarray(re.findall('(\d+) DATA: T= (.+) degC',t.read()), dtype=np.float64)
    #temptemp[np.where(temptemp<MINTEMP)] = np.nan
    temp = np.ma.masked_less(temptemp, current.MINTEMP)
    current.temp = temp[len(temp)-1,1]            # most recent temp
    now = int(temp[len(temp)-1,0])                # in Unix seconds
    if args.verbose:
        print "Timezone offset: %s" % current.timezone
    # store as Python datetime, in local time, naive format with no real tzinfo set
    current.time = dates.num2date(dates.epoch2num(now-current.timezone)) 
    current.max = np.max(temp[temp[:,0] > (now-86400),1])
    current.min = np.min(temp[temp[:,0] > (now-86400),1])
    if args.verbose:
        print "Temperature records: %s" % len(temp)
    t.seek(0)
    pressure = np.asarray(re.findall('(\d+) DATA: P= (\d+) Pa',t.read()), dtype=np.float64)
    current.pressure = sealevel(pressure[len(pressure)-1,1]/100,h)
    if args.verbose:
        print "Pressure records: %s" % len(pressure)
    t.seek(0)
    humid = np.asarray(re.findall('(\d+) DATA: H= (\d+) %',t.read()), dtype=np.int)
    t.close()
    current.humid = humid[len(humid)-1,1]
    if args.verbose:
        print "Humidity records: %s" % len(humid)
    # set start time to midnight local time, # of days ago specified
    start = (np.floor((now-current.timezone)/86400.0) - args.days)*86400 + current.timezone
    if args.verbose:
        print "Current timestamp: %s" % now
    if args.verbose:
        print "Start timestamp: %s" % start
    temp=temp[temp[:,0]>start,:]
    pressure=pressure[pressure[:,0]>start,:]
    humid=humid[humid[:,0]>start,:]
    m=temp[0,0]
    if args.verbose:
        print "First actual timestamp: %s" % m
    current.report()
    current.save_html()
    fig = Figure(figsize=(8,8))
    # ensure that all 3 plots are on same x-axis
    end = (np.floor((now)/86400.0) + 1)*86400
    if args.verbose:
        print "last plot time: %f, %s" % (end, time.strftime("%a %d %b %Y %H:%M:%S",time.gmtime(end)))
    xlim=(dates.epoch2num(start - current.timezone),dates.epoch2num(end))

    # Temperature plot
    ax = fig.add_subplot(311)
    ax.plot(dates.epoch2num(temp[:,0]-current.timezone),temp[:,1])
    ax.set_xlim(xlim)
    ax.set_ylabel(u'Temp (°C)')
    ax2 = ax.twinx()
    clim = pyplot.get(ax,'ylim')
    ax2.set_ylim(c2f(clim[0]),c2f(clim[1]))
    datelabels(ax)
    ax2.set_ylabel(u'Temp (°F)')

    # Humidity plot
    ax = fig.add_subplot(312)
    ax.plot(dates.epoch2num(humid[:,0]-current.timezone),humid[:,1],'-')
    ax.set_xlim(xlim)
    ax.set_ylim(0,100)
    ax.set_ylabel('Humidity (%)')
    ax2 = ax.twinx()
    ax2.set_ylim(0,100)
    datelabels(ax)
    ax2.set_ylabel('Humidity (%)')

    # Pressure plot
    ax = fig.add_subplot(313)
    ax.plot(dates.epoch2num(pressure[:,0]-current.timezone),sealevel(pressure[:,1],h)/100,'-')
    ax.set_xlim(xlim)
    ax.set_ylabel('Pressure (mbar)')
    ax.set_xlabel('local time (%s)' % current.TZ)
    ax2 = ax.twinx()
    clim = pyplot.get(ax,'ylim')
    ax2.set_ylim(clim[0]*0.02954,clim[1]*0.02954)
    datelabels(ax)
    ax.xaxis.set_major_locator(
        dates.HourLocator(interval=12)
        )
    ax.xaxis.set_major_formatter(
        dates.DateFormatter('%H:%M')
        )
    ax2.set_ylabel('P (inches Hg)')
    canvas = FigureCanvasAgg(fig)
    canvas.print_figure(os.path.join(args.outdir,'plot.png'), dpi=80)
    canvas.print_figure(os.path.join(args.outdir,'plot.pdf'))

    if args.upload:
        # upload static html file & images
        os.system('sitecopy -u weather')

    if args.show:
        # show the plot
        # doesn't work with FigureCanvasAgg
        #pyplot.show()
        # Linux (or X11 in OS X)
        os.system("display %s" % os.path.join(args.outdir,'plot.png'))
        # OS X
        # os.system("open %s" % os.path.join(args.outdir,'plot.png'))
        
# end main()

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description='Plot weather record')
    parser.add_argument('-v', dest='verbose', action='store_true', help='verbose')
    parser.add_argument('-u', dest='upload', action='store_true', help='Upload to live website (requires sitecopy)')
    parser.add_argument('-p', dest='show', action='store_true', help='Show the plot')
    parser.add_argument('-d', '--days', dest='days', default=4, type=int, help='Number of days to plot (default 4)')
    parser.add_argument('-l', '--logdir', dest='logdir', default='/usr/local/share/logserial', help='Directory to find serial log files (default /usr/local/share/logserial)')
    parser.add_argument('-o', '--outdir', dest='outdir', default='/home/kels/html/weather', help='Directory to find serial log files (default /home/kels/html/weather)')
    args = parser.parse_args()
    main(args)
