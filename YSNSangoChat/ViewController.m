//
//  ViewController.m
//  YSNSangoChat
//
//  Created by yosan on 2015/09/24.
//  Copyright © 2015年 yosan. All rights reserved.
//

#import "ViewController.h"
#import "YSNChatViewController.h"

@interface ViewController ()

@property (weak, nonatomic) IBOutlet UITextField *displayName;

@end

@implementation ViewController

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender
{
    if ([segue.identifier isEqualToString:@"StartChat"])
    {
        YSNChatViewController *vc = (YSNChatViewController *)segue.destinationViewController;
        vc.senderDisplayName = self.displayName.text;
    }
}

@end
