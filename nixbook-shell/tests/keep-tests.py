#!/usr/bin/env python3
"""Tests for the Google Keep sync's merge (nixbook-shell/scripts/keep-sync.py).

The merge is a pure function of the shell's notes and Keep's notes, so it is
tested here without an account and without gkeepapi (the script imports it
only when a sync actually runs).

Run: python3 tests/keep-tests.py [path/to/keep-sync.py]
"""

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
SCRIPT = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "scripts", "keep-sync.py")

spec = importlib.util.spec_from_file_location("keep_sync", SCRIPT)
keep_sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(keep_sync)

failures = 0


def check(name, expected, actual):
    global failures
    if expected == actual:
        print(f"ok   - {name}")
    else:
        print(f"FAIL - {name}", file=sys.stderr)
        print(f"       expected: {expected!r}", file=sys.stderr)
        print(f"       actual:   {actual!r}", file=sys.stderr)
        failures += 1


def remote(id, title="", text="", items=None, pinned=False, created=1000, edited=2000):
    """A Keep note, as the merge sees it."""
    return {
        "id": id,
        "title": title,
        "text": text,
        "items": items,
        "pinned": pinned,
        "created": created,
        "edited": edited,
        "trashed": False,
        "deleted": False,
    }


def local(id, content, updated=1000, pinned=False, keep_id=None, keep_edited=0):
    """A note of the shell."""
    note = {
        "id": id,
        "content": content,
        "attachments": [],
        "createdAt": 1000,
        "updatedAt": updated,
        "pinned": pinned,
    }
    if keep_id:
        note["keepId"] = keep_id
        note["keepEdited"] = keep_edited
    return note


def actions_of(actions, op):
    return [action for action in actions if action["op"] == op]


# -- The content of a note ----------------------------------------------------

check(
    "a note's first line is its title",
    ("Shopping", "milk\neggs", None),
    keep_sync.parse_note("Shopping\nmilk\neggs"),
)
check(
    "a note without a title",
    ("milk", "", None),
    keep_sync.parse_note("milk"),
)
check(
    "a checklist is a list",
    ("", None, [("milk", False), ("eggs", True)]),
    keep_sync.parse_note("- [ ] milk\n- [x] eggs"),
)
check(
    "a checklist with a title",
    ("Shopping", None, [("milk", False)]),
    keep_sync.parse_note("Shopping\n- [ ] milk"),
)
check(
    "a note with a list line and a text line is not a list",
    ("Shopping", "- [ ] milk\nand eggs", None),
    keep_sync.parse_note("Shopping\n- [ ] milk\nand eggs"),
)
check(
    "the content of a note comes back the same",
    "Shopping\nmilk\neggs",
    keep_sync.render_note(*keep_sync.parse_note("Shopping\nmilk\neggs")),
)
check(
    "the content of a checklist comes back the same",
    "Shopping\n- [ ] milk\n- [x] eggs",
    keep_sync.render_note(*keep_sync.parse_note("Shopping\n- [ ] milk\n- [x] eggs")),
)
check(
    "an empty note stays empty",
    "",
    keep_sync.render_note(*keep_sync.parse_note("")),
)

# -- The merge ----------------------------------------------------------------

# A note that isn't in Keep yet is created there.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk")], [], push=True, pull=True
)
check("a new note is created in Keep", 1, len(actions_of(actions, "create")))
check("the creation keeps the title", "Shopping", actions_of(actions, "create")[0]["title"])
check("the creation keeps the text", "milk", actions_of(actions, "create")[0]["text"])
check("the note is kept", "Shopping\nmilk", merged[0]["content"])

# The same note, already in Keep: it is linked, not duplicated.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk")],
    [remote("k1", title="Shopping", text="milk")],
)
check("an identical note is linked", 1, len(actions_of(actions, "link")))
check("nothing is created", 0, len(actions_of(actions, "create")))
check("the link is kept", "k1", merged[0]["keepId"])

# Nothing changed: nothing happens.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk", updated=2000, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", text="milk", edited=2000)],
)
check("an unchanged note is left alone", 0, len(actions))
check("the note is not pushed", 0, stats["pushed"])

# The note changed here: it is pushed.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nbread", updated=3000, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", text="milk", edited=2000)],
)
check("a changed note is pushed", 1, stats["pushed"])
check("the push carries the new text", "bread", actions_of(actions, "push")[0]["text"])

# The note changed in Keep: it comes back.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk", updated=2000, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", text="bread", edited=3000)],
)
check("a note changed in Keep comes back", 1, stats["pulled"])
check("the new text is here", "Shopping\nbread", merged[0]["content"])

# Both changed: the newer one wins.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk", updated=4000, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", text="bread", edited=3000)],
)
check("a conflict is counted", 1, stats["conflicts"])
check("the newer side wins (here)", "Shopping\nmilk", merged[0]["content"])
check("the newer side wins (there)", "Shopping\nbread",
      keep_sync.merge_notes(
          [local("1", "Shopping\nmilk", updated=2500, keep_id="k1", keep_edited=2000)],
          [remote("k1", title="Shopping", text="bread", edited=3000)],
      )[0][0]["content"])

