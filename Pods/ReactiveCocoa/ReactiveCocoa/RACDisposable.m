//
//  RACDisposable.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 3/16/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACDisposable.h"
#import "RACScopedDisposable.h"
#import <libkern/OSAtomic.h>

@interface RACDisposable () {
	// A copied block of type void (^)(void) containing the logic for disposal,
	// a pointer to `self` if no logic should be performed upon disposal, or
	// NULL if the receiver is already disposed.
	//
	// This should only be used atomically.
	void * volatile _disposeBlock;// logic -> self -> null,这里之所以不用  void (^_disposeBlock)(void)，考虑到这样太单一，也就是说，block不能很好的指向logic,self，null三种数据形式，转换方式很复杂，比如把self赋值给block,就需要这样写 _disposeBlock = (__bridge void (^)(void))((__bridge void *)self);
//    void (^_disposeBlock)(void);
}

@end

@implementation RACDisposable

#pragma mark Properties

- (BOOL)isDisposed {
	return _disposeBlock == NULL;
}

#pragma mark Lifecycle

- (id)init {
	self = [super init];
	if (self == nil) return nil;

	_disposeBlock = (__bridge void *)self;
	OSMemoryBarrier();

	return self;
}

- (id)initWithBlock:(void (^)(void))block {
	NSCParameterAssert(block != nil);

	self = [super init];
	if (self == nil) return nil;

	_disposeBlock = (void *)CFBridgingRetain([block copy]); //把oc对象转换成core foundatiin 对象，并且会持有对象的生命周期,要负责释放！！这里之所以用 CFBridgingRetain 而不用 __bridge,因为自己要管理生命周期。等同于__bridge_retained
	OSMemoryBarrier();//内存屏障的概念如上所述，它是一种屏障和指令类，可以让CPU或编译器强制将barrier之前和之后的内存操作分开。CPU采用了一些可能导致乱序执行的性能优化。在单个线程的执行中，内存操作的顺序一般是悄无声息的，但是在并发编程和设备驱动程序中就可能出现一些不可预知的行为，除非我们小心地去控制。排序约束的特性是依赖于硬件的，并由架构的内存顺序模型来定义。一些架构定义了多种barrier来执行不同的顺序约束。http://southpeak.github.io/2014/10/17/osatomic-operation/

	return self;
}

+ (instancetype)disposableWithBlock:(void (^)(void))block {
	return [[self alloc] initWithBlock:block];
}

- (void)dealloc {
	if (_disposeBlock == NULL || _disposeBlock == (__bridge void *)self) return;

	CFRelease(_disposeBlock);
	_disposeBlock = NULL;
}

#pragma mark Disposal

//执行logic block
- (void)dispose {
	void (^disposeBlock)(void) = NULL;

	while (YES) {
		void *blockPtr = _disposeBlock;
		if (OSAtomicCompareAndSwapPtrBarrier(blockPtr, NULL, &_disposeBlock)) {
			if (blockPtr != (__bridge void *)self) {
				disposeBlock = CFBridgingRelease(blockPtr);//把core foundation的对象转换成oc对象，由arc管理生命周期，等同于__bridge_transfer
			}

			break;
		}
	}

	if (disposeBlock != nil) disposeBlock();
}

#pragma mark Scoped Disposables

- (RACScopedDisposable *)asScopedDisposable {
	return [RACScopedDisposable scopedDisposableWithDisposable:self];
}

@end
