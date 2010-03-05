/* Name: lacrosse.pde
 * Version: 1.0
 * Author: Kelsey Jordahl
 * Copyright: Kelsey Jordahl 2010
   (portions copyright Marc Alexander, Jonathan Oxer 2009)
 * License: GPLv3
 * Time-stamp: <Fri Mar  5 18:15:11 EST 2010> 

Receive La Crosse TX4 weather sensor data with Arduino and log to
serial (USB) port.  Also records indoor temperature from two on-board
sensors, a thermistor and an LM-61.  Assumes the 433 MHz data pin is
connected to Digital Pin 8 (PB0).  Analog pins 0 and 1 are used for
the temperature sensors, set in the define statements below.

Based on idea, and some code, from Practical Arduino
 http://www.practicalarduino.com/projects/weather-station-receiver
 http://github.com/practicalarduino/WeatherStationReceiver

Also useful was the detailed data protocol description at
 http://www.f6fbb.org/domo/sensors/tx3_th.php

433.92 MHz RF receiver:
 http://www.sparkfun.com/commerce/product_info.php?products_id=8950

Thermistor:
 Vishay 10 kOhm NTC thermistor
 part no: NTCLE100E3103GB0
 <http://www.vishay.com/thermistors/list/product-29049>

LM61:
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

// Comment out for a normal build
// Uncomment for a debug build
#define DEBUG

#define INPUT_CAPTURE_IS_RISING_EDGE()    ((TCCR1B & _BV(ICES1)) != 0)
#define INPUT_CAPTURE_IS_FALLING_EDGE()   ((TCCR1B & _BV(ICES1)) == 0)
#define SET_INPUT_CAPTURE_RISING_EDGE()   (TCCR1B |=  _BV(ICES1))
#define SET_INPUT_CAPTURE_FALLING_EDGE()  (TCCR1B &= ~_BV(ICES1))
#define GREEN_TESTLED_ON()          ((PORTD &= ~(1<<PORTD6)))
#define GREEN_TESTLED_OFF()         ((PORTD |=  (1<<PORTD6)))
// I reversed the red - did I flip the LED?
#define RED_TESTLED_OFF()            ((PORTD &= ~(1<<PORTD7)))
#define RED_TESTLED_ON()           ((PORTD |=  (1<<PORTD7)))

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

/* ADC depends on reference voltage.  Could tie this to internal 1.05 V */
/* Linux machine voltage */
#define VCC 4.85		/* supply voltage on USB */
/* MacBook voltage */
//#define VCC 5.05		/* supply voltage on USB */
#define LM61PIN 0		/* analog pin for LM61 */
#define THERMPIN 1		/* analog pin for thermistor */

unsigned int uiICP_CapturedTime;
unsigned int uiICP_PreviousCapturedTime;
unsigned int uiICP_CapturedPeriod;
unsigned int uiICP_PreviousCapturedPeriod;
unsigned int SinceLastBit;
unsigned int LastBitTime;
unsigned int BitCount;
byte j;
float tempC;			/* temperature in deg C */
float tempF;			/* temperature in deg F */
byte h;			/* relative humidity */
byte DataPacket[PACKET_SIZE]; /* actively loading packet */
byte FinishedPacket[PACKET_SIZE]; /* fully read packet */
byte PacketBitCounter;
boolean ReadingPacket;
boolean PacketDone;

