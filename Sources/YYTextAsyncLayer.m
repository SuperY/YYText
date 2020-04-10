//
//  YYTextAsyncLayer.m
//  YYText <https://github.com/ibireme/YYText>
//
//  Created by ibireme on 15/4/11.
//  Copyright (c) 2015 ibireme.
//
//  This source code is licensed under the MIT-style license found in the
//  LICENSE file in the root directory of this source tree.
//

#import "YYTextAsyncLayer.h"
#import <stdatomic.h>


/// Global display queue, used for content rendering.
static dispatch_queue_t YYTextAsyncLayerGetDisplayQueue() {
#define MAX_QUEUE_COUNT 16
    static int queueCount;
    static dispatch_queue_t queues[MAX_QUEUE_COUNT];
    static dispatch_once_t onceToken;
    static _Atomic(int) counter = 0;
    dispatch_once(&onceToken, ^{
        queueCount = (int)[NSProcessInfo processInfo].activeProcessorCount;
        queueCount = queueCount < 1 ? 1 : queueCount > MAX_QUEUE_COUNT ? MAX_QUEUE_COUNT : queueCount;
        for (NSUInteger i = 0; i < queueCount; i++) {
            dispatch_queue_attr_t attr = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_USER_INITIATED, 0);
            queues[i] = dispatch_queue_create("com.ibireme.text.render", attr);
        }
        
    });
    _Atomic(int) cur = atomic_fetch_add_explicit(&counter, 1, memory_order_relaxed);
    return queues[(cur) % queueCount];
#undef MAX_QUEUE_COUNT
}

static dispatch_queue_t YYTextAsyncLayerGetReleaseQueue() {
#ifdef YYDispatchQueuePool_h
    return YYDispatchQueueGetForQOS(NSQualityOfServiceDefault);
#else
    return dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0);
#endif
}


/// a thread safe incrementing counter.
@interface _YYTextSentinel : NSObject
/// Returns the current value of the counter.
@property (atomic, readonly) _Atomic(int) value;
/// Increase the value atomically. @return The new value.
- (_Atomic(int))increase;
@end

@implementation _YYTextSentinel {
    _Atomic(int) _value;
}
- (int)value {
    return _value;
}
- (_Atomic(int))increase {
    return atomic_fetch_add_explicit(&_value, 1, memory_order_relaxed);
}
@end


@implementation YYTextAsyncLayerDisplayTask
@end


@interface YYTextAsyncLayer ()
@property(nullable, nonatomic, strong) UIGraphicsImageRenderer *imageRenderer;
@end

@implementation YYTextAsyncLayer {
    _YYTextSentinel *_sentinel;
}

#pragma mark - Override

+ (id)defaultValueForKey:(NSString *)key {
    if ([key isEqualToString:@"displaysAsynchronously"]) {
        return @(YES);
    } else {
        return [super defaultValueForKey:key];
    }
}

- (instancetype)init {
    self = [super init];
    static CGFloat scale; //global
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        scale = [UIScreen mainScreen].scale;
    });
    self.contentsScale = scale;
    _sentinel = [_YYTextSentinel new];
    _displaysAsynchronously = YES;
    return self;
}

- (void)dealloc {
    [_sentinel increase];
}

- (void)layoutSublayers {
    [super layoutSublayers];
    self.imageRenderer = nil;
}

- (void)setNeedsDisplay {
    [self _cancelAsyncDisplay];
    [super setNeedsDisplay];
}

- (void)display {
    super.contents = super.contents;
    [self _displayAsync:_displaysAsynchronously];
}

#pragma mark - Private

