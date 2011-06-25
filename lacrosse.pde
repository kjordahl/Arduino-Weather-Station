/* Name: lacrosse.pde
 * Version: 1.1
 * Author: Kelsey Jordahl
 * Copyright: Kelsey Jordahl 2010
   (portions copyright Marc Alexander, Jonathan Oxer 2009;
    Interactive Matter 2009 [licensed under GPL with permission])
 * License: GPLv3
 * Time-stamp: <Sat Jun 25 12:47:25 EDT 2011> 

Receive La Crosse TX4 weather sensor data with Arduino and send to
serial (USB) port.  Also records indoor pressure and temperature from
two on-board I2C sensors, a BMP085 and a DS1631.  Assumes the 433 MHz
data pin is connected to Digital Pin 8 (PB0).  Analog pins 4 and 5 are
used for I2C communication with pressure and temperature sensors.

Based on idea, and some code, from Practical Arduino
 http://www.practicalarduino.com/projects/weather-station-receiver
 http://github.com/practicalarduino/WeatherStationReceiver

Also useful was the detailed data protocol description at
 http://www.f6fbb.org/domo/sensors/tx3_th.php

433.92 MHz RF receiver:
 http://www.sparkfun.com/commerce/product_info.php?products_id=8950

BMP085 pressure sensor:
 Breakout board and datasheet available from SparkFun:
 http://www.sparkfun.com/commerce/product_info.php?products_id=9694
  functions to communicate with BMP085 via I2C from:
 http://interactive-matter.org/2009/12/arduino-barometric-pressure-sensor-bmp085
  see also:
 http://news.jeelabs.org/2009/02/19/hooking-up-a-bmp085-sensor

DS1631 temperature sensor:
 Maxim digital temperature sensor with I2C interface in DIP-8 package
 http://www.maxim-ic.com/datasheet/index.mvp/id/3241
  see also:
 http://kennethfinnegan.blogspot.com/2009/10/arduino-temperature-logger.html

Thermistor (no longer used):
 Vishay 10 kOhm NTC thermistor
 part no: NTCLE100E3103GB0
 <http://www.vishay.com/thermistors/list/product-29049>

LM61 (no longer used):
 National Semiconductor TO-92 Temperature Sensor
 10 mV/degree with 600 mV offset, temperature range -30 deg C to 100 deg C
 part no: LM61BIZ
 <http://www.national.com/mpf/LM/LM61.html>

     see: http://www.arduino.cc/playground/ComponentLib/Thermistor2
     and: http://www.ladyada.net/learn/sensors/tmp36.html



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

*/

#include <math.h>
#include <Wire.h>

// Comment out for a normal build
// Uncomment for a debug build
#define DEBUG

#define INPUT_CAPTURE_IS_RISING_EDGE()    ((TCCR1B & _BV(ICES1)) != 0)
#define INPUT_CAPTURE_IS_FALLING_EDGE()   ((TCCR1B & _BV(ICES1)) == 0)
#define SET_INPUT_CAPTURE_RISING_EDGE()   (TCCR1B |=  _BV(ICES1))
#define SET_INPUT_CAPTURE_FALLING_EDGE()  (TCCR1B &= ~_BV(ICES1))
#define GREEN_TESTLED_ON()          ((PORTD &= ~(1<<PORTD6)))
#define GREEN_TESTLED_OFF()         ((PORTD |=  (1<<PORTD6)))
// I reversed the red - did I flip the LED from the schematic?
#define RED_TESTLED_OFF()            ((PORTD &= ~(1<<PORTD7)))
#define RED_TESTLED_ON()           ((PORTD |=  (1<<PORTD7)))
#define BMP085_ADDRESS 0x77	/* I2C address of BMP085 pressure sensor */
#define DS1631_ADDRESS 0x48	/* I2C address of DS1631 temp sensor */
#define MAXTICK 6009	 /* about 60 s interval for pressure sampling */

// DS1631 command codes
#define STARTTEMP 0x51
#define READTEMP 0xAA

/* serial port communication (via USB) */
#define BAUD_RATE 9600

