//
//  RACCompoundDisposable.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACCompoundDisposable.h"
#import "RACCompoundDisposableProvider.h"
#import <libkern/OSAtomic.h>

// The number of child disposables for which space will be reserved directly in
// `RACCompoundDisposable`.
//
// This number has been empirically determined to provide a good tradeoff
// between performance, memory usage, and `RACCompoundDisposable` instance size
// in a moderately complex GUI application.
//
// Profile any change!
#define RACCompoundDisposableInlineCount 2

static CFMutableArrayRef RACCreateDisposablesArray(void) {
	// Compare values using only pointer equality.
    /*
     typedef struct {
         CFIndex				version;//0
         CFArrayRetainCallBack		retain; //The callback used to retain each value as they are added to the collection. If NULL, values are not retained.
     
         CFArrayReleaseCallBack		release;//The callback used to release values as they are removed from the collection. If NULL, values are not released
     
         CFArrayCopyDescriptionCallBack	copyDescription;
     
         CFArrayEqualCallBack		equal;//The callback used to compare values in the array for equality for some operations. If NULL, the collection will use pointer equality to compare values in the collection.
     } CFArrayCallBacks;
     */
	CFArrayCallBacks callbacks = kCFTypeArrayCallBacks;//持有对象
	callbacks.equal = NULL;

	return CFArrayCreateMutable(NULL, 0, &callbacks);
}

@interface RACCompoundDisposable () {
	// Used for synchronization.
	OSSpinLock _spinLock;

	#if RACCompoundDisposableInlineCount
	// A fast array to the first N of the receiver's disposables.
	//
	// Once this is full, `_disposables` will be created and used for additional
	// disposables.
	//
	// This array should only be manipulated while _spinLock is held.
	RACDisposable *_inlineDisposables[RACCompoundDisposableInlineCount];//前两个RACDisposable，指针数组
	#endif

	// Contains the receiver's disposables.
	//
	// This array should only be manipulated while _spinLock is held. If
	// `_disposed` is YES, this may be NULL.
	CFMutableArrayRef _disposables;//除了前两个RACDisposable的数据

	// Whether the receiver has already been disposed.
	//
	// This ivar should only be accessed while _spinLock is held.
	BOOL _disposed;//是否正在执行disposed方法
}

@end

@implementation RACCompoundDisposable

#pragma mark Properties

- (BOOL)isDisposed {
    //OSSpinLock可能引起优先级翻转
	OSSpinLockLock(&_spinLock);
	BOOL disposed = _disposed;
	OSSpinLockUnlock(&_spinLock);

	return disposed;
}

#pragma mark Lifecycle

//和init一样
+ (instancetype)compoundDisposable {
	return [[self alloc] initWithDisposables:nil];
}

+ (instancetype)compoundDisposableWithDisposables:(NSArray *)disposables {
	return [[self alloc] initWithDisposables:disposables];
}

- (id)initWithDisposables:(NSArray *)otherDisposables {
	self = [self init];
	if (self == nil) return nil;

	#if RACCompoundDisposableInlineCount
	[otherDisposables enumerateObjectsUsingBlock:^(RACDisposable *disposable, NSUInteger index, BOOL *stop) {
		_inlineDisposables[index] = disposable;

		// Stop after this iteration if we've reached the end of the inlined
		// array.
		if (index == RACCompoundDisposableInlineCount - 1) *stop = YES;
	}];
	#endif

	if (otherDisposables.count > RACCompoundDisposableInlineCount) {
		_disposables = RACCreateDisposablesArray();

		CFRange range = CFRangeMake(RACCompoundDisposableInlineCount, (CFIndex)otherDisposables.count - RACCompoundDisposableInlineCount);
		CFArrayAppendArray(_disposables, (__bridge CFArrayRef)otherDisposables, range);
	}

	return self;
}

- (id)initWithBlock:(void (^)(void))block {
	RACDisposable *disposable = [RACDisposable disposableWithBlock:block];
	return [self initWithDisposables:@[ disposable ]];
}

