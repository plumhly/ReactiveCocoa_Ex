//
//  RACQueueScheduler.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 11/30/12.
//  Copyright (c) 2012 GitHub, Inc. All rights reserved.
//

#import "RACQueueScheduler.h"
#import "RACDisposable.h"
#import "RACQueueScheduler+Subclass.h"
#import "RACScheduler+Private.h"

@implementation RACQueueScheduler

#pragma mark Lifecycle

- (id)initWithName:(NSString *)name queue:(dispatch_queue_t)queue {
	NSCParameterAssert(queue != NULL);

	self = [super initWithName:name];
	if (self == nil) return nil;

	_queue = queue;
#if !OS_OBJECT_HAVE_OBJC_SUPPORT
	dispatch_retain(_queue);
#endif

	return self;
}

#if !OS_OBJECT_HAVE_OBJC_SUPPORT

- (void)dealloc {
	if (_queue != NULL) {
		dispatch_release(_queue);
		_queue = NULL;
	}
}

#endif

#pragma mark Date Conversions

+ (dispatch_time_t)wallTimeWithDate:(NSDate *)date {
	NSCParameterAssert(date != nil);

	double seconds = 0;
    double frac = modf(date.timeIntervalSince1970, &seconds);/*modf() 将浮点数分解为整数和小数部分，其原型为： double modf (double x, double* intpart);
    【参数】x 为带分解双精度浮点数，intpart 为用来保存整数部分的指针。
    【返回值】返回分解后的小数部分 */

	struct timespec walltime = {
		.tv_sec = (time_t)fmin(fmax(seconds, LONG_MIN), LONG_MAX),
		.tv_nsec = (long)fmin(fmax(frac * NSEC_PER_SEC, LONG_MIN), LONG_MAX)
	};

	return dispatch_walltime(&walltime, 0);//dispatch_time 在电脑睡眠的时候会停止运行， dispatch_walltime 能在睡眠的时候正常运行.比如: So if you want to do an action in one hour from now, but after 5 minutes your computer goes to sleep for 50 minutes, dispatch_walltime will execute an hour from now, 5 minutes after the computer wakes up. dispatch_time will execute after the computer is running for an hour, that is 55 minutes after it wakes up.
}

#pragma mark RACScheduler

- (RACDisposable *)schedule:(void (^)(void))block {
	NSCParameterAssert(block != NULL);

	RACDisposable *disposable = [[RACDisposable alloc] init];

	dispatch_async(self.queue, ^{
		if (disposable.disposed) return;
		[self performAsCurrentScheduler:block];
	});

	return disposable;
}

- (RACDisposable *)after:(NSDate *)date schedule:(void (^)(void))block {
	NSCParameterAssert(date != nil);
	NSCParameterAssert(block != NULL);

	RACDisposable *disposable = [[RACDisposable alloc] init];

	dispatch_after([self.class wallTimeWithDate:date], self.queue, ^{
		if (disposable.disposed) return;
		[self performAsCurrentScheduler:block];
	});

	return disposable;
}

- (RACDisposable *)after:(NSDate *)date repeatingEvery:(NSTimeInterval)interval withLeeway:(NSTimeInterval)leeway schedule:(void (^)(void))block {
	NSCParameterAssert(date != nil);
	NSCParameterAssert(interval > 0.0 && interval < INT64_MAX / NSEC_PER_SEC);
	NSCParameterAssert(leeway >= 0.0 && leeway < INT64_MAX / NSEC_PER_SEC);
	NSCParameterAssert(block != NULL);

	uint64_t intervalInNanoSecs = (uint64_t)(interval * NSEC_PER_SEC);
	uint64_t leewayInNanoSecs = (uint64_t)(leeway * NSEC_PER_SEC);

	dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, self.queue);
	dispatch_source_set_timer(timer, [self.class wallTimeWithDate:date], intervalInNanoSecs, leewayInNanoSecs);
	dispatch_source_set_event_handler(timer, block);
	dispatch_resume(timer);

	return [RACDisposable disposableWithBlock:^{
		dispatch_source_cancel(timer);
	}];
}

@end
