#import "ApolloDuoFeedRail.h"
#import "ApolloDuoFeedRailToggle.h"
#import "ApolloDuoFeedRailMultiStore.h"
#import "ApolloDuoFeedRailMultis.h"
#import "ApolloFeedShortcutsAppearance.h"
#import "ApolloGalleryImageLoader.h"
#import "ApolloNativeSubredditIcons.h"
#import "ApolloSubredditInfoCache.h"
#import "ApolloThemeRuntime.h"
#import "ApolloUserProfileCache.h"
#import "UserDefaultConstants.h"
#import "ApolloCommon.h"

// The panel sits 12pt in from the display's top, bottom and leading edges,
// like the subreddit drawer that opens beside it.
static const CGFloat kRailInset = 12;
// The buttons' width in either style: room for a subreddit name under its icon.
static const CGFloat kRailColumnWidth = 92;
// The buttons' distance from the display edge and from the divider before
// the feed; the rounded panel's too.
static const CGFloat kRailSideInset = 4;
static const CGFloat kRailButtonHeight = 62;
static const CGFloat kRailFavoriteHeight = 60;
static const CGFloat kRailGlyphSize = 24;
static const CGFloat kRailAvatarSize = 32;
// The highlight sits this far inside the panel's sides, and 2pt inside its
// button's top and bottom.
static const CGFloat kRailSelectionInset = 4;
// A rounded rectangle rather than the lens's capsule, whose curve would cut
// into the names along its bottom; at this radius the longest name fits.
static const CGFloat kRailSelectionRadius = 16;
// Room under the last favorite, so its highlight clears the panel's rounded
// bottom when the list is scrolled to the end.
static const CGFloat kRailFavoritesBottomInset = 10;
static const NSInteger kRailSubredditsTag = -1;
static const NSInteger kRailFavoriteTag = -2;
// The collapse arrow: a glass circle this wide, centered in a slot this tall
// at the bottom of the panel, below the favorites.
static const CGFloat kRailToggleSize = 32;
static const CGFloat kRailToggleSlot = 48;
static const NSInteger kRailMultiTag = -3;

// A multireddit's custom icon (ApolloMultiredditEdit.xm), by path.
extern UIImage *ApolloMultiEditCustomIconForPath(NSString *path);

// Reddit's model path and the feed's own path can differ in case and in a
// trailing slash; both name the same multireddit.
BOOL ApolloDuoFeedRailSameMultiredditPath(NSString *a, NSString *b) {
    if (!a.length || !b.length) return NO;
    NSCharacterSet *slash = [NSCharacterSet characterSetWithCharactersInString:@"/"];
    NSString *left = [a stringByTrimmingCharactersInSet:slash];
    NSString *right = [b stringByTrimmingCharactersInSet:slash];
    return [left caseInsensitiveCompare:right] == NSOrderedSame;
}

// The highlight is the shade UIKit's lens gives the tab rail's selected tab,
// darker than the glass (sampled from the rail on iOS 26 and 27), with the
// item itself in the accent.
static UIColor *ApolloDuoFeedRailSelectionColor(void) {
    static UIColor *color;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        color = [UIColor colorWithDynamicProvider:^UIColor *(UITraitCollection *traits) {
            BOOL dark = traits.userInterfaceStyle == UIUserInterfaceStyleDark;
            return [UIColor colorWithWhite:0 alpha:dark ? 0.69 : 0.09];
        }];
    });
    return color;
}

static char kApolloDuoFeedRailFavoritesContext;

// "u/name" favorites are followed users.
static NSString *ApolloDuoFeedRailUsername(NSString *favorite) {
    return [favorite.lowercaseString hasPrefix:@"u/"] && favorite.length > 2 ? [favorite substringFromIndex:2] : nil;
}

