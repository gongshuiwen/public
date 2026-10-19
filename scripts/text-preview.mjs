import { basename, extname } from "node:path";
import { codeToTokens } from "shiki";

export const MAX_PREVIEW_BYTES = 1024 * 1024;

const languages = new Map([
  [".ps1", "PowerShell"], [".psm1", "PowerShell"], [".psd1", "PowerShell"],
  [".sh", "Shell"], [".bash", "Shell"], [".zsh", "Shell"],
  [".bat", "Batch"], [".cmd", "Batch"], [".py", "Python"],
  [".js", "JavaScript"], [".mjs", "JavaScript"], [".cjs", "JavaScript"],
  [".ts", "TypeScript"], [".tsx", "TypeScript"], [".jsx", "JavaScript"],
  [".json", "JSON"], [".jsonc", "JSON"], [".md", "Markdown"],
  [".txt", "纯文本"], [".log", "日志"], [".csv", "CSV"], [".tsv", "TSV"],
  [".yaml", "YAML"], [".yml", "YAML"], [".toml", "TOML"],
  [".ini", "INI"], [".conf", "配置"], [".cfg", "配置"],
  [".html", "HTML"], [".htm", "HTML"], [".xml", "XML"], [".svg", "SVG"],
  [".css", "CSS"], [".sql", "SQL"], [".c", "C"], [".h", "C"],
  [".cpp", "C++"], [".cs", "C#"], [".java", "Java"], [".go", "Go"],
  [".rs", "Rust"], [".rb", "Ruby"], [".php", "PHP"],
]);

const syntaxAliases = new Map([
  ["Shell", "shellscript"], ["Batch", "bat"], ["C++", "cpp"], ["C#", "csharp"],
  ["SVG", "xml"], ["配置", "ini"], ["纯文本", "text"], ["日志", "text"],
]);

export function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;",
  }[character]));
}

export function getTextPreview(path, bytes) {
  const extension = extname(path).toLowerCase();
  const language = languages.get(extension) ??
    (/^(license|copying|notice|makefile|dockerfile)$/i.test(basename(path)) ? "纯文本" : null);
  if (!language || bytes.length > MAX_PREVIEW_BYTES) return null;

  let encoding = "utf-8";
  if (bytes[0] === 0xff && bytes[1] === 0xfe) encoding = "utf-16le";
  if (bytes[0] === 0xfe && bytes[1] === 0xff) encoding = "utf-16be";

  try {
    const text = new TextDecoder(encoding, { fatal: true }).decode(bytes);
    if (text.includes("\0")) return null;
    const syntax = [".jsx", ".tsx", ".jsonc"].includes(extension)
      ? extension.slice(1)
      : syntaxAliases.get(language) ?? language.toLowerCase();
    return { language, syntax, lines: text.split(/\r\n|\r|\n/) };
  } catch {
    return null;
  }
}

export async function renderPreviewLines(lines, syntax = "text") {
  const highlighted = syntax === "text" ? null : (await codeToTokens(lines.join("\n"), {
    lang: syntax,
    themes: { light: "github-light", dark: "github-dark" },
    defaultColor: false,
  })).tokens;

  return lines.map((line, index) => {
    const number = index + 1;
    const content = highlighted
      ? highlighted[index].map((token) => {
        const style = Object.entries(token.htmlStyle ?? {})
          .map(([property, value]) => property + ":" + value).join(";");
        return '<span class="syntax-token" style="' + escapeHtml(style) + '">' +
          escapeHtml(token.content) + '</span>';
      }).join("")
      : escapeHtml(line);
    return '<span class="code-line" id="L' + number +
      '"><a class="line-number" href="#L' + number + '" aria-label="第 ' +
      number + ' 行">' + number + '</a><span class="line-content">' +
      content + '</span></span>';
  }).join("");
}
