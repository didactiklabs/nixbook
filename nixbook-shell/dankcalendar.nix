{
  pkgs,
  dankcalendarSrc,
  flakeCompatSrc,
}:
# DankCalendar (`dcal`): calendar and task sync (Google with its own built-in
# OAuth client, Microsoft, CalDAV, iCloud, iCal feeds) behind the shell's
# calendars and to-do list (src/services/CalendarEvents.qml, Todo.qml). Built
# from its flake against our nixpkgs.
((import flakeCompatSrc { src = dankcalendarSrc; }).defaultNix.lib.buildDcalPkgs pkgs).dankcalendar
