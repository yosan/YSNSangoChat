//
//  YSNChatViewController.m
//  YSNSangoChat
//
//  Created by yosan on 2015/09/24.
//  Copyright © 2015年 yosan. All rights reserved.
//

#import "YSNChatViewController.h"

@interface YSNChatViewController ()

@property (strong, nonatomic) MQTTClient *client;
@property (strong, nonatomic) NSMutableArray *messages;
@property (nonatomic) JSQMessagesBubbleImage *incomingBubble;
@property (nonatomic) JSQMessagesBubbleImage *outgoingBubble;

@end

@implementation YSNChatViewController

static NSString* const kHost = @"your.host.name";
static NSString* const kUserName = @"user.name";
static NSString* const kPassword = @"user.password";
static NSString* const kTopic = @"topic";
static const unsigned short kPort = 1234;

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // メッセージ初期化
    self.messages = [NSMutableArray new];
    
    // senderIdにUUIDを設定する
    self.senderId = [UIDevice currentDevice].identifierForVendor.UUIDString;
    
    // アピアランスの変更
    [self YSN_setViewDesign];
    

    // クライアントの初期化
    self.client = [self YSN_createClient];
    
    __weak typeof(self) weakself = self;
    
    // メッセージ受信時の処理
    [self.client setMessageHandler:^(MQTTMessage *message) {
        YSNChatViewController *localSelf = weakself;
        if (localSelf)
        {
            NSError *error = nil;
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:message.payload
                                                                 options:NSJSONReadingAllowFragments
                                                                   error:&error];
            if (error)
            {
                NSLog(@"JSON Parse error.");
            }
            else
            {
                //ペイロードの内容からJSQMessageを作成する
                NSString *senderIdStr = json[@"senderId"];
                NSString *senderDisplayNameStr = json[@"senderDisplayName"];
                NSString *messageStr = json[@"message"];
                JSQMessage *newMessage = [JSQMessage messageWithSenderId:senderIdStr
                                                             displayName:senderDisplayNameStr
                                                                    text:messageStr];
                
                //受信したメッセージが自分のものではない場合に、messageDataに追加する
                //自分が発信したメッセージは発信が完了したタイミングで格納されているため
                if (![json[@"senderId"] isEqualToString:weakself.senderId]){
                    [localSelf.messages addObject:newMessage];
                }
                
                
                //messageDataの表示内容を更新する
                dispatch_async(dispatch_get_main_queue(), ^{
                    [localSelf finishReceivingMessageAnimated:YES];
                });
            }
        }
    }];
    
    // 接続
    [self.client connectToHost:kHost
             completionHandler:^(MQTTConnectionReturnCode code) {
                 YSNChatViewController *localSelf = weakself;
                 if (localSelf)
                 {
                     if (code == ConnectionAccepted) {
                         //接続が完了したらトピックのサブスクライブを開始する
                         [localSelf.client subscribe:kTopic withCompletionHandler:nil];
                     }
                     else
                     {
                         NSLog(@"connection error...");
                     }
                 }
             }];
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [self.client disconnectWithCompletionHandler:nil];
}

#pragma mark UICollectionView protocol

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    return self.messages.count;
}

- (UICollectionViewCell *)collectionView:(JSQMessagesCollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessagesCollectionViewCell *cell = (JSQMessagesCollectionViewCell *)[super collectionView:collectionView cellForItemAtIndexPath:indexPath];
    JSQMessage *msg = self.messages[indexPath.item];
    
    if (!msg.isMediaMessage)
    {
        if ([msg.senderId isEqualToString:self.senderId])
        {
            cell.textView.textColor = [UIColor blackColor];
        }
        else
        {
            cell.textView.textColor = [UIColor whiteColor];
        }
        
        cell.textView.linkTextAttributes = @{ NSForegroundColorAttributeName : cell.textView.textColor,
                                              NSUnderlineStyleAttributeName : @(NSUnderlineStyleSingle | NSUnderlinePatternSolid) };
    }
    
    return cell;
}

#pragma mark JSQMessagesViewController protcol

- (NSAttributedString *)collectionView:(JSQMessagesCollectionView *)collectionView attributedTextForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessage *message = self.messages[indexPath.item];
    
    if ([message.senderId isEqualToString:self.senderId]) {
        return nil;
    }
    
    if (indexPath.item - 1 > 0) {
        JSQMessage *previousMessage = self.messages[indexPath.item - 1];
        if ([previousMessage.senderId isEqualToString:message.senderId]) {
            return nil;
        }
    }
    
    return [[NSAttributedString alloc] initWithString:message.senderDisplayName];
}

