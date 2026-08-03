const installButton = document.querySelector("[data-copy]");

if (installButton) {
  installButton.addEventListener("click", async () => {
    const command = installButton.dataset.copy;
    const label = installButton.querySelector(".copy-label");

    try {
      await navigator.clipboard.writeText(command);
      label.textContent = "Copied";
      window.setTimeout(() => {
        label.textContent = "Copy";
      }, 1800);
    } catch {
      label.textContent = "Select";
      const range = document.createRange();
      range.selectNodeContents(installButton.querySelector(".command-text"));
      const selection = window.getSelection();
      selection.removeAllRanges();
      selection.addRange(range);
    }
  });
}
