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

#import "FinderSync.h"
#import <SocketRocket/SRWebSocket.h>

@interface FinderSync () <SRWebSocketDelegate>

@property NSURL *syncFolder;
@property NSSet *sharedPaths;
@property NSString *appPath;
@property NSImage *icon;
@property SRWebSocket *webSocket;

@end

@implementation FinderSync

- (instancetype)init {
    self = [super init];
    self.appPath = [[[[[NSBundle mainBundle] bundlePath]
                      stringByDeletingLastPathComponent]
                     stringByDeletingLastPathComponent]
                    stringByDeletingLastPathComponent];
    
    self.icon = [[NSWorkspace sharedWorkspace] iconForFile:self.appPath];
    
    self.syncFolder = nil;
    [FIFinderSyncController defaultController].directoryURLs = nil;
    
    NSImage* img = [NSImage imageNamed:@"synced"];
    [[FIFinderSyncController defaultController]
     setBadgeImage:img
     label:@"synced"
     forBadgeIdentifier:@"synced"];
    img = [NSImage imageNamed:@"syncing"];
    [[FIFinderSyncController defaultController]
     setBadgeImage:img
     label:@"syncing"
     forBadgeIdentifier:@"syncing"];
    img = [NSImage imageNamed:@"paused"];
    [[FIFinderSyncController defaultController]
     setBadgeImage:img
     label:@"paused"
     forBadgeIdentifier:@"paused"];
    img = [NSImage imageNamed:@"error"];
    [[FIFinderSyncController defaultController]
     setBadgeImage:img
     label:@"error"
     forBadgeIdentifier:@"error"];

    [self connectToPvtboxApplication];
    
    return self;
}

- (void)connectionFailed {
    self.webSocket.delegate = nil;
    self.webSocket = nil;
    self.syncFolder = nil;
     [FIFinderSyncController defaultController].directoryURLs = nil;
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

#pragma mark - Primary Finder Sync protocol methods

- (void)beginObservingDirectoryAtURL:(NSURL *)url {
    NSLog(@"beginObservingDirectoryAtURL:%@", url.filePathURL);
    
}


- (void)endObservingDirectoryAtURL:(NSURL *)url {
    NSLog(@"endObservingDirectoryAtURL:%@", url.filePathURL);
    NSString* path = [[url filePathURL] path];
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{@"cmd" : @"status_unsubscribe", @"path" : path}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }
}

- (void)requestBadgeIdentifierForURL:(NSURL *)url {
    NSLog(@"requestBadgeIdentifierForURL:%@", url.filePathURL);
    NSString* path = [[url filePathURL] path];
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{@"cmd" : @"status_subscribe", @"path" : path}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }
}

#pragma mark - Menu and toolbar item support

- (NSString *)toolbarItemName {
    return @"Pvtbox";
}

- (NSString *)toolbarItemToolTip {
    return @"Pvtbox: Click the toolbar item for a menu.";
}

- (NSImage *)toolbarItemImage {
    return self.icon;
}

- (NSMenu *)menuForMenuKind:(FIMenuKind)whichMenu {
    NSLog(@"menuForMenuKind");
    if (!self.syncFolder) {
        return nil;
    }
    NSURL* target = [[FIFinderSyncController defaultController] targetedURL];
    NSArray* items = [[FIFinderSyncController defaultController] selectedItemURLs];
    
    bool insideSync = target;
    
    __block int sharedCount = 0;
    [items enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* path = [[obj filePathURL] path];
        if([self.sharedPaths containsObject:path]) {
            sharedCount += 1;
        }
    }];
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Pvtbox"];
    switch (whichMenu) {
        case FIMenuKindContextualMenuForItems:
            if (items && [[items[0] filePathURL] isEqual:self.syncFolder]) {
                [menu addItem:[self goToFolderMenuItem]];
                [menu addItem:[self showOnSiteMenuItem]];
            } else {
                [menu addItem:[self getLinkMenuItem]];
                [menu addItem:[self mainLinkMenuItem]];
                if (sharedCount == items.count) {
                    [menu addItem:[self removeLinkMenuItem]];
                }
                [menu addItem:[self showOnSiteMenuItem]];
            }
            break;
        case FIMenuKindContextualMenuForContainer:
        case FIMenuKindContextualMenuForSidebar:
            [menu addItem:[self showOnSiteMenuItem]];
            break;
        case FIMenuKindToolbarItemMenu:
            if (insideSync) {
                [menu addItem:[self showOnSiteMenuItem]];
            } else {
                [menu addItem:[self goToFolderMenuItem]];
            }
        default:
            break;
    }
    return menu;
}

- (NSMenuItem *)goToFolderMenuItem {
    NSLog(@"goToFolderMenuItem");
    NSMenuItem* item = [[NSMenuItem alloc] init];
    [item setImage:self.icon];
    [item setTitle:@"Go to Pvtbox secured sync folder"];
    [item setAction:@selector(openSyncFolderAction:)];
    return item;
}

- (IBAction)openSyncFolderAction:(id)sender {
    NSLog(@"openSyncFolderAction");
    [[NSWorkspace sharedWorkspace] selectFile:self.syncFolder.path
                     inFileViewerRootedAtPath:@""];
}