// A glyph scaled into a square template image, so Apollo's bundled art and SF
// Symbols share one size.
static UIImage *ApolloDuoFeedRailGlyph(UIImage *source) {
    if (!source || source.size.width <= 0 || source.size.height <= 0) return nil;
    CGFloat scale = kRailGlyphSize / MAX(source.size.width, source.size.height);
    CGSize size = CGSizeMake(source.size.width * scale, source.size.height * scale);
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(kRailGlyphSize, kRailGlyphSize)];
    UIImage *image = [renderer imageWithActions:^(__unused UIGraphicsImageRendererContext *context) {
        [[source imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate]
            drawInRect:CGRectMake((kRailGlyphSize - size.width) / 2, (kRailGlyphSize - size.height) / 2, size.width, size.height)];
    }];
    return [image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

// One entry: a glyph (feeds, Subreddits) or a subreddit's icon (favorites)
// over its name, on a rounded highlight while it is what the feed shows.
@interface ApolloDuoFeedRailButton : UIControl
@property(nonatomic, strong) UIView *selection;
@property(nonatomic, strong) UIImageView *icon;
@property(nonatomic, strong) UILabel *initial;
@property(nonatomic, strong) UILabel *label;
@property(nonatomic, copy) NSString *subreddit;
// A picked multireddit's path; its `subreddit` is then the first member
// subreddit, whose icon it shows when it has no custom one.
@property(nonatomic, copy) NSString *multiredditPath;
@property(nonatomic, strong) ApolloGalleryImageRequest *iconRequest;
// The subreddit info lookup has been asked for (once, when first in view).
@property(nonatomic) BOOL infoRequested;
// An icon is loading or shown.
@property(nonatomic) BOOL hasIcon;
@property(nonatomic) BOOL avatar;
// A feed shortcut drawn as a tile, circle or Classic icon, at the avatars' size.
@property(nonatomic) BOOL styled;
@property(nonatomic) BOOL chosen;
// The highlight's top corner radius: the panel's own curve, less the inset,
// for the button at the top of the panel; kRailSelectionRadius elsewhere.
@property(nonatomic) CGFloat selectionTopRadius;
// Shapes the top button's highlight under the panel's rounded top.
@property(nonatomic, strong) CAShapeLayer *domeMask;
@end

@implementation ApolloDuoFeedRailButton
- (instancetype)initWithTitle:(NSString *)title {
    if (!(self = [super initWithFrame:CGRectZero])) return nil;
    self.selectionTopRadius = kRailSelectionRadius;
    self.selection = [UIView new];
    self.selection.userInteractionEnabled = NO;
    self.selection.backgroundColor = ApolloDuoFeedRailSelectionColor();
    self.selection.layer.cornerRadius = kRailSelectionRadius;
    self.selection.layer.cornerCurve = kCACornerCurveContinuous;
    self.selection.hidden = YES;
    [self addSubview:self.selection];
    self.icon = [UIImageView new];
    self.icon.userInteractionEnabled = NO;
    [self addSubview:self.icon];
    self.label = [UILabel new];
    self.label.text = title;
    self.label.textAlignment = NSTextAlignmentCenter;
    // A long name shrinks a little, then truncates, so it stays inside the
    // highlight.
    self.label.adjustsFontSizeToFitWidth = YES;
    self.label.minimumScaleFactor = 0.8;
    self.label.lineBreakMode = NSLineBreakByTruncatingTail;
    [self addSubview:self.label];
    self.isAccessibilityElement = YES;
    self.accessibilityLabel = title;
    return self;
}
- (instancetype)initWithGlyph:(UIImage *)glyph title:(NSString *)title {
    if (!(self = [self initWithTitle:title])) return nil;
    self.icon.image = ApolloDuoFeedRailGlyph(glyph);
    self.icon.contentMode = UIViewContentModeCenter;
    self.label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    return self;
}
// A feed shortcut as the subreddit list draws it in the chosen icon style
// (Settings > Feed Shortcuts). Monochrome takes the rail's colors; the other
// styles keep their own. Bare glyphs (Tinted, Monochrome) are centered on the
// glyph box and overhang it as the list's do; tiles, circles and Classic sit
// at the avatars' size.
- (instancetype)initWithShortcutIcon:(UIImage *)icon style:(ApolloSubredditFeedIconStyle)style title:(NSString *)title {
    if (!(self = [self initWithTitle:title])) return nil;
    BOOL monochrome = style == ApolloSubredditFeedIconStyleMonochrome;
    BOOL bare = monochrome || style == ApolloSubredditFeedIconStyleTinted;
    self.styled = !bare;
    self.icon.image = [icon imageWithRenderingMode:monochrome ? UIImageRenderingModeAlwaysTemplate
                                                              : UIImageRenderingModeAlwaysOriginal];
    self.icon.contentMode = bare ? UIViewContentModeCenter : UIViewContentModeScaleAspectFit;
    self.label.font = [UIFont systemFontOfSize:11 weight:UIFontWeightSemibold];
    return self;
}
- (instancetype)initWithSubreddit:(NSString *)subreddit iconURL:(NSURL *)iconURL {
    if (!(self = [self initWithTitle:subreddit])) return nil;
    self.avatar = YES;
    self.subreddit = subreddit;
    NSString *username = ApolloDuoFeedRailUsername(subreddit);
    self.accessibilityLabel = username ? subreddit : [@"r/" stringByAppendingString:subreddit];
    self.label.font = [UIFont systemFontOfSize:10 weight:UIFontWeightMedium];
    self.icon.contentMode = UIViewContentModeScaleAspectFill;
    self.icon.clipsToBounds = YES;
    self.icon.layer.cornerRadius = kRailAvatarSize / 2;
    // Until the icon loads (or for a subreddit without one), its first letter.
    self.initial = [UILabel new];
    NSString *name = username ?: subreddit;
    self.initial.text = name.length ? [name substringToIndex:1].uppercaseString : @"r";
    self.initial.font = [UIFont systemFontOfSize:15 weight:UIFontWeightBold];
    self.initial.textAlignment = NSTextAlignmentCenter;
    self.initial.clipsToBounds = YES;
    self.initial.layer.cornerRadius = kRailAvatarSize / 2;
    [self insertSubview:self.initial belowSubview:self.icon];
    [self loadIconFromURL:iconURL];
    return self;
}
// A picked multireddit: its name over its custom icon, or over its first
// member subreddit's icon once that loads, its first letter until then.
- (instancetype)initWithMultiredditPath:(NSString *)path title:(NSString *)title iconSubreddit:(NSString *)iconSubreddit {
    if (!(self = [self initWithSubreddit:title iconURL:nil])) return nil;
    self.multiredditPath = path;
    self.subreddit = iconSubreddit;
    self.accessibilityLabel = [title stringByAppendingString:@", multireddit"];
    self.initial.text = title.length ? [title substringToIndex:1].uppercaseString : @"m";
    UIImage *custom = ApolloMultiEditCustomIconForPath(path);
    if (custom) {
        self.hasIcon = YES;
        self.icon.image = custom;
        self.initial.hidden = YES;
    }
    return self;
}
- (void)loadIconFromURL:(NSURL *)url {
    if (!url || self.hasIcon) return;
    self.hasIcon = YES;
    [self.iconRequest cancel];
    __weak ApolloDuoFeedRailButton *weakSelf = self;
    self.iconRequest = [ApolloGalleryImageLoader.sharedLoader loadThumbnailAtURL:url completion:^(UIImage *image) {
        ApolloDuoFeedRailButton *button = weakSelf;
        if (!button) return;
        if (!image) {
            // A stale or broken URL: the info lookup may still find a working one.
            button.hasIcon = NO;
            return;
        }
        button.icon.image = image;
        button.initial.hidden = YES;
    }];
}
- (void)dealloc {
    [_iconRequest cancel];
}
- (void)layoutSubviews {
    [super layoutSubviews];
    CGRect bounds = self.bounds;
    CGRect selection = CGRectInset(bounds, kRailSelectionInset, 2);
    self.selection.frame = selection;
    [self shapeSelection];
    // Icon and name sit in the middle of the highlight, the name well above
    // its rounded bottom corners and inset from its sides.
    BOOL large = self.avatar || self.styled;
    CGFloat iconSize = large ? kRailAvatarSize : kRailGlyphSize;
    CGFloat iconTop = CGRectGetMinY(selection) + (large ? 5 : 8);
    self.icon.frame = CGRectMake((bounds.size.width - iconSize) / 2, iconTop, iconSize, iconSize);
    self.initial.frame = self.icon.frame;
    CGFloat labelInset = self.avatar ? 6 : 5;
    self.label.frame = CGRectMake(CGRectGetMinX(selection) + labelInset, CGRectGetMaxY(self.icon.frame) + (large ? 3 : 5),
                                  CGRectGetWidth(selection) - labelInset * 2, self.avatar ? 12 : 13);
}
// Under the panel's rounded top, the highlight's top follows it in circular
// arcs, as the panel's corners are, so the gap there matches the sides'.
// UIKit's corner radii are continuous curves, which hug the corner and pinch
// that gap.
- (void)shapeSelection {
    CGSize size = self.selection.bounds.size;
    CGFloat top = MIN(self.selectionTopRadius, size.width / 2);
    CGFloat bottom = MIN(kRailSelectionRadius, MIN(size.width / 2, size.height - top));
    BOOL dome = top > kRailSelectionRadius && bottom > 0;
    CGFloat radius = dome ? 0 : kRailSelectionRadius;
    if (@available(iOS 26.0, *)) {
        self.selection.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:
            [UICornerRadius fixedRadius:radius]];
    } else {
        self.selection.layer.cornerRadius = radius;
    }
    if (!dome) {
        self.selection.layer.mask = nil;
        return;
    }
    UIBezierPath *path = [UIBezierPath bezierPath];
    [path moveToPoint:CGPointMake(0, top)];
    [path addArcWithCenter:CGPointMake(top, top) radius:top startAngle:M_PI endAngle:M_PI * 1.5 clockwise:YES];
    [path addArcWithCenter:CGPointMake(size.width - top, top) radius:top startAngle:M_PI * 1.5 endAngle:0 clockwise:YES];
    [path addArcWithCenter:CGPointMake(size.width - bottom, size.height - bottom) radius:bottom
                startAngle:0 endAngle:M_PI_2 clockwise:YES];
    [path addArcWithCenter:CGPointMake(bottom, size.height - bottom) radius:bottom
                startAngle:M_PI_2 endAngle:M_PI clockwise:YES];
    [path closePath];
    if (!self.domeMask) self.domeMask = [CAShapeLayer layer];
    self.domeMask.frame = self.selection.bounds;
    self.domeMask.path = path.CGPath;
    self.selection.layer.mask = self.domeMask;
}
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.alpha = highlighted ? 0.55 : 1;
}
- (void)applyAccent:(UIColor *)accent neutral:(UIColor *)neutral {
    self.selection.hidden = !self.chosen;
    self.icon.tintColor = self.chosen ? accent : neutral;
    self.label.textColor = self.chosen ? accent : neutral;
    self.initial.textColor = accent;
    self.initial.backgroundColor = [accent colorWithAlphaComponent:0.18];
    self.accessibilityTraits = UIAccessibilityTraitButton | (self.chosen ? UIAccessibilityTraitSelected : 0);
}
@end

