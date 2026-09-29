# chocomooncake's personal nixbook-shell settings. They override the shared
# ones (homeManagerModules/nixbookShellConfig/settings.nix, set as defaults).
{
  customHomeManagerModules.nixbookShellConfig.settings = {
    # Persona cut-in rules. "last:" is the last message of a chat thread with
    # its sender: the phone (KDE Connect) re-posts the whole conversation on
    # every message, mine included.
    notifications.cutIn = {
      keywords = [
        # Calendar reminders (the shared rule, replaced by this list).
        "app:^\"Dank Calendar\""
        # Khoa (profiles/totoro/khoa). "Khoa" as a whole word only: not
        # "khoai" nor "khóa".
        "\"Khoa\""
        "Victor Hang"
        "Victor Tiến Khoa"
        "vtk_hg"
        "victortk"
      ];
      # Reactions and likes: a normal notification is enough. "line:" is the
      # newest message only. My own messages: the last message is sent by
      # me (a thread with Khoa is titled with his name).
      blacklist = [
        "line:Liked your message"
        "line:Liked a message"
        "line:\"Reacted\" + line:\"to\""
        "last:^\"You:\""
        "last:^\"Vous:\""
        "last:^\"Bạn:\""
        "last:^\"Choco Mooncake:\""
        "last:^\"chocomooncake:\""
        "last:^\"wolfey182:\""
        "last:^\"Huyền:\""
        "last:^\"Huyen:\""
        "last:^\"Diệu Huyền:\""
        "last:^\"Dieu Huyen:\""
        "last:^\"Diệu Huyền Nguyễn:\""
        "last:^\"Dieu Huyen Nguyen:\""
        "last:^\"Nguyễn Diệu Huyền:\""
        "last:^\"Nguyen Dieu Huyen:\""
      ];
    };
  };
}
