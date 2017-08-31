//
//  ViewController.m
//  ReactiveCocoa_Ex
//
//  Created by Plum on 2017/7/23.
//  Copyright © 2017年 Plum. All rights reserved.
//

#import "ViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "Extension_T.h"

//宏中用 _0, _1等和字母表示一样的，如果不想用很多的字母，就可以用这种形式
#define MI(_0, _1, _2) my(_1, _2)
#define my(x, y) x+y

@interface ViewController ()

@property (nonatomic, strong) NSString *name;

@end

@implementation ViewController



- (void)viewDidLoad {
    [super viewDidLoad];
    int c = MI(1,2,3);
    [RACObserve(self, name) subscribeNext:^(NSString *x) {
        NSLog(@"%@", x);
    }];
    self.name = @"libo";

    /*
    {
        NSArray *numbers = @[@1, @2, @3];
        NSEnumerator *en = [numbers objectEnumerator];
        id ob = nil;
        while ((ob = en.nextObject)) {
            NSLog(@"Enumerator %@", ob);
        }
    }

    {
        
//        RACSequence *sequence = @[@1, @2, @3].rac_sequence.tail;
        RACSequence *sequence = [@[@1, @2, @3].rac_sequence map:^id(NSNumber *value) {
            return value.stringValue;
        }];
        for (NSString *ob in sequence) {
            NSLog(@"%@",ob);
        }
    
        NSLog(@"%@",sequence.array);
    }
     */
}


- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)buttonClick:(id)sender {
    self.name = @"plum";
}

// https://stackoverflow.com/questions/25126864/va-args-causing-exc-bad-access
//[self setNameWithFormate:@"%@%@%@", @"l", @"i", @"b", nil];
- (void)setNameWithFormate:(NSString *)formate,... {//需要nil作为结束的标志
    va_list list;
    va_start(list, formate);
    for (NSString *str = formate; str != nil; str = va_arg(list, NSString *)) {
        NSLog(@"%@", str);
    }
    va_end(list);
}
@end
