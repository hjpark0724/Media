// #define LITTLE_ENDIAN

#include <arpa/inet.h>
#include <stdlib.h>

#define MIN_SEQUENCE        160
#define MAX_SEQUENCE        100000
#define MIN_TIMESTAMP       160
#define MAX_TIMESTAMP       4294960000UL
#define TIME_SLICE          160

#define randomR(a, b)       (rand()%(b-a))+a
#define randomize()         srand((unsigned)time(NULL))


   typedef struct {
   #ifdef LITTLE_ENDIAN
      unsigned short cc:4;      // CSRC count
      unsigned short x:1;       // Extension bit 여부
      unsigned short p:1;       // Padding bit 여부  1 : 있음, 0 : 없음
      unsigned short v:2;       // VERSION default : 2
      unsigned short pt:7;      // PAYLOAD TYPE  ( 0 : G.711 U-law,  2 : G.726 32kbps,  3 : GSM,  4 : G.723,  8 : G.711 A-law,  15 : G.728,  18 : G.729
      unsigned short m:1;       // Marker bit   Silence Suppression이 끝나고 말을 시작하는 첫번째 RTP 패킷에서 마킹
   #else
      unsigned short v:2;       // VERSION default : 2
      unsigned short p:1;       // Padding bit 여부  1 : 있음, 0 : 없음
      unsigned short x:1;       // Extension bit 여부
      unsigned short cc:4;      // CSRC count
      unsigned short m:1;       // Marker bit   Silence Suppression이 끝나고 말을 시작하는 첫번째 RTP 패킷에서 마킹
      unsigned short pt:7;      // PAYLOAD TYPE  ( 0 : G.711 U-law,  2 : G.726 32kbps,  3 : GSM,  4 : G.723,  8 : G.711 A-law,  15 : G.728,  18 : G.729
   #endif
      unsigned short seq;    // Sequence Number
//      long timestamp; // RTP 패킷의 발생시간
//      long ssrc;      // Synchronization Source Identifier
	   int timestamp; // RTP 패킷의 발생시간
	   int ssrc;      // Synchronization Source Identifier
   } _rtp_header;

   typedef struct {
      unsigned char events;
   #ifdef LITTLE_ENDIAN
      unsigned char volume:6;
      unsigned char r:1;
      unsigned char e:1;
   #else
      unsigned char e:1;
      unsigned char r:1;
      unsigned char volume:6;
   #endif
      unsigned short duration;
   } _dtmf_event;

   typedef struct {
      _rtp_header rHeader;
      unsigned char buffer[1500];
   } rtp_stream;

   typedef struct {
      _rtp_header rHeader;
      _dtmf_event event;
   } dtmf_stream;

   typedef struct {
   #ifdef LITTLE_ENDIAN
      unsigned short rc:5;
      unsigned short p:1;
      unsigned short v:2;
   #else
      unsigned short v:2;
      unsigned short p:1;
      unsigned short rc:5;
   #endif
      unsigned char type;
      unsigned short length;
//      long ssrc;
	   int ssrc;
   } _rtcp_header;

   typedef struct {
      double ntptimestamp;   // NTP TimeStamp
//      long rtptimestamp;     // RTP TimeStamp
//      long spc;              // Sender's packet count
//      long soc;              // Sender's Octet count
	   int rtptimestamp;     // RTP TimeStamp
	   int spc;              // Sender's packet count
	   int soc;              // Sender's Octet count
	   
   } _sender_info;

   typedef struct {
//      long ssrc_n;  // 소스식별자
	   int ssrc_n;  // 소스식별자
   #ifdef LITTLE_ENDIAN
//      long cnpl:24; // Comulative number of packets lost
//      long fc:8;
	   int cnpl:24; // Comulative number of packets lost
	   int fc:8;
   #else
//      long fc:8;
//      long cnpl:24; // Comulative number of packets lost
	   int fc:8;
	   int cnpl:24; // Comulative number of packets lost
#endif
//      long esnr;    // Extended Highest Sequence Number Received
//      long jitter;  // Interarrival Jitter
//      long lsr;     // Last SR Timestamp
//      long dlsr;    // Delay since last SR
	   int esnr;    // Extended Highest Sequence Number Received
	   int jitter;  // Interarrival Jitter
	   int lsr;     // Last SR Timestamp
	   int dlsr;    // Delay since last SR
   } _report_block;