@interface ApolloDuoFeedRailToggleButton ()
@property(nonatomic, strong) UIVisualEffectView *glass;
@property(nonatomic, strong) UIImageView *chevron;
@end

@implementation ApolloDuoFeedRailToggleButton
- (instancetype)initPointingRight:(BOOL)pointsRight {
    if (!(self = [super initWithFrame:CGRectMake(0, 0, kRailToggleSize, kRailToggleSize)])) return nil;
    UIVisualEffect *effect = nil;
    if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
    else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemThinMaterial];
    self.glass = [[UIVisualEffectView alloc] initWithEffect:effect];
    self.glass.userInteractionEnabled = NO;
    self.glass.clipsToBounds = YES;
    if (@available(iOS 26.0, *)) {
        self.glass.cornerConfiguration = [UICornerConfiguration configurationWithUniformRadius:
            [UICornerRadius fixedRadius:kRailToggleSize / 2]];
    } else {
        self.glass.layer.cornerRadius = kRailToggleSize / 2;
    }
    [self addSubview:self.glass];
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:13
                                                                                         weight:UIImageSymbolWeightSemibold];
    self.chevron = [[UIImageView alloc] initWithImage:
        [UIImage systemImageNamed:pointsRight ? @"chevron.right" : @"chevron.left" withConfiguration:symbol]];
    self.chevron.contentMode = UIViewContentModeCenter;
    self.chevron.userInteractionEnabled = NO;
    [self addSubview:self.chevron];
    self.isAccessibilityElement = YES;
    self.accessibilityTraits = UIAccessibilityTraitButton;
    self.accessibilityLabel = pointsRight ? @"Show Sidebar" : @"Hide Sidebar";
    [self refreshColors];
    return self;
}
- (void)layoutSubviews {
    [super layoutSubviews];
    // The circle stays its size and centered whatever room the control has.
    CGRect circle = CGRectMake((self.bounds.size.width - kRailToggleSize) / 2,
                               (self.bounds.size.height - kRailToggleSize) / 2, kRailToggleSize, kRailToggleSize);
    self.glass.frame = circle;
    self.chevron.frame = circle;
}
// The press dims the circle, not the control: the host shows and hides the
// reopen arrow through the control's own alpha, which a late unhighlight
// would otherwise undo.
- (void)setHighlighted:(BOOL)highlighted {
    [super setHighlighted:highlighted];
    self.glass.alpha = highlighted ? 0.55 : 1;
    self.chevron.alpha = highlighted ? 0.55 : 1;
}
- (void)refreshColors {
    self.chevron.tintColor = ApolloNavigationChromeColor() ?: UIColor.labelColor;
}
- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self refreshColors];
}
- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self refreshColors];
}
@end

@interface ApolloDuoFeedRail () <UIScrollViewDelegate, UIGestureRecognizerDelegate>
@property(nonatomic, strong) ApolloDuoFeedRailToggleButton *collapseButton;
@property(nonatomic, strong) UIVisualEffectView *panel;
@property(nonatomic, strong) NSArray<ApolloDuoFeedRailButton *> *feedButtons;
@property(nonatomic, strong) NSArray<ApolloDuoFeedRailButton *> *favoriteButtons;
@property(nonatomic, strong) ApolloDuoFeedRailButton *subredditsButton;
@property(nonatomic, strong) UIScrollView *favorites;
@property(nonatomic, strong) UIView *separator;
// The hairline on the column's trailing edge, where the feed begins.
@property(nonatomic, strong) UIView *divider;
@property(nonatomic, copy) NSArray<NSNumber *> *shortcuts;
@property(nonatomic) NSInteger shortcutStyle;
@property(nonatomic, copy) NSArray<NSString *> *favoriteNames;
// The picked multireddits, after the favorites in the same scroll area.
@property(nonatomic, strong) NSArray<ApolloDuoFeedRailButton *> *multiButtons;
@property(nonatomic, copy) NSArray<NSDictionary<NSString *, NSString *> *> *multiPicks;
// The multireddit a held press lifted, while it is dragged.
@property(nonatomic, weak) ApolloDuoFeedRailButton *draggedButton;
// Drag to reorder: the multireddits in the order the drag shows, the lifted
// one's slot and where it started, the finger in the scroll area's content
// coordinates and its offset from the lifted button's center.
@property(nonatomic, strong) UILongPressGestureRecognizer *dragPress;
@property(nonatomic, strong) CADisplayLink *dragScroll;
@property(nonatomic, copy) NSArray<ApolloDuoFeedRailButton *> *dragOrder;
@property(nonatomic) NSInteger dragSlot;
@property(nonatomic) NSInteger dragStartSlot;
@property(nonatomic) CGFloat dragFingerY;
@property(nonatomic) CGFloat dragGrabOffset;
@property(nonatomic, strong) UISelectionFeedbackGenerator *dragFeedback;
// The picks changed mid-drag; the rail rebuilds once the drag ends.
@property(nonatomic) BOOL reloadAfterDrag;
@end