#define PACKET_SIZE 9   /* number of nibbles in packet (after inital byte) */
#define PACKET_START 0x0A	/* byte to match for start of packet */

// 0.5 ms high is a one
#define MIN_ONE 135		// minimum length of '1'
#define MAX_ONE 155		// maximum length of '1'
// 1.3 ms high is a zero
#define MIN_ZERO 335		// minimum length of '0'
#define MAX_ZERO 370		// maximum length of '0'
// 1 ms between bits
#define MIN_WAIT 225		// minimum interval since end of last bit
#define MAX_WAIT 275		// maximum interval since end of last bit

/* constants for extended Steinhart-Hart equation from thermistor datasheet */
#define A 3.354016E-03
#define B 2.569850E-04
#define C 2.620131E-06
#define D 6.383091E-08

/* ADC depends on reference voltage.  Could tie this to internal 1.05 V? */
/* Linux machine voltage */
//#define VCC 4.85		/* supply voltage on USB */
/* MacBook voltage */
//#define VCC 5.05		/* supply voltage on USB */
//#define LM61PIN 0		/* analog pin for LM61 sensor */
//#define THERMPIN 1		/* analog pin for thermistor */

const unsigned char oversampling_setting = 3; //oversampling for measurement
const unsigned char pressure_waittime[4] = { 5, 8, 14, 26 };

/*  calibration constants from the BMP085 datasheet */
int ac1;
int ac2; 
int ac3; 
unsigned int ac4;
unsigned int ac5;
unsigned int ac6;
int b1; 
int b2;
int mb;
int mc;
int md;

unsigned int CapturedTime;
unsigned int PreviousCapturedTime;
unsigned int CapturedPeriod;
unsigned int PreviousCapturedPeriod;
unsigned int SinceLastBit;
unsigned int LastBitTime;
unsigned int BitCount;
byte j;
float tempC;			/* temperature in deg C */
float tempF;			/* temperature in deg F */
float dp;			/* dewpoint (deg C) */
byte h;				/* relative humidity */
byte DataPacket[PACKET_SIZE];	  /* actively loading packet */
byte FinishedPacket[PACKET_SIZE]; /* fully read packet */
byte PacketBitCounter;
boolean ReadingPacket;
boolean PacketDone;

byte CapturedPeriodWasHigh;
byte PreviousCapturedPeriodWasHigh;
byte mask;		    /* temporary mask byte */
byte CompByte;		    /* byte containing the last 8 bits read */

volatile unsigned int tick = 0;			/* count ticks of the clock */
int  temperature = 0;				/* BMP085 temp (0.1 deg) */
long pressure = 0;				/* BMP085 pressure (Pa) */
unsigned int starttime;
unsigned int interval;
boolean timerflag = false;	/* flag to set when timer goes off */

// pressure sample interval timer
ISR(TIMER2_COMPA_vect) {
  if (tick++ > MAXTICK) {
    timerflag = true;
    tick=0;
  }
}

// does nothing now
ISR( TIMER1_OVF_vect )
{
  //increment the 32 bit timestamp counter (see overflow notes above)
  //overflow is allowed as this timestamp is most likely to be used as a delta from the previous timestamp,
  //so if it's used externally in the same 32 bit unsigned type it will come out ok.
 GREEN_TESTLED_OFF();
}