- (void)dealloc {
	#if RACCompoundDisposableInlineCount
	for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
		_inlineDisposables[i] = nil;
	}
	#endif

	if (_disposables != NULL) {
		CFRelease(_disposables);
		_disposables = NULL;
	}
}

#pragma mark Addition and Removal

//添加RACDisposable，如果此时正常 RACCompoundDisposable dispose被调用，那么调用disposable的 dispose方法
- (void)addDisposable:(RACDisposable *)disposable {
	NSCParameterAssert(disposable != self);
	if (disposable == nil || disposable.disposed) return;

	BOOL shouldDispose = NO;

	OSSpinLockLock(&_spinLock);
	{
		if (_disposed) {
			shouldDispose = YES;
		} else {
            //优先加入到_inlineDisposables，如果_inlineDisposables已经满了，则加入_disposables
			#if RACCompoundDisposableInlineCount
			for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
				if (_inlineDisposables[i] == nil) {
					_inlineDisposables[i] = disposable;
					goto foundSlot;
				}
			}
			#endif

			if (_disposables == NULL) _disposables = RACCreateDisposablesArray();
			CFArrayAppendValue(_disposables, (__bridge void *)disposable);

			if (RACCOMPOUNDDISPOSABLE_ADDED_ENABLED()) {
				RACCOMPOUNDDISPOSABLE_ADDED(self.description.UTF8String, disposable.description.UTF8String, CFArrayGetCount(_disposables) + RACCompoundDisposableInlineCount);
			}

		#if RACCompoundDisposableInlineCount
		foundSlot:;
		#endif
		}
	}
	OSSpinLockUnlock(&_spinLock);

	// Performed outside of the lock in case the compound disposable is used
	// recursively.
	if (shouldDispose) [disposable dispose];
}

- (void)removeDisposable:(RACDisposable *)disposable {
	if (disposable == nil) return;

	OSSpinLockLock(&_spinLock);
	{
		if (!_disposed) {
			#if RACCompoundDisposableInlineCount
			for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
				if (_inlineDisposables[i] == disposable) _inlineDisposables[i] = nil;
			}
			#endif

			if (_disposables != NULL) {
				CFIndex count = CFArrayGetCount(_disposables);
				for (CFIndex i = count - 1; i >= 0; i--) {
					const void *item = CFArrayGetValueAtIndex(_disposables, i);
					if (item == (__bridge void *)disposable) {
						CFArrayRemoveValueAtIndex(_disposables, i);
					}
				}

				if (RACCOMPOUNDDISPOSABLE_REMOVED_ENABLED()) {
					RACCOMPOUNDDISPOSABLE_REMOVED(self.description.UTF8String, disposable.description.UTF8String, CFArrayGetCount(_disposables) + RACCompoundDisposableInlineCount);
				}
			}
		}
	}
	OSSpinLockUnlock(&_spinLock);
}

#pragma mark RACDisposable

static void disposeEach(const void *value, void *context) {
	RACDisposable *disposable = (__bridge id)value;
	[disposable dispose];
}

//把包含的所有 RACDisposable 的 dispose方法，批处理
- (void)dispose {
	#if RACCompoundDisposableInlineCount
	RACDisposable *inlineCopy[RACCompoundDisposableInlineCount];
	#endif

	CFArrayRef remainingDisposables = NULL;

	OSSpinLockLock(&_spinLock);
	{
		_disposed = YES;

		#if RACCompoundDisposableInlineCount
		for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
			inlineCopy[i] = _inlineDisposables[i];
			_inlineDisposables[i] = nil;
		}
		#endif

		remainingDisposables = _disposables;
		_disposables = NULL;
	}
	OSSpinLockUnlock(&_spinLock);

	#if RACCompoundDisposableInlineCount
	// Dispose outside of the lock in case the compound disposable is used
	// recursively.
	for (unsigned i = 0; i < RACCompoundDisposableInlineCount; i++) {
		[inlineCopy[i] dispose];
	}
	#endif

	if (remainingDisposables == NULL) return;

	CFIndex count = CFArrayGetCount(remainingDisposables);
	CFArrayApplyFunction(remainingDisposables, CFRangeMake(0, count), &disposeEach, NULL);
	CFRelease(remainingDisposables);
}

@end