@implementation ApolloDuoFeedRail

+ (CGFloat)reservedWidth { return kRailSideInset * 2 + kRailColumnWidth; }
+ (CGFloat)panelMaxXFilled:(BOOL)filled {
    return filled ? ApolloDuoFeedRail.reservedWidth : kRailSideInset + kRailColumnWidth;
}
+ (CGPoint)toggleCenterInBounds:(CGRect)bounds bottomSafeArea:(CGFloat)bottomSafeArea {
    return CGPointMake(CGRectGetMinX(bounds) + kRailSideInset + kRailColumnWidth / 2,
                       CGRectGetMinY(bounds) + ApolloDuoRailToggleCenterY(bounds.size.height, kRailInset,
                                                                          bottomSafeArea, kRailToggleSlot));
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (!(self = [super initWithFrame:frame])) return nil;
    _selectedFeed = -1;
    self.panel = [[UIVisualEffectView alloc] initWithEffect:nil];
    self.panel.clipsToBounds = YES;
    [self applyPanelStyle];
    [self addSubview:self.panel];
    self.favorites = [UIScrollView new];
    self.favorites.delegate = self;
    self.favorites.showsVerticalScrollIndicator = NO;
    self.favorites.alwaysBounceVertical = NO;
    self.favorites.contentInset = UIEdgeInsetsMake(0, 0, kRailFavoritesBottomInset, 0);
    [self.panel.contentView addSubview:self.favorites];
    // A held press on a picked multireddit lifts it to drag into a new order.
    // A quick tap still opens it and a swipe still scrolls: the press only
    // begins after the hold, and cancels the button's own tap when it does.
    self.dragPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(dragMultireddit:)];
    self.dragPress.minimumPressDuration = 0.35;
    self.dragPress.cancelsTouchesInView = YES;
    self.dragPress.delegate = self;
    [self.favorites addGestureRecognizer:self.dragPress];
    self.separator = [UIView new];
    self.separator.userInteractionEnabled = NO;
    [self.panel.contentView addSubview:self.separator];
    self.divider = [UIView new];
    self.divider.userInteractionEnabled = NO;
    [self addSubview:self.divider];
    UIImageSymbolConfiguration *symbol = [UIImageSymbolConfiguration configurationWithPointSize:20 weight:UIImageSymbolWeightSemibold];
    self.subredditsButton = [[ApolloDuoFeedRailButton alloc]
        initWithGlyph:[UIImage systemImageNamed:@"list.bullet" withConfiguration:symbol] title:@"Subreddits"];
    self.subredditsButton.tag = kRailSubredditsTag;
    [self.subredditsButton addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.panel.contentView addSubview:self.subredditsButton];
    self.collapseButton = [[ApolloDuoFeedRailToggleButton alloc] initPointingRight:NO];
    [self.collapseButton addTarget:self action:@selector(collapseTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.panel.contentView addSubview:self.collapseButton];
    self.accessibilityLabel = @"Feeds";
    for (NSString *name in @[ApolloFavoriteSubredditsUpdatedNotification, ApolloFeedShortcutsChangedNotification,
                             ApolloDuoFeedRailMultisChangedNotification]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(reloadShortcuts) name:name object:nil];
    }
    // Another account's picks show after a switch, even with the Posts feed
    // left on screen.
    for (NSString *name in @[@"com.christianselig.RedditCurrentAccountChanged",
                             @"com.christianselig.RedditAccountChanged"]) {
        [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(accountChanged) name:name object:nil];
    }
    // Apollo saves a star from the subreddit list (or a confirmed unfavorite)
    // without posting anything, so the column watches the saved list itself.
    [NSUserDefaults.standardUserDefaults addObserver:self forKeyPath:UDKeyApolloFavoriteSubreddits options:0
                                             context:&kApolloDuoFeedRailFavoritesContext];
    [self reloadShortcuts];
    return self;
}

- (void)dealloc {
    [NSUserDefaults.standardUserDefaults removeObserver:self forKeyPath:UDKeyApolloFavoriteSubreddits
                                                context:&kApolloDuoFeedRailFavoritesContext];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if (context != &kApolloDuoFeedRailFavoritesContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    // After the write that changed it; a burst of writes (the alphabetizing
    // pass writes again) rebuilds once, the rest find nothing new.
    __weak ApolloDuoFeedRail *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{ [weakSelf reloadShortcuts]; });
}

// The signed-in username can settle a moment after the switch is announced,
// so the picks are read again shortly after too.
- (void)accountChanged {
    __weak ApolloDuoFeedRail *weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakSelf reloadShortcuts];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [weakSelf reloadShortcuts];
        });
    });
}

