
#include "G711.h"
#include <iostream>
#define  LOBYTE(w)		((unsigned char)(w))
#define  HIBYTE(w)		((unsigned char)(((short)(w) >> 8) & 0xFF))

#define  SIGN_BIT		(0x80)                     /* Sign bit for a A-law byte. */
#define  QUANT_MASK		(0xf)                      /* Quantization field mask. */
#define  NSEGS			(8)                        /* Number of A-law segments. */
#define  SEG_SHIFT		(4)                        /* Left shift for segment number. */
#define  SEG_MASK		(0x70)                     /* Segment field mask. */

#define  BIAS			(0x84)                     /* Bias for linear code. */
#define  CLIP			8159

static short seg_aend[8] = {0x1F, 0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF};
static short seg_uend[8] = {0x3F, 0x7F, 0xFF, 0x1FF, 0x3FF, 0x7FF, 0xFFF, 0x1FFF};

/* copy from CCITT G.711 specifications */
static unsigned char _u2a[128] = {  /* u- to A-law conversions */
	1,    1,    2,    2,    3,    3,    4,    4,
	5,    5,    6,    6,    7,    7,    8,    8,
	9,   10,   11,   12,   13,   14,   15,   16,
	17,   18,   19,   20,   21,   22,   23,   24,
	25,   27,   29,   31,   33,   34,   35,   36,
	37,   38,   39,   40,   41,   42,   43,   44,
	46,   48,   49,   50,   51,   52,   53,   54,
	55,   56,   57,   58,   59,   60,   61,   62,
	64,   65,   66,   67,   68,   69,   70,   71,
	72,   73,   74,   75,   76,   77,   78,   79,
	80,   82,   83,   84,   85,   86,   87,   88,
	89,   90,   91,   92,   93,   94,   95,   96,
	97,   98,   99,  100,  101,  102,  103,  104,
	105,  106,  107,  108,  109,  110,  111,  112,
	113,  114,  115,  116,  117,  118,  119,  120,
	121,  122,  123,  124,  125,  126,  127,  128 };

static unsigned char _a2u[128] = {  /* A- to u-law conversions */
	  1,    3,    5,    7,    9,   11,   13,   15,
	 16,   17,   18,   19,   20,   21,   22,   23,
	 24,   25,   26,   27,   28,   29,   30,   31,
	 32,   32,   33,   33,   34,   34,   35,   35,
	 36,   37,   38,   39,   40,   41,   42,   43,
	 44,   45,   46,   47,   48,   48,   49,   49,
	 50,   51,   52,   53,   54,   55,   56,   57,
	 58,   59,   60,   61,   62,   63,   64,   64,
	 65,   66,   67,   68,   69,   70,   71,   72,
	 73,   74,   75,   76,   77,   78,   79,   80,
	 80,   81,   82,   83,   84,   85,   86,   87,
	 88,   89,   90,   91,   92,   93,   94,   95,
	 96,   97,   98,   99,  100,  101,  102,  103,
	104,  105,  106,  107,  108,  109,  110,  111,
	112,  113,  114,  115,  116,  117,  118,  119,
	120,  121,  122,  123,  124,  125,  126,  127 };

static int bMarker;
//static long wTimeStamp;
//static long seq;
//static long ssrc;
static int wTimeStamp;
static int seq;
static int ssrc;

void G711_Codec(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode);
short search(short val, short *table, short size);
unsigned char linear2alaw(short pcm_val);
short alaw2linear(unsigned char a_val);
unsigned char linear2ulaw(short pcm_val);
short ulaw2linear(unsigned char u_val);
unsigned char alaw2ulaw(unsigned char aval);
unsigned char ulaw2alaw(unsigned char uval);
short swap_linear(short pcm_val);

void G711_InitVar()
{
    bMarker = 1;
    wTimeStamp = MIN_TIMESTAMP;
    seq = MIN_SEQUENCE;
	ssrc = randomR(31415621, 100000000);
}

void G711_Decode(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode)
{
    G711_Codec(pStream, pSource, nLen, nMode);
}

void G711_Encode(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode)
{
    G711_Codec(pStream, pSource, nLen, nMode);
}

void G711_Codec(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode)
{
	int i;
	int nStep = 0;
	int nLength;
	short nTemp;
	short *iSource = 0;
	unsigned char cChr;
	unsigned char *cSource = 0;

	switch (nMode)
	{
	case 1:     // linear PCM -> A-law PCM
	case 3:     // linear PCM -> U-law PCM
		nStep = nLen/sizeof(short);
		nLength = nStep;
		iSource = new short[nLen];
		memcpy((short *)iSource, pSource, nLen);
		break;
	case 2:    // A-law PCM -> linear PCM
	case 4:    // U-law PCM -> linear PCM
		nStep = nLen;
		nLength = nStep*2;
		cSource = new unsigned char[nLen];
		memcpy(cSource, pSource, nLen);
		break;
	}

	for (i=0; i<nStep; i++)
	{
		switch (nMode)
		{
		case 1:  // PCM -> ALAW
			pStream[i] = (unsigned char)(linear2alaw(iSource[i]));
			break;
		case 2:  // ALAW -> PCM
			nTemp = alaw2linear( cSource[i] );
			pStream[2*i] = (unsigned char)LOBYTE(nTemp);
			pStream[2*i+1] = (unsigned char)HIBYTE(nTemp);
			break;
		case 3:  // PCM -> ULAW
			pStream[i] = (unsigned char)(linear2ulaw(iSource[i]));
			break;
		case 4:  // ULAW -> PCM
			cChr = ulaw2alaw(cSource[i]);
			nTemp = alaw2linear(cChr);
			pStream[2*i] = (unsigned char)LOBYTE(nTemp);
			pStream[2*i+1] = (unsigned char)HIBYTE(nTemp);
			break;
		}
	}
    
	if (nMode == 1 || nMode == 3)
		delete[] iSource;	//free(iSource);

	if (nMode == 2 || nMode == 4)
		delete[] cSource;	//free(cSource);
}