# A pin is synced both ways.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping", updated=2000, pinned=True, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", pinned=False, edited=2000)],
)
check("a pin is pushed", True, actions_of(actions, "push")[0]["pinned"])
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping", updated=2000, pinned=False, keep_id="k1", keep_edited=2000)],
    [remote("k1", title="Shopping", pinned=True, edited=3000)],
)
check("a pin comes back", True, merged[0]["pinned"])

# A note of Keep's, not here yet: it is imported.
merged, actions, stats = keep_sync.merge_notes(
    [], [remote("k1", title="Shopping", text="milk", edited=3000)]
)
check("a note of Keep's is imported", 1, stats["imported"])
check("the imported note keeps its title", "Shopping\nmilk", merged[0]["content"])
check("the imported note is linked", "k1", merged[0]["keepId"])
check("the imported note keeps Keep's time", 3000, merged[0]["updatedAt"])

# A note of Keep's whose shell note is gone: it is not imported again.
merged, actions, stats = keep_sync.merge_notes(
    [], [remote("k1", title="Shopping", text="milk", edited=3000)], ignored=["k1"]
)
check("a deleted note is not imported again", 0, stats["imported"])
check("the list stays empty", 0, len(merged))

# A note deleted in Keep stays here, and is not created again.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk", updated=2000, keep_id="k1", keep_edited=2000)], []
)
check("a note deleted in Keep stays", 1, len(merged))
check("a note deleted in Keep is not created again", 0, len(actions))

# The directions can be turned off.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk")], [], push=False
)
check("nothing is pushed when pushing is off", 0, len(actions))
merged, actions, stats = keep_sync.merge_notes(
    [], [remote("k1", title="Shopping", text="milk")], pull=False
)
check("nothing is imported when pulling is off", 0, len(merged))

# A checklist is a list in Keep.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\n- [ ] milk\n- [x] eggs")], []
)
check("a checklist is created as a list", [("milk", False), ("eggs", True)],
      actions_of(actions, "create")[0]["items"])

# A list of Keep's comes back as a checklist.
merged, actions, stats = keep_sync.merge_notes(
    [], [remote("k1", title="Shopping", items=[("milk", False), ("eggs", True)])]
)
check("a list comes back as a checklist", "Shopping\n- [ ] milk\n- [x] eggs", merged[0]["content"])

# A trashed note is not imported.
trashed = remote("k1", title="Shopping", text="milk")
trashed["trashed"] = True
merged, actions, stats = keep_sync.merge_notes([], [trashed])
check("a trashed note is not imported", 0, stats["imported"])

# A note whose Keep note was trashed there stays here, and nothing is pushed
# into Keep's trash.
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nbread", updated=3000, keep_id="k1", keep_edited=2000)], [trashed]
)
check("a note trashed in Keep stays here", "Shopping\nbread", merged[0]["content"])
check("a note trashed in Keep is not pushed", [], [a for a in actions if a["op"] == "push"])

# The overlay's scratchpad (a note flagged "scratchpad": Keep can't store
# the flag) stays the scratchpad through every kind of sync.
def scratchpad(note):
    return dict(note, scratchpad=True)


merged, actions, stats = keep_sync.merge_notes([scratchpad(local("s", "Scratch\nmilk"))], [])
check("a new scratchpad is created in Keep", 1, stats["created"])
check("a new scratchpad stays the scratchpad", True, merged[0].get("scratchpad"))
merged, actions, stats = keep_sync.merge_notes(
    [scratchpad(local("s", "Scratch\nmilk"))], [remote("k1", title="Scratch", text="milk")]
)
check("a linked scratchpad stays the scratchpad", (True, "k1"), (merged[0].get("scratchpad"), merged[0]["keepId"]))
merged, actions, stats = keep_sync.merge_notes(
    [scratchpad(local("s", "Scratch\nmilk", updated=2000, keep_id="k1", keep_edited=2000))],
    [remote("k1", title="Scratch", text="bread", edited=3000)],
)
check("a scratchpad changed in Keep comes back", "Scratch\nbread", merged[0]["content"])
check("a scratchpad changed in Keep stays the scratchpad", True, merged[0].get("scratchpad"))
merged, actions, stats = keep_sync.merge_notes(
    [scratchpad(local("s", "Scratch\neggs", updated=3000, keep_id="k1", keep_edited=2000))],
    [remote("k1", title="Scratch", text="milk", edited=2000)],
)
check("a scratchpad changed here is pushed", 1, stats["pushed"])
check("a pushed scratchpad stays the scratchpad", True, merged[0].get("scratchpad"))
merged, actions, stats = keep_sync.merge_notes(
    [scratchpad(local("s", "", updated=3000, keep_id="k1", keep_edited=2000))],
    [remote("k1", title="Scratch", text="milk", edited=2000)],
)
check("an emptied scratchpad is pushed empty", ("", ""), (actions[0]["title"], actions[0]["text"]))
check("an emptied scratchpad stays the scratchpad", (True, ""), (merged[0].get("scratchpad"), merged[0]["content"]))
merged, actions, stats = keep_sync.merge_notes(
    [local("1", "Shopping\nmilk")], [remote("k1", title="Scratch", text="bread")]
)
check("a note from Keep is never the scratchpad", [False, False], [bool(n.get("scratchpad")) for n in merged])

