#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Duo, flat, landscape: the leading column beside the Posts feed. A
// full-height panel (rounded glass inset like the subreddit drawer, or filled:
// solid and square across the whole column) on a plain backdrop that ends in
// a divider where the feed begins: the feed shortcuts
// the subreddit list shows (Home, Popular, All, Moderator, in its icon style)
// and Subreddits, which opens the drawer beside it, at the top, then the
// account's favorite subreddits and followed users, then the multireddits
// picked with Show in Sidebar, which a held press drags into a new order. The
// host sizes the view to the column's reserved width and shows it.
@interface ApolloDuoFeedRail : UIView
/// Width the feed reserves for the column: the panel, its 12pt inset from
/// the display edge and a 12pt gap before the feed.
@property(class, nonatomic, readonly) CGFloat reservedWidth;
/// The panel fills the column from the display edge to the divider, square
/// and solid, instead of a rounded glass panel inset like the drawer.
@property(nonatomic) BOOL filled;
/// 0 Home, 1 Popular, 2 All, 3 Moderator; -1 when the feed is none of them.
@property(nonatomic) NSInteger selectedFeed;
/// Whether Moderator is among the shortcuts: Settings shows it and the
/// subreddit list has its row (the account moderates). Set before
/// -reloadShortcuts.
@property(nonatomic) BOOL showsModerator;
/// The subreddit the feed shows, matched against the favorites; nil for none.
@property(nonatomic, copy, nullable) NSString *selectedSubreddit;
/// The multireddit path (/user/<owner>/m/<name>) the feed shows, matched
/// against the picked multireddits; nil for none.
@property(nonatomic, copy, nullable) NSString *selectedMultiredditPath;
@property(nonatomic) BOOL subredditsSelected;
@property(nonatomic, copy, nullable) void (^selectFeed)(NSInteger feed);
@property(nonatomic, copy, nullable) void (^selectSubreddit)(NSString *subreddit);
/// A picked multireddit was tapped; its path.
@property(nonatomic, copy, nullable) void (^selectMultireddit)(NSString *path);
@property(nonatomic, copy, nullable) void (^toggleSubreddits)(void);
/// Rebuilds the buttons when the shortcuts (Popular and All can be hidden in
/// Settings), the favorites or the picked multireddits changed.
- (void)reloadShortcuts;
- (void)refreshColors;
@end

/// Whether two multireddit paths name the same multireddit, ignoring case and
/// leading or trailing slashes.
FOUNDATION_EXPORT BOOL ApolloDuoFeedRailSameMultiredditPath(NSString *_Nullable a, NSString *_Nullable b);

NS_ASSUME_NONNULL_END
