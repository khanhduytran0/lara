//
//  fileutils.h
//  lara
//
//  Created by ruter on 26.03.26.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FileUtils : NSObject

+ (int)open:(NSString *)path;
+ (void)close:(int)fd;
+ (NSData * _Nullable)read:(int)fd size:(NSUInteger)size;
+ (NSData * _Nullable)readFile:(NSString *)path seek:(off_t)seek length:(NSUInteger)length;
+ (BOOL)writeFile:(NSString *)path data:(NSData *)data;
+ (BOOL)appendFile:(NSString *)path data:(NSData *)data;
+ (void)deleteFile:(NSString *)path;

+ (void)foreachDir:(NSString *)path block:(void (^)(NSString *name))block;
+ (BOOL)foreachFile:(NSString *)path block:(void (^)(NSString *name))block;
+ (BOOL)createDir:(NSString *)path permission:(mode_t)permission;
+ (BOOL)deleteDir:(NSString *)path recursive:(BOOL)recursive;

+ (BOOL)exists:(NSString *)path permission:(int)permission;
+ (NSDictionary * _Nullable)stat:(NSString *)path;

@end

NS_ASSUME_NONNULL_END
