/*
   ITU-T G.729 Annex C - Reference C code for floating point
                         implementation of G.729 Annex A
                         Version 1.01 of 15.September.98
*/

/*
----------------------------------------------------------------------
                    COPYRIGHT NOTICE
----------------------------------------------------------------------
   ITU-T G.729 Annex C ANSI C source code
   Copyright (C) 1998, AT&T, France Telecom, NTT, University of
   Sherbrooke.  All rights reserved.

----------------------------------------------------------------------
*/

/*
 File : CODERA.C
 Used for the floating point version of G.729A only
 (not for G.729 main body)
*/

/*-------------------------------------------------------------------*
 * Main program of the ITU-T G.729A  8 kbit/s encoder.               *
 *                                                                   *
 *    Usage : coder speech_file  bitstream_file                      *
 *-------------------------------------------------------------------*/
#include <time.h>
#include "typedef.h"
#include "ld8a.h"
#include "../rtp.h"
#include <string.h>

static FFLOAT m_synth_buf[L_FRAME+M];
static FFLOAT *m_synth;
int bad_lsf;        /* bad LSF indicator   */
static FFLOAT  m_Az_dec[MP1*2];            /* Decoded Az for post-filter */
static int    m_T2[2];
static int m_prm[PRM_SIZE+2];

static int bMarker;
//static long wTimeStamp;
//static long seq;
//static long ssrc;
static int wTimeStamp;
static int seq;
static int ssrc;


void va_g729a_init_encoder()
{
/*
	cod_lsp_old[0]=(F)0.9595;
	cod_lsp_old[1]=(F)0.8413;
	cod_lsp_old[2]=(F)0.6549;
	cod_lsp_old[3]=(F)0.4154;
	cod_lsp_old[4]=(F)0.1423;
	cod_lsp_old[5]=(F)-0.1423;
	cod_lsp_old[6]=(F)-0.4154;
	cod_lsp_old[7]=(F)-0.6549;
	cod_lsp_old[8]=(F)-0.8413;
	cod_lsp_old[9]=(F)-0.9595;
*/
/*
	m_qua_gain_past_qua_en[0]=(F)-14.0;
	m_qua_gain_past_qua_en[1]=(F)-14.0;
	m_qua_gain_past_qua_en[2]=(F)-14.0;
	m_qua_gain_past_qua_en[3]=(F)-14.0;
*/
	init_pre_process();
	init_coder_ld8a();           /* Initialize the coder             */

}

void va_g729a_encoder(short *speech, unsigned char *bitstream)
{
	extern FFLOAT *new_speech;           /* Pointer to new speech data   */
	static int prm[PRM_SIZE];           /* Transmitted parameters        */
	static INT16 serial[SERIAL_SIZE];   /* Output bit stream buffer      */
	int i,j,k;
	INT16 nb_words;
	int length;
	char buffer[20];
	unsigned char data,mask;
	 

	for (i = 0; i < L_FRAME; i++)  new_speech[i] = (FFLOAT) speech[i];

	pre_process( new_speech, L_FRAME);

	coder_ld8a(prm);

	prm2bits_ld8k(prm, serial);
	nb_words = serial[1] +  2;
	length=0;
	switch( serial[1] )
	{
	  case 0:
		  length=0;
		  for(i=0;i<10;i++)
		  {
			buffer[i]=0;
		  }
		  break;
	  case 15:
	  case 16:
		  length+=2;
		  k=2;
		  for(i=0;i<2;i++)
		  {
			data=0;
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( serial[k++]==BIT_1 )
					data|=mask;
				mask>>=1;
			}
			buffer[i]=data;
		  }
		  for(i=2;i<10;i++)
		  {
			buffer[i]=0;
		  }
			//  buffer+=10;
		  break;
	  case 80:
		  length+=10;
		  k=2;
		  for(i=0;i<10;i++)
		  {
			data=0; // buffer[i];
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( serial[k++]==BIT_1 )
					data|=mask;
				mask>>=1;
			}
			buffer[i]=data;
		  }
		  break;
	}
	memcpy(bitstream,buffer,10);
}

void va_g729a_init_decoder()
{
	int i;
/*
	dec_lsp_old[0]=(F)0.9595;
	dec_lsp_old[1]=(F)0.8413;
	dec_lsp_old[2]=(F)0.6549;
	dec_lsp_old[3]=(F)0.4154;
	dec_lsp_old[4]=(F)0.1423;
	dec_lsp_old[5]=(F)-0.1423;
	dec_lsp_old[6]=(F)-0.4154;
	dec_lsp_old[7]=(F)-0.6549;
	dec_lsp_old[8]=(F)-0.8413;
	dec_lsp_old[9]=(F)-0.9595;
*/
/*
	m_dec_gain_past_qua_en[0]=(F)-14.0;
	m_dec_gain_past_qua_en[1]=(F)-14.0;
	m_dec_gain_past_qua_en[2]=(F)-14.0;
	m_dec_gain_past_qua_en[3]=(F)-14.0;
*/
	for (i=0; i<M; i++)	m_synth_buf[i] = (F)0.0;
	m_synth = m_synth_buf + M;

	bad_lsf = 0;          /* Initialize bad LSF indicator */
	init_decod_ld8a();
	init_post_filter();
	init_post_process();
	
}