ISR( TIMER1_CAPT_vect )
{
  // Immediately grab the current capture time in case it triggers again and
  // overwrites ICR1 with an unexpected new value
  CapturedTime = ICR1;

  // GREEN test led on (flicker for debug)
  GREEN_TESTLED_ON();
  if( INPUT_CAPTURE_IS_RISING_EDGE() )
  {
    SET_INPUT_CAPTURE_FALLING_EDGE();      //previous period was low and just transitioned high
    CapturedPeriodWasHigh = false;    //uiICP_CapturedPeriod about to be stored will be a low period
  } else {
    SET_INPUT_CAPTURE_RISING_EDGE();       //previous period was high and transitioned low
    CapturedPeriodWasHigh = true;     //uiICP_CapturedPeriod about to be stored will be a high period
  }

  CapturedPeriod = (CapturedTime - PreviousCapturedTime);

  if ((CapturedPeriod > MIN_ONE) && (CapturedPeriodWasHigh == true)) { // possible bit
    /* time from end of last bit to beginning of this one */
    SinceLastBit = (PreviousCapturedTime - LastBitTime);
    
    if ((CapturedPeriod < MAX_ONE) && (SinceLastBit > MIN_WAIT)) {
      if (SinceLastBit > MAX_WAIT) { // too long since last bit read
	if ((SinceLastBit > (2*MIN_WAIT+MIN_ONE)) && (SinceLastBit < (2*MAX_WAIT+MAX_ONE))) { /* missed a one */
          #ifdef DEBUG
	  Serial.println("missed one");
	  #endif
	} else {
	  if ((SinceLastBit > (2*MIN_WAIT+MIN_ZERO)) && (SinceLastBit < (2*MAX_WAIT+MAX_ZERO))) { /* missed a zero */
            #ifdef DEBUG
	    Serial.println("missed zero");
	    #endif
	  }
	}
	RED_TESTLED_OFF();
	if (ReadingPacket) {
          #ifdef DEBUG
	  Serial.print("dropped packet. bits read: ");
	  Serial.println(PacketBitCounter,DEC);
	  #endif
	  ReadingPacket=0;
	  PacketBitCounter=0;
	}
	CompByte=0xFF;			  /* reset comparison byte */
      } else { /* call it a one */
	if (ReadingPacket) {	/* record the bit as a one */
	  //	  Serial.print("1");
	  mask = (1 << (3 - (PacketBitCounter & 0x03)));
	  DataPacket[(PacketBitCounter >> 2)] |= mask;
	  PacketBitCounter++;
	} else {		  /* still looking for valid packet data */
	  if (CompByte != 0xFF) {	/* don't bother recording if no zeros recently */
	    CompByte = ((CompByte << 1) | 0x01); /* push one on the end */
	  }
	}
	LastBitTime = CapturedTime;
      }
    } else {			/* Check whether it's a zero */
      if ((CapturedPeriod > MIN_ZERO) && (CapturedPeriod < MAX_ZERO)) {
	if (ReadingPacket) {	/* record the bit as a zero */
	  //	  Serial.print("0");
	  mask = (1 << (3 - (PacketBitCounter & 0x03)));
	  DataPacket[(PacketBitCounter >> 2)] &= ~mask;
	  PacketBitCounter++;
	} else {		      /* still looking for valid packet data */
	  CompByte = (CompByte << 1); /* push zero on the end */
/* 	  if ((CompByte & 0xF0) != 0xf0) { */
/* 	    Serial.println(CompByte,HEX); */
/* 	  } */
	}
	LastBitTime = CapturedTime;
      }
    }
  }

  if (ReadingPacket) {
    if (PacketBitCounter == (4*PACKET_SIZE)) { /* done reading packet */
      memcpy(&FinishedPacket,&DataPacket,PACKET_SIZE);
      RED_TESTLED_OFF();
      PacketDone = 1;
      ReadingPacket = 0;
      PacketBitCounter = 0;
    }
  } else {
    /* Check whether we have the start of a data packet */
    if (CompByte == PACKET_START) {
      //      Serial.println("Got packet start!");
      CompByte=0xFF;		/* reset comparison byte */
      RED_TESTLED_ON();
      /* set a flag and start recording data */
      ReadingPacket = 1;
    }
  }

  //save the current capture data as previous so it can be used for period calculation again next time around
  PreviousCapturedTime           = CapturedTime;
  PreviousCapturedPeriod         = CapturedPeriod;
  PreviousCapturedPeriodWasHigh   = CapturedPeriodWasHigh;
  
  //GREEN test led off (flicker for debug)
  GREEN_TESTLED_OFF();
}

float Thermistor(int RawADC) {
  float Temp;
  Temp = log(((1024/float(RawADC)) - 1)); /* relative to 10 kOhm */
  Temp = 1 / (A + (B * Temp) + (C * Temp * Temp) + (D * Temp * Temp * Temp));
  Temp = Temp - 273.15;		/* convert to C */
  // Temp = (Temp * 9.0)/ 5.0 + 32.0; // Convert Celcius to Fahrenheit
  return Temp;
}