- (void)reloadShortcuts {
    if (!NSThread.isMainThread) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self reloadShortcuts]; });
        return;
    }
    // Never rebuild the buttons out from under a finger.
    if (self.draggedButton) {
        self.reloadAfterDrag = YES;
        return;
    }
    // The feed shortcuts Settings > Feed Shortcuts shows, in its icon style.
    NSMutableArray<NSNumber *> *shortcuts = [NSMutableArray array];
    for (NSNumber *index in ApolloFeedShortcutVisibleIndexes()) {
        if (index.integerValue <= 2 || self.showsModerator) [shortcuts addObject:index];
    }
    NSInteger style = sSubredditFeedIconStyle;
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    for (id name in [NSUserDefaults.standardUserDefaults arrayForKey:UDKeyApolloFavoriteSubreddits] ?: @[]) {
        if ([name isKindOfClass:NSString.class] && [name length]) [names addObject:name];
    }
    BOOL shortcutsChanged = !self.feedButtons || ![shortcuts isEqualToArray:self.shortcuts ?: @[]]
        || style != self.shortcutStyle;
    BOOL favoritesChanged = !self.favoriteButtons || ![names isEqualToArray:self.favoriteNames ?: @[]];
    NSArray<NSDictionary<NSString *, NSString *> *> *picks = [ApolloDuoFeedRailMultiStore picksForActiveAccount];
    BOOL multisChanged = !self.multiButtons || ![picks isEqualToArray:self.multiPicks ?: @[]];
    if (!shortcutsChanged && !favoritesChanged && !multisChanged) return;
    if (shortcutsChanged) {
        self.shortcuts = shortcuts;
        self.shortcutStyle = style;
        for (UIView *view in self.feedButtons) [view removeFromSuperview];
        NSMutableArray<ApolloDuoFeedRailButton *> *buttons = [NSMutableArray array];
        for (NSNumber *index in shortcuts) {
            NSString *title = ApolloFeedShortcutShortTitle(index.integerValue);
            // Monochrome's shape is Tinted's, drawn here in the rail's colors.
            ApolloSubredditFeedIconStyle drawn = style == ApolloSubredditFeedIconStyleMonochrome
                ? ApolloSubredditFeedIconStyleTinted : (ApolloSubredditFeedIconStyle)style;
            UIImage *icon = ApolloFeedShortcutIconImage(index.integerValue, drawn, ApolloSubredditFeedLayoutRows, shortcuts.count);
            ApolloDuoFeedRailButton *button = icon
                ? [[ApolloDuoFeedRailButton alloc] initWithShortcutIcon:icon style:(ApolloSubredditFeedIconStyle)style title:title]
                : [[ApolloDuoFeedRailButton alloc] initWithGlyph:ApolloFeedShortcutTemplateGlyph(index.integerValue) title:title];
            button.tag = index.integerValue;
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.panel.contentView addSubview:button];
            [buttons addObject:button];
        }
        self.feedButtons = buttons;
    }
    if (favoritesChanged) {
        if (self.favoriteNames) ApolloLog(@"[DuoFeedRail] favorites changed: %lu", (unsigned long)names.count);
        self.favoriteNames = names;
        for (UIView *view in self.favoriteButtons) [view removeFromSuperview];
        // The subreddit list's own icon cache first, then Apollo's icon
        // tracker. Either way the image itself usually comes out of a cache.
        NSDictionary<NSString *, NSURL *> *icons = names.count
            ? ApolloNativeSubredditIconURLs([NSUserDefaults.standardUserDefaults dataForKey:@"SubredditIconData"]) : @{};
        ApolloSubredditInfoCache *cache = ApolloSubredditInfoCache.sharedCache;
        NSMutableArray<ApolloDuoFeedRailButton *> *buttons = [NSMutableArray array];
        for (NSString *name in names) {
            // A followed user's avatar comes from the profile cache Apollo's
            // comment and feed avatars use.
            NSString *username = ApolloDuoFeedRailUsername(name);
            NSURL *iconURL = username ? [ApolloUserProfileCache.sharedCache cachedInfoForUsername:username].iconURL
                : ([cache cachedInfoForSubreddit:name].iconURL ?: icons[name.lowercaseString]);
            ApolloDuoFeedRailButton *button = [[ApolloDuoFeedRailButton alloc] initWithSubreddit:name iconURL:iconURL];
            button.tag = kRailFavoriteTag;
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.favorites addSubview:button];
            [buttons addObject:button];
        }
        self.favoriteButtons = buttons;
    }
    if (multisChanged) {
        if (self.multiPicks) ApolloLog(@"[DuoFeedRail] multireddit picks changed: %lu", (unsigned long)picks.count);
        self.multiPicks = picks;
        for (UIView *view in self.multiButtons) [view removeFromSuperview];
        NSDictionary<NSString *, NSURL *> *icons = picks.count
            ? ApolloNativeSubredditIconURLs([NSUserDefaults.standardUserDefaults dataForKey:@"SubredditIconData"]) : @{};
        NSMutableArray<ApolloDuoFeedRailButton *> *buttons = [NSMutableArray array];
        for (NSDictionary<NSString *, NSString *> *pick in picks) {
            NSString *path = pick[@"path"];
            NSString *title = pick[@"title"] ?: path.lastPathComponent;
            NSString *iconSubreddit = pick[@"icon"];
            ApolloDuoFeedRailButton *button = [[ApolloDuoFeedRailButton alloc] initWithMultiredditPath:path title:title
                                                                                          iconSubreddit:iconSubreddit];
            if (!button.hasIcon && iconSubreddit.length) {
                [button loadIconFromURL:[ApolloSubredditInfoCache.sharedCache cachedInfoForSubreddit:iconSubreddit].iconURL
                    ?: icons[iconSubreddit.lowercaseString]];
            }
            button.tag = kRailMultiTag;
            [button addTarget:self action:@selector(tapped:) forControlEvents:UIControlEventTouchUpInside];
            [self.favorites addSubview:button];
            [buttons addObject:button];
        }
        self.multiButtons = buttons;
        [self refreshMultiAccessibilityActions];
    }
    [self refreshColors];
    [self setNeedsLayout];
}

- (void)setFilled:(BOOL)filled {
    if (_filled == filled) return;
    _filled = filled;
    [self applyPanelStyle];
    [self refreshColors];
    [self setNeedsLayout];
}

// Rounded is glass, its corners following the display's concentrically as
// the drawer's do. Filled is solid, on the subreddit list's own background
// like the drawer's Standard style, and square at the divider; its left
// corners follow the display, which rounds them there anyway, so the top
// highlight can follow it too.
- (void)applyPanelStyle {
    UIVisualEffect *effect = nil;
    if (!self.filled) {
        if (@available(iOS 26.0, *)) effect = [UIGlassEffect effectWithStyle:UIGlassEffectStyleRegular];
        else effect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemMaterial];
    }
    self.panel.effect = effect;
    if (@available(iOS 26.0, *)) {
        self.panel.cornerConfiguration = self.filled
            ? [UICornerConfiguration configurationWithUniformLeftRadius:[UICornerRadius containerConcentricRadius]
                                                      uniformRightRadius:[UICornerRadius fixedRadius:0]]
            : [UICornerConfiguration configurationWithUniformRadius:[UICornerRadius containerConcentricRadiusWithMinimum:24]];
    } else {
        self.panel.layer.cornerRadius = self.filled ? 0 : 24;
        self.panel.layer.cornerCurve = kCACornerCurveContinuous;
    }
}

