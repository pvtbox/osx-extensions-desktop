/**
*  
*  Pvtbox. Fast and secure file transfer & sync directly across your devices. 
*  Copyright © 2020  Pb Private Cloud Solutions Ltd. 
*  
*  This program is free software: you can redistribute it and/or modify
*  it under the terms of the GNU General Public License as published by
*  the Free Software Foundation, either version 3 of the License, or
*  (at your option) any later version.
*  
*  This program is distributed in the hope that it will be useful,
*  but WITHOUT ANY WARRANTY; without even the implied warranty of
*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
*  GNU General Public License for more details.
*  
*  You should have received a copy of the GNU General Public License
*  along with this program.  If not, see <https://www.gnu.org/licenses/>.
*  
**/

#import "ShareViewController.h"
#import <SocketRocket/SRWebSocket.h>

@interface ShareViewController () <SRWebSocketDelegate>
@property SRWebSocket *webSocket;
@property (nonatomic, strong) NSString* pdfName;
@property (nonatomic, strong) NSData* pdfData;
@property (nonatomic) int countToCopy;
@property (nonatomic, strong) NSMutableArray<NSString*>* paths;
@end

@implementation ShareViewController

- (void)loadView {
    [super loadView];
    
    // Insert code here to customize the view
    self.title = NSLocalizedString(@"Share via Pvtbox", @"Share via Pvtbox");
    self.placeholder = NSLocalizedString(@"Tap 'Post' to share", @"Tap 'Post' to share");
    [self.textView setString:@"Tap 'Post' to share"];
    [self.textView setEditable:NO];
    [self.textView setSelectable:NO];
    
    /*
    if (@available(macOS 10.15, *)) {
        [NSWorkspace.sharedWorkspace
         openApplicationAtURL:[NSWorkspace.sharedWorkspace
                               URLForApplicationWithBundleIdentifier:@"net.pvtbox.Pvtbox"]
         configuration: [[NSWorkspaceOpenConfiguration alloc] init]
         completionHandler:nil];
    } else {
     */
        [NSWorkspace.sharedWorkspace launchApplication:@"Pvtbox" showIcon:NO autolaunch:NO];
    /*
    }
     */
    
    self.paths = [[NSMutableArray alloc] init];
    self.countToCopy = 0;
    self.pdfData = nil;
    self.pdfName = nil;
    
    [self connectToPvtboxApplication];
    NSLog(@"Input Items = %@", self.extensionContext.inputItems);
}

