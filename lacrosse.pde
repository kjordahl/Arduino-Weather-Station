// test RF receiver
// receive La Crosse sensor date

#define INPUT_CAPTURE_IS_RISING_EDGE()    ((TCCR1B & _BV(ICES1)) != 0)
#define INPUT_CAPTURE_IS_FALLING_EDGE()   ((TCCR1B & _BV(ICES1)) == 0)
#define SET_INPUT_CAPTURE_RISING_EDGE()   (TCCR1B |=  _BV(ICES1))
#define SET_INPUT_CAPTURE_FALLING_EDGE()  (TCCR1B &= ~_BV(ICES1))
#define GREEN_TESTLED_ON()          ((PORTD &= ~(1<<PORTD6)))
#define GREEN_TESTLED_OFF()         ((PORTD |=  (1<<PORTD6)))
// I reversed the red - did I flip the LED?
#define RED_TESTLED_OFF()            ((PORTD &= ~(1<<PORTD7)))
#define RED_TESTLED_ON()           ((PORTD |=  (1<<PORTD7)))
// 0.5 ms high is a one
#define MIN_ONE 135		// minimum length of '1'
#define MAX_ONE 155		// maximum length of '1'
// 1.3 ms high is a zero
#define MIN_ZERO 335		// minimum length of '0'
#define MAX_ZERO 370		// maximum length of '0'
// 1 ms between bits
#define MIN_WAIT 225		// minimum interval since end of last bit
#define MAX_WAIT 275		// maximum interval since enf of last bit

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
unsigned int BitWait[200];
unsigned int BitTime[200];
volatile byte BitVal[200];

byte bICP_CapturedPeriodWasHigh;
byte bICP_PreviousCapturedPeriodWasHigh;
byte echo;

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
      } else {		  /* call it a one */
	if ((echo>4) && (BitCount<200)) {		// don't do anything before at least 4 zeros
	  BitVal[BitCount]=1;	// stupid, inefficient way to store a bit
	  BitTime[BitCount]=uiICP_CapturedPeriod;
	  BitWait[BitCount]=SinceLastBit;
	  BitCount++;
	  LastBitTime = uiICP_CapturedTime;
	  echo++;
	} else {
	  //	  echo=0;
	}
      }
    } else {
      if ((uiICP_CapturedPeriod > MIN_ZERO) && (uiICP_CapturedPeriod < MAX_ZERO)) {
	RED_TESTLED_ON();
	BitVal[BitCount]=0;	// stupid, inefficient way to store a bit
	BitTime[BitCount]=uiICP_CapturedPeriod;
	BitWait[BitCount]=SinceLastBit;
	BitCount++;
	LastBitTime = uiICP_CapturedTime;
	echo++;
      }
    }
  }    
  //----------------------------------------------------------------------------
  //save the current capture data as previous so it can be used for period calculation again next time around
  uiICP_PreviousCapturedTime           = uiICP_CapturedTime;
  uiICP_PreviousCapturedPeriod         = uiICP_CapturedPeriod;
  bICP_PreviousCapturedPeriodWasHigh   = bICP_CapturedPeriodWasHigh;
  
  //GREEN test led off (flicker for debug)
  GREEN_TESTLED_OFF();
}

void setup(void)
{
  Serial.begin( 38400 );   //using the serial port at 38400bps for debugging and logging
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

void loop(void)
{

  delay(1000);                  // wait for a second
  if ((BitCount) && (~echo)) {	// have a bit string that's ended
    if (BitCount>16) {		/* skip packets < 2 bytes */
      Serial.print("RAW: ");
      for (j=0; j<(BitCount/4); j++) {
	Serial.print(nib(j), HEX);
      } 
      Serial.println("");
      if ((BitCount>29*4) && (nib(0)==0) && (nib(1)==0xE)) {
	Serial.print("DATA: T= ");
	tempC=(nib(26)*10-50 + nib(27) + ( (float) nib(28))/10);
	tempF=tempC*9/5 + 32;
	h=nib(15)*10+nib(16);
	Serial.print(tempC,1);	/* print to 0.1 deg precision */
	Serial.print(" degC, ");
	Serial.print(tempF,1);	/* print to 0.1 deg precision */
	Serial.print(" degF, H= ");
	Serial.print(h,DEC);
	Serial.print(" rawT ");
 	Serial.print(nib(26),HEX);
 	Serial.print(nib(27),HEX);
 	Serial.print(nib(28),HEX);
      } else {
	Serial.print("garbled packet, T= ");
	if (BitCount >=29*4) {
	  tempC=(nib(26)*10-50 + nib(27) + ( (float) nib(28))/10);
	  Serial.print(tempC,1);
	} else {
	  Serial.print("NaN");
	}
      }
      Serial.println("");
    }
    BitCount=0;
  }
}

// get a nibble
byte nib(byte bc) {

byte tmp;

 tmp = ((BitVal[bc*4+1] << 3) + (BitVal[bc*4+2] << 2) + (BitVal[bc*4+3] << 1) + (BitVal[bc*4+4]));
/*  Serial.print(BitVal[bc*4+1],DEC); */
/*  Serial.print(BitVal[bc*4+2],DEC); */
/*  Serial.print(BitVal[bc*4+3],DEC); */
/*  Serial.println(BitVal[bc*4+4],DEC); */
/*  Serial.println(tmp,BIN); */
/*  Serial.println(tmp,HEX); */
 return tmp;
}
