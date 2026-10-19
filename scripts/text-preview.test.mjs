import assert from "node:assert/strict";
import test from "node:test";
import { getTextPreview, renderPreviewLines } from "./text-preview.mjs";

function renderedSource(html) {
  const entities = { amp: "&", lt: "<", gt: ">", quot: '"', "#39": "'" };
  return html.split('<span class="code-line"').slice(1).map((line) => {
    const content = line.slice(line.indexOf('<span class="line-content">'));
    return content.replace(/<[^>]*>/g, "")
      .replace(/&(amp|lt|gt|quot|#39);/g, (_, entity) => entities[entity]);
  }).join("\n");
}

test("PowerShell highlighting preserves multiline state, blank lines and source text", async () => {
  const source = '<# block comment\ncontinued comment #>\n\n$name = "hello"\nWrite-Host $name\n';
  const preview = getTextPreview("example.ps1", Buffer.from(source));
  const html = await renderPreviewLines(preview.lines, preview.syntax);
  assert.equal(renderedSource(html), source);
  assert.equal((html.match(/class="code-line"/g) ?? []).length, preview.lines.length);
  assert.ok(html.includes('id="L6"'));
  assert.ok(html.includes("--shiki-light:"));
  assert.ok(html.includes("--shiki-dark:"));
  const commentColors = [...html.matchAll(/style="([^"]*)">(?:&lt;# block comment|continued comment #&gt;)<\/span>/g)];
  assert.equal(commentColors.length, 2);
  assert.equal(commentColors[0][1], commentColors[1][1]);
  assert.ok(new Set([...html.matchAll(/--shiki-light:(#[A-Fa-f0-9]+)/g)].map((match) => match[1])).size > 1);
});

test("highlighted HTML-like source remains escaped and copies verbatim", async () => {
  const source = '</span></script><img src=x onerror="alert(1)">\n&amp; <script>alert("hello")</script>\n';
  const preview = getTextPreview("example.html", Buffer.from(source));
  const html = await renderPreviewLines(preview.lines, preview.syntax);
  assert.equal(renderedSource(html), source);
  assert.ok(!html.includes("<img"));
  assert.ok(!html.includes("<script"));
  assert.ok(!html.includes("</script>"));
});

test("all preview language mappings resolve to bundled Shiki grammars", async () => {
  const extensions = ["ps1", "psm1", "psd1", "sh", "bash", "zsh", "bat", "cmd", "py",
    "js", "mjs", "cjs", "ts", "tsx", "jsx", "json", "jsonc", "md", "csv", "tsv",
    "yaml", "yml", "toml", "ini", "conf", "cfg", "html", "htm", "xml", "svg",
    "css", "sql", "c", "h", "cpp", "cs", "java", "go", "rs", "rb", "php"];
  for (const extension of extensions) {
    const preview = getTextPreview("example." + extension, Buffer.from("value\n"));
    const html = await renderPreviewLines(preview.lines, preview.syntax);
    assert.equal(renderedSource(html), "value\n", extension);
    assert.ok(html.includes("syntax-token"), extension);
  }
  for (const extension of ["tsx", "jsx", "jsonc"]) {
    assert.equal(getTextPreview("example." + extension, Buffer.from("value")).syntax, extension);
  }
});

test("plain text keeps original whitespace without syntax markup", async () => {
  const source = '\tplain <text> & "quotes"\r\n\r\nlast\r\n';
  for (const path of ["example.txt", "example.log", "LICENSE"]) {
    const preview = getTextPreview(path, Buffer.from(source));
    const html = await renderPreviewLines(preview.lines, preview.syntax);
    assert.equal(renderedSource(html), source.replaceAll("\r\n", "\n"));
    assert.ok(!html.includes("syntax-token"));
  }
});
