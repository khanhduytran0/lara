//
//  fileutils.m
//  lara
//
//  Created by ruter on 26.03.26.
//

#import "fileutils.h"
#include <fcntl.h>
#include <unistd.h>
#include <sys/stat.h>
#include <dirent.h>

@implementation FileUtils

+ (int)open:(NSString *)path {
    int fd = open([path UTF8String], O_RDONLY);
    if (fd == -1) {
        NSLog(@"FILE-UTILS: Unable to open: %@", path);
        return -1;
    }
    return fd;
}

+ (void)close:(int)fd {
    close(fd);
}

+ (NSData * _Nullable)read:(int)fd size:(NSUInteger)size {
    if (size == 0) return nil;
    NSMutableData *data = [NSMutableData dataWithLength:size];
    ssize_t len = read(fd, [data mutableBytes], size);
    if (len <= 0) return nil;
    data.length = len;
    return data;
}

+ (NSData * _Nullable)readFile:(NSString *)path seek:(off_t)seek length:(NSUInteger)length {
    int fd = [self open:path];
    if (fd == -1) return nil;

    if (seek) lseek(fd, seek, SEEK_SET);

    NSMutableData *data = [NSMutableData data];
    size_t bufferSize = 0x4000;
    uint8_t buffer[bufferSize];

    NSUInteger remaining = length;
    while (YES) {
        size_t sizeToRead = remaining ? MIN(bufferSize, remaining) : bufferSize;
        ssize_t len = read(fd, buffer, sizeToRead);
        if (len <= 0) break;
        [data appendBytes:buffer length:len];

        if (remaining) {
            remaining -= len;
            if (remaining == 0) break;
        }
    }

    [self close:fd];
    return data;
}

+ (BOOL)writeFile:(NSString *)path data:(NSData *)data {
    int fd = open([path UTF8String], O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd == -1) {
        NSLog(@"FILE-UTILS: Unable to open: %@", path);
        return NO;
    }

    ssize_t written = write(fd, [data bytes], [data length]);
    close(fd);
    return written == [data length];
}

+ (BOOL)appendFile:(NSString *)path data:(NSData *)data {
    int fd = open([path UTF8String], O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd == -1) {
        NSLog(@"FILE-UTILS: Unable to open: %@", path);
        return NO;
    }

    ssize_t written = write(fd, [data bytes], [data length]);
    close(fd);
    return written == [data length];
}

+ (void)deleteFile:(NSString *)path {
    unlink([path UTF8String]);
}

+ (void)foreachDir:(NSString *)path block:(void (^)(NSString *name))block {
    DIR *dir = opendir([path UTF8String]);
    if (!dir) { NSLog(@"FILE-UTILS: Unable to open dir: %@", path); return; }

    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (entry->d_type == DT_DIR && entry->d_name[0] != '.') {
            block([NSString stringWithUTF8String:entry->d_name]);
        }
    }
    closedir(dir);
}

+ (BOOL)foreachFile:(NSString *)path block:(void (^)(NSString *name))block {
    DIR *dir = opendir([path UTF8String]);
    if (!dir) { NSLog(@"FILE-UTILS: Unable to open dir: %@", path); return NO; }

    struct dirent *entry;
    while ((entry = readdir(dir))) {
        if (entry->d_type == DT_REG) {
            block([NSString stringWithUTF8String:entry->d_name]);
        }
    }
    closedir(dir);
    return YES;
}

+ (BOOL)createDir:(NSString *)path permission:(mode_t)permission {
    return mkdir([path UTF8String], permission) == 0;
}

+ (BOOL)deleteDir:(NSString *)path recursive:(BOOL)recursive {
    if (recursive) {
        DIR *dir = opendir([path UTF8String]);
        if (!dir) { NSLog(@"FILE-UTILS: deleteDir unable to open %@", path); return NO; }

        struct dirent *entry;
        while ((entry = readdir(dir))) {
            NSString *name = [NSString stringWithUTF8String:entry->d_name];
            if ([name hasPrefix:@"."]) continue;
            NSString *fullPath = [path stringByAppendingPathComponent:name];

            if (entry->d_type == DT_DIR) {
                [self deleteDir:fullPath recursive:YES];
            } else if (entry->d_type == DT_REG) {
                [self deleteFile:fullPath];
            }
        }
        closedir(dir);
    }
    return rmdir([path UTF8String]) == 0;
}

+ (BOOL)exists:(NSString *)path permission:(int)permission {
    return access([path UTF8String], permission) == 0;
}

+ (NSDictionary * _Nullable)stat:(NSString *)path {
    struct stat st;
    if (stat([path UTF8String], &st) != 0) return nil;

    return @{
        @"mode": @(st.st_mode),
        @"ino": @(st.st_ino),
        @"dev": @(st.st_dev),
        @"nlink": @(st.st_nlink),
        @"uid": @(st.st_uid),
        @"gid": @(st.st_gid),
        @"size": @(st.st_size),
        @"atime": @(st.st_atime),
        @"mtime": @(st.st_mtime),
        @"ctime": @(st.st_ctime)
    };
}

@end
