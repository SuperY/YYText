//
//  UIPasteboard+YYText.m
//  YYText <https://github.com/ibireme/YYText>
//
//  Created by ibireme on 15/4/2.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "UIPasteboard+YYText.h"
#import "NSAttributedString+YYText.h"
#import <CoreServices/CoreServices.h>


#if __has_include("YYImage.h")
#import "YYImage.h"
#define YYTextAnimatedImageAvailable 1
#elif __has_include(<YYImage/YYImage.h>)
#import <YYImage/YYImage.h>
#define YYTextAnimatedImageAvailable 1
#elif __has_include(<YYWebImage/YYImage.h>)
#import <YYWebImage/YYImage.h>
#define YYTextAnimatedImageAvailable 1
#else
#define YYTextAnimatedImageAvailable 0
#endif


const CFStringRef kUTTypeYYTextAttributedString = CFSTR("com.ibireme.NSAttributedString");
const CFStringRef kUTTypeYYTextWEBP = CFSTR("com.google.webp");

@implementation UIPasteboard (YYText)


- (void)setYy_PNGData:(NSData *)PNGData {
    [self setData:PNGData forPasteboardType:(id)kUTTypePNG];
}

- (NSData *)yy_PNGData {
    return [self dataForPasteboardType:(id)kUTTypePNG];
}

- (void)setYy_JPEGData:(NSData *)JPEGData {
    [self setData:JPEGData forPasteboardType:(id)kUTTypeJPEG];
}

- (NSData *)yy_JPEGData {
    return [self dataForPasteboardType:(id)kUTTypeJPEG];
}

- (void)setYy_GIFData:(NSData *)GIFData {
    [self setData:GIFData forPasteboardType:(id)kUTTypeGIF];
}

- (NSData *)yy_GIFData {
    return [self dataForPasteboardType:(id)kUTTypeGIF];
}

- (void)setYy_WEBPData:(NSData *)WEBPData {
    [self setData:WEBPData forPasteboardType:(__bridge NSString *)kUTTypeYYTextWEBP];
}

- (NSData *)yy_WEBPData {
    return [self dataForPasteboardType:(__bridge NSString *)kUTTypeYYTextWEBP];
}

- (void)setYy_ImageData:(NSData *)imageData {
    [self setData:imageData forPasteboardType:(id)kUTTypeImage];
}

- (NSData *)yy_ImageData {
    return [self dataForPasteboardType:(id)kUTTypeImage];
}

- (void)setYy_AttributedString:(NSAttributedString *)attributedString {
    self.string = [attributedString yy_plainTextForRange:[attributedString yy_rangeOfAll]];
    NSData *data = [attributedString yy_archiveToDataWithError: NULL];
    if (data) {
        NSDictionary *item = @{(__bridge NSString *)kUTTypeYYTextAttributedString : data};
        [self addItems:@[item]];
    }
    [attributedString enumerateAttribute:YYTextAttachmentAttributeName inRange:NSMakeRange(0, attributedString.length) options:NSAttributedStringEnumerationLongestEffectiveRangeNotRequired usingBlock:^(YYTextAttachment *attachment, NSRange range, BOOL *stop) {
        
        // save image
        UIImage *simpleImage = nil;
        if ([attachment.content isKindOfClass:[UIImage class]]) {
            simpleImage = attachment.content;
        } else if ([attachment.content isKindOfClass:[UIImageView class]]) {
            simpleImage = ((UIImageView *)attachment.content).image;
        }
        if (simpleImage) {
            NSDictionary *item = @{@"com.apple.uikit.image" : simpleImage};
            [self addItems:@[item]];
        }
        
#if YYTextAnimatedImageAvailable
        // save animated image
        if ([attachment.content isKindOfClass:[UIImageView class]]) {
            UIImageView *imageView = attachment.content;
            Class aniImageClass = NSClassFromString(@"YYImage");
            UIImage *image = imageView.image;
            if (aniImageClass && [image isKindOfClass:aniImageClass]) {
                NSData *data = [image valueForKey:@"animatedImageData"];
                NSNumber *type = [image valueForKey:@"animatedImageType"];
                if (data) {
                    switch (type.unsignedIntegerValue) {
                        case YYImageTypeGIF: {
                            NSDictionary *item = @{(id)kUTTypeGIF : data};
                            [self addItems:@[item]];
                        } break;
                        case YYImageTypePNG: { // APNG
                            NSDictionary *item = @{(id)kUTTypePNG : data};
                            [self addItems:@[item]];
                        } break;
                        case YYImageTypeWebP: {
                            NSDictionary *item = @{(id)YYTextUTTypeWEBP : data};
                            [self addItems:@[item]];
                        } break;
                        default: break;
                    }
                }
            }
        }
#endif
        
    }];
}

- (NSAttributedString *)yy_AttributedString {
    for (NSDictionary *items in self.items) {
        NSData *data = items[(__bridge NSString *)kUTTypeYYTextAttributedString];
        if (data) {
            return [NSAttributedString yy_unarchiveFromData:data withError: NULL];
        }
    }
    return nil;
}

@end
