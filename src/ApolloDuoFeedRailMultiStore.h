#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main thread after the picks change.
FOUNDATION_EXPORT NSString *const ApolloDuoFeedRailMultisChangedNotification;

// The multireddits picked for the Duo feed sidebar (Show in Sidebar in the
// subreddit list), kept in NSUserDefaults under UDKeyDuoFeedRailMultireddits
// in sidebar order. Each pick is {"path", "title", "icon"}: the path is the
// rename-stable /user/<owner>/m/<name>, the title its display name when
// picked or last loaded, and icon its first member subreddit, which the
// sidebar uses for the icon when the multireddit has no custom one. Paths
// compare ignoring case. Main thread only.
@interface ApolloDuoFeedRailMultiStore : NSObject
/// The picks whose path's owner is the signed-in account, in sidebar order;
/// empty when no account is signed in.
+ (NSArray<NSDictionary<NSString *, NSString *> *> *)picksForActiveAccount;
+ (BOOL)containsPath:(NSString *)path;
/// Appends a pick; does nothing when the path is already picked.
+ (void)addPath:(NSString *)path title:(NSString *)title iconSubreddit:(nullable NSString *)icon;
+ (void)removePath:(NSString *)path;
/// Moves a pick to `index` among the active account's picks. Other accounts'
/// picks keep their order.
+ (void)movePath:(NSString *)path toActiveIndex:(NSUInteger)index;
/// The active account's multireddit list (RDKMultireddit objects) just
/// loaded: drops that account's picks it no longer has and refreshes their
/// titles and icons. Does nothing for an empty list.
+ (void)reconcileWithMultireddits:(NSArray *)multireddits;
/// The title and icon subreddit to save for an RDKMultireddit.
+ (nullable NSString *)titleForMultireddit:(id)multireddit;
+ (nullable NSString *)iconSubredditForMultireddit:(id)multireddit;
@end

NS_ASSUME_NONNULL_END