void va_g729a_decoder(unsigned char *buffer, short *synth_short, int bfi)
{
	int i,j,k;
	unsigned char data;
	unsigned char mask;
	int length;
	int written;
	INT16 serial[SERIAL_SIZE];       /* Serial stream              */
	FFLOAT temp;

	if( bfi )
		length=0;
	else
		length=10;

	written = 0;
	serial[0] = SYNC_WORD;
	switch( length )
	{
	case 0:
		serial[1]=80;
		for(i=0;i<80;i++)
			serial[i+2]=0;
		break;
	case 1:
		serial[1]=16 /*RATE_SID_OCTET*/;
		k=2;
		for(i=0;i<1;i++)
		{
			data=buffer[i];
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( data&mask )
					serial[k++]=BIT_1;
				else
					serial[k++]=BIT_0;
				mask>>=1;
			}
		}
		for(i=1;i<10;i++)
		{
			for(j=0;j<8;j++)
			{
				serial[k++]=BIT_0;
			}
		}
		written=1;
		break;
	case 4:
		serial[1]=80;
		k=2;
		for(i=0;i<4;i++)
		{
			data=buffer[i];
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( data&mask )
					serial[k++]=BIT_0;
				else
					serial[k++]=BIT_0;
				mask>>=1;
			}
		}
		for(i=4;i<10;i++)
		{
			for(j=0;j<8;j++)
			{
				serial[k++]=BIT_0;
			}
		}
		written=length;
		break;
	case 2:
		serial[1]=80 /*RATE_8000*/;
		k=2;
		for(i=0;i<2;i++)
		{
			data=buffer[i];
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( data&mask )
					serial[k++]=BIT_0;
				else
					serial[k++]=BIT_0;
				mask>>=1;
			}
		}
		for(i=2;i<10;i++)
		{
			for(j=0;j<8;j++)
			{
				serial[k++]=BIT_0;
			}
		}
		written=length;
		break;
	case 10:
		serial[1]=80 /*RATE_8000*/;
		k=2;
		for(i=0;i<10;i++)
		{
			data=buffer[i];
			mask=0x80;
			for(j=0;j<8;j++)
			{
				if( data&mask )
					serial[k++]=BIT_1;
				else
					serial[k++]=BIT_0;
				mask>>=1;
			}
		}
		written+=10;
		break;
	default:
		if( length>=10 )
		{
			serial[1]=80 /*RATE_8000*/;
			k=2;
			for(i=0;i<10;i++)
			{
				data=buffer[i];
				mask=0x80;
				for(j=0;j<8;j++)
				{
					if( data&mask )
						serial[k++]=BIT_1;
					else
						serial[k++]=BIT_0;
					mask>>=1;
				}
			}
			written+=10;
		}
		else
			serial[1]=0;
		break;
	}

    bits2prm_ld8k(&serial[2], &m_prm[1]);

	m_prm[0] = 0;           /* No frame erasure */

    if(serial[1] != 0) {
		for (i=0; i < serial[1]; i++)
		if (serial[i+2] == 0 ) m_prm[0] = 1;  /* frame erased     */
	}
	else if(serial[0] != SYNC_WORD) m_prm[0] = 1;

		/* check parity and put 1 in parm[5] if parity error */
	m_prm[4] = check_parity_pitch(m_prm[3], m_prm[4]);

    decod_ld8a(m_prm, m_synth, m_Az_dec, m_T2);             /* decoder */
    post_filter(m_synth, m_Az_dec, m_T2);                  /* Post-filter */
    post_process(m_synth, L_FRAME);                    /* Highpass filter */

	for (i=0; i<L_FRAME; i++) {
	/* round and convert to int  */
		temp = m_synth[i];
		if (temp >= (F)0.0)
			temp += (F)0.5;
		else
			temp -= (F)0.5;

		if (temp >  (F)32767.0 ) temp = (F)32767.0;
		if (temp < (F)-32768.0 ) temp = (F)-32768.0;
		synth_short[i] = (INT16) temp;
	}

}

void G729_InitCodec()
{
    va_g729a_init_encoder();
    va_g729a_init_decoder();
}

void G729_InitVar()
{
    randomize();	//System Only 1 Try G729
    
    bMarker = 1;
    wTimeStamp = MIN_TIMESTAMP;
    seq = MIN_SEQUENCE;
    ssrc = randomR(31415621, 100000000);
}

void G729_Encode(short *speech, int offset, unsigned char *bitstream, int payloadType)
{
    _rtp_header header;
    unsigned char encPkt[20];
    
    va_g729a_encoder((short *)((unsigned char *)speech + offset), encPkt);
    va_g729a_encoder((short *)((unsigned char *)speech + offset + 160), encPkt + 10);

    if ((wTimeStamp += TIME_SLICE) >= MAX_TIMESTAMP)
        wTimeStamp = MIN_TIMESTAMP;
    
    if (++seq > MAX_SEQUENCE)
        seq = MIN_SEQUENCE;
    
    header.v = 2;      // VERSION
    header.p = 0;      // PADDING BIT
    header.x = 0;      // OPTION FIELD
    header.cc = 0;     // CSRC COUNT
    
    if( bMarker )                 // MARKER BIT
        header.m = 1;
    else
        header.m = 0;
    
    header.pt = payloadType;
    
    header.seq = htons((unsigned short)seq); // SEQUENCE NUMBER
    header.timestamp = htonl(wTimeStamp);    // TIMESTAMP
    header.ssrc = htonl(ssrc);
    
    memcpy(bitstream, (unsigned char *)&header, 12);
    memcpy(bitstream + 12, encPkt, 20);
    
    if (bMarker)
        bMarker = 0;
}

void G729_Decode(unsigned char *buffer, int offset, short *synth_short, int bfi)
{
    va_g729a_decoder((unsigned char *)buffer, (short *)((unsigned char *)synth_short + offset), bfi);
    va_g729a_decoder((unsigned char *)buffer + 10, (short *)((unsigned char *)synth_short + offset + 160), bfi);
}

