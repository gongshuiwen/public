const copyButton = document.querySelector("#copy-source");
const wrapButton = document.querySelector("#toggle-wrap");
const status = document.querySelector("#preview-status");
const codeView = document.querySelector("#code-view");

copyButton.addEventListener("click", async () => {
  const source = Array.from(document.querySelectorAll(".line-content"),
    (line) => line.textContent).join("\n");
  try {
    await navigator.clipboard.writeText(source);
    status.textContent = "已复制全文";
  } catch {
    status.textContent = "复制未成功，请选择文本复制，或下载原文件。";
  }
});

wrapButton.addEventListener("click", () => {
  const wrapped = codeView.classList.toggle("is-wrapped");
  wrapButton.setAttribute("aria-pressed", String(wrapped));
  wrapButton.textContent = wrapped ? "取消换行" : "自动换行";
});

if (!navigator.clipboard?.writeText) {
  copyButton.disabled = true;
  copyButton.title = "当前浏览器不支持复制，请选择文本复制或下载原文件。";
}