- (void)layoutSubviews {
    [super layoutSubviews];
    CGFloat height = MAX(0, self.bounds.size.height - kRailInset * 2);
    CGFloat scale = self.window.screen.scale ?: UIScreen.mainScreen.scale;
    CGFloat hairline = 1 / scale;
    // Filled, the panel runs to the display edges and the divider; the
    // buttons keep the rounded panel's place.
    CGFloat contentX = 0, contentY = 0, columnWidth = kRailColumnWidth;
    if (self.filled) {
        self.panel.frame = CGRectMake(0, 0, MAX(0, self.bounds.size.width - hairline), self.bounds.size.height);
        contentX = kRailSideInset;
        contentY = kRailInset;
    } else {
        self.panel.frame = CGRectMake(kRailSideInset, kRailInset, kRailColumnWidth, height);
    }
    self.divider.frame = CGRectMake(self.bounds.size.width - hairline, 0, hairline, self.bounds.size.height);
    // The top button's highlight follows the panel's rounded top-left from
    // inside it, no closer to it than the highlight sits from its edges.
    CGFloat cornerRadius = self.filled ? 0 : columnWidth / 2;
    if (@available(iOS 26.0, *)) cornerRadius = [self.panel effectiveRadiusForCorner:UIRectCornerTopLeft];
    CGFloat cornerInset = MAX(contentX, contentY) + kRailSelectionInset;
    CGFloat topRadius = MAX(kRailSelectionRadius,
                            MIN(columnWidth / 2 - kRailSelectionInset, cornerRadius - cornerInset));
    // Home, Popular and All, then Subreddits, which opens the drawer.
    NSMutableArray<ApolloDuoFeedRailButton *> *buttons = [self.feedButtons mutableCopy] ?: [NSMutableArray array];
    [buttons addObject:self.subredditsButton];
    CGFloat y = kRailSelectionInset - 2;
    for (ApolloDuoFeedRailButton *button in buttons) {
        CGFloat radius = button == buttons.firstObject ? topRadius : kRailSelectionRadius;
        if (fabs(button.selectionTopRadius - radius) > 0.5) {
            button.selectionTopRadius = radius;
            [button setNeedsLayout];
        }
        button.frame = CGRectMake(contentX, contentY + y, columnWidth, kRailButtonHeight);
        y += kRailButtonHeight;
    }
    self.separator.frame = CGRectMake(contentX + 16, contentY + y + 6, columnWidth - 32, hairline * 2);
    y += 12;
    // The collapse arrow keeps a slot at the bottom, where the reopen arrow
    // sits while the sidebar is collapsed; the favorites fill the rest of the
    // panel above it and scroll when they don't fit.
    CGPoint toggle = [ApolloDuoFeedRail toggleCenterInBounds:self.bounds bottomSafeArea:self.safeAreaInsets.bottom];
    CGPoint panelOrigin = self.panel.frame.origin;
    self.collapseButton.bounds = CGRectMake(0, 0, columnWidth, kRailToggleSlot);
    self.collapseButton.center = CGPointMake(toggle.x - panelOrigin.x, toggle.y - panelOrigin.y);
    CGFloat favoritesHeight = ApolloDuoRailFavoritesHeight(panelOrigin.y + contentY + y, toggle.y, kRailToggleSlot);
    self.favorites.frame = CGRectMake(contentX, contentY + y, columnWidth, favoritesHeight);
    CGFloat favoriteY = 0;
    for (ApolloDuoFeedRailButton *button in self.favoriteButtons) {
        button.frame = CGRectMake(0, favoriteY, columnWidth, kRailFavoriteHeight);
        favoriteY += kRailFavoriteHeight;
    }
    // The picked multireddits follow, in their saved order, or the order a
    // drag shows. The dragged one follows the finger instead.
    for (ApolloDuoFeedRailButton *button in self.dragOrder ?: self.multiButtons) {
        if (button != self.draggedButton) {
            button.frame = CGRectMake(0, favoriteY, columnWidth, kRailFavoriteHeight);
        } else {
            button.bounds = CGRectMake(0, 0, columnWidth, kRailFavoriteHeight);
        }
        favoriteY += kRailFavoriteHeight;
    }
    self.favorites.contentSize = CGSizeMake(columnWidth, favoriteY);
    self.favorites.alwaysBounceVertical = favoriteY + kRailFavoritesBottomInset > self.favorites.bounds.size.height;
    self.separator.hidden = self.favoriteButtons.count + self.multiButtons.count == 0;
    [self requestVisibleIcons];
}

// A favorite with no icon on hand asks once it is in view, as the subreddit
// list does for its rows: the subreddit info cache, or for a followed user
// the profile cache. Both coalesce and keep what they learn, so this costs at
// most one lookup per favorite.
- (void)requestVisibleIcons {
    if (!self.window || self.hidden || self.alpha < 0.01) return;
    CGRect visible = self.favorites.bounds;
    NSArray<ApolloDuoFeedRailButton *> *buttons = [self.favoriteButtons ?: @[] arrayByAddingObjectsFromArray:self.multiButtons ?: @[]];
    for (ApolloDuoFeedRailButton *button in buttons) {
        if (button.hasIcon || button.infoRequested || !button.subreddit.length
            || !CGRectIntersectsRect(button.frame, visible)) continue;
        button.infoRequested = YES;
        __weak ApolloDuoFeedRailButton *weakButton = button;
        NSString *username = ApolloDuoFeedRailUsername(button.subreddit);
        if (username) {
            // Completes on the main queue, from the cache first when it can.
            [ApolloUserProfileCache.sharedCache requestInfoForUsername:username completion:^(ApolloUserProfileInfo *info) {
                if (info.iconURL) [weakButton loadIconFromURL:info.iconURL];
            }];
            continue;
        }
        [ApolloSubredditInfoCache.sharedCache requestInfoForSubreddit:button.subreddit completion:^(ApolloSubredditInfo *info) {
            if (!info.iconURL) return;
            dispatch_async(dispatch_get_main_queue(), ^{ [weakButton loadIconFromURL:info.iconURL]; });
        }];
    }
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self requestVisibleIcons];
}

- (void)didMoveToWindow {
    [super didMoveToWindow];
    // Off screen mid-drag (rotation, fold): drop the drag, which also stops
    // its display link.
    if (!self.window && self.draggedButton) [self finishDrag:NO];
    [self setNeedsLayout];
}

// The panel alone takes touches; the gap beside it passes them on.
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    UIView *hit = [super hitTest:point withEvent:event];
    return hit == self ? nil : hit;
}

- (void)setSelectedFeed:(NSInteger)selectedFeed {
    if (_selectedFeed == selectedFeed) return;
    _selectedFeed = selectedFeed;
    [self refreshColors];
}

