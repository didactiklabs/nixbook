"""Build the launcher's emoji list (services/Emojis.qml) from Unicode's
emoji-test.txt and CLDR's English annotations.

  emojis.py <emoji-test.txt> <annotations/en.xml> <annotationsDerived/en.xml>  >  emojis.txt

Output: a "### DATA ###" line, then one fully-qualified emoji per line, in
Unicode's order: "<emoji> <name>\t<keywords>". The launcher shows the name
and searches name and keywords ("lol" finds 😂). Skin-tone variants are left
out so they don't crowd the results; the neutral emoji stays.
"""

import re
import sys
import xml.etree.ElementTree as ET

test_path, *annotation_paths = sys.argv[1:]

keywords = {}
for path in annotation_paths:
    for node in ET.parse(path).getroot().iter("annotation"):
        if node.get("type") is None and node.text:
            keywords.setdefault(node.get("cp"), node.text)

line_re = re.compile(r"^[0-9A-F ]+;\s*fully-qualified\s*#\s*(\S+)\s+E\d+\.\d+\s+(.+)$")

print("### DATA ###")
with open(test_path, encoding="utf-8") as test:
    for line in test:
        match = line_re.match(line)
        if not match:
            continue
        emoji, name = match.groups()
        if "skin tone" in name:
            continue
        words = keywords.get(emoji) or keywords.get(emoji.replace("️", ""), "")
        words = " ".join(w.strip() for w in words.split("|") if w.strip() and w.strip() != name)
        print(f"{emoji} {name}\t{words}" if words else f"{emoji} {name}")
