import { execFileSync } from "node:child_process";
import { copyFile, lstat, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { dirname, join, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

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

const escapeHtml = (value) => value.replace(/[&<>"']/g, (character) => ({
  "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
}[character]));

const rows = [];
for (const path of [...new Set(files)]) {
  const source = join(root, path);
  const metadata = await lstat(source);
  if (!metadata.isFile()) continue;
  const target = join(assetsDirectory, path);
  await mkdir(dirname(target), { recursive: true });
  await copyFile(source, target);
  const href = "/" + path.split("/").map(encodeURIComponent).join("/");
  rows.push('<tr><td><a href="' + href + '">' + escapeHtml(path) +
    '</a></td><td>' + metadata.size.toLocaleString("en") +
    ' B</td><td><a class="download" download href="' + href + '">下载</a></td></tr>');
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
console.log("Prepared " + rows.length + " public files.");
