//
//  peutils.h
//  lara
//
//  Created by ruter on 26.03.26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface Utils : NSObject

+ (NSString *)hex:(uint64_t)val;
+ (NSInteger)memmem:(NSData *)haystack needle:(NSData *)needle;
+ (void)printArrayBufferInChunks:(NSData *)buffer;

+ (uint64_t)ptrauthStringDiscriminator:(NSString *)discriminator;
+ (uint64_t)ptrauthStringDiscriminatorSpecial:(NSString *)discriminator;
+ (uint64_t)ptrauthBlendDiscriminator:(uint64_t)diver discriminator:(uint64_t)discriminator;

+ (NSInteger)MIN:(NSInteger)a b:(NSInteger)b;
+ (NSInteger)MAX:(NSInteger)a b:(NSInteger)b;

@end

NS_ASSUME_NONNULL_END
