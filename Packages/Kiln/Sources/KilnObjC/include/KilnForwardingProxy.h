//
//  KilnForwardingProxy.h
//  Kiln (PLAN.md §1.5)
//
//  An object that conforms to Objective-C protocols at run time and hands
//  each message it gets to a block, with the arguments boxed. Kiln makes one
//  for an app's class that adopts a native delegate protocol
//  (`UIImagePickerControllerDelegate`, `CLLocationManagerDelegate`): the
//  framework talks to the proxy, and the proxy calls the app's methods.
//
//  Only public runtime API (`protocol_getMethodDescription`, `NSInvocation`).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KilnForwardingProxy : NSProxy

/// `responds` answers `respondsToSelector:` for the protocols' methods (the
/// app implements that one). `handler` gets the selector and its arguments:
/// objects as they are (nil as `NSNull`), numbers as `NSNumber`, structs and
/// pointers as `NSValue`, a selector as its name. What it returns becomes the
/// method's return value, converted the same way back.
- (instancetype)initWithProtocols:(NSArray<Protocol *> *)protocols
                         responds:(BOOL (^)(SEL selector))responds
                          handler:(id _Nullable (^)(SEL selector, NSArray *arguments))handler;

@property (nonatomic, readonly, copy) NSArray<Protocol *> *kilnProtocols;

/// Drops the blocks (and what they hold): the proxy then answers nothing.
- (void)kilnInvalidate;

/// The type encoding of `selector` in `protocols` (or the protocols they
/// adopt), required or optional; nil when none declares it.
+ (nullable NSString *)typesForSelector:(SEL)selector inProtocols:(NSArray<Protocol *> *)protocols;

@end

NS_ASSUME_NONNULL_END