- (id<JSQMessageData>)collectionView:(JSQMessagesCollectionView *)collectionView messageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return self.messages[indexPath.item];
}

- (id<JSQMessageBubbleImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView messageBubbleImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    JSQMessage *message = self.messages[indexPath.item];
    return [message.senderId isEqualToString:self.senderId] ? self.outgoingBubble : self.incomingBubble;
}

- (id<JSQMessageAvatarImageDataSource>)collectionView:(JSQMessagesCollectionView *)collectionView avatarImageDataForItemAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

//sendボタンがタップされた場合に呼び出されるメソッド
- (void)didPressSendButton:(UIButton *)button
           withMessageText:(NSString *)text
                  senderId:(NSString *)senderId
         senderDisplayName:(NSString *)senderDisplayName
                      date:(NSDate *)date
{
    NSDictionary *payload = @{@"senderId":senderId,
                              @"senderDisplayName":senderDisplayName,
                              @"message":text
                              };
    NSError *error = nil;
    NSData *payloadData = [NSJSONSerialization dataWithJSONObject:payload
                                                          options:0
                                                            error:&error];
    if (error){
        NSLog(@"JSON parse error.");
    } else {
        //MQTTメッセージを発行する
        [self.client publishString:[[NSString alloc] initWithData:payloadData
                                                         encoding:NSUTF8StringEncoding]
                           toTopic:kTopic
                           withQos:AtMostOnce
                            retain:NO
                 completionHandler:^(int mid) {
                     JSQMessage *message = [[JSQMessage alloc] initWithSenderId:senderId
                                                              senderDisplayName:senderDisplayName
                                                                           date:date
                                                                           text:text];
                     dispatch_async(dispatch_get_main_queue(), ^{
                         [self.messages addObject:message];
                         [self finishSendingMessageAnimated:YES];
                     });
                 }];
    }
}

#pragma mark - Adjusting cell label heights

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.item % 3 == 0)
    {
        return kJSQMessagesCollectionViewCellLabelHeightDefault;
    }
    
    return 0.0f;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForMessageBubbleTopLabelAtIndexPath:(NSIndexPath *)indexPath
{
    /**
     *  iOS7-style sender name labels
     */
    JSQMessage *currentMessage = self.messages[indexPath.item];
    if ([[currentMessage senderId] isEqualToString:self.senderId]) {
        return 0.0f;
    }
    
    if (indexPath.item - 1 > 0) {
        JSQMessage *previousMessage = self.messages[indexPath.item - 1];
        if ([[previousMessage senderId] isEqualToString:[currentMessage senderId]]) {
            return 0.0f;
        }
    }
    
    return kJSQMessagesCollectionViewCellLabelHeightDefault;
}

- (CGFloat)collectionView:(JSQMessagesCollectionView *)collectionView
                   layout:(JSQMessagesCollectionViewFlowLayout *)collectionViewLayout heightForCellBottomLabelAtIndexPath:(NSIndexPath *)indexPath
{
    return 0.0f;
}

#pragma mark - Private

- (void)YSN_setViewDesign
{
    // メッセージの背景
    JSQMessagesBubbleImageFactory *bubbleFactory = [JSQMessagesBubbleImageFactory new];
    self.incomingBubble = [bubbleFactory  incomingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleBlueColor]];
    self.outgoingBubble = [bubbleFactory  outgoingMessagesBubbleImageWithColor:[UIColor jsq_messageBubbleGreenColor]];
    
    //メッセージ画面のアバター設定
    self.collectionView.collectionViewLayout.incomingAvatarViewSize = CGSizeZero;
    self.collectionView.collectionViewLayout.outgoingAvatarViewSize = CGSizeZero;
}

- (MQTTClient *)YSN_createClient
{
    // client初期化
    MQTTClient *client = [[MQTTClient alloc] initWithClientId:self.senderDisplayName];
    client.username = kUserName;
    client.password = kPassword;
    client.port = kPort;
    
    // willのセット
    NSDictionary *will = @{@"senderId":self.senderId,
                           @"senderDisplayName":self.senderDisplayName,
                           @"message":@"君がこれを読んでいるということは、僕はもうセッションが維持できていないだろう。"
                           };
    NSError *error = nil;
    NSData *willData = [NSJSONSerialization dataWithJSONObject:will
                                                       options:0
                                                         error:&error];
    [client setWillData:willData toTopic:kTopic withQos:AtMostOnce retain:NO];
    
    return client;
}

@end
