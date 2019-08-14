//
//  ViewController.m
//  WMLinkMapAnalyzer
//
//  Created by Mac on 16/1/5.
//  Copyright © 2016年 wmeng. All rights reserved.
//

#import "ViewController.h"
#import "symbolModel.h"

#define kLinkMapHistoryPath @"kLinkMapHistoryPath"
#define kLinkMapHistoryUtil @"kLinkMapHistoryUtil"
#define kLinkMapHistoryPathHead @"文件路径："

@interface ViewController()
@property (weak) IBOutlet NSTextField *fileTF;//显示选择的文件路径
@property (weak) IBOutlet NSProgressIndicator *INdicator;//指示器


@property (weak) IBOutlet NSTextField *filterTextFiled;

@property (weak) IBOutlet NSScrollView *contentView;//分析的内容
@property (unsafe_unretained) IBOutlet NSTextView *contentTextView;

@property (nonatomic,strong) NSURL *ChooseLinkMapFileURL;
@property (nonatomic,strong) NSString *linkMapContent;

@property (nonatomic,strong) NSMutableAttributedString *result;//分析的结果


@end
@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Do any additional setup after loading the view.
    self.INdicator.hidden = YES;
    
    NSString *historyPath = [[NSUserDefaults standardUserDefaults] objectForKey:kLinkMapHistoryPath];
    NSString *historyUtil = [[NSUserDefaults standardUserDefaults] objectForKey:kLinkMapHistoryUtil];
    [self.fileTF setEditable:YES];
    if (historyPath) {
        self.fileTF.stringValue = historyPath;
        self.ChooseLinkMapFileURL = [NSURL fileURLWithPath:historyPath];
        
        NSLog(@"xxx %@", historyPath);
    }
    if (historyUtil) {
        self.filterTextFiled.stringValue = historyUtil;
    }
    
}

- (void)setRepresentedObject:(id)representedObject {
    [super setRepresentedObject:representedObject];

    // Update the view, if already loaded.
}

- (IBAction)ChooseFile:(id)sender {
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:NO];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:YES];
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL*  theDoc = [[panel URLs] objectAtIndex:0];
            NSLog(@"xxxx %@", theDoc);
            _fileTF.stringValue = [NSString stringWithFormat:@"%@%@",kLinkMapHistoryPathHead,[theDoc path]] ;
            self.ChooseLinkMapFileURL = theDoc;
        }
    }];
}

- (IBAction)clearButton:(id)sender {
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kLinkMapHistoryPath];
    [[NSUserDefaults standardUserDefaults] setObject:nil forKey:kLinkMapHistoryUtil];
    self.ChooseLinkMapFileURL = nil;
    self.filterTextFiled.stringValue = @"";
    self.fileTF.stringValue = kLinkMapHistoryPathHead;
}