- (void)setSelectedSubreddit:(NSString *)selectedSubreddit {
    if (_selectedSubreddit == selectedSubreddit || [_selectedSubreddit isEqualToString:selectedSubreddit]) return;
    _selectedSubreddit = [selectedSubreddit copy];
    [self refreshColors];
}

- (void)setSelectedMultiredditPath:(NSString *)selectedMultiredditPath {
    if (_selectedMultiredditPath == selectedMultiredditPath
        || [_selectedMultiredditPath isEqualToString:selectedMultiredditPath]) return;
    _selectedMultiredditPath = [selectedMultiredditPath copy];
    [self refreshColors];
}

- (void)setSubredditsSelected:(BOOL)subredditsSelected {
    if (_subredditsSelected == subredditsSelected) return;
    _subredditsSelected = subredditsSelected;
    [self refreshColors];
}

- (void)refreshColors {
    UIColor *accent = ApolloThemeAccentColor() ?: self.tintColor ?: UIColor.systemBlueColor;
    UIColor *neutral = ApolloNavigationChromeColor() ?: UIColor.labelColor;
    // A system color that shows on the glass panel, which washes out the
    // separator colors (the theme's and UIKit's both nearly vanish there).
    self.separator.backgroundColor = UIColor.tertiaryLabelColor;
    self.divider.backgroundColor = ApolloThemeSeparatorColor() ?: UIColor.separatorColor;
    // The column has its own plain backdrop, so the feed's rows end at the
    // divider instead of running behind the panel.
    self.backgroundColor = ApolloThemePageBackgroundColor() ?: UIColor.systemBackgroundColor;
    self.panel.backgroundColor = self.filled
        ? (ApolloThemeSubredditListBackgroundColor() ?: UIColor.secondarySystemBackgroundColor) : nil;
    for (ApolloDuoFeedRailButton *button in self.feedButtons) {
        button.chosen = button.tag == self.selectedFeed;
        [button applyAccent:accent neutral:neutral];
    }
    for (ApolloDuoFeedRailButton *button in self.favoriteButtons) {
        button.chosen = self.selectedSubreddit && [button.subreddit caseInsensitiveCompare:self.selectedSubreddit] == NSOrderedSame;
        [button applyAccent:accent neutral:neutral];
    }
    [self.collapseButton refreshColors];
    for (ApolloDuoFeedRailButton *button in self.multiButtons) {
        button.chosen = ApolloDuoFeedRailSameMultiredditPath(button.multiredditPath, self.selectedMultiredditPath);
        [button applyAccent:accent neutral:neutral];
    }
    self.subredditsButton.chosen = self.subredditsSelected;
    [self.subredditsButton applyAccent:accent neutral:neutral];
}

- (void)tintColorDidChange {
    [super tintColorDidChange];
    [self refreshColors];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previous {
    [super traitCollectionDidChange:previous];
    [self refreshColors];
}

- (void)setAlpha:(CGFloat)alpha {
    [super setAlpha:alpha];
    if (alpha > 0.01) [self requestVisibleIcons];
}

- (void)collapseTapped {
    if (self.collapse) self.collapse();
}

#pragma mark - Drag to reorder

// VoiceOver can't drag; it moves a multireddit one place at a time. Rebuilt
// whenever the order changes (a rebuild or a drop), and each action reads the
// button's current place when it runs.
- (void)refreshMultiAccessibilityActions {
    NSUInteger count = self.multiButtons.count;
    __weak ApolloDuoFeedRail *weakSelf = self;
    [self.multiButtons enumerateObjectsUsingBlock:^(ApolloDuoFeedRailButton *button, NSUInteger index, __unused BOOL *stop) {
        __weak ApolloDuoFeedRailButton *weakButton = button;
        BOOL (^move)(NSInteger) = ^BOOL(NSInteger step) {
            ApolloDuoFeedRail *rail = weakSelf;
            ApolloDuoFeedRailButton *moving = weakButton;
            NSUInteger current = moving ? [rail.multiButtons indexOfObject:moving] : NSNotFound;
            if (!rail || current == NSNotFound || !moving.multiredditPath.length) return NO;
            NSInteger target = (NSInteger)current + step;
            if (target < 0 || target >= (NSInteger)rail.multiButtons.count) return NO;
            [ApolloDuoFeedRailMultiStore movePath:moving.multiredditPath toActiveIndex:(NSUInteger)target];
            return YES;
        };
        NSMutableArray<UIAccessibilityCustomAction *> *moves = [NSMutableArray array];
        if (index > 0) {
            [moves addObject:[[UIAccessibilityCustomAction alloc] initWithName:@"Move Up"
                actionHandler:^BOOL(__unused UIAccessibilityCustomAction *action) { return move(-1); }]];
        }
        if (index + 1 < count) {
            [moves addObject:[[UIAccessibilityCustomAction alloc] initWithName:@"Move Down"
                actionHandler:^BOOL(__unused UIAccessibilityCustomAction *action) { return move(1); }]];
        }
        button.accessibilityCustomActions = moves;
    }];
}

// The picked multireddit under a point in the scroll area's content, or nil.
- (ApolloDuoFeedRailButton *)multiButtonAtPoint:(CGPoint)point {
    for (ApolloDuoFeedRailButton *button in self.multiButtons) {
        if (CGRectContainsPoint(button.frame, point)) return button;
    }
    return nil;
}

- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)recognizer {
    if (recognizer != self.dragPress) return YES;
    return self.multiButtons.count >= 2 && [self multiButtonAtPoint:[recognizer locationInView:self.favorites]];
}

// The first multireddit's top in the scroll area's content: they follow the
// favorites.
- (CGFloat)multiTop {
    return self.favoriteButtons.count * kRailFavoriteHeight;
}

- (void)dragMultireddit:(UILongPressGestureRecognizer *)press {
    switch (press.state) {
        case UIGestureRecognizerStateBegan: [self beginDragAt:[press locationInView:self.favorites]]; break;
        case UIGestureRecognizerStateChanged:
            self.dragFingerY = [press locationInView:self.favorites].y;
            [self updateDrag];
            break;
        case UIGestureRecognizerStateEnded: [self finishDrag:YES]; break;
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed: [self finishDrag:NO]; break;
        default: break;
    }
}

