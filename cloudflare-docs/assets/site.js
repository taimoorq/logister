document.addEventListener("DOMContentLoaded", () => {
  const navToggle = document.querySelector("[data-nav-toggle]");
  const navPanel = document.querySelector("[data-nav-panel]");

  if (navToggle && navPanel) {
    navToggle.addEventListener("click", () => {
      const expanded = navToggle.getAttribute("aria-expanded") === "true";
      navToggle.setAttribute("aria-expanded", String(!expanded));
      navPanel.classList.toggle("is-open", !expanded);
    });
  }

  document.querySelectorAll("[data-copy-button]").forEach((button) => {
    button.addEventListener("click", async () => {
      const selector = button.getAttribute("data-copy-target");
      const source = selector ? document.querySelector(selector) : button.closest(".code-block")?.querySelector("code");
      if (!source) return;

      const original = button.textContent;
      try {
        await navigator.clipboard.writeText(source.textContent || "");
        button.textContent = "Copied";
        button.classList.add("is-copied");
      } catch (_error) {
        button.textContent = "Failed";
        button.classList.add("is-failed");
      }

      window.setTimeout(() => {
        button.textContent = original;
        button.classList.remove("is-copied", "is-failed");
      }, 1500);
    });
  });
});