# -- With gkeepapi itself ----------------------------------------------------
#
# The tests above need no account; these need the library (the shell's
# Python environment), but no network: they are about how the notes are
# written to Keep's nodes.

try:
    import gkeepapi
except ImportError:
    gkeepapi = None

if gkeepapi is not None:
    keep = gkeepapi.Keep()
    note = keep.createNote("Shopping", "milk")
    keep_sync.apply_action(
        keep,
        {
            "op": "push",
            "keepId": note.id,
            "title": "Shopping",
            "text": "milk and eggs",
            "items": None,
            "pinned": True,
        },
    )
    pushed = keep.get(note.id)
    check("a note's title is pushed", "Shopping", pushed.title)
    check("a note's text is pushed", "milk and eggs", pushed.text)
    check("a note's pin is pushed", True, pushed.pinned)

    # A checklist is a list, and its items keep their order.
    lst = keep.createList("Shopping", [("milk", False), ("eggs", True)])
    check(
        "a list keeps its items' order",
        [("milk", False), ("eggs", True)],
        [(item.text, item.checked) for item in lst.items],
    )
    keep_sync.apply_action(
        keep,
        {
            "op": "push",
            "keepId": lst.id,
            "title": "Shopping",
            "text": "",
            "items": [("milk", False), ("bread", True)],
            "pinned": False,
        },
    )
    check(
        "a pushed list changes its items",
        [("milk", False), ("bread", True)],
        [(item.text, item.checked) for item in keep.get(lst.id).items],
    )
    keep_sync.apply_action(
        keep,
        {
            "op": "push",
            "keepId": lst.id,
            "title": "Shopping",
            "text": "",
            "items": [("milk", False)],
            "pinned": False,
        },
    )
    check(
        "a pushed list drops the items that are gone",
        [("milk", False)],
        [(item.text, item.checked) for item in keep.get(lst.id).items],
    )

    # A note of the shell becomes a Keep note (or a list).
    created = keep_sync.apply_action(
        keep,
        {
            "op": "create",
            "localId": "1",
            "title": "Shopping",
            "text": "milk",
            "items": None,
            "pinned": False,
        },
    )
    check("a created note has its title", "Shopping", created.title)
    check("a created note has its text", "milk", created.text)
    created_list = keep_sync.apply_action(
        keep,
        {
            "op": "create",
            "localId": "2",
            "title": "Shopping",
            "text": "",
            "items": [("milk", False)],
            "pinned": False,
        },
    )
    check(
        "a created list has its items",
        [("milk", False)],
        [(item.text, item.checked) for item in created_list.items],
    )

    # A note that changed kind: Keep can't turn a list into a note (or the
    # other way), so a new Keep note of the right kind takes its place and
    # the old one goes to the trash.
    old_list = keep.createList("Errands", [("post", False)])
    replaced = keep_sync.apply_action(
        keep,
        {
            "op": "push",
            "keepId": old_list.id,
            "title": "Errands",
            "text": "post the letter\ncall the bank",
            "items": None,
            "pinned": True,
        },
    )
    check("a list that became a note is a new Keep note", False, hasattr(replaced, "items"))
    check("its text is pushed", "post the letter\ncall the bank", replaced.text)
    check("its pin is pushed", True, replaced.pinned)
    check("the old list goes to the trash", True, keep.get(old_list.id).trashed)
    old_note = keep.createNote("Errands", "post")
    replaced = keep_sync.apply_action(
        keep,
        {
            "op": "push",
            "keepId": old_note.id,
            "title": "Errands",
            "text": "",
            "items": [("post", True), ("bank", False)],
            "pinned": False,
        },
    )
    check(
        "a note that became a checklist is a new Keep list",
        [("post", True), ("bank", False)],
        [(item.text, item.checked) for item in replaced.items],
    )
    check("the old note goes to the trash", True, keep.get(old_note.id).trashed)

    # What the shell reads back from a Keep note.
    check(
        "a Keep note is read back as its title and text",
        "Shopping\nmilk and eggs",
        keep_sync.remote_content(keep_sync.to_remote(pushed)),
    )
    check(
        "a Keep list is read back as a checklist",
        "Shopping\n- [ ] milk",
        keep_sync.remote_content(keep_sync.to_remote(keep.get(lst.id))),
    )
else:
    print("ok   - the gkeepapi tests are skipped (no gkeepapi here)")

if failures:
    print(f"{failures} failed", file=sys.stderr)
    sys.exit(1)
print("keep: every test passed")
