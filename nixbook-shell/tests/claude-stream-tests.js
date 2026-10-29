// The side panel's Claude Code stream (src/services/ai/ClaudeCodeApiStrategy.qml,
// a QML QtObject run here under node): once a turn has taken a step, the
// words between steps are never shown, the first line and the answer are.
// Run by claude-stream.sh.
"use strict";
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(
  path.join(__dirname, "../src/services/ai/ClaudeCodeApiStrategy.qml"),
  "utf8",
);
let body = src.slice(
  src.indexOf("{", src.indexOf("QtObject")) + 1,
  src.lastIndexOf("}"),
);
body = body.replace(/^\s*property\s+\w+\s+(\w+):\s*(.*)$/gm, "self.$1 = $2;");
body = body.replace(/^(\s*)function (\w+)\(/gm, "$1self.$2 = function(");
const o = {};
new Function("self", "with (self) {" + body + "}")(o);

let failed = 0;
function check(name, got, want) {
  if (got === want) return console.log(`ok   - ${name}`);
  failed++;
  console.log(
    `FAIL - ${name}: got ${JSON.stringify(got)}, want ${JSON.stringify(want)}`,
  );
}
function turn(messages) {
  o.reset();
  const msg = { rawContent: "", content: "" };
  const ev = (e) =>
    o.parseResponseLine(
      JSON.stringify({ type: "stream_event", event: e }),
      msg,
    );
  for (const [text, withTool] of messages) {
    ev({ type: "message_start" });
    if (text) {
      ev({ type: "content_block_start", content_block: { type: "text" } });
      for (const piece of text.match(/.{1,4}/g))
        ev({
          type: "content_block_delta",
          delta: { type: "text_delta", text: piece },
        });
      ev({ type: "content_block_stop" });
    }
    if (withTool) {
      ev({ type: "content_block_start", content_block: { type: "tool_use" } });
      ev({ type: "content_block_stop" });
    }
    ev({
      type: "message_delta",
      delta: { stop_reason: withTool ? "tool_use" : "end_turn" },
    });
    ev({ type: "message_stop" });
  }
  o.parseResponseLine(JSON.stringify({ type: "result", usage: {} }), msg);
  return msg.content;
}

check(
  "the first line and the answer, not the words between steps",
  turn([
    ["Closing them all. ", true],
    ["Need to close rest.", true],
    ["Still closing.", true],
    ["All closed.", false],
  ]),
  "Closing them all. All closed.",
);
check(
  "a turn without steps, as it streams",
  turn([["Hello there", false]]),
  "Hello there",
);
check(
  "a step without words, then the answer",
  turn([
    [null, true],
    ["Done.", false],
  ]),
  "Done.",
);
check(
  "the next turn starts afresh",
  turn([
    ["Looking.", true],
    ["Found it.", false],
  ]),
  "Looking.Found it.",
);
process.exit(failed ? 1 : 0);
