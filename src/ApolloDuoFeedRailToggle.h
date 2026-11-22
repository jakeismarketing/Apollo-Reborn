#ifndef APOLLO_DUO_FEED_RAIL_TOGGLE_H
#define APOLLO_DUO_FEED_RAIL_TOGGLE_H

// Where the Duo feed sidebar's collapse toggle sits. The open sidebar draws it
// at the bottom of its panel and the collapsed one leaves it in the same spot
// over the feed, so both use these. Plain C, so the host tests in
// tests/duo_feed_rail_toggle_tests.c can run them.

// The toggle's center y for a column `height` tall: half a `slot` above the
// bottom, which is `inset` up from the edge or the bottom safe area when that
// is larger. Never above the top.
static inline double ApolloDuoRailToggleCenterY(double height, double inset, double bottomSafeArea, double slot) {
    double bottom = height - (bottomSafeArea > inset ? bottomSafeArea : inset);
    double center = bottom - slot / 2;
    return center < 0 ? 0 : center;
}

// The height the scrolling favorites keep when they start at `favoritesTop`
// and the toggle's slot is centered at `toggleCenterY`.
static inline double ApolloDuoRailFavoritesHeight(double favoritesTop, double toggleCenterY, double slot) {
    double height = toggleCenterY - slot / 2 - favoritesTop;
    return height < 0 ? 0 : height;
}

#endif