// not currently used
/*
float lm61(int RawADC) {
  float Temp;
  float voltage = RawADC * VCC / 1024; 
  Temp = (voltage - 0.6) * 100 ;  //10 mV/degree with 600 mV offset
  return Temp;
} */

float dewpoint(float T, float h) {
  float td;
  // Simplified dewpoint formula from Lawrence (2005), doi:10.1175/BAMS-86-2-225
  td = T - (100-h)*pow(((T+273.15)/300),2)/5 - 0.00135*pow(h-84,2) + 0.35;
  return td;
}

void setup() {
  Serial.begin( BAUD_RATE );   //using the USB serial port for debugging and logging
  Serial.println( "La Crosse weather station capture begin" );
  Wire.begin();
  bmp085_get_cal_data();
  // initialize the DS1631 temperature sensor
  Wire.beginTransmission(DS1631_ADDRESS);
  Wire.send(STARTTEMP);
  Wire.endTransmission();

  cli();
  DDRB = 0x2F;   // B00101111
  DDRB  &= ~(1<<DDB0);    //PBO(ICP1) input
  PORTB &= ~(1<<PORTB0);  //ensure pullup resistor is also disabled

  //PORTD6 and PORTD7, GREEN and RED test LED setup
  DDRD  |=  B11000000;      //(1<<PORTD6);   //DDRD  |=  (1<<PORTD7); (example of B prefix)
  GREEN_TESTLED_OFF();      //GREEN test led off
//  RED_TESTLED_ON();         //RED test led on
  // Set up timer1 for RF signal detection
  TCCR1A = B00000000;   //Normal mode of operation, TOP = 0xFFFF, TOV1 Flag Set on MAX
  TCCR1B = ( _BV(ICNC1) | _BV(CS11) | _BV(CS10) );
  SET_INPUT_CAPTURE_RISING_EDGE();
  //Timer1 Input Capture Interrupt Enable, Overflow Interrupt Enable  
  TIMSK1 = ( _BV(ICIE1) | _BV(TOIE1) );
  //  Set up timer2 for countdown timer
  TCCR2A = (1<<WGM21);				/* CTC mode */
  TCCR2B = ((1<<CS22) | (1<<CS21) | (1<<CS20)); /* clock/1024 prescaler */
  TIMSK2 = (1<<OCIE2A);	  /* enable interupts */
  ASSR &= ~(1<<AS2);	  /* make sure we're running on internal clock */
  OCR2A = 155;	       /* interrupt f=100.16 Hz, just under 10 ms period */
  sei();
  interrupts();   // Enable interrupts (NOTE: is this necessary? Should be enabled by default)

}

// in the main loop, just hang around waiting to see whether the interrupt routine has gathered a full packet yet
void loop() {

  delay(2);                  // wait for a short time
  if (PacketDone) {	     // have a bit string that's ended
    ParsePacket(FinishedPacket);
    PacketDone=0;
  }
  if (timerflag) {		// time to take a pressure sample
    timerflag = false;
    interval=millis() - starttime; /* measure time since last sample */
    starttime = millis();
    PrintIndoor();		/* get DS1631 temp */
    bmp085_read_temperature_and_pressure(&temperature,&pressure);
    Serial.print("ELAPSED MS= ");
    Serial.println(interval,DEC);
    Serial.print("BMP085 TEMP: ");
    Serial.println(temperature,DEC);
    Serial.print("DATA: P= ");
    Serial.print(pressure,DEC);
    Serial.println(" Pa");
  }
}


