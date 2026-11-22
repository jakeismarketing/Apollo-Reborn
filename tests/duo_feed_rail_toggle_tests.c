#include "ApolloDuoFeedRailToggle.h"

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
    /* The toggle's center sits half a slot above the bottom: the panel's
       12pt inset, or the bottom safe area when that is larger. Open and
       collapsed share it, so the arrow never moves between states. */
    Check(ApolloDuoRailToggleCenterY(800, 12, 0, 48) == 764, "inset bottom, no safe area");
    Check(ApolloDuoRailToggleCenterY(800, 12, 21, 48) == 755, "safe area wins when larger");
    Check(ApolloDuoRailToggleCenterY(800, 12, 8, 48) == 764, "inset wins when larger");
    Check(ApolloDuoRailToggleCenterY(30, 12, 0, 48) == 0, "never above the top");

    /* The favorites end where the toggle's slot begins. */
    Check(ApolloDuoRailFavoritesHeight(300, 764, 48) == 440, "favorites stop above the slot");
    Check(ApolloDuoRailFavoritesHeight(800, 764, 48) == 0, "no negative height");

    printf("duo_feed_rail_toggle_tests: %u checks passed\n", checks);
    return 0;
}
