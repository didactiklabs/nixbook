{
  pkgs,
  dankcalendarSrc,
  flakeCompatSrc,
}:
# DankCalendar (`dcal`): calendar and task sync (Google with its own built-in
# OAuth client, Microsoft, CalDAV, iCloud, iCal feeds) behind the shell's
# calendars and to-do list (src/services/CalendarEvents.qml, Todo.qml). Built
# from its flake against our nixpkgs.
#
# patches/dankcalendar-tasklists.patch: `tasks.listCreate`, `listRename` and
# `listDelete`, which create, rename and delete Google task lists themselves
# (upstream only renames its local copy and creates lists in local accounts);
# the Tasks app and the desktop agents' `tasks` tool use them. Also: a call
# held back after Google rate-limited it ("Google API retry deferred for
# 2s") names Google's answer (429, rateLimitExceeded, a 5xx…). Made against
# the pinned revision (npins/, the same as nixbook's).
((import flakeCompatSrc { src = dankcalendarSrc; }).defaultNix.lib.buildDcalPkgs pkgs)
.dankcalendar.overrideAttrs
  (old: {
    patches = (old.patches or [ ]) ++ [ ./patches/dankcalendar-tasklists.patch ];
  })