// parse a raw data string
void ParsePacket(byte *Packet) {

  byte chksum;

  #ifdef DEBUG
  Serial.print("RAW: ");
  for (j=0; j<PACKET_SIZE; j++) {
    Serial.print(Packet[j], HEX);
  }	
  Serial.println("");
  #endif

  chksum = 0x0A;
  for (j=0; j<(PACKET_SIZE-1); j++) {
    chksum += Packet[j];
  }
  
  if ((chksum & 0x0F) == Packet[PACKET_SIZE-1]) { /* checksum pass */
    /* check for bad digits and make sure that most significant digits repeat */
    if ((Packet[3]==Packet[6]) && (Packet[4]==Packet[7]) && (Packet[3]<10) && (Packet[4]<10) && (Packet[5]<10)) {
      if (Packet[0]==0) {		/* temperature packet */
	Serial.print("DATA: T= ");
	tempC=(Packet[3]*10-50 + Packet[4] + ( (float) Packet[5])/10);
	tempF=tempC*9/5 + 32;
	Serial.print(tempC,1);	/* print to 0.1 deg precision */
	Serial.print(" degC, ");
	Serial.print(tempF,1);	/* print to 0.1 deg precision */
	Serial.println(" degF");
	/* PrintIndoor(); // moved to time interval sampling with pressure */
	dp=dewpoint(tempC,h);
	Serial.print("DEWPOINT: ");
	Serial.print(dp,1);
	Serial.print(" degC, ");
	Serial.print(dp*9/5 + 32,1);
	Serial.println(" degF");
      } else {
	if (Packet[0]==0x0E) {		/* humidity packet */
	  Serial.print("DATA: H= ");
	  h=(Packet[3]*10 + Packet[4]);
	  Serial.print(h,DEC);
	  Serial.println(" %");
	} else  {
	  if (Packet[0]==0x0B) {		/* custom packet */
	    Serial.print("CUSTOM: T= ");
	    tempC=(Packet[3]*10-50 + Packet[4] + ( (float) Packet[5])/10);
	    tempF=tempC*9/5 + 32;
	    Serial.print(tempC,1);	/* print to 0.1 deg precision */
	    Serial.print(" degC, ");
	    Serial.print(tempF,1);	/* print to 0.1 deg precision */
	    Serial.println(" degF");
	  }
	}
      }
    } else {
      #ifdef DEBUG
      Serial.println("Fail secondary data check.");
      #endif
    }
  } else {			/* checksum fail */
    #ifdef DEBUG
    Serial.print("chksum = 0x");
    Serial.print(chksum,HEX);
    Serial.print(" data chksum = 0x");
    Serial.println(Packet[PACKET_SIZE-1],HEX);
    #endif
  }
}

// send indoor temperature to serial port
void PrintIndoor() {
  byte temp[2];
  Wire.beginTransmission(DS1631_ADDRESS);
  Wire.send(READTEMP);
  Wire.endTransmission();
  Wire.requestFrom(DS1631_ADDRESS, 2);
  temp[0] = Wire.receive(); // MSB
  temp[1] = Wire.receive(); // LSB

  Serial.print("INDOOR: ");
  Serial.print(temp[0], DEC);
  Serial.print(".");
  Serial.print(temp[1] / 25, DEC); // fractional degree
  Serial.println(" deg C (DS1631)");
}

void bmp085_read_temperature_and_pressure(int* temperature, long* pressure) {
  long ut= bmp085_read_ut();
  long up = bmp085_read_up();
  long x1, x2, x3, b3, b5, b6, p;
  unsigned long b4, b7;

   //calculate the temperature
   x1 = ((long)ut - ac6) * ac5 >> 15;
   x2 = ((long) mc << 11) / (x1 + md);
   b5 = x1 + x2;
   *temperature = (b5 + 8) >> 4;
   
   //calculate the pressure
   b6 = b5 - 4000;
   x1 = (b2 * (b6 * b6 >> 12)) >> 11; 
   x2 = ac2 * b6 >> 11;
   x3 = x1 + x2;
   //   b3 = (((int32_t) ac1 * 4 + x3)<<oversampling_setting + 2) >> 2;
   b3 = (((int32_t) ac1 * 4 + x3)<<oversampling_setting) >> 2;
   x1 = ac3 * b6 >> 13;
   x2 = (b1 * (b6 * b6 >> 12)) >> 16;
   x3 = ((x1 + x2) + 2) >> 2;
   b4 = (ac4 * (uint32_t) (x3 + 32768)) >> 15;
   b7 = ((uint32_t) up - b3) * (50000 >> oversampling_setting);
   p = b7 < 0x80000000 ? (b7 * 2) / b4 : (b7 / b4) * 2;
   
   x1 = (p >> 8) * (p >> 8);
   x1 = (x1 * 3038) >> 16;
   x2 = (-7357 * p) >> 16;
   *pressure = p + ((x1 + x2 + 3791) >> 4);

}

