#ifndef APOLLO_DUO_FEED_RAIL_MULTIS_H
#define APOLLO_DUO_FEED_RAIL_MULTIS_H

// Pure helpers for the multireddits the Duo feed sidebar shows: which account
// a pick belongs to, where a dragged one lands, and how fast the sidebar
// scrolls while one is dragged near its ends. Plain C, so the host tests in
// tests/duo_feed_rail_multis_tests.c can run them.

#include <ctype.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// Whether `path` is a multireddit path, /user/<owner>/m/<name> (the leading
// slash optional, u/ accepted for user/), whose owner is `username`, ignoring
// ASCII case.
static inline bool ApolloDuoRailMultiPathOwnerMatches(const char *path, const char *username) {
    if (!path || !username || !*username) return false;
    if (*path == '/') path++;
    if (strncmp(path, "user/", 5) == 0) {
        path += 5;
    } else if (strncmp(path, "u/", 2) == 0) {
        path += 2;
    } else {
        return false;
    }
    size_t length = strlen(username);
    for (size_t i = 0; i < length; i++) {
        if (!path[i] || tolower((unsigned char)path[i]) != tolower((unsigned char)username[i])) return false;
    }
    path += length;
    if (strncmp(path, "/m/", 3) != 0) return false;
    path += 3;
    return *path && *path != '/';
}

// The slot, 0 to count - 1, whose row holds `centerY`, for `count` rows of
// `rowHeight` starting at `firstTop`. Clamped to the first and last row; -1
// when there are no rows.
static inline long ApolloDuoRailMultiDropSlot(double centerY, double firstTop, double rowHeight, long count) {
    if (count <= 0 || rowHeight <= 0) return -1;
    double offset = (centerY - firstTop) / rowHeight;
    if (offset < 0) return 0;
    long slot = (long)offset;
    return slot >= count ? count - 1 : slot;
}

// Where the lifted multireddit's center sits: the finger's y less the offset
// it was grabbed at, kept between the first and last of `count` rows of
// `rowHeight` from `firstTop`.
static inline double ApolloDuoRailDragCenterY(double fingerY, double grabOffset, double firstTop,
                                             double rowHeight, long count) {
    double half = rowHeight / 2;
    double first = firstTop + half;
    double last = firstTop + (count > 0 ? count - 1 : 0) * rowHeight + half;
    double center = fingerY - grabOffset;
    return center < first ? first : center > last ? last : center;
}

// Points to scroll per frame while a finger at `fingerY` drags in a visible
// area from `visibleTop` that is `visibleHeight` tall: negative within `edge`
// of the top, positive within `edge` of the bottom, growing linearly to
// `maxStep` at (and past) the edge; 0 elsewhere. An area shorter than both
// edges splits at its middle.
static inline double ApolloDuoRailAutoScrollStep(double fingerY, double visibleTop, double visibleHeight,
                                                double edge, double maxStep) {
    if (visibleHeight <= 0 || edge <= 0 || maxStep <= 0) return 0;
    double zone = edge * 2 > visibleHeight ? visibleHeight / 2 : edge;
    double fromTop = fingerY - visibleTop;
    double fromBottom = visibleTop + visibleHeight - fingerY;
    if (fromTop < zone && fromTop <= fromBottom) {
        double depth = fromTop <= 0 ? 1 : (zone - fromTop) / zone;
        return -maxStep * depth;
    }
    if (fromBottom < zone) {
        double depth = fromBottom <= 0 ? 1 : (zone - fromBottom) / zone;
        return maxStep * depth;
    }
    return 0;
}

#endif
