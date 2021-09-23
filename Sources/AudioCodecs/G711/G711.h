//
//  G711.h
//  
//
//  Created by HYEONJUN PARK on 2021/05/14.
//

#ifndef G711_h
#define G711_h
#include <cstring>
#include <cstdlib>
#include <time.h>
#include "../rtp.h"

void G711_Decode(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode);
void G711_Encode(unsigned char *pStream, unsigned char *pSource, short nLen, short nMode);

#endif
