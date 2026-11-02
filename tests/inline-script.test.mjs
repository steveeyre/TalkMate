// Guards for the single-file app: the inline script must parse, and the
// install payloads embedded in index.html must match their canonical sources.
import test from "node:test";
import assert from "node:assert/strict";
import vm from "node:vm";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(path.join(root, "index.html"), "utf8");
const normalize = (text) => text.replace(/^\uFEFF/, "").replace(/\r\n/g, "\n").trim();

const EMBEDS = [
  ["embed-whisper-py", "scripts/local_whisper_server.py"],
  ["embed-tts-py", "scripts/local_tts_server.py"],
  ["embed-whisper-ps1", "scripts/deploy-local-whisper.ps1"],
  ["embed-tts-ps1", "scripts/deploy-local-tts.ps1"]
];

test("inline app script parses", () => {
  const blocks = [...html.matchAll(/<script>([\s\S]*?)<\/script>/g)];
  assert.equal(blocks.length, 1, "expected exactly one inline <script> block");
  assert.doesNotThrow(() => new vm.Script(blocks[0][1], { filename: "index.html" }));
});

for (const [id, rel] of EMBEDS) {
  test(`embed block ${id} matches ${rel}`, () => {
    const block = html.match(
      new RegExp('<script type="text/plain" id="' + id + '">([\\s\\S]*?)</script>')
    );
    assert.ok(block, `block ${id} not found`);
    const source = normalize(readFileSync(path.join(root, rel), "utf8"));
    assert.equal(normalize(block[1]), source, `run scripts/sync-embeds.ps1`);
  });
}
