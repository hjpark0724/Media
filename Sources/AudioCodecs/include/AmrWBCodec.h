
#import <Foundation/Foundation.h>
#import <RTPAudioCodec.h>
typedef NS_ENUM(NSInteger, BitrateMode) {
    BitrateModeMode_7k,
    BitrateModeMode_9k,
    BitrateModeMode_12k,
    BitrateModeMode_14k,
    BitrateModeMode_16k,
    BitrateModeMode_18k,
    BitrateModeMode_20k,
    BitrateModeMode_23k,
    BitrateModeMode_24k,
};

@interface AmrWBCodec : NSObject<RTPAudioCodec>
-(instancetype) init:(BitrateMode) bitmode;
-(NSData*)encode:(NSData*)data;
-(NSData*)decode:(NSData*)data;
@end
