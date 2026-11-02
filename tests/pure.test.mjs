// The pure helpers live inside index.html; extract them so their behaviour can
// be regression-tested without a browser.
import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
const html = readFileSync(path.join(root, "index.html"), "utf8");

function extractFunction(name) {
  const marker = "function " + name + "(";
  const start = html.indexOf(marker);
  assert.notEqual(start, -1, name + " not found in index.html");
  let depth = 0;
  for (let i = html.indexOf("{", start); i < html.length; i += 1) {
    if (html[i] === "{") depth += 1;
    else if (html[i] === "}") {
      depth -= 1;
      if (depth === 0) return html.slice(start, i + 1);
    }
  }
  throw new Error("unterminated function " + name);
}

const names = [
  "escapeHtml",
  "renderRichText",
  "splitNote",
  "normalizeOllamaModel",
  "extractLlmText",
  "storyAgeMin",
  "stripSlashV",
  "v1Url"
];
const api = new Function(
  names.map(extractFunction).join("\n") + "\nreturn { " + names.join(", ") + " };"
)();

test("escapeHtml neutralises markup and quotes", () => {
  assert.equal(
    api.escapeHtml(`<b>"x"&'y'</b>`),
    "&lt;b&gt;&quot;x&quot;&amp;&#39;y&#39;&lt;/b&gt;"
  );
});

test("renderRichText keeps ** and == styling but never raw HTML", () => {
  const out = api.renderRichText("==nice== **word** <script>alert(1)</script>");
  assert.match(out, /<span class="md-hl">nice<\/span>/);
  assert.match(out, /<strong class="md-b">word<\/strong>/);
  assert.ok(!out.includes("<script>"), out);
  assert.ok(out.includes("&lt;script&gt;"), out);
});

test("splitNote separates the coaching note from the spoken text", () => {
  assert.deepEqual(api.splitNote("Hello there.\nNote: use past tense"), {
    text: "Hello there.",
    note: "use past tense"
  });
  assert.deepEqual(api.splitNote("Hi\n纠错：用 went"), { text: "Hi", note: "用 went" });
  assert.deepEqual(api.splitNote("Just a line"), { text: "Just a line", note: null });
});

test("normalizeOllamaModel matches Ollama's naming", () => {
  assert.equal(api.normalizeOllamaModel("models/Qwen3_8B:latest"), "qwen3-8b");
  assert.equal(api.normalizeOllamaModel("  Llama3.2  "), "llama3.2");
});

test("extractLlmText handles the provider response shapes it claims to", () => {
  assert.equal(api.extractLlmText({ choices: [{ message: { content: "hi" } }] }), "hi");
  assert.equal(
    api.extractLlmText({
      choices: [{ message: { content: [{ type: "text", text: "a" }, { type: "text", text: "b" }] } }]
    }),
    "ab"
  );
  assert.equal(api.extractLlmText({ choices: [{ text: "legacy" }] }), "legacy");
  assert.equal(api.extractLlmText({ output_text: "output" }), "output");
  assert.equal(
    api.extractLlmText({ choices: [{ message: { content: "", reasoning_content: "one\ntwo" } }] }),
    "one\ntwo"
  );
  assert.equal(api.extractLlmText({}), "");
  assert.equal(api.extractLlmText(null), "");
});

test("storyAgeMin reads the first number in an age range", () => {
  assert.equal(api.storyAgeMin({ age: "6-8" }), 6);
  assert.equal(api.storyAgeMin({ age: "9" }), 9);
  assert.equal(api.storyAgeMin({ age: "all ages" }), 99);
  assert.equal(api.storyAgeMin({}), 9, "missing age falls back to 9");
  assert.equal(api.storyAgeMin(null), 9);
});

test("v1Url does not duplicate /v1", () => {
  assert.equal(api.v1Url("http://127.0.0.1:8787/v1/", "/health"), "http://127.0.0.1:8787/v1/health");
  assert.equal(
    api.v1Url("https://api.deepseek.com/", "/chat/completions"),
    "https://api.deepseek.com/v1/chat/completions"
  );
});
