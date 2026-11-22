#import "ApolloDuoFeedRailMultiStore.h"
#import "ApolloAccountCredentials.h"
#import "ApolloDuoFeedRailMultis.h"
#import "UserDefaultConstants.h"
#import "ApolloCommon.h"

NSString *const ApolloDuoFeedRailMultisChangedNotification = @"ApolloDuoFeedRailMultisChanged";

// The RDKMultireddit and member accessors read below, declared so the
// selectors are known; every call checks respondsToSelector: first.
@protocol ApolloDuoRailMultiModel
@optional
- (NSString *)path;
- (NSString *)name;
- (NSString *)displayName;
- (NSArray *)subreddits;
@end

static NSString *const kPickPath = @"path";
static NSString *const kPickTitle = @"title";
static NSString *const kPickIcon = @"icon";

// The saved picks, skipping anything that isn't a pick with a path.
static NSArray<NSDictionary<NSString *, NSString *> *> *ApolloDuoRailMultiStored(void) {
    NSMutableArray *picks = [NSMutableArray array];
    for (id entry in [NSUserDefaults.standardUserDefaults arrayForKey:UDKeyDuoFeedRailMultireddits] ?: @[]) {
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        id path = entry[kPickPath];
        if (![path isKindOfClass:NSString.class] || ![path length]) continue;
        [picks addObject:entry];
    }
    return picks;
}

static void ApolloDuoRailMultiSave(NSArray *picks, NSArray *previous) {
    if ([picks isEqualToArray:previous]) return;
    [NSUserDefaults.standardUserDefaults setObject:picks forKey:UDKeyDuoFeedRailMultireddits];
    ApolloLog(@"[DuoFeedRail] multireddit picks saved: %lu", (unsigned long)picks.count);
    void (^post)(void) = ^{
        [NSNotificationCenter.defaultCenter postNotificationName:ApolloDuoFeedRailMultisChangedNotification object:nil];
    };
    if (NSThread.isMainThread) post();
    else dispatch_async(dispatch_get_main_queue(), post);
}

static BOOL ApolloDuoRailMultiSamePath(NSString *a, NSString *b) {
    return a && b && [a caseInsensitiveCompare:b] == NSOrderedSame;
}

static NSInteger ApolloDuoRailMultiIndexOfPath(NSArray<NSDictionary *> *picks, NSString *path) {
    for (NSUInteger i = 0; i < picks.count; i++) {
        if (ApolloDuoRailMultiSamePath(picks[i][kPickPath], path)) return (NSInteger)i;
    }
    return NSNotFound;
}

static BOOL ApolloDuoRailMultiOwnedBy(NSDictionary *pick, NSString *username) {
    NSString *path = pick[kPickPath];
    return username.length && ApolloDuoRailMultiPathOwnerMatches(path.UTF8String, username.UTF8String);
}

static NSString *ApolloDuoRailMultiString(id object, SEL selector) {
    if (![object respondsToSelector:selector]) return nil;
    id value = ((id (*)(id, SEL))objc_msgSend)(object, selector);
    return [value isKindOfClass:NSString.class] && [value length] ? value : nil;
}

@implementation ApolloDuoFeedRailMultiStore

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)picksForActiveAccount {
    NSString *username = ApolloActiveAccountUsername();
    if (!username.length) return @[];
    NSMutableArray *picks = [NSMutableArray array];
    for (NSDictionary *pick in ApolloDuoRailMultiStored()) {
        if (ApolloDuoRailMultiOwnedBy(pick, username)) [picks addObject:pick];
    }
    return picks;
}

+ (BOOL)containsPath:(NSString *)path {
    return path.length && ApolloDuoRailMultiIndexOfPath(ApolloDuoRailMultiStored(), path) != NSNotFound;
}

+ (void)addPath:(NSString *)path title:(NSString *)title iconSubreddit:(NSString *)icon {
    if (!path.length) return;
    NSArray *previous = ApolloDuoRailMultiStored();
    if (ApolloDuoRailMultiIndexOfPath(previous, path) != NSNotFound) return;
    NSMutableDictionary *pick = [NSMutableDictionary dictionaryWithObject:path forKey:kPickPath];
    pick[kPickTitle] = title.length ? title : path.lastPathComponent;
    if (icon.length) pick[kPickIcon] = icon;
    ApolloDuoRailMultiSave([previous arrayByAddingObject:pick], previous);
}

