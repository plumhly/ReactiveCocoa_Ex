//
//  RACSubscriptionScheduler.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACSubscriptionScheduler.h"
#import "RACScheduler+Private.h"

@interface RACSubscriptionScheduler ()

// A private background scheduler on which to subscribe if the +currentScheduler
// is unknown.
@property (nonatomic, strong, readonly) RACScheduler *backgroundScheduler;

@end

@implementation RACSubscriptionScheduler

#pragma mark Lifecycle
//初始化super.name,并且创建一个_backgroundScheduler的RACScheduler
- (id)init {
	self = [super initWithName:@"com.ReactiveCocoa.RACScheduler.subscriptionScheduler"];//添加名字
	if (self == nil) return nil;

    //_backgroundScheduler是一个target queue是优先级为default的global queue的串行queue
	_backgroundScheduler = [RACScheduler scheduler];//backgroundScheduler属性是readonly，所以没有setter,这里直接给实例变量赋值

	return self;
}

#pragma mark RACScheduler

//如果存在currentScheduler，那么执行block,如果没有就在backgroundScheduler的queue里面执行
- (RACDisposable *)schedule:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	if (RACScheduler.currentScheduler == nil) return [self.backgroundScheduler schedule:block];

	block();
	return nil;
}

- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date schedule:block];
}

- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	RACScheduler *scheduler = RACScheduler.currentScheduler ?: self.backgroundScheduler;
	return [scheduler after:date repeatingEvery:interval withLeeway:leeway schedule:block];
}

@end
