//-------------------------------------------------------------------------------------//
//
// iLBC Codec For Harbour Interface 
//     Cybertel bridge/Loche
//		    07/16/2013 
//
// rawbuf : 320 bytes (160 short)
// encbuf : 38 bytes (19 short)
// data per 20ms
// enhance mode decoding
//
//-------------------------------------------------------------------------------------//

#include <time.h>
#include "../rtp.h"

#include "iLBC_define.h"
#include "iLBC_encode.h"
#include "iLBC_decode.h"

#define ILBCNOOFWORDS_MAX   (NO_OF_BYTES_20MS/2)

static iLBC_Enc_Inst_t Enc_Inst;
static iLBC_Dec_Inst_t Dec_Inst;

static int bMarker;
//static long wTimeStamp;
//static long seq;
//static long ssrc;
static int wTimeStamp;
static int seq;
static int ssrc;


//-------------------------------------------------------------------------------------//

void iLBC_InitCodec()
{
    initEncode(&Enc_Inst, 20);		// frame size mode : 20ms
    initDecode(&Dec_Inst, 20, 1);	// enhance mode : 1
}

//-------------------------------------------------------------------------------------//

void iLBC_InitVar()
{
    bMarker = 1;
    wTimeStamp = MIN_TIMESTAMP;
    seq = MIN_SEQUENCE;
    ssrc = randomR(31415621, 100000000);
}

//-------------------------------------------------------------------------------------//

int iLBC_Encode(short *rawbuf, short *encbuf, int payloadType)
{
    short encoded_data[ILBCNOOFWORDS_MAX];  // 19
    float block[BLOCKL_20MS];               // 160
    int k;
    
    _rtp_header header;

    /* convert signal to float */

    for (k=0; k<Enc_Inst.blockl; k++)
    	block[k] = (float)rawbuf[k];

    /* do the actual encoding */

    iLBC_encode((unsigned char *)encoded_data, block, &Enc_Inst);
    
    if ((wTimeStamp += TIME_SLICE) >= MAX_TIMESTAMP)
        wTimeStamp = MIN_TIMESTAMP;
    
    if (++seq > MAX_SEQUENCE)
        seq = MIN_SEQUENCE;
    
    header.v = 2;       // Version
    header.p = 0;       // Padding Bit
    header.x = 0;       // Option Field
    header.cc = 0;      // CSRC Count
    
    if (bMarker)
        header.m = 1;   // Marker Bit
    else
        header.m = 0;
    
    header.pt = payloadType;
    
    header.seq = htons((unsigned short)seq);    // Sequence Number
    header.timestamp = htonl(wTimeStamp);       // TimeStamp
    header.ssrc = htonl(ssrc);
    
    memcpy((unsigned char *)encbuf, (unsigned char *)&header, 12);
    memcpy((unsigned char *)encbuf + 12, (unsigned char *)encoded_data, 38);
    
    if (bMarker)
        bMarker = 0;

    return (Enc_Inst.no_of_bytes);
}

//-------------------------------------------------------------------------------------//

int iLBC_Decode(short *encbuf, short *rawbuf)
{
    int k;
    float decblock[BLOCKL_20MS], dtmp;
    short encoded_data[ILBCNOOFWORDS_MAX];  // 19
    
    memcpy((unsigned char *)encoded_data, (unsigned char *)encbuf + 12, NO_OF_BYTES_20MS);

    /* do actual decoding of block */

    iLBC_decode(decblock, (unsigned char *)encbuf, &Dec_Inst, 1);

    /* convert to short */

    for (k=0; k<Dec_Inst.blockl; k++){
        dtmp = decblock[k];

        if (dtmp < MIN_SAMPLE)
            dtmp = MIN_SAMPLE;
        else if (dtmp > MAX_SAMPLE)
            dtmp = MAX_SAMPLE;

        rawbuf[k] = (short)dtmp;
    }

    return (Dec_Inst.blockl);
}

//-------------------------------------------------------------------------------------//
