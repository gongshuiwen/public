import { execFileSync } from "node:child_process";
import { copyFile, lstat, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { escapeHtml, getTextPreview, MAX_PREVIEW_BYTES, renderPreviewLines } from "./text-preview.mjs";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const assetsDirectory = join(root, ".generated", "public");
const excludedFiles = new Set([
  "package.json", "package-lock.json", "cloudflare.config.ts",
  "vite.config.ts", "index.html",
]);
const excludedDirectories = new Set(["src", "scripts", "site", "node_modules", "dist"]);

const files = execFileSync("git", [
  "ls-files", "--cached", "--others", "--exclude-standard", "-z",
], { cwd: root, encoding: "utf8" })
  .split("\0")
  .filter(Boolean)
  .filter((path) => {
    const parts = path.split("/");
    return !parts.some((part) => part.startsWith(".")) &&
      !excludedFiles.has(path) && !excludedDirectories.has(parts[0]);
  })
  .sort((left, right) => left.localeCompare(right, "en"));

if (!assetsDirectory.startsWith(root + sep)) {
  throw new Error("Generated assets directory must stay inside the repository.");
}
await rm(assetsDirectory, { recursive: true, force: true });
await mkdir(assetsDirectory, { recursive: true });

if (files.some((path) => /^(preview|site-assets)\//.test(path))) {
  throw new Error("preview/ and site-assets/ are reserved for the website's preview pages.");
}

const previewTemplate = await readFile(join(root, "site", "preview.template.html"), "utf8");
await mkdir(join(assetsDirectory, "site-assets"), { recursive: true });
await copyFile(join(root, "site", "preview.js"), join(assetsDirectory, "site-assets", "preview.js"));

const rows = [];
let previewCount = 0;
for (const path of [...new Set(files)]) {
  const source = join(root, path);
  const metadata = await lstat(source);
  if (!metadata.isFile()) continue;
  const target = join(assetsDirectory, path);
  await mkdir(dirname(target), { recursive: true });
  await copyFile(source, target);
  const href = "/" + path.split("/").map(encodeURIComponent).join("/");
  const preview = metadata.size <= MAX_PREVIEW_BYTES
    ? getTextPreview(path, await readFile(source))
    : null;
  const previewHref = preview ? "/preview" + href + "/" : null;

  if (preview) {
    const tokens = {
      TITLE: escapeHtml(path),
      NAME: escapeHtml(path),
      LANGUAGE: escapeHtml(preview.language),
      SIZE: metadata.size.toLocaleString("en"),
      LINE_COUNT: preview.lines.length.toLocaleString("en"),
      DOWNLOAD_URL: escapeHtml(href),
      LINES: renderPreviewLines(preview.lines),
    };
    const page = previewTemplate.replace(/\{\{([A-Z_]+)\}\}/g, (_, token) => tokens[token]);
    const previewTarget = join(assetsDirectory, "preview", path, "index.html");
    await mkdir(dirname(previewTarget), { recursive: true });
    await writeFile(previewTarget, page);
    previewCount++;
  }

  const previewLink = previewHref
    ? '<a href="' + previewHref + '" aria-label="预览 ' + escapeHtml(path) + '">预览</a>'
    : "";
  rows.push('<tr><td><a href="' + (previewHref ?? href) + '">' + escapeHtml(path) +
    '</a></td><td>' + metadata.size.toLocaleString("en") +
    ' B</td><td><div class="file-actions">' + previewLink +
    '<a class="download" download href="' + href + '">下载</a></div></td></tr>');
}

const template = await readFile(join(root, "site", "index.template.html"), "utf8");
await writeFile(join(root, "index.html"), template.replace("{{FILES}}", rows.join("\n")));
await writeFile(join(assetsDirectory, "_headers"), [
  "/*",
  "  X-Content-Type-Options: nosniff",
  "  Referrer-Policy: no-referrer",
  "  Cache-Control: public, max-age=60, must-revalidate",
  "/*.ps1",
  "  Content-Type: text/plain; charset=utf-8",
  "  Content-Disposition: attachment",
  "",
].join("\n"));
console.log("Prepared " + rows.length + " public files and " + previewCount + " text previews.");