byte bICP_CapturedPeriodWasHigh;
byte bICP_PreviousCapturedPeriodWasHigh;
byte echo;
byte mask;		    /* temporary mask byte */
byte CompByte;		    /* byte containing the last 8 bits read */

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
  uiICP_CapturedTime = ICR1;

  // GREEN test led on (flicker for debug)
  GREEN_TESTLED_ON();
  if( INPUT_CAPTURE_IS_RISING_EDGE() )
  {
    SET_INPUT_CAPTURE_FALLING_EDGE();      //previous period was low and just transitioned high
    bICP_CapturedPeriodWasHigh = false;    //uiICP_CapturedPeriod about to be stored will be a low period
  } else {
    SET_INPUT_CAPTURE_RISING_EDGE();       //previous period was high and transitioned low
    bICP_CapturedPeriodWasHigh = true;     //uiICP_CapturedPeriod about to be stored will be a high period
  }

  uiICP_CapturedPeriod = (uiICP_CapturedTime - uiICP_PreviousCapturedTime);

  if ((uiICP_CapturedPeriod > MIN_ONE) && (bICP_CapturedPeriodWasHigh == true)) { // possible bit
    /* time from end of last bit to beginning of this one */
    SinceLastBit = (uiICP_PreviousCapturedTime - LastBitTime);
    
    if ((uiICP_CapturedPeriod < MAX_ONE) && (SinceLastBit > MIN_WAIT)) {
      if (SinceLastBit > MAX_WAIT) { // too long since last bit read
	RED_TESTLED_OFF();
	echo=0;
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
	LastBitTime = uiICP_CapturedTime;
      }
    } else {			/* Check whether it's a zero */
      if ((uiICP_CapturedPeriod > MIN_ZERO) && (uiICP_CapturedPeriod < MAX_ZERO)) {
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
	LastBitTime = uiICP_CapturedTime;
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
  uiICP_PreviousCapturedTime           = uiICP_CapturedTime;
  uiICP_PreviousCapturedPeriod         = uiICP_CapturedPeriod;
  bICP_PreviousCapturedPeriodWasHigh   = bICP_CapturedPeriodWasHigh;
  
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

float lm61(int RawADC) {
  float Temp;
  float voltage = RawADC * VCC / 1024; 
  Temp = (voltage - 0.6) * 100 ;  //10 mV/degree with 600 mV offset
  return Temp;
}

void setup() {
  Serial.begin( BAUD_RATE );   //using the USB serial port for debugging and logging
  Serial.println( "La Crosse weather station capture begin" );
  DDRB = 0x2F;   // B00101111
  DDRB  &= ~(1<<DDB0);    //PBO(ICP1) input
  PORTB &= ~(1<<PORTB0);  //ensure pullup resistor is also disabled

  //PORTD6 and PORTD7, GREEN and RED test LED setup
  DDRD  |=  B11000000;      //(1<<PORTD6);   //DDRD  |=  (1<<PORTD7); (example of B prefix)
  GREEN_TESTLED_OFF();      //GREEN test led off
//  RED_TESTLED_ON();         //RED test led on

  TCCR1A = B00000000;   //Normal mode of operation, TOP = 0xFFFF, TOV1 Flag Set on MAX
  TCCR1B = ( _BV(ICNC1) | _BV(CS11) | _BV(CS10) );
  SET_INPUT_CAPTURE_RISING_EDGE();
  //Timer1 Input Capture Interrupt Enable, Overflow Interrupt Enable  
  TIMSK1 = ( _BV(ICIE1) | _BV(TOIE1) );
  interrupts();   // Enable interrupts (NOTE: is this necessary? Should be enabled by default)

}

// in the main loop, just hang around waiting to see whether the interrupt routine has gathered a full packet yet
void loop() {

  delay(2);                  // wait for a short time
  if (PacketDone) {	     // have a bit string that's ended
    ParsePacket(FinishedPacket);
    PacketDone=0;
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
    if (Packet[0]==0) {		/* temperature packet */
      Serial.print("DATA: T= ");
      tempC=(Packet[3]*10-50 + Packet[4] + ( (float) Packet[5])/10);
      tempF=tempC*9/5 + 32;
      Serial.print(tempC,1);	/* print to 0.1 deg precision */
      Serial.print(" degC, ");
      Serial.print(tempF,1);	/* print to 0.1 deg precision */
      Serial.println(" degF");
      PrintIndoor();
    } else {
      if (Packet[0]==0x0E) {		/* humidity packet */
	Serial.print("DATA: H= ");
	h=(Packet[3]*10 + Packet[4]);
	Serial.print(h,DEC);
	Serial.println(" %");
      }
    }
  }
  else {			/* checksum fail */
    #ifdef DEBUG
    Serial.print("chksum = 0x");
    Serial.print(chksum,HEX);
    Serial.print(" data chksum = 0x");
    Serial.println(Packet[PACKET_SIZE-1],HEX);
    #endif
  }
}

// send indoor temperature to serial port
void PrintIndoor(void) {
      Serial.print("INDOOR1: ");
      Serial.print(lm61(analogRead(LM61PIN)),1);
      Serial.println(" deg C (LM61)");
      Serial.print("INDOOR2: ");
      Serial.print(Thermistor(analogRead(THERMPIN)),1); 
      Serial.println(" deg C (thermistor)");
}