- (void)didSelectPost {
    // Perform the post operation
    // When the operation is complete (probably asynchronously), the service should notify the success or failure as well as the items that were actually shared
    
    NSExtensionItem *inputItem = self.extensionContext.inputItems.firstObject;
    
    if (inputItem.attachments != nil && inputItem.attachments.count > 0) {
        for (NSItemProvider* item in inputItem.attachments) {
            if ([item hasItemConformingToTypeIdentifier:(NSString*)kUTTypeFileURL]) {
                [self processFileUrl:item];
            } else if ([item hasItemConformingToTypeIdentifier:(NSString*)kUTTypeImage]) {
                [self processImage:item];
            } else if ([item hasItemConformingToTypeIdentifier:(NSString*)kUTTypePDF]) {
                [self processPdfData:item];
            } else if ([item hasItemConformingToTypeIdentifier:(NSString*) kUTTypeURL]) {
                [self processPdfUrl:item];
            }
        }
    } else if (inputItem.attributedContentText != nil && inputItem.attributedContentText.length > 0) {
        [self processText:inputItem];
    } else {
        [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
        [self didSelectCancel];
    }
}

- (void)processFileUrl:(NSItemProvider*) item {
    self.countToCopy++;
    [item
     loadItemForTypeIdentifier:(NSString*)kUTTypeFileURL
     options:nil
     completionHandler:^(id<NSSecureCoding>  _Nullable item,
                         NSError * _Null_unspecified error) {
        NSURL* url = item;
        if (url != nil) {
            NSLog(@"selected: %@", url.path);
            [self.paths addObject:url.path];
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self.countToCopy--;
            if (self.countToCopy == 0) {
                if (self.paths.count > 0) {
                    NSData* data = [NSJSONSerialization
                                    dataWithJSONObject:@{
                                        @"cmd" : @"share_copy",
                                        @"paths" : self.paths}
                                    options:NSJSONWritingPrettyPrinted
                                    error:nil];
                    if (data) {
                        NSString* message = [[NSString alloc]
                                             initWithData:data
                                             encoding:NSUTF8StringEncoding];
                        [self.webSocket send:message];
                    }
                }
                [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
                [self didSelectCancel];
            }
        });
    }];
}

- (void)processImage:(NSItemProvider*) item {
    [item
     loadItemForTypeIdentifier:(NSString*)kUTTypeImage
     options:nil
     completionHandler:^(id<NSSecureCoding>  _Nullable item,
                         NSError * _Null_unspecified error) {
        NSImage* image = item;
        if (image != nil) {
            NSLog(@"Image ok, name: %@", image.name);
            NSDate* date = [[NSDate alloc] init];
            NSDateFormatter* formatter = [[NSDateFormatter alloc] init];
            formatter.dateFormat = @"YYYYMMdd_HHmm";
            NSString* dateStr = [formatter stringFromDate:date];
            NSString* name = [[NSString alloc] initWithFormat:@"Screenshot_%@.png", dateStr];
            NSString* dateTemplate = @"Screenshot_%@ %d.png";
            int i = 0;
            while ([NSFileManager.defaultManager
                    fileExistsAtPath:[NSHomeDirectory()
                                      stringByAppendingPathComponent:name]]) {
                i++;
                name = [[NSString alloc] initWithFormat:dateTemplate, dateStr, i];
            }
            
            NSData* data = [image
                            TIFFRepresentationUsingCompression:NSTIFFCompressionLZW
                            factor:0.5f];
            if (data != nil) {
                NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc] initWithData:data];
                if (bitmap != nil) {
                    NSData* bitmapData = [bitmap
                                          representationUsingType:NSBitmapImageFileTypePNG
                                          properties:@{}];
                    if (bitmapData != nil) {
                        [bitmapData
                         writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:name]
                         atomically:true];
                        NSLog(@"Saved image to %@", [NSHomeDirectory() stringByAppendingPathComponent:name]);
                        [self.paths
                         addObject:[NSHomeDirectory() stringByAppendingPathComponent:name]];
                    }
                }
                
            }
        }
     
            
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.paths.count > 0) {
                NSData* data = [NSJSONSerialization
                                dataWithJSONObject:@{
                                    @"cmd" : @"share_move",
                                    @"paths" : self.paths}
                                options:NSJSONWritingPrettyPrinted
                                error:nil];
                if (data) {
                    NSString* message = [[NSString alloc]
                                         initWithData:data
                                         encoding:NSUTF8StringEncoding];
                    [self.webSocket send:message];
                }
            }
            [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
            [self didSelectCancel];
        });
    }];
}

- (void)processPdfData:(NSItemProvider*) item {
    [item
     loadItemForTypeIdentifier:(NSString*)kUTTypePDF
     options:nil
     completionHandler:^(id<NSSecureCoding>  _Nullable item,
                         NSError * _Null_unspecified error) {
        self.pdfData = item;
        if (self.pdfData != nil) {
            NSLog(@"Data ok, length: %lu", (unsigned long)self.pdfData.length);
            if (self.pdfName != nil) {
                [self savePdf];
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
                [self didSelectCancel];
            });
        }
    }];
}

- (void)processPdfUrl:(NSItemProvider*) item {
    [item
     loadItemForTypeIdentifier:(NSString*)kUTTypeURL
     options:nil
     completionHandler:^(id<NSSecureCoding>  _Nullable item,
                         NSError * _Null_unspecified error) {
        NSURL* url = item;
        if (url != nil) {
            NSLog(@"Url ok: %@", url);
            self.pdfName = [[[url.absoluteString stringByReplacingOccurrencesOfString:@"//" withString:@"_"] stringByReplacingOccurrencesOfString:@"/" withString:@"_"] stringByReplacingOccurrencesOfString:@":" withString:@""];
            if (self.pdfData != nil) {
                [self savePdf];
            }
        } else {
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
                [self didSelectCancel];
            });
        }
    }];
}

- (void)savePdf {
    NSString* name = [[NSString alloc] initWithFormat:@"%@.pdf", self.pdfName];
    NSString* template = @"%@ %d.pdf";
    int i = 0;
    while ([NSFileManager.defaultManager
            fileExistsAtPath:[NSHomeDirectory()
                              stringByAppendingPathComponent:name]]) {
        i++;
        name = [[NSString alloc] initWithFormat:template, self.pdfName, i];
    }
    [self.pdfData
     writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:name]
     atomically:true];
    NSLog(@"Saved pdf to %@", [NSHomeDirectory() stringByAppendingPathComponent:name]);
    [self.paths addObject:[NSHomeDirectory() stringByAppendingPathComponent:name]];
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{
                        @"cmd" : @"share_move",
                        @"paths" : self.paths}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc]
                             initWithData:data
                             encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }

    [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
    [self didSelectCancel];
}

