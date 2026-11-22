#include "ApolloDuoFeedRailMultis.h"

#include <stdio.h>
#include <stdlib.h>

static unsigned checks;

static void Check(int condition, const char *message) {
    checks++;
    if (!condition) {
        fprintf(stderr, "FAIL: %s\n", message);
        exit(1);
    }
}

int main(void) {
    /* A pick belongs to the signed-in account when its path's owner is that
       username, ignoring case. */
    Check(ApolloDuoRailMultiPathOwnerMatches("/user/Alice/m/tech", "alice"), "owner match ignores case");
    Check(ApolloDuoRailMultiPathOwnerMatches("user/alice/m/tech", "alice"), "leading slash optional");
    Check(ApolloDuoRailMultiPathOwnerMatches("/u/alice/m/tech", "alice"), "u/ accepted");
    Check(ApolloDuoRailMultiPathOwnerMatches("/user/alice/m/tech/", "ALICE"), "trailing slash accepted");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/other/m/tech", "alice"), "other owner rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/aliceb/m/tech", "alice"), "prefix is not a match");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/alic/m/tech", "alice"), "shorter owner is not a match");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/r/tech", "alice"), "subreddit path rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/alice/m/", "alice"), "missing name rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/alice/saved", "alice"), "non-multireddit user path rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches(NULL, "alice"), "null path rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/alice/m/x", ""), "empty username rejected");
    Check(!ApolloDuoRailMultiPathOwnerMatches("/user/alice/m/x", NULL), "null username rejected");

    /* Where a dragged multireddit lands: the row under its center, clamped to
       the multireddits' own span. */
    Check(ApolloDuoRailMultiDropSlot(130, 100, 60, 3) == 0, "inside first row");
    Check(ApolloDuoRailMultiDropSlot(170, 100, 60, 3) == 1, "inside second row");
    Check(ApolloDuoRailMultiDropSlot(250, 100, 60, 3) == 2, "inside third row");
    Check(ApolloDuoRailMultiDropSlot(10, 100, 60, 3) == 0, "above clamps to first");
    Check(ApolloDuoRailMultiDropSlot(900, 100, 60, 3) == 2, "below clamps to last");
    Check(ApolloDuoRailMultiDropSlot(130, 100, 60, 0) == -1, "empty list");
    Check(ApolloDuoRailMultiDropSlot(130, 100, 0, 3) == -1, "zero row height");

    /* Auto-scroll while dragging near the scroll area's top or bottom. */
    Check(ApolloDuoRailAutoScrollStep(105, 100, 400, 40, 8) < 0, "near top scrolls up");
    Check(ApolloDuoRailAutoScrollStep(495, 100, 400, 40, 8) > 0, "near bottom scrolls down");
    Check(ApolloDuoRailAutoScrollStep(300, 100, 400, 40, 8) == 0, "middle holds still");
    Check(ApolloDuoRailAutoScrollStep(100, 100, 400, 40, 8) == -8, "top edge is max speed");
    Check(ApolloDuoRailAutoScrollStep(500, 100, 400, 40, 8) == 8, "bottom edge is max speed");
    Check(ApolloDuoRailAutoScrollStep(40, 100, 400, 40, 8) == -8, "above the area stays at max speed");
    Check(ApolloDuoRailAutoScrollStep(120, 100, 400, 40, 8) == -4, "halfway into the top edge is half speed");
    /* An area shorter than both edges together splits at its middle, so the
       top half only scrolls up and the bottom half only down. */
    Check(ApolloDuoRailAutoScrollStep(110, 100, 60, 40, 8) < 0, "short area top half scrolls up");
    Check(ApolloDuoRailAutoScrollStep(150, 100, 60, 40, 8) > 0, "short area bottom half scrolls down");
    Check(ApolloDuoRailAutoScrollStep(300, 100, 0, 40, 8) == 0, "empty area holds still");

    printf("duo_feed_rail_multis_tests: %u checks passed\n", checks);
    return 0;
}
