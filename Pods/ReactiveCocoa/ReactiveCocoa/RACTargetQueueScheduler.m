//
//  RACTargetQueueScheduler.m
//  ReactiveCocoa
//
//  Created by Josh Abernathy on 6/6/13.
//  Copyright (c) 2013 GitHub, Inc. All rights reserved.
//

#import "RACTargetQueueScheduler.h"
#import "RACQueueScheduler+Subclass.h"

@implementation RACTargetQueueScheduler

#pragma mark Lifecycle

//依靠name来 创建 串行queue，并且设置目标targetQueue为它的目标queue
- (id)initWithName:(NSString *)name targetQueue:(dispatch_queue_t)targetQueue {
	NSCParameterAssert(targetQueue != NULL);

	if (name == nil) {
		name = [NSString stringWithFormat:@"com.ReactiveCocoa.RACTargetQueueScheduler(%s)", dispatch_queue_get_label(targetQueue)];
	}

	dispatch_queue_t queue = dispatch_queue_create(name.UTF8String, DISPATCH_QUEUE_SERIAL);
	if (queue == NULL) return nil;

	dispatch_set_target_queue(queue, targetQueue);

	return [super initWithName:name queue:queue];
}

@end
