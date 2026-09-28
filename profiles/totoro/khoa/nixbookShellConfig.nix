# khoa's personal nixbook-shell settings, on every machine of mine (imported
# by the totoro, anya and tanjiro profiles). They override the shared ones
# (homeManagerModules/nixbookShellConfig/settings.nix, set as defaults).
{
  customHomeManagerModules.nixbookShellConfig.settings = {
    appearance.persona.enable = true;
    # Persona cut-in rules. "last:" is the last message of a chat thread with
    # its sender: the phone (KDE Connect) re-posts the whole conversation on
    # every message, mine included.
    notifications.cutIn = {
      keywords = [
        # Calendar events
        "Calendar"
        "Reminder"
        "Google Agenda"
        # Family and friends
        "Alesio"
        "chocomooncake"
        "choco mooncake"
        "wolfey182"
        "huyền"
        "Huyen"
        "\"Diệu\""
        "Trang HANG"
        "Tin Dinh"
        "aamoyel"
        "Alan Amoyel"
        # About me: mentions and answers to my messages, only in the last
        # message (a title or earlier line holding my name is my own
        # conversation or message), and not in mail (newsletters and account
        # mails say "Hi Victor" too): Thunderbird, or Gmail mirrored from the
        # phone (KDE Connect, title "Gmail").
        "last:\"@vtk_hg\""
        "last:\"@victortk\""
        "last:Victor Tiến Khoa + !app:Thunderbird + !title:Gmail"
        "last:Victor Hang + !app:Thunderbird + !title:Gmail"
        "last:ビクタ + !app:Thunderbird + !title:Gmail"
        "last:mentioned you"
        "last:tagged you"
        "last:replied to you"
        "last:your message"
      ];
      # Reactions and likes (Instagram "Liked your message", "Reacted 😂 to
      # your message"), from anyone, friends included: a normal notification
      # is enough. "line:" is the newest message only (the thread's last
      # line), so a like earlier in the thread doesn't veto a real message.
      # My own messages: the last message is sent by me.
      blacklist = [
        "line:Liked your message"
        "line:Liked a message"
        "line:\"Reacted\" + line:\"to\""
        "last:^\"You:\""
        "last:^\"Vous:\""
        "last:^\"Bạn:\""
        "last:^\"Victor Hang:\""
        "last:^\"Victor Tiến Khoa Hang:\""
        "last:^\"Victor Tiến Khoa:\""
        "last:^\"vtk_hg:\""
        "last:^\"victortk:\""
      ];
    };
  };
}