short search(short val, short *table, short size)
{
	short i;

	for(i = 0; i < size; i++)
	{
		if (val <= *table++)
			return (i);
	}

	return (size);
}

unsigned char linear2alaw(short pcm_val)      /* 2's complement (16-bit range) */
{
	short mask;
	short seg;
	unsigned char aval;

	pcm_val = pcm_val >> 3;

	if (pcm_val >= 0)
		mask = 0xD5;                        /* sign (7th) bit = 1 */
	else
	{
		mask = 0x55;                        /* sign bit = 0 */
		pcm_val = -pcm_val - 1;
	}

	/* Convert the scaled magnitude to segment number. */
	seg = search(pcm_val, seg_aend, 8);

	/* Combine the sign, segment, and quantization bits. */

	if (seg >= 8)							/* out of range, return maximum value. */
		return (unsigned char)(0x7F ^ mask);
	else
	{
		aval = (unsigned char)seg << SEG_SHIFT;
		if (seg < 2)
			aval |= (pcm_val >> 1) & QUANT_MASK;
		else
			aval |= (pcm_val >> seg) & QUANT_MASK;

		return (aval ^ mask);
	}
}

short alaw2linear(unsigned char a_val)
{
	short t;
	short seg;

	a_val ^= 0x55;

	t = (a_val & QUANT_MASK) << 4;
	seg = ((unsigned)a_val & SEG_MASK) >> SEG_SHIFT;

	switch (seg)
	{
	case 0:
		t += 8;
		break;
	case 1:
		t += 0x108;
		break;
	default:
		t += 0x108;
		t <<= seg - 1;
	}

	return ((a_val & SIGN_BIT) ? t : -t);
}

unsigned char linear2ulaw(short pcm_val)            /* 2's complement (16-bit range) */
{
	short mask;
	short seg;
	unsigned char uval;

	/* Get the sign and the magnitude of the value. */
	pcm_val = pcm_val >> 2;

	if (pcm_val < 0)
	{
		pcm_val = -pcm_val;
		mask = 0x7F;
	}
	else
		mask = 0xFF;

	if (pcm_val > CLIP) pcm_val = CLIP;				/* clip the magnitude */
		pcm_val += (BIAS >> 2);

	/* Convert the scaled magnitude to segment number. */
	seg = search(pcm_val, seg_uend, 8);

	/*
	 * Combine the sign, segment, quantization bits;
	 * and complement the code word.
	*/
	if (seg >= 8)									/* out of range, return maximum value. */
		return (unsigned char)(0x7F ^ mask);
	else
	{
		uval = (unsigned char)(seg << 4) | ((pcm_val >> (seg + 1)) & 0xF);
		return (uval ^ mask);
	}
}

short ulaw2linear(unsigned char u_val)
{
	short t;

	/* Complement to obtain normal u-law value. */
	u_val = ~u_val;

	/*
	 * Extract and bias the quantization bits. Then
	 * shift up by the segment number and subtract out the bias.
	*/
	t = ((u_val & QUANT_MASK) << 3) + BIAS;
	t <<= ((unsigned)u_val & SEG_MASK) >> SEG_SHIFT;

	return ((u_val & SIGN_BIT) ? (BIAS - t) : (t - BIAS));
}

unsigned char alaw2ulaw(unsigned char aval)
{
	aval &= 0xff;
	return (unsigned char)((aval & 0x80) ? (0xFF ^ _a2u[aval ^ 0xD5]) : (0x7F ^ _a2u[aval ^ 0x55]));
}

unsigned char ulaw2alaw(unsigned char uval)
{
	uval &= 0xff;
	return (unsigned char)((uval & 0x80) ? (0xD5 ^ (_u2a[0xFF ^ uval] - 1)) : (unsigned char)(0x55 ^ (_u2a[0x7F ^ uval] - 1)));
}

short swap_linear(short pcm_val)
{
	struct lohibyte { unsigned char lb, hb;};
	union { struct lohibyte b;
			short i;
	} exchange;
	unsigned char c;

	exchange.i      = pcm_val;
	c               = exchange.b.hb;
	exchange.b.hb   = exchange.b.lb;
	exchange.b.lb   = c;

	return (exchange.i);
}
