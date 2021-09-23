//
//  G711Codec.m
//
//
//  Created by HYEONJUN PARK on 2020/12/24.
//

#import <Foundation/Foundation.h>
#import <RTPAudioCodec.h>
#include "G711.h"
#include <iostream>
#include <memory>


@interface G711Codec : NSObject<RTPAudioCodec>{
    int mode;
}
@end

@implementation G711Codec
typedef NS_ENUM(NSInteger, ConversionMode) {
    LinearToPCMA = 1,
    PCMAToLinear,
    LinearToPCMU,
    PCMUToLinear,
};
@synthesize codecType;
-(instancetype) init:(ConversionMode) conversionMode {
    if( self = [super init] ) {
        mode = (int)conversionMode;
        codecType = g711;
    }
    return self;
}

-(void)dealloc {
    //NSLog(@"dealloc");
}

-(NSData*)encode:(NSData*)data {
    NSInteger length = data.length / 2;
    auto packets = std::make_unique<uint8_t[]>(length);
    G711_Encode((unsigned char*)packets.get(), (unsigned char*)data.bytes, data.length, mode);
    return [NSData dataWithBytes:packets.get() length:length];
}


-(NSData*)decode:(NSData*)data {
    NSInteger length = data.length * 2;
    auto decodedData = std::make_unique<unsigned char[]>(length);
    G711_Decode(decodedData.get(), (unsigned char*)data.bytes, data.length, mode);
    return [NSData dataWithBytes:decodedData.get() length:length];
}

@end