- (void)processText:(NSExtensionItem*) item {
    NSString* name = @"note.txt";
    NSString* template = @"note %d.txt";
    int i = 0;
    while ([NSFileManager.defaultManager
           fileExistsAtPath:[NSHomeDirectory()
                             stringByAppendingPathComponent:name]]) {
       i++;
       name = [[NSString alloc] initWithFormat:template, i];
    }
    [item.attributedContentText.string
    writeToFile:[NSHomeDirectory() stringByAppendingPathComponent:name]
    atomically:true encoding:NSUTF8StringEncoding
    error:nil];
    NSLog(@"Saved text to %@", [NSHomeDirectory() stringByAppendingPathComponent:name]);
    [self.paths addObject:[NSHomeDirectory() stringByAppendingPathComponent:name]];
    NSData* data = [NSJSONSerialization
                   dataWithJSONObject:@{
                       @"cmd" : @"share_move",
                       @"paths" : self.paths}
                   options:NSJSONWritingPrettyPrinted
                   error:nil];
    if (data) {
       NSString* message = [[NSString alloc]
                            initWithData:data
                            encoding:NSUTF8StringEncoding];
       [self.webSocket send:message];
    }

    [self.extensionContext completeRequestReturningItems:nil completionHandler:nil];
    [self didSelectCancel];
}

- (void)didSelectCancel {
    self.webSocket.delegate = nil;
    [self.webSocket close];
    self.webSocket = nil;
    
    // Notify the Service was cancelled
    NSError *cancelError = [NSError
                            errorWithDomain:NSCocoaErrorDomain
                            code:NSUserCancelledError
                            userInfo:nil];
    [self.extensionContext cancelRequestWithError:cancelError];
}

- (BOOL)isContentValid {
    return YES;
}

- (void)connectionFailed {
    self.webSocket.delegate = nil;
    self.webSocket = nil;
}

- (void)connectToPvtboxApplication {
    self.webSocket = [[SRWebSocket alloc] initWithURL:[self getPvtboxApplicationUrl]];
    self.webSocket.delegate = self;
    [self.webSocket open];
}

- (NSURL *)getPvtboxApplicationUrl {
    NSInteger port = [self getPvtboxApplicationPort];
    NSString *url = [NSString stringWithFormat:@"ws://127.0.0.1:%ld/", (long)port];
    return [NSURL URLWithString:url];
}

- (NSInteger)getPvtboxApplicationPort {
    NSString *portFilePath = [NSHomeDirectory() stringByAppendingPathComponent:@"pvtbox.port"];
    
    NSString* port = [NSString stringWithContentsOfFile:portFilePath
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    return [port integerValue];
}

///--------------------------------------
#pragma mark - SRWebSocketDelegate
///--------------------------------------

- (void)webSocketDidOpen:(SRWebSocket *)webSocket;
{
    NSLog(@"Websocket Connected");
    [self performSelector:@selector(ping) withObject:nil afterDelay:10.0];
}

- (void)webSocket:(SRWebSocket *)webSocket didFailWithError:(NSError *)error;
{
    NSLog(@":( Websocket Failed With Error %@", error);
    [self connectionFailed];
    [self performSelector:@selector(connectToPvtboxApplication)
               withObject:nil afterDelay:10.0];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceiveMessage:(nonnull NSString *)string
{
    NSLog(@"Received \"%@\"", string);
}

- (void)webSocket:(SRWebSocket *)webSocket didCloseWithCode:(NSInteger)code reason:(NSString *)reason wasClean:(BOOL)wasClean;
{
    NSLog(@"WebSocket closed");
    [self connectionFailed];
    [self performSelector:@selector(connectToPvtboxApplication)
               withObject:nil afterDelay:10.0];
}

- (void)webSocket:(SRWebSocket *)webSocket didReceivePong:(NSData *)pongPayload;
{
    NSLog(@"WebSocket received pong");
    [self performSelector:@selector(ping)
               withObject:nil afterDelay:10.0];
}

- (void)ping {
    if (self.webSocket) {
        [self.webSocket sendPing:nil];
    }
}


@end
