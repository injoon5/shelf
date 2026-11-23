//
//  KilnForwardingProxy.m
//  Kiln (PLAN.md §1.5)
//

#import "KilnForwardingProxy.h"
#import <objc/runtime.h>

@implementation KilnForwardingProxy {
    NSArray<Protocol *> *_protocols;
    BOOL (^_responds)(SEL);
    id _Nullable (^_handler)(SEL, NSArray *);
    id _lastReturn;
}

- (instancetype)initWithProtocols:(NSArray<Protocol *> *)protocols
                         responds:(BOOL (^)(SEL))responds
                          handler:(id _Nullable (^)(SEL, NSArray *))handler {
    _protocols = [protocols copy];
    _responds = [responds copy];
    _handler = [handler copy];
    return self;
}

- (NSArray<Protocol *> *)kilnProtocols { return _protocols; }

- (void)kilnInvalidate {
    _responds = nil;
    _handler = nil;
    _lastReturn = nil;
}

static const char *KilnTypes(Protocol *p, SEL sel, NSMutableSet<NSString *> *seen) {
    NSString *name = NSStringFromProtocol(p);
    if ([seen containsObject:name]) return NULL;
    [seen addObject:name];
    for (int required = 1; required >= 0; required--) {
        struct objc_method_description d = protocol_getMethodDescription(p, sel, (BOOL)required, YES);
        if (d.types) return d.types;
    }
    unsigned int count = 0;
    Protocol * __unsafe_unretained *adopted = protocol_copyProtocolList(p, &count);
    const char *found = NULL;
    for (unsigned int i = 0; i < count && !found; i++) found = KilnTypes(adopted[i], sel, seen);
    free(adopted);
    return found;
}

+ (NSString *)typesForSelector:(SEL)selector inProtocols:(NSArray<Protocol *> *)protocols {
    NSMutableSet *seen = [NSMutableSet set];
    for (Protocol *p in protocols) {
        const char *t = KilnTypes(p, selector, seen);
        if (t) return @(t);
    }
    return nil;
}

- (BOOL)conformsToProtocol:(Protocol *)aProtocol {
    if (protocol_isEqual(aProtocol, @protocol(NSObject))) return YES;
    for (Protocol *p in _protocols) {
        if (protocol_isEqual(p, aProtocol) || protocol_conformsToProtocol(p, aProtocol)) return YES;
    }
    return NO;
}

- (BOOL)respondsToSelector:(SEL)aSelector {
    if (class_respondsToSelector(NSProxy.class, aSelector)) return YES;
    if (!_responds || ![KilnForwardingProxy typesForSelector:aSelector inProtocols:_protocols]) return NO;
    return _responds(aSelector);
}

- (NSMethodSignature *)methodSignatureForSelector:(SEL)sel {
    NSString *types = [KilnForwardingProxy typesForSelector:sel inProtocols:_protocols];
    if (types) return [NSMethodSignature signatureWithObjCTypes:types.UTF8String];
    // Answer anything else with a signature that returns nothing, so an
    // unexpected message is dropped rather than crashing the app.
    return [NSMethodSignature signatureWithObjCTypes:"v@:"];
}

/// Skips type qualifiers (`r` const, `n` in, `o` out…).
static const char *KilnStrip(const char *t) {
    while (*t && strchr("rnNoORV", *t)) t++;
    return t;
}

static id KilnBox(NSInvocation *inv, NSUInteger index, const char *type) {
    const char *t = KilnStrip(type);
    switch (*t) {
        case '@': { __unsafe_unretained id o = nil; [inv getArgument:&o atIndex:index]; return o ?: NSNull.null; }
        case '#': { __unsafe_unretained Class c = nil; [inv getArgument:&c atIndex:index]; return c ?: NSNull.null; }
        case ':': { SEL s = NULL; [inv getArgument:&s atIndex:index]; return s ? NSStringFromSelector(s) : NSNull.null; }
        case 'B': { bool v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'c': { char v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'C': { unsigned char v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 's': { short v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'S': { unsigned short v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'i': { int v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'I': { unsigned int v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'l': { long v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'L': { unsigned long v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'q': { long long v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'Q': { unsigned long long v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'f': { float v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case 'd': { double v = 0; [inv getArgument:&v atIndex:index]; return @(v); }
        case '^': case '*': { void *p = NULL; [inv getArgument:&p atIndex:index]; return [NSValue valueWithPointer:p]; }
        default: {
            NSUInteger size = 0, align = 0;
            NSGetSizeAndAlignment(t, &size, &align);
            void *buf = calloc(1, size ? size : 1);
            [inv getArgument:buf atIndex:index];
            NSValue *v = [NSValue valueWithBytes:buf objCType:t];
            free(buf);
            return v;
        }
    }
}

- (void)forwardInvocation:(NSInvocation *)inv {
    NSMethodSignature *sig = inv.methodSignature;
    const char *ret = KilnStrip(sig.methodReturnType);
    NSUInteger retSize = sig.methodReturnLength;
    if (!_handler) {
        if (retSize) { void *zero = calloc(1, retSize); [inv setReturnValue:zero]; free(zero); }
        return;
    }
    NSMutableArray *args = [NSMutableArray arrayWithCapacity:sig.numberOfArguments];
    for (NSUInteger i = 2; i < sig.numberOfArguments; i++) {
        [args addObject:KilnBox(inv, i, [sig getArgumentTypeAtIndex:i])];
    }
    id result = _handler(inv.selector, args);
    if (*ret == 'v' || retSize == 0) return;
    if (result == NSNull.null) result = nil;
    switch (*ret) {
        case '@': {
            // Kept alive until the next call: the caller doesn't own it.
            _lastReturn = result;
            __unsafe_unretained id r = result;
            [inv setReturnValue:&r];
            return;
        }
        case 'B': { bool v = [result boolValue]; [inv setReturnValue:&v]; return; }
        case 'c': { char v = [result charValue]; [inv setReturnValue:&v]; return; }
        case 'C': { unsigned char v = [result unsignedCharValue]; [inv setReturnValue:&v]; return; }
        case 's': { short v = [result shortValue]; [inv setReturnValue:&v]; return; }
        case 'S': { unsigned short v = [result unsignedShortValue]; [inv setReturnValue:&v]; return; }
        case 'i': { int v = [result intValue]; [inv setReturnValue:&v]; return; }
        case 'I': { unsigned int v = [result unsignedIntValue]; [inv setReturnValue:&v]; return; }
        case 'l': { long v = [result longValue]; [inv setReturnValue:&v]; return; }
        case 'L': { unsigned long v = [result unsignedLongValue]; [inv setReturnValue:&v]; return; }
        case 'q': { long long v = [result longLongValue]; [inv setReturnValue:&v]; return; }
        case 'Q': { unsigned long long v = [result unsignedLongLongValue]; [inv setReturnValue:&v]; return; }
        case 'f': { float v = [result floatValue]; [inv setReturnValue:&v]; return; }
        case 'd': { double v = [result doubleValue]; [inv setReturnValue:&v]; return; }
        default: {
            void *buf = calloc(1, retSize);
            if ([result isKindOfClass:NSValue.class]) {
                NSUInteger size = 0;
                NSGetSizeAndAlignment([(NSValue *)result objCType], &size, NULL);
                if (size == retSize) [(NSValue *)result getValue:buf size:retSize];
            }
            [inv setReturnValue:buf];
            free(buf);
            return;
        }
    }
}

@end
