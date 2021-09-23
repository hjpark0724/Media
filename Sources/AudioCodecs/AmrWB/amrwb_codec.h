#pragma once
#ifdef __cplusplus
extern "C" {
#endif
class CAmrwb
{
public:
	CAmrwb();
	virtual ~CAmrwb();

	void InitCodec();
	void CloseCodec();
	void InitVar(int _ssrc);
    //void SetSsrc(int _ssrc);
	void Encode(uint8_t * rawbuf, uint8_t * packets, int bitmode);
	void Decode(uint8_t * packets, uint8_t * rawbuf);
	void DecodeShortBuf(uint8_t * packets, short * rawbuf);
	void MakeHeaderHWcodec(uint8_t * header, int payloadType);
	void MakeHeaderNBHWcodec(uint8_t * header, int payloadType);
protected:
	void *enst;
    void *dest;
    //int bMarker;
    //long wTimeStamp;
    //long seq;
    //long ssrc;

};
#ifdef __cplusplus
}
#endif