+ (void)removePath:(NSString *)path {
    NSArray *previous = ApolloDuoRailMultiStored();
    NSInteger index = ApolloDuoRailMultiIndexOfPath(previous, path);
    if (index == NSNotFound) return;
    NSMutableArray *picks = [previous mutableCopy];
    [picks removeObjectAtIndex:(NSUInteger)index];
    ApolloDuoRailMultiSave(picks, previous);
}

+ (void)movePath:(NSString *)path toActiveIndex:(NSUInteger)index {
    NSString *username = ApolloActiveAccountUsername();
    if (!username.length) return;
    NSArray *previous = ApolloDuoRailMultiStored();
    // The active account's picks move among the slots they already hold, so
    // every other account's picks stay where they were.
    NSMutableArray<NSNumber *> *slots = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *active = [NSMutableArray array];
    for (NSUInteger i = 0; i < previous.count; i++) {
        if (!ApolloDuoRailMultiOwnedBy(previous[i], username)) continue;
        [slots addObject:@(i)];
        [active addObject:previous[i]];
    }
    NSInteger from = ApolloDuoRailMultiIndexOfPath(active, path);
    if (from == NSNotFound) return;
    NSDictionary *moving = active[(NSUInteger)from];
    [active removeObjectAtIndex:(NSUInteger)from];
    [active insertObject:moving atIndex:MIN(index, active.count)];
    NSMutableArray *picks = [previous mutableCopy];
    for (NSUInteger i = 0; i < slots.count; i++) picks[slots[i].unsignedIntegerValue] = active[i];
    ApolloDuoRailMultiSave(picks, previous);
}

+ (void)reconcileWithMultireddits:(NSArray *)multireddits owner:(NSString *)owner {
    NSString *username = owner;
    if (!username.length || !multireddits.count) return;
    NSMutableDictionary<NSString *, id> *byPath = [NSMutableDictionary dictionary];
    for (id multireddit in multireddits) {
        NSString *path = ApolloDuoRailMultiString(multireddit, @selector(path));
        if (path) byPath[path.lowercaseString] = multireddit;
    }
    NSArray *previous = ApolloDuoRailMultiStored();
    NSMutableArray *picks = [NSMutableArray array];
    for (NSDictionary *pick in previous) {
        if (!ApolloDuoRailMultiOwnedBy(pick, username)) {
            [picks addObject:pick];
            continue;
        }
        id multireddit = byPath[[pick[kPickPath] lowercaseString]];
        // Deleted on Reddit (or no longer this account's): drop it.
        if (!multireddit) continue;
        NSMutableDictionary *updated = [pick mutableCopy];
        NSString *title = [self titleForMultireddit:multireddit];
        NSString *icon = [self iconSubredditForMultireddit:multireddit];
        if (title) updated[kPickTitle] = title;
        if (icon) updated[kPickIcon] = icon;
        [picks addObject:updated];
    }
    ApolloDuoRailMultiSave(picks, previous);
}

+ (NSString *)titleForMultireddit:(id)multireddit {
    return ApolloDuoRailMultiString(multireddit, @selector(displayName))
        ?: ApolloDuoRailMultiString(multireddit, @selector(name));
}

// The first member subreddit's name. Members arrive as names, dictionaries
// or model objects depending on Apollo's transformer, so each is accepted.
+ (NSString *)iconSubredditForMultireddit:(id)multireddit {
    if (![multireddit respondsToSelector:@selector(subreddits)]) return nil;
    id members = ((id (*)(id, SEL))objc_msgSend)(multireddit, @selector(subreddits));
    if (![members isKindOfClass:NSArray.class]) return nil;
    for (id member in (NSArray *)members) {
        NSString *name = nil;
        if ([member isKindOfClass:NSString.class]) {
            name = member;
        } else if ([member isKindOfClass:NSDictionary.class]) {
            id value = member[@"name"];
            name = [value isKindOfClass:NSString.class] ? value : nil;
        } else {
            name = ApolloDuoRailMultiString(member, @selector(name))
                ?: ApolloDuoRailMultiString(member, @selector(displayName));
        }
        if (name.length) return name;
    }
    return nil;
}

@end
