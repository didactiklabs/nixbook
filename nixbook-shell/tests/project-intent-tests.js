// The bubble's plain-code phrases for projects and teach mode
// (src/modules/common/functions/project_intent.js) in the four languages,
// and what they must leave to DAI or to other commands. Run by
// projects.sh (node).
"use strict";
const fs = require("fs");
const path = require("path");

const src = fs
  .readFileSync(
    path.join(__dirname, "../src/modules/common/functions/project_intent.js"),
    "utf8",
  )
  .replace(/^\.pragma library/m, "");
const lib = new Function(
  src + "\nreturn { projectIntent: projectIntent, teachIntent: teachIntent }",
)();

let failed = 0,
  passed = 0;
function check(name, got, want) {
  const g = JSON.stringify(got),
    w = JSON.stringify(want);
  if (g === w) {
    passed++;
    return;
  }
  failed++;
  console.log(`FAIL ${name}: got ${g}, want ${w}`);
}

const names = ["hackathon", "tax-return", "Thesis"];
const open = (n) => ({ action: "open", name: n });
const pause = (n) => ({ action: "pause", name: n });
const cases = [
  // English
  ["work on the hackathon", open("hackathon")],
  ["Let's work on hackathon", open("hackathon")],
  ["DAI, work on the tax return please", open("tax-return")],
  ["back to my thesis", open("Thesis")],
  ["resume hackathon", open("hackathon")],
  ["open the hackathon project", open("hackathon")],
  ["switch to project thesis", open("Thesis")],
  ["pause the hackathon", pause("hackathon")],
  ["pause hackathon.", pause("hackathon")],
  ["close the hackathon project", pause("hackathon")],
  ["I'm done with the tax return", pause("tax-return")],
  ["stop working on hackathon", pause("hackathon")],
  // French
  ["travaille sur le hackathon", open("hackathon")],
  ["on bosse sur la thesis", open("Thesis")],
  ["je reprends le hackathon", open("hackathon")],
  ["retour au hackathon", open("hackathon")],
  ["ouvre le projet hackathon", open("hackathon")],
  ["mets le hackathon en pause", pause("hackathon")],
  ["j'arrête le hackathon", pause("hackathon")],
  ["ferme le projet hackathon", pause("hackathon")],
  // German
  ["arbeite an dem hackathon", open("hackathon")],
  ["arbeite am Hackathon", open("hackathon")],
  ["ich arbeite jetzt an der thesis", open("Thesis")],
  ["weiter mit hackathon", open("hackathon")],
  ["zurück zum hackathon", open("hackathon")],
  ["pausiere den hackathon", pause("hackathon")],
  ["hackathon pausieren", pause("hackathon")],
  ["hör auf mit dem hackathon", pause("hackathon")],
  // Vietnamese
  ["làm việc với hackathon", open("hackathon")],
  ["tiếp tục hackathon", open("hackathon")],
  ["mở dự án hackathon", open("hackathon")],
  ["làm hackathon nhé", open("hackathon")],
  ["tạm dừng hackathon", pause("hackathon")],
  ["tạm dừng dự án hackathon", pause("hackathon")],
  // Not a saved project, or not about one: left alone.
  ["work on the website", null],
  ["pause the music", null],
  ["pause", null],
  ["open firefox", null],
  ["mets la musique en pause", null],
  ["tạm dừng nhạc", null],
  ["what is the hackathon about?", null],
  [
    "work on the hackathon and then email Bob about the deadline tomorrow morning ok",
    null,
  ],
];
for (const [text, want] of cases)
  check(`project: ${text}`, lib.projectIntent(text, names), want);
check("no projects: nothing", lib.projectIntent("work on hackathon", []), null);

const teach = [
  ["watch me", false, "start"],
  ["Watch me do it once", false, "start"],
  ["let me show you", false, "start"],
  ["regarde-moi faire", false, "start"],
  ["je vais te montrer", false, "start"],
  ["schau mir zu", false, "start"],
  ["ich zeige es dir", false, "start"],
  ["xem tôi làm nhé", false, "start"],
  ["để tôi chỉ cho bạn", false, "start"],
  ["done", true, "stop"],
  ["I'm done.", true, "stop"],
  ["c'est fini", true, "stop"],
  ["fertig", true, "stop"],
  ["xong rồi", true, "stop"],
  ["never mind", true, "cancel"],
  ["laisse tomber", true, "cancel"],
  ["vergiss es", true, "cancel"],
  // Only while recording, and never other words.
  ["done", false, null],
  ["watch me", true, null],
  ["watch the video", false, null],
  ["open firefox", true, null],
];
for (const [text, recording, want] of teach)
  check(
    `teach (${recording ? "recording" : "idle"}): ${text}`,
    lib.teachIntent(text, recording),
    want,
  );

// Fast: a sentence in well under a millisecond.
const t0 = process.hrtime.bigint();
for (let i = 0; i < 2000; i++)
  lib.projectIntent("travaille sur le hackathon", names);
const per = Number(process.hrtime.bigint() - t0) / 2000 / 1e6;
check(`fast (${per.toFixed(3)} ms a sentence)`, per < 0.5, true);

console.log(`${passed} passed, ${failed} failed`);
process.exit(failed ? 1 : 0);
