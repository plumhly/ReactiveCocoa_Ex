//
//  NSObject+RACDeallocating.m
//  ReactiveCocoa
//
//  Created by Kazuo Koga on 2013/03/15.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "NSObject+RACDeallocating.h"
#import "RACCompoundDisposable.h"
#import "RACDisposable.h"
#import "RACReplaySubject.h"
#import <objc/message.h>
#import <objc/runtime.h>

static const void *RACObjectCompoundDisposable = &RACObjectCompoundDisposable;

//返回进行交换的 class Set
static NSMutableSet *swizzledClasses() {
	static dispatch_once_t onceToken;
	static NSMutableSet *swizzledClasses = nil;
	dispatch_once(&onceToken, ^{
		swizzledClasses = [[NSMutableSet alloc] init];
	});
	
	return swizzledClasses;
}

//方法转换 dealloc
static void swizzleDeallocIfNeeded(Class classToSwizzle) {
	@synchronized (swizzledClasses()) {
		NSString *className = NSStringFromClass(classToSwizzle);
		if ([swizzledClasses() containsObject:className]) return;

		SEL deallocSelector = sel_registerName("dealloc");

		__block void (*originalDealloc)(__unsafe_unretained id, SEL) = NULL;//此处用__block,是为了block捕获 originalDealloc ，没有添加__block,是值copy.添加了就是引用。

		id newDealloc = ^(__unsafe_unretained id self) {
			RACCompoundDisposable *compoundDisposable = objc_getAssociatedObject(self, RACObjectCompoundDisposable);
			[compoundDisposable dispose];
            //如果没有 originalDealloc，那么尝试调用父类的 originalDealloc
			if (originalDealloc == NULL) {
				struct objc_super superInfo = {
					.receiver = self,
					.super_class = class_getSuperclass(classToSwizzle)
				};

				void (*msgSend)(struct objc_super *, SEL) = (__typeof__(msgSend))objc_msgSendSuper;
				msgSend(&superInfo, deallocSelector);
			} else {
				originalDealloc(self, deallocSelector);
			}
		};
		
		IMP newDeallocIMP = imp_implementationWithBlock(newDealloc);
		
		if (!class_addMethod(classToSwizzle, deallocSelector, newDeallocIMP, "v@:")) {
			// The class already contains a method implementation.
			Method deallocMethod = class_getInstanceMethod(classToSwizzle, deallocSelector);
			
			// We need to store original implementation before setting new implementation
			// in case method is called at the time of setting.
			originalDealloc = (__typeof__(originalDealloc))method_getImplementation(deallocMethod);
			
			// We need to store original implementation again, in case it just changed.
			originalDealloc = (__typeof__(originalDealloc))method_setImplementation(deallocMethod, newDeallocIMP);
		}

		[swizzledClasses() addObject:className];
	}
}

@implementation NSObject (RACDeallocating)


//获取RACReplaySubject，并且会创建一个RACDisposable加入到维护的RACCompoundDisposable，在block中会调用RACReplaySubject的sendCompleted方法。
- (RACSignal *)rac_willDeallocSignal {
	RACSignal *signal = objc_getAssociatedObject(self, _cmd);//_cmd 是一个selector,typedef struct objc_selector *SEL;
	if (signal != nil) return signal;

	RACReplaySubject *subject = [RACReplaySubject subject];//相等于调用[RACReplaySubject init]

	[self.rac_deallocDisposable addDisposable:[RACDisposable disposableWithBlock:^{
		[subject sendCompleted];//发送 完成信号
	}]];

	objc_setAssociatedObject(self, _cmd, subject, OBJC_ASSOCIATION_RETAIN);

	return subject;
}

- (RACCompoundDisposable *)rac_deallocDisposable {
	@synchronized (self) {
        //维护一个 RACCompoundDisposable 实例，这个实例的dealloc方法被替换了。
		RACCompoundDisposable *compoundDisposable = objc_getAssociatedObject(self, RACObjectCompoundDisposable);
		if (compoundDisposable != nil) return compoundDisposable;

		swizzleDeallocIfNeeded(self.class);

		compoundDisposable = [RACCompoundDisposable compoundDisposable];//类似 【【RACCompoundDisposable alloc】int 】
		objc_setAssociatedObject(self, RACObjectCompoundDisposable, compoundDisposable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

		return compoundDisposable;
	}
}

@end

@implementation NSObject (RACDeallocatingDeprecated)

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-implementations"

- (RACSignal *)rac_didDeallocSignal {
	RACSubject *subject = [RACSubject subject];

	RACScopedDisposable *disposable = [[RACDisposable
		disposableWithBlock:^{
			[subject sendCompleted];
		}]
		asScopedDisposable];
	
	objc_setAssociatedObject(self, (__bridge void *)disposable, disposable, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
	return subject;
}

- (void)rac_addDeallocDisposable:(RACDisposable *)disposable {
	[self.rac_deallocDisposable addDisposable:disposable];
}

#pragma clang diagnostic pop

@end