- (IBAction)StartAnalyzer:(id)sender {
    
    if (!_ChooseLinkMapFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:[_ChooseLinkMapFileURL path] isDirectory:nil])
    {
        NSAlert *alert = [[NSAlert alloc]init];
        alert.messageText = @"没有找到该路径！";
        [alert addButtonWithTitle:@"是的"];
        [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
            
        }];
        return;
    }
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        NSString *content = [NSString stringWithContentsOfURL:_ChooseLinkMapFileURL encoding:NSMacOSRomanStringEncoding error:&error];
        NSRange objsFileTagRange = [content rangeOfString:@"# Object files:"];
        NSString *subObjsFileSymbolStr = [content substringFromIndex:objsFileTagRange.location + objsFileTagRange.length];
        NSRange symbolsRange = [subObjsFileSymbolStr rangeOfString:@"# Symbols:"];
        if ([content rangeOfString:@"# Path:"].length <= 0||objsFileTagRange.location == NSNotFound||symbolsRange.location == NSNotFound)
        {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSAlert *alert = [[NSAlert alloc]init];
                alert.messageText = @"文件格式不正确";
                [alert addButtonWithTitle:@"是的"];
                [alert beginSheetModalForWindow:[NSApplication sharedApplication].windows[0] completionHandler:^(NSModalResponse returnCode) {
                    
                }];
                
            });
            return;
        }
        
        NSString *historyPath = [[NSUserDefaults standardUserDefaults] objectForKey:kLinkMapHistoryPath];
        NSString *historyUtil = [[NSUserDefaults standardUserDefaults] objectForKey:kLinkMapHistoryUtil];

        if (![_fileTF.stringValue isEqualToString:kLinkMapHistoryPathHead] && ![_fileTF.stringValue isEqualToString:historyPath]) {
            [[NSUserDefaults standardUserDefaults] setObject:[_fileTF.stringValue stringByReplacingOccurrencesOfString:kLinkMapHistoryPathHead withString:@""] forKey:kLinkMapHistoryPath];
        }
        if (self.filterTextFiled.stringValue.length > 0 && ![self.filterTextFiled.stringValue isEqualToString:historyUtil]) {
            [[NSUserDefaults standardUserDefaults] setObject:self.filterTextFiled.stringValue forKey:kLinkMapHistoryUtil];
        }

        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.INdicator.hidden = NO;
            [self.INdicator startAnimation:self];
            
        });
        
        NSMutableDictionary <NSString *,symbolModel *>*sizeMap = [NSMutableDictionary new];
        // 符号文件列表
        NSArray *lines = [content componentsSeparatedByString:@"\n"];
        
        BOOL reachFiles = NO;
        BOOL reachSymbols = NO;
        BOOL reachSections = NO;
        
        for(NSString *line in lines)
        {
            if([line hasPrefix:@"#"])   //注释行
            {
                if([line hasPrefix:@"# Object files:"])
                    reachFiles = YES;
                else if ([line hasPrefix:@"# Sections:"])
                    reachSections = YES;
                else if ([line hasPrefix:@"# Symbols:"])
                    reachSymbols = YES;
            }
            else
            {
                if(reachFiles == YES && reachSections == NO && reachSymbols == NO)
                {
                    NSRange range = [line rangeOfString:@"]"];
                    if(range.location != NSNotFound)
                    {
                        symbolModel *symbol = [symbolModel new];
                        symbol.file = [line substringFromIndex:range.location+1];
                        NSString *key = [line substringToIndex:range.location+1];
                        sizeMap[key] = symbol;
                    }
                }
                else if (reachFiles == YES &&reachSections == YES && reachSymbols == NO)
                {
                }
                else if (reachFiles == YES && reachSections == YES && reachSymbols == YES)
                {
                    NSArray <NSString *>*symbolsArray = [line componentsSeparatedByString:@"\t"];
                    if(symbolsArray.count == 3)
                    {
                        //Address Size File Name
                        NSString *fileKeyAndName = symbolsArray[2];
                        NSUInteger size = strtoul([symbolsArray[1] UTF8String], nil, 16);
                        
                        NSRange range = [fileKeyAndName rangeOfString:@"]"];
                        if(range.location != NSNotFound)
                        {
                            symbolModel *symbol = sizeMap[[fileKeyAndName substringToIndex:range.location+1]];
                            if(symbol)
                            {
                                symbol.size = size;
                            }
                        }
                    }
                }
            }
            
        }
        
        NSArray <symbolModel *>*symbols = [sizeMap allValues];
        NSArray *sorted = [symbols sortedArrayUsingComparator:^NSComparisonResult(symbolModel *  _Nonnull obj1, symbolModel *  _Nonnull obj2) {
            if(obj1.size > obj2.size)
                return NSOrderedAscending;
            else if (obj1.size < obj2.size)
                return NSOrderedDescending;
            else
                return NSOrderedSame;
        }];
        
        if (self.result) {
            self.result = nil;
        }
        self.result = [[NSMutableAttributedString alloc] initWithString:@"各模块体积大小\n\n"];
        NSUInteger totalSize = 0;
        NSUInteger filterSize = 0;
        
        for(symbolModel *symbol in sorted)
        {
            
            NSDictionary *attribute = nil;
            // 筛选出来的字符串加红
            if ([[[[[symbol.file componentsSeparatedByString:@"/"] lastObject] componentsSeparatedByString:@"("] firstObject] isEqualToString:self.filterTextFiled.stringValue]) {
                filterSize += symbol.size;
                attribute = @{NSForegroundColorAttributeName:[NSColor redColor]};
            }

            if (symbol.size/1024.0 < 1) {
                NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %@K\n",[[symbol.file componentsSeparatedByString:@"/"] lastObject],@(symbol.size)] attributes:attribute];
                [_result appendAttributedString:string];
                
            } else {
                NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@: %.4fM\n",[[symbol.file componentsSeparatedByString:@"/"] lastObject],(symbol.size/1024.0)] attributes:attribute];
                [_result appendAttributedString:string];
            }
            
            
//            NSLog(@"%@",result);
            totalSize += symbol.size;
        }
        
        if (self.filterTextFiled.stringValue.length > 0) {
            NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@ : %@K\n",self.filterTextFiled.stringValue, @(filterSize)]];
            [_result insertAttributedString:string atIndex:0];

//            [_result insertString:[NSString stringWithFormat:@"%@ : %@K\n",self.filterTextFiled.stringValue, @(filterSize)] atIndex:0];
        }
        NSAttributedString *string = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"总体积: %.4fM\n",(totalSize/1024.0)]];
        [_result insertAttributedString:string atIndex:0];

//        [_result insertString:[NSString stringWithFormat:@"总体积: %.4fM\n",(totalSize/1024.0)] atIndex:0];
//        NSLog(@"%@",result);

        
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"%@", self.result.string);
            [self.contentTextView insertText:self.result replacementRange:NSMakeRange(0, self.result.string.length)];
//            self.contentTextView.string = self.result;
            self.INdicator.hidden = YES;
            [self.INdicator stopAnimation:self];
            
        });
    });
    
}
- (IBAction)inputFile:(id)sender {
    
    NSOpenPanel* panel = [NSOpenPanel openPanel];
    [panel setAllowsMultipleSelection:NO];
    [panel setCanChooseDirectories:YES];
    [panel setResolvesAliases:NO];
    [panel setCanChooseFiles:NO];
    
    [panel beginWithCompletionHandler:^(NSInteger result){
        if (result == NSFileHandlingPanelOKButton) {
            NSURL*  theDoc = [[panel URLs] objectAtIndex:0];
            NSLog(@"%@", theDoc);
            NSMutableString *content =[[NSMutableString alloc]initWithCapacity:0];
            [content appendString:[theDoc path]];
            [content appendString:@"/linkMap.txt"];
            NSLog(@"content=%@",content);
            [_result.string writeToFile:content atomically:YES encoding:NSUTF8StringEncoding error:nil];

        }
    }];

    
    
}

@end