- (void)_displayAsync:(BOOL)async {
    __strong id<YYTextAsyncLayerDelegate> delegate = (id)self.delegate;
    YYTextAsyncLayerDisplayTask *task = [delegate newAsyncDisplayTask];
    if (!task.display) {
        if (task.willDisplay) task.willDisplay(self);
        self.contents = nil;
        if (task.didDisplay) task.didDisplay(self, YES);
        return;
    }
    
    if (async) {
        if (task.willDisplay) task.willDisplay(self);
        _YYTextSentinel *sentinel = _sentinel;
        int32_t value = sentinel.value;
        BOOL (^isCancelled)(void) = ^BOOL() {
            return value != sentinel.value;
        };
        CGSize size = self.bounds.size;
        BOOL opaque = self.opaque;
        CGFloat scale = self.contentsScale;
        CGColorRef backgroundColor = (opaque && self.backgroundColor) ? CGColorRetain(self.backgroundColor) : NULL;
        if (size.width < 1 || size.height < 1) {
            CGImageRef image = (__bridge_retained CGImageRef)(self.contents);
            self.contents = nil;
            if (image) {
                dispatch_async(YYTextAsyncLayerGetReleaseQueue(), ^{
                    CFRelease(image);
                });
            }
            if (task.didDisplay) task.didDisplay(self, YES);
            CGColorRelease(backgroundColor);
            return;
        }
        
        dispatch_async(YYTextAsyncLayerGetDisplayQueue(), ^{
            if (isCancelled()) {
                CGColorRelease(backgroundColor);
                return;
            }
            
            if (!self.imageRenderer) {
                UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
                format.scale = scale;
                format.opaque = opaque;
                self.imageRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
            }
            
            UIImage *image = [self.imageRenderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
                if (opaque) {
                    CGContextSaveGState(rendererContext.CGContext);
                    if (!backgroundColor || CGColorGetAlpha(backgroundColor) < 1) {
                        [UIColor.whiteColor setFill];
                        [rendererContext fillRect:CGRectMake(0, 0, size.width, size.height)];
                    }
                    if (backgroundColor) {
                        CGContextSetFillColorWithColor(rendererContext.CGContext, backgroundColor);
                        [rendererContext fillRect:CGRectMake(0, 0, size.width, size.height)];
                    }
                    CGContextRestoreGState(rendererContext.CGContext);
                    CGColorRelease(backgroundColor);
                }
                task.display(rendererContext.CGContext, size, isCancelled);
            }];
            
            if (isCancelled()) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (task.didDisplay) task.didDisplay(self, NO);
                });
                return;
            }

            dispatch_async(dispatch_get_main_queue(), ^{
                if (isCancelled()) {
                    if (task.didDisplay) task.didDisplay(self, NO);
                } else {
                    self.contents = (__bridge id)(image.CGImage);
                    if (task.didDisplay) task.didDisplay(self, YES);
                }
            });
        });
    } else {
        [_sentinel increase];
        if (task.willDisplay) task.willDisplay(self);

        CGSize size = self.bounds.size;

        if (!self.imageRenderer) {
            UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat new];
            format.scale = self.contentsScale;
            format.opaque = self.opaque;
            self.imageRenderer = [[UIGraphicsImageRenderer alloc] initWithSize:size format:format];
        }
        
        UIImage *image = [self.imageRenderer imageWithActions:^(UIGraphicsImageRendererContext * _Nonnull rendererContext) {
            if (self.opaque) {
                CGContextSaveGState(rendererContext.CGContext);
                if (!self.backgroundColor || CGColorGetAlpha(self.backgroundColor) < 1) {
                    [UIColor.whiteColor setFill];
                    [rendererContext fillRect:CGRectMake(0, 0, size.width, size.height)];
                }
                if (self.backgroundColor) {
                    CGContextSetFillColorWithColor(rendererContext.CGContext, self.backgroundColor);
                    [rendererContext fillRect:CGRectMake(0, 0, size.width, size.height)];
                }
                CGContextRestoreGState(rendererContext.CGContext);
            }
            task.display(rendererContext.CGContext, size, ^{return NO;});
        }];
        
        self.contents = (__bridge id)(image.CGImage);
        if (task.didDisplay) task.didDisplay(self, YES);
    }
}

- (void)_cancelAsyncDisplay {
    [_sentinel increase];
}

@end
