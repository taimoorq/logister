const DEFAULT_RESULT_LIMIT = 6;
const MINIMUM_QUERY_LENGTH = 2;

export function normalizeSearchQuery(value) {
  return String(value || "").replace(/\s+/g, " ").trim();
}

export function pagefindDataToSuggestion(data) {
  if (!data || typeof data !== "object") return null;

  const pageTitle = String(data.meta?.title || "")
    .replace(/\s+[|–—-]\s+Logister\s*$/i, "")
    .trim();
  const section = Array.isArray(data.sub_results)
    ? data.sub_results.find((result) => result?.title && result?.url)
    : null;
  const title = String(section?.title || pageTitle || "Documentation").trim();
  const url = String(section?.url || data.url || "").trim();

  if (!url) return null;

  return {
    title,
    context: section && pageTitle && pageTitle !== title ? pageTitle : "",
    excerpt: String(section?.plain_excerpt || data.plain_excerpt || "").trim(),
    url
  };
}

export function highlightedSearchSegments(value, query) {
  const text = String(value || "");
  const terms = [...new Set(
    normalizeSearchQuery(query)
      .split(" ")
      .map((term) => term.trim())
      .filter((term) => term.length >= MINIMUM_QUERY_LENGTH)
  )].sort((left, right) => right.length - left.length);

  if (!text || terms.length === 0) return [{ text, highlighted: false }];

  const escapedTerms = terms.map((term) => term.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"));
  const matcher = new RegExp(`(${escapedTerms.join("|")})`, "giu");

  return text
    .split(matcher)
    .filter(Boolean)
    .map((segment) => ({
      text: segment,
      highlighted: terms.some((term) => term.toLocaleLowerCase() === segment.toLocaleLowerCase())
    }));
}

export function initDocsSearch({
  element,
  pagefindUrl,
  resultLimit = DEFAULT_RESULT_LIMIT
}) {
  if (!element || !pagefindUrl || element.dataset.searchEnhanced === "true") return;

  const isMac = /Mac|iPhone|iPad/.test(navigator.platform || navigator.userAgent || "");
  const shortcutLabel = isMac ? "⌘K" : "Ctrl K";

  element.innerHTML = `
    <form class="docs-search-form" role="search">
      <label class="docs-search-label" for="docs-search-input">Search Logister documentation</label>
      <span class="docs-search-icon" aria-hidden="true">
        <svg viewBox="0 0 20 20" focusable="false">
          <path d="m14.2 13 3.4 3.4-1.2 1.2-3.4-3.4a6.5 6.5 0 1 1 1.2-1.2Zm-5.7 1A4.8 4.8 0 1 0 8.5 4a4.8 4.8 0 0 0 0 9.7Z"></path>
        </svg>
      </span>
      <input
        id="docs-search-input"
        class="docs-search-input"
        type="search"
        placeholder="Search docs"
        autocomplete="off"
        autocapitalize="none"
        spellcheck="false"
        role="combobox"
        aria-autocomplete="list"
        aria-controls="docs-search-options"
        aria-expanded="false"
      >
      <span class="docs-search-shortcut" aria-hidden="true">${shortcutLabel}</span>
      <button class="docs-search-clear" type="button" aria-label="Clear search" hidden>
        <span aria-hidden="true">×</span>
      </button>
    </form>
    <div class="docs-search-popover" data-search-popover hidden>
      <div class="docs-search-popover-header">
        <span>Suggested pages</span>
        <span data-search-count></span>
      </div>
      <ul id="docs-search-options" class="docs-search-results" role="listbox"></ul>
      <p class="docs-search-empty" data-search-empty hidden></p>
      <div class="docs-search-popover-footer" aria-hidden="true">
        <span><kbd>↑</kbd><kbd>↓</kbd> Navigate</span>
        <span><kbd>↵</kbd> Open</span>
        <span><kbd>Esc</kbd> Close</span>
      </div>
    </div>
    <p class="docs-search-status" aria-live="polite" aria-atomic="true"></p>
  `;
  element.dataset.searchEnhanced = "true";

  const form = element.querySelector(".docs-search-form");
  const input = element.querySelector(".docs-search-input");
  const shortcut = element.querySelector(".docs-search-shortcut");
  const clearButton = element.querySelector(".docs-search-clear");
  const popover = element.querySelector("[data-search-popover]");
  const resultList = element.querySelector(".docs-search-results");
  const resultCount = element.querySelector("[data-search-count]");
  const emptyMessage = element.querySelector("[data-search-empty]");
  const liveStatus = element.querySelector(".docs-search-status");

  let pagefindPromise;
  let suggestions = [];
  let activeIndex = -1;
  let searchSequence = 0;

  const loadPagefind = () => {
    if (!pagefindPromise) {
      pagefindPromise = import(pagefindUrl).then(async (pagefind) => {
        await pagefind.options({
          baseUrl: "/",
          excerptLength: 22
        });
        return pagefind;
      });
    }

    return pagefindPromise;
  };

  const setPopoverOpen = (isOpen) => {
    popover.hidden = !isOpen;
    input.setAttribute("aria-expanded", String(isOpen));
    if (!isOpen) {
      input.removeAttribute("aria-activedescendant");
    }
  };

  const setActiveIndex = (nextIndex) => {
    if (suggestions.length === 0) {
      activeIndex = -1;
      input.removeAttribute("aria-activedescendant");
      return;
    }

    activeIndex = (nextIndex + suggestions.length) % suggestions.length;
    resultList.querySelectorAll('[role="option"]').forEach((option, index) => {
      const isActive = index === activeIndex;
      option.setAttribute("aria-selected", String(isActive));
      option.classList.toggle("is-active", isActive);
      if (isActive) {
        input.setAttribute("aria-activedescendant", option.id);
        option.scrollIntoView({ block: "nearest" });
      }
    });
  };

  const appendHighlightedText = (target, value, query) => {
    highlightedSearchSegments(value, query).forEach((segment) => {
      if (!segment.highlighted) {
        target.appendChild(document.createTextNode(segment.text));
        return;
      }

      const mark = document.createElement("mark");
      mark.textContent = segment.text;
      target.appendChild(mark);
    });
  };

  const renderSuggestions = (query) => {
    resultList.replaceChildren();
    emptyMessage.hidden = true;
    activeIndex = -1;
    input.removeAttribute("aria-activedescendant");

    suggestions.forEach((suggestion, index) => {
      const item = document.createElement("li");
      item.setAttribute("role", "presentation");

      const link = document.createElement("a");
      link.id = `docs-search-option-${index}`;
      link.className = "docs-search-result";
      link.href = suggestion.url;
      link.setAttribute("role", "option");
      link.setAttribute("aria-selected", "false");

      const heading = document.createElement("span");
      heading.className = "docs-search-result-heading";

      const title = document.createElement("strong");
      title.className = "docs-search-result-title";
      appendHighlightedText(title, suggestion.title, query);
      heading.appendChild(title);

      if (suggestion.context) {
        const context = document.createElement("span");
        context.className = "docs-search-result-context";
        context.textContent = suggestion.context;
        heading.appendChild(context);
      }

      const excerpt = document.createElement("span");
      excerpt.className = "docs-search-result-excerpt";
      appendHighlightedText(excerpt, suggestion.excerpt, query);

      const arrow = document.createElement("span");
      arrow.className = "docs-search-result-arrow";
      arrow.setAttribute("aria-hidden", "true");
      arrow.textContent = "↗";

      link.append(heading, excerpt, arrow);
      link.addEventListener("pointermove", () => setActiveIndex(index));
      link.addEventListener("focus", () => setActiveIndex(index));
      item.appendChild(link);
      resultList.appendChild(item);
    });

    const count = suggestions.length;
    resultCount.textContent = count === 1 ? "1 result" : `${count} results`;
    liveStatus.textContent = count === 0
      ? `No documentation matches ${query}.`
      : `${count} documentation suggestions available for ${query}.`;

    if (count === 0) {
      emptyMessage.textContent = `No pages found for “${query}”. Try a feature, setting, runtime, or error message.`;
      emptyMessage.hidden = false;
    }

    input.removeAttribute("aria-busy");
    setPopoverOpen(true);
  };

  const showMessage = (message, { busy = false } = {}) => {
    suggestions = [];
    activeIndex = -1;
    resultList.replaceChildren();
    resultCount.textContent = "";
    emptyMessage.textContent = message;
    emptyMessage.hidden = false;
    liveStatus.textContent = message;
    input.toggleAttribute("aria-busy", busy);
    setPopoverOpen(true);
  };

  const performSearch = async () => {
    const query = normalizeSearchQuery(input.value);
    shortcut.hidden = query.length > 0;
    clearButton.hidden = query.length === 0;

    if (query.length === 0) {
      searchSequence += 1;
      suggestions = [];
      liveStatus.textContent = "";
      input.removeAttribute("aria-busy");
      setPopoverOpen(false);
      return;
    }

    if (query.length < MINIMUM_QUERY_LENGTH) {
      searchSequence += 1;
      showMessage("Type one more character to search the documentation.");
      return;
    }

    const currentSequence = ++searchSequence;
    showMessage("Searching documentation…", { busy: true });

    try {
      const pagefind = await loadPagefind();
      const search = await pagefind.debouncedSearch(query, {}, 140);
      if (!search || currentSequence !== searchSequence) return;

      const data = await Promise.all(
        search.results.slice(0, resultLimit).map((result) => result.data())
      );
      if (currentSequence !== searchSequence) return;

      suggestions = data
        .map(pagefindDataToSuggestion)
        .filter(Boolean);
      renderSuggestions(query);
    } catch (_error) {
      if (currentSequence !== searchSequence) return;
      input.removeAttribute("aria-busy");
      showMessage("Search is temporarily unavailable. Reload the page and try again.");
    }
  };

  const openActiveSuggestion = () => {
    const index = activeIndex >= 0 ? activeIndex : 0;
    const suggestion = suggestions[index];
    if (suggestion) window.location.assign(suggestion.url);
  };

  input.addEventListener("focus", () => {
    void loadPagefind().catch(() => {});
    if (normalizeSearchQuery(input.value).length >= MINIMUM_QUERY_LENGTH) {
      setPopoverOpen(true);
    }
  });

  input.addEventListener("input", () => {
    void performSearch();
  });

  input.addEventListener("keydown", (event) => {
    if (event.key === "ArrowDown" && suggestions.length > 0) {
      event.preventDefault();
      setPopoverOpen(true);
      setActiveIndex(activeIndex + 1);
    } else if (event.key === "ArrowUp" && suggestions.length > 0) {
      event.preventDefault();
      setPopoverOpen(true);
      setActiveIndex(activeIndex <= 0 ? suggestions.length - 1 : activeIndex - 1);
    } else if (event.key === "Enter" && suggestions.length > 0) {
      event.preventDefault();
      openActiveSuggestion();
    } else if (event.key === "Escape" && !popover.hidden) {
      event.preventDefault();
      setPopoverOpen(false);
    }
  });

  form.addEventListener("submit", (event) => {
    event.preventDefault();
    openActiveSuggestion();
  });

  clearButton.addEventListener("click", () => {
    input.value = "";
    void performSearch();
    input.focus();
  });

  document.addEventListener("pointerdown", (event) => {
    if (!element.contains(event.target)) setPopoverOpen(false);
  });

  element.addEventListener("focusout", () => {
    window.setTimeout(() => {
      if (!element.contains(document.activeElement)) setPopoverOpen(false);
    }, 0);
  });

  document.addEventListener("keydown", (event) => {
    const target = event.target;
    const isEditable = target instanceof HTMLElement && (
      target.isContentEditable ||
      target.matches("input, textarea, select")
    );
    const isSearchShortcut = event.key === "/" && !event.metaKey && !event.ctrlKey && !event.altKey;
    const isCommandShortcut = event.key.toLocaleLowerCase() === "k" && (event.metaKey || event.ctrlKey);

    if ((isSearchShortcut && !isEditable) || isCommandShortcut) {
      event.preventDefault();
      input.focus();
      input.select();
    }
  });
}