unsigned int bmp085_read_ut() {
  write_register(0xf4,0x2e);
  delay(5); //longer than 4.5 ms
  return read_int_register(0xf6);
}

void  bmp085_get_cal_data() {
  #ifdef DEBUG
  Serial.println("Reading BMP085 calibration data");
  #endif
  ac1 = read_int_register(0xAA);
  ac2 = read_int_register(0xAC);
  ac3 = read_int_register(0xAE);
  ac4 = read_int_register(0xB0);
  ac5 = read_int_register(0xB2);
  ac6 = read_int_register(0xB4);
  b1 = read_int_register(0xB6);
  b2 = read_int_register(0xB8);
  mb = read_int_register(0xBA);
  mc = read_int_register(0xBC);
  md = read_int_register(0xBE);
  #ifdef DEBUG
  Serial.print("AC1: ");
  Serial.println(ac1,DEC);
  Serial.print("AC2: ");
  Serial.println(ac2,DEC);
  Serial.print("AC3: ");
  Serial.println(ac3,DEC);
  Serial.print("AC4: ");
  Serial.println(ac4,DEC);
  Serial.print("AC5: ");
  Serial.println(ac5,DEC);
  Serial.print("AC6: ");
  Serial.println(ac6,DEC);
  Serial.print("B1: ");
  Serial.println(b1,DEC);
  Serial.print("B2: ");
  Serial.println(b1,DEC);
  Serial.print("MB: ");
  Serial.println(mb,DEC);
  Serial.print("MC: ");
  Serial.println(mc,DEC);
  Serial.print("MD: ");
  Serial.println(md,DEC);
  #endif
}


long bmp085_read_up() {
  write_register(0xf4,0x34+(oversampling_setting<<6));
  delay(pressure_waittime[oversampling_setting]);
  
  unsigned char msb, lsb, xlsb;
  Wire.beginTransmission(BMP085_ADDRESS);
  Wire.send(0xf6);  // register to read
  Wire.endTransmission();

  Wire.requestFrom(BMP085_ADDRESS, 3); // read a byte
  while(!Wire.available()) {
    // waiting
  }
  msb = Wire.receive();
  while(!Wire.available()) {
    // waiting
  }
  lsb |= Wire.receive();
  while(!Wire.available()) {
    // waiting
  }
  xlsb |= Wire.receive();
  return (((long)msb<<16) | ((long)lsb<<8) | ((long)xlsb)) >>(8-oversampling_setting);
}

void write_register(unsigned char r, unsigned char v)
{
  Wire.beginTransmission(BMP085_ADDRESS);
  Wire.send(r);
  Wire.send(v);
  Wire.endTransmission();
}

char read_register(unsigned char r)
{
  unsigned char v;
  Wire.beginTransmission(BMP085_ADDRESS);
  Wire.send(r);  // register to read
  Wire.endTransmission();

  Wire.requestFrom(BMP085_ADDRESS, 1); // read a byte
  while(!Wire.available()) {
    // waiting
  }
  v = Wire.receive();
  return v;
}

int read_int_register(unsigned char r)
{
  unsigned char msb, lsb;
  Wire.beginTransmission(BMP085_ADDRESS);
  Wire.send(r);  // register to read
  Wire.endTransmission();

  Wire.requestFrom(BMP085_ADDRESS, 2); // read a byte
  while(!Wire.available()) {
    // waiting
  }
  msb = Wire.receive();
  while(!Wire.available()) {
    // waiting
  }
  lsb = Wire.receive();
  return (((int)msb<<8) | ((int)lsb));
}