- (void)beginDragAt:(CGPoint)point {
    ApolloDuoFeedRailButton *button = [self multiButtonAtPoint:point];
    NSUInteger index = button ? [self.multiButtons indexOfObject:button] : NSNotFound;
    if (index == NSNotFound) return;
    self.draggedButton = button;
    self.dragOrder = self.multiButtons;
    self.dragSlot = self.dragStartSlot = (NSInteger)index;
    self.dragFingerY = point.y;
    self.dragGrabOffset = point.y - button.center.y;
    // The finger owns the list now; it scrolls only by the drag's auto-scroll.
    self.favorites.scrollEnabled = NO;
    [self.favorites bringSubviewToFront:button];
    [[[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight] impactOccurred];
    self.dragFeedback = [UISelectionFeedbackGenerator new];
    [self.dragFeedback prepare];
    button.layer.shadowColor = UIColor.blackColor.CGColor;
    button.layer.shadowOffset = CGSizeMake(0, 4);
    button.layer.shadowRadius = 10;
    BOOL reduceMotion = UIAccessibilityIsReduceMotionEnabled();
    [UIView animateWithDuration:reduceMotion ? 0 : 0.15 animations:^{
        if (!reduceMotion) button.transform = CGAffineTransformMakeScale(1.06, 1.06);
        button.layer.shadowOpacity = 0.25;
    }];
    self.dragScroll = [CADisplayLink displayLinkWithTarget:self selector:@selector(dragScrollTick:)];
    [self.dragScroll addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
    ApolloLog(@"[DuoFeedRail] multireddit drag began at %ld", (long)index);
}

// The lifted button follows the finger within the multireddits' span; the
// others slide to make room where it would land.
- (void)updateDrag {
    ApolloDuoFeedRailButton *button = self.draggedButton;
    if (!button) return;
    long count = (long)self.multiButtons.count;
    CGFloat top = self.multiTop;
    CGFloat centerY = ApolloDuoRailDragCenterY(self.dragFingerY, self.dragGrabOffset, top, kRailFavoriteHeight, count);
    button.center = CGPointMake(button.center.x, centerY);
    long slot = ApolloDuoRailMultiDropSlot(centerY, top, kRailFavoriteHeight, count);
    if (slot < 0 || slot == self.dragSlot) return;
    self.dragSlot = slot;
    NSMutableArray<ApolloDuoFeedRailButton *> *order = [self.multiButtons mutableCopy];
    [order removeObject:button];
    [order insertObject:button atIndex:(NSUInteger)slot];
    self.dragOrder = order;
    [self.dragFeedback selectionChanged];
    [self.dragFeedback prepare];
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
}

// Near the scroll area's top or bottom the list scrolls under the lifted
// multireddit, so it can travel the whole list. The lifted one's clamped
// center decides, not the raw finger: past the first or last slot the list
// stops once that slot is in view instead of scrolling on through the
// favorites and leaving the lifted one behind.
- (void)dragScrollTick:(__unused CADisplayLink *)link {
    UIScrollView *scroll = self.favorites;
    if (!self.draggedButton) return;
    CGFloat centerY = ApolloDuoRailDragCenterY(self.dragFingerY, self.dragGrabOffset, self.multiTop,
                                               kRailFavoriteHeight, (long)self.multiButtons.count);
    CGFloat step = ApolloDuoRailAutoScrollStep(centerY, scroll.bounds.origin.y, scroll.bounds.size.height, 44, 8);
    if (step == 0) return;
    UIEdgeInsets inset = scroll.adjustedContentInset;
    CGFloat minimum = -inset.top;
    CGFloat maximum = MAX(minimum, scroll.contentSize.height + inset.bottom - scroll.bounds.size.height);
    CGFloat offset = MAX(minimum, MIN(maximum, scroll.contentOffset.y + step));
    CGFloat delta = offset - scroll.contentOffset.y;
    if (fabs(delta) < 0.01) return;
    scroll.contentOffset = CGPointMake(scroll.contentOffset.x, offset);
    // The finger stays put on screen while the content moves under it.
    self.dragFingerY += delta;
    [self updateDrag];
}

// Drops the lifted multireddit in its slot and saves the order, or (cancelled)
// puts everything back.
- (void)finishDrag:(BOOL)commit {
    [self.dragScroll invalidate];
    self.dragScroll = nil;
    self.favorites.scrollEnabled = YES;
    ApolloDuoFeedRailButton *button = self.draggedButton;
    if (!button) return;
    NSInteger from = self.dragStartSlot, to = self.dragSlot;
    BOOL moved = commit && to != from && to >= 0 && to < (NSInteger)self.multiButtons.count;
    if (moved) {
        // The rail takes the new order itself, so the store's change notice
        // finds nothing new to rebuild.
        NSMutableArray *picks = [self.multiPicks mutableCopy];
        NSDictionary *pick = picks[(NSUInteger)from];
        [picks removeObjectAtIndex:(NSUInteger)from];
        [picks insertObject:pick atIndex:(NSUInteger)to];
        self.multiPicks = picks;
        self.multiButtons = self.dragOrder;
        [self refreshMultiAccessibilityActions];
    }
    self.dragOrder = nil;
    self.draggedButton = nil;
    self.dragFeedback = nil;
    [UIView animateWithDuration:UIAccessibilityIsReduceMotionEnabled() ? 0 : 0.2 delay:0
                        options:UIViewAnimationOptionBeginFromCurrentState | UIViewAnimationOptionAllowUserInteraction
                     animations:^{
        button.transform = CGAffineTransformIdentity;
        button.layer.shadowOpacity = 0;
        [self setNeedsLayout];
        [self layoutIfNeeded];
    } completion:nil];
    ApolloLog(@"[DuoFeedRail] multireddit drag ended moved=%d (%ld -> %ld)", moved, (long)from, (long)to);
    if (moved) [ApolloDuoFeedRailMultiStore movePath:button.multiredditPath toActiveIndex:(NSUInteger)to];
    if (self.reloadAfterDrag) {
        self.reloadAfterDrag = NO;
        [self reloadShortcuts];
    }
}

- (void)tapped:(ApolloDuoFeedRailButton *)button {
    if (button.tag == kRailSubredditsTag) {
        if (self.toggleSubreddits) self.toggleSubreddits();
    } else if (button.tag == kRailFavoriteTag) {
        if (self.selectSubreddit && button.subreddit.length) self.selectSubreddit(button.subreddit);
    } else if (button.tag == kRailMultiTag) {
        if (self.selectMultireddit && button.multiredditPath.length) self.selectMultireddit(button.multiredditPath);
    } else if (self.selectFeed) {
        self.selectFeed(button.tag);
    }
}

@end