- (NSMenuItem *)showOnSiteMenuItem {
    NSLog(@"showOnSiteMenuItem");
    NSMenuItem* item = [[NSMenuItem alloc] init];
    [item setImage:self.icon];
    [item setTitle:@"Show on site"];
    [item setAction:@selector(showOnSiteAction:)];
    return item;
}

- (IBAction)showOnSiteAction:(id)sender {
    NSLog(@"showOnSiteAction");
    [[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"https://pvtbox.net/"]];
}

- (NSMenuItem *)getLinkMenuItem {
    NSLog(@"getLinkMenuItem");
    NSMenuItem* item = [[NSMenuItem alloc] init];
    [item setImage:self.icon];
    [item setTitle:@"Get link"];
    [item setAction:@selector(getLinkAction:)];
    return item;
}

- (IBAction)getLinkAction:(id)sender {
    NSLog(@"getLinkAction");
    if (!self.webSocket) return;
    NSArray* items = [[FIFinderSyncController defaultController] selectedItemURLs];
    if (!items) return;
    
    NSMutableArray<NSString*>* paths = [[NSMutableArray alloc] init];
    [items enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* path = [[obj filePathURL] path];
        [paths addObject:path];
    }];
    
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{@"cmd" : @"share_path", @"paths" : paths}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc]
                             initWithData:data
                             encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }
}

- (NSMenuItem *)removeLinkMenuItem {
    NSLog(@"removeLinkMenuItem");
    NSMenuItem* item = [[NSMenuItem alloc] init];
    [item setImage:self.icon];
    [item setTitle:@"Remove link"];
    [item setAction:@selector(removeLinkAction:)];
    return item;
}

- (IBAction)removeLinkAction:(id)sender {
    NSLog(@"removeLinkAction");
    if (!self.webSocket) return;
    NSArray* items = [[FIFinderSyncController defaultController] selectedItemURLs];
    if (!items) return;
    
    NSMutableArray<NSString*>* paths = [[NSMutableArray alloc] init];
    [items enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* path = [[obj filePathURL] path];
        [paths addObject:path];
    }];
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{@"cmd" : @"block_path", @"paths" : paths}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc]
                             initWithData:data
                             encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }
}

- (NSMenuItem *)mainLinkMenuItem {
    NSLog(@"mainLinkMenuItem");
    NSMenuItem* item = [[NSMenuItem alloc] init];
    [item setImage:self.icon];
    [item setTitle:@"Send link to E-mail"];
    [item setAction:@selector(mailLinkAction:)];
    return item;
}

- (IBAction)mailLinkAction:(id)sender {
    NSLog(@"mailLinkAction");
    if (!self.webSocket) return;
    NSArray* items = [[FIFinderSyncController defaultController] selectedItemURLs];
    if (!items) return;
    
    NSMutableArray<NSString*>* paths = [[NSMutableArray alloc] init];
    [items enumerateObjectsUsingBlock: ^(id obj, NSUInteger idx, BOOL *stop) {
        NSString* path = [[obj filePathURL] path];
        [paths addObject:path];
    }];
    NSData* data = [NSJSONSerialization
                    dataWithJSONObject:@{@"cmd" : @"email_link", @"paths" : paths}
                    options:NSJSONWritingPrettyPrinted
                    error:nil];
    if (data) {
        NSString* message = [[NSString alloc]
                             initWithData:data
                             encoding:NSUTF8StringEncoding];
        [self.webSocket send:message];
    }
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
    // Set up the directory we are syncing.
    
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary* message = [NSJSONSerialization
                             JSONObjectWithData:data
                             options:NSJSONReadingMutableContainers
                             error:nil];
    if (message) {
        NSString* command = message[@"cmd"];
        if (!command) return;
        if ([command isEqual:@"get_sync_dir"] || [command isEqual:@"sync_dir"]) {
            NSString* path = message[@"path"];
            if (path) {
                self.syncFolder = [NSURL fileURLWithPath:path];
                [FIFinderSyncController defaultController].directoryURLs =
                    [NSSet setWithObject:self.syncFolder];
            }
        } else if ([command isEqual:@"status"]) {
            NSString* status = message[@"status"];
            NSSet* paths = message[@"paths"];
            [paths enumerateObjectsUsingBlock:^(id  _Nonnull path, BOOL * _Nonnull stop) {
                NSURL* url = [NSURL fileURLWithPath:path];
                [[FIFinderSyncController defaultController]
                 setBadgeIdentifier:status
                 forURL:url];
            }];
        } else if ([command isEqual:@"shared"]) {
            NSSet* paths = message[@"paths"];
            if (paths) {
                self.sharedPaths = paths;
            }
        }
    }
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
        if (!self.syncFolder) {
            NSData* data = [NSJSONSerialization
                            dataWithJSONObject:@{@"cmd" : @"sync_dir"}
                            options:NSJSONWritingPrettyPrinted
                            error:nil];
            NSString* message = [[NSString alloc]
                                 initWithData:data
                                 encoding:NSUTF8StringEncoding];
            [self.webSocket send:message];
        }
        [self.webSocket sendPing:nil];
    }
}

@end

