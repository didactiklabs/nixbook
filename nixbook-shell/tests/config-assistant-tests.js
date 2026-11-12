// The config assistant (src/services/ConfigAssistant.qml, a QML singleton run
// here under node) against the real how-tos of hm-module.nix, in English: the
// other languages' questions go through its lexicons onto the same facts.
// Run by config-assistant.sh.
"use strict";
const fs = require("fs");
const path = require("path");
const src = fs.readFileSync(
  path.join(__dirname, "../src/services/ConfigAssistant.qml"),
  "utf8",
);
let body = src.slice(src.indexOf("{", src.indexOf("Singleton {")) + 1);
body = body.slice(0, body.lastIndexOf("}"));
body = body.replace(/^\s*id: root$/m, "");
body = body.replace(/^ {4}FileView \{[\s\S]*?^ {4}\}$/m, "");
body = body.replace(/^ {4}(?:readonly )?property \w+ (\w+):/gm, "root.$1 =");
body = body.replace(/^ {4}function (\w+)\(/gm, "root.$1 = function(");
const root = {};
new Function("root", "Qt", body)(root, {
  locale: () => ({ name: "en_US" }),
});

const howTos = {};
const nix = fs.readFileSync(path.join(__dirname, "../hm-module.nix"), "utf8");
for (const m of nix.matchAll(/(\w+) = \{\s*en = "((?:[^"\\]|\\.)*)";/g))
  howTos[m[1]] = m[2].replace(/\\(.)/g, "$1");

const binds = {
  "Mod+A": "Press Mod+A to close the focused window.",
  "Mod+Ctrl+I": "Press Mod+Ctrl+I to move the column to the workspace above.",
  "Mod+Shift+Escape":
    "Press Mod+Shift+Escape to stop (pause) the AI agents controlling the desktop.",
};
const os = ["The Linux kernel is version 7.3.1."];
const facts = [...Object.values(binds), ...os, ...Object.values(howTos)];
const kinds = [
  ...Object.keys(binds).map((k) => `bind:${k}`),
  ...os.map(() => "os"),
  ...Object.keys(howTos).map((k) => `howto:${k}`),
];
root.load(
  JSON.stringify({
    host: "test",
    facts,
    kinds,
    modules: { all: [], enabled: [] },
    packages: [],
    settingPaths: [],
    toggles: [],
  }),
);

let failed = 0;
function check(question, want) {
  const got = root.answer(question);
  if (got.startsWith(want)) return console.log(`ok   - ${question}`);
  failed++;
  console.log(
    `FAIL - ${question}: got ${JSON.stringify(got.slice(0, 90))}, want ${JSON.stringify(want.slice(0, 90))}`,
  );
}
function cant(lang, questions) {
  for (const q of questions) check(q, root.strings[lang].cantDo);
}

// A request to do something: no how-to answers it.
cant("en", [
  "add that to memory i guess",
  "remember this",
  "remember that I like tea",
  "can you remember this for me",
  "put that in the notes",
  "note that down",
  "yes do it",
  "fix it",
  "forget that",
]);
cant("fr", ["ajoute ça à la mémoire", "retiens ça", "souviens-toi de ça"]);
cant("de", ["merk dir das", "speichere das", "füg das hinzu"]);
cant("vi", ["nhớ cái này", "thêm cái đó vào bộ nhớ", "lưu cái đó"]);

// A how-to answers on its topic or one sentence, not on scattered words.
check("can dai add a transaction in actual budget", howTos.budgetQuestions);
check("can dai create a schedule in actual", howTos.budgetQuestions);
check("can dai read my gmail", howTos.gmailMail);
check("how do I put websites in the theme colours in zen", howTos.zenWebsites);
check("how do I make a gmail filter", howTos.gmailMail);
check("how do I put gmail in the theme colours", howTos.gmailMail);
check("add memory", howTos.desktopMemory);
check("how does the agent memory work", howTos.desktopMemory);
check("how do i remember this", howTos.personalMemory);
check("how do i request a feature", howTos.agentFeatures);
check("can DAI build features", howTos.agentFeatures);
check("how do fixes work", howTos.agentFixes);
check("how do I find a file", howTos.findAnything);
check("how do I send a gif in the mesh", howTos.mesh);
check("how do we listen together in the mesh", howTos.mesh);
check("how do we watch together on jellyfin in the mesh", howTos.mesh);
check("how do I turn on echo cancellation", howTos.echoCancel);
check(
  "the music is heard through my microphone in calls, echo",
  howTos.echoCancel,
);
check("comment activer l'annulation d'écho", howTos.echoCancel);
check("wie schalte ich die Echounterdrückung ein", howTos.echoCancel);
check("làm sao bật khử tiếng vọng", howTos.echoCancel);
check("where is my music visualizer", howTos.visualizer);
check("the visualizer doesn't appear anymore", howTos.visualizer);
check("pourquoi le visualiseur ne s'affiche plus", howTos.visualizer);
check("wo ist die Musik-Visualisierung", howTos.visualizer);
check("trình hiển thị nhạc không hiện", howTos.visualizer);
check("how do I set a charge limit for the battery", howTos.batteryPanel);
check("how do I stop charging at 80%", howTos.batteryPanel);
check("how do I change the power profile", howTos.batteryPanel);
check("comment limiter la charge de la batterie", howTos.batteryPanel);
check("comment changer le profil d'alimentation", howTos.batteryPanel);
check("wie stelle ich die Ladegrenze ein", howTos.batteryPanel);
check("wie ändere ich das Energieprofil", howTos.batteryPanel);
check("làm sao đặt giới hạn sạc pin", howTos.batteryPanel);
check("làm sao đổi chế độ nguồn", howTos.batteryPanel);
check("how do I change the sound output to my headphones", howTos.soundOutput);
check("why is the easyeffects sink not in the output list", howTos.soundOutput);
check("comment changer la sortie audio", howTos.soundOutput);
check("wie wähle ich die Tonausgabe", howTos.soundOutput);
check("làm sao chọn đầu ra âm thanh", howTos.soundOutput);
check("how do I make my voice clearer in calls", howTos.clearVoices);
check("the others sound muffled in calls", howTos.clearVoices);
check("comment avoir une voix plus claire en appel", howTos.clearVoices);
check("wie wird meine Stimme klarer in Anrufen", howTos.clearVoices);
check("làm sao cho giọng rõ hơn khi gọi", howTos.clearVoices);
check("comment regarder ensemble un film", howTos.mesh);
check("comment écouter ensemble de la musique", howTos.mesh);
check("wie können wir zusammen hören", howTos.mesh);
check("làm sao nghe nhạc cùng nhau", howTos.mesh);
check("how do I send a photo to someone in the mesh", howTos.mesh);
check("comment envoyer une photo dans le mesh", howTos.mesh);
check("wie kann ich im Mesh eine Datei senden", howTos.mesh);
check("làm sao gửi ảnh trong mesh", howTos.mesh);
check("can DAI see my private window", howTos.privateWindowsIncognito);
check(
  "does the agent read my password manager",
  howTos.privateWindowsIncognito,
);
check(
  "why is the screenshot refused with private browsing open",
  howTos.privateWindowsIncognito,
);
check("DAI peut-il voir ma fenêtre privée", howTos.privateWindowsIncognito);
check("kann DAI mein privates Fenster sehen", howTos.privateWindowsIncognito);
check(
  "DAI có thấy cửa sổ riêng tư của tôi không",
  howTos.privateWindowsIncognito,
);
check("comment fonctionne la mémoire", howTos.desktopMemory);
check("wie funktioniert das Gedächtnis", howTos.desktopMemory);

// A statement stays alone, no how-to mentioning a word of it comes along.
{
  const got = root.answer("which kernel?");
  if (got === os[0]) console.log("ok   - which kernel?");
  else {
    failed++;
    console.log(
      `FAIL - which kernel?: got ${JSON.stringify(got.slice(0, 90))}`,
    );
  }
}

// A keybinding still comes first, a pronoun before a noun isn't a request.
check("close window", binds["Mod+A"]);
check("close this window", binds["Mod+A"]);
check("move window to workspace 2", binds["Mod+Ctrl+I"]);
check("how do I stop the agent", binds["Mod+Shift+Escape"]);

console.log(failed ? `${failed} failed` : "all passed");
process.exit(failed ? 1 : 0);
