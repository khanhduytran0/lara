//
//  peutils.m
//  lara
//
//  Created by ruter on 26.03.26.
//

#import "peutils.h"

@implementation Utils

+ (NSString *)hex:(uint64_t)val {
    return [NSString stringWithFormat:@"%llx", val];
}

+ (NSInteger)memmem:(NSData *)haystack needle:(NSData *)needle {
    const uint8_t *h = haystack.bytes;
    const uint8_t *n = needle.bytes;
    NSUInteger hLen = haystack.length;
    NSUInteger nLen = needle.length;

    if (nLen == 0 || hLen < nLen) return 0;

    for (NSUInteger i = 0; i <= hLen - nLen; i++) {
        BOOL found = YES;
        for (NSUInteger j = 0; j < nLen; j++) {
            if (h[i+j] != n[j]) { found = NO; break; }
        }
        if (found) return i;
    }
    return 0;
}

+ (void)printArrayBufferInChunks:(NSData *)buffer {
    const uint8_t *bytes = buffer.bytes;
    NSUInteger len = buffer.length;
    for (NSUInteger i = 0; i < len; i += 8) {
        uint64_t chunk = 0;
        NSUInteger chunkSize = MIN(8, len - i);
        memcpy(&chunk, bytes + i, chunkSize);
        NSLog(@"UTILS: 0x%zx: %llx", i, chunk);
    }
}

+ (uint64_t)ptrauthStringDiscriminator:(NSString *)discriminator {
    if ([discriminator isEqualToString:@"pc"]) return 0x7481;
    if ([discriminator isEqualToString:@"lr"]) return 0x77d3;
    if ([discriminator isEqualToString:@"sp"]) return 0xcbed;
    if ([discriminator isEqualToString:@"fp"]) return 0x4517;
    NSLog(@"UTILS: Cannot find discriminator for value: %@", discriminator);
    return 0;
}

+ (uint64_t)ptrauthStringDiscriminatorSpecial:(NSString *)discriminator {
    if ([discriminator isEqualToString:@"pc"]) return 0x7481000000000000;
    if ([discriminator isEqualToString:@"lr"]) return 0x77d3000000000000;
    if ([discriminator isEqualToString:@"sp"]) return 0xcbed000000000000;
    if ([discriminator isEqualToString:@"fp"]) return 0x4517000000000000;
    NSLog(@"UTILS: Cannot find discriminator for value: %@", discriminator);
    return 0;
}

+ (uint64_t)ptrauthBlendDiscriminator:(uint64_t)diver discriminator:(uint64_t)discriminator {
    return (diver & 0xFFFFFFFFFFFF) | discriminator;
}

+ (NSInteger)MIN:(NSInteger)a b:(NSInteger)b {
    return a < b ? a : b;
}

+ (NSInteger)MAX:(NSInteger)a b:(NSInteger)b {
    return a > b ? a : b;
}

@end
