// Minimal EN/TR switcher. Each page defines window.I18N = { en: {...}, tr: {...} }.
// Elements use data-i18n="key" (text) or data-i18n-html="key" (trusted markup from the page itself).
(function () {
  const STORAGE_KEY = "macos-apps-lang";
  const supported = ["en", "tr"];

  function storedLang() {
    try { return localStorage.getItem(STORAGE_KEY); } catch (e) { return null; }
  }

  function saveLang(lang) {
    try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) { /* private mode */ }
  }

  function initialLang() {
    const fromUrl = new URLSearchParams(location.search).get("lang");
    if (supported.includes(fromUrl)) return fromUrl;
    const stored = storedLang();
    if (supported.includes(stored)) return stored;
    return (navigator.language || "en").toLowerCase().startsWith("tr") ? "tr" : "en";
  }

  function apply(lang) {
    const dict = (window.I18N && window.I18N[lang]) || {};
    document.documentElement.lang = lang;
    document.querySelectorAll("[data-i18n]").forEach((el) => {
      const value = dict[el.dataset.i18n];
      if (value !== undefined) el.textContent = value;
    });
    document.querySelectorAll("[data-i18n-html]").forEach((el) => {
      const value = dict[el.dataset.i18nHtml];
      if (value !== undefined) el.innerHTML = value;
    });
    if (dict["meta.title"]) document.title = dict["meta.title"];
    const description = document.querySelector('meta[name="description"]');
    if (description && dict["meta.description"]) description.setAttribute("content", dict["meta.description"]);
    document.querySelectorAll(".lang-toggle button").forEach((button) => {
      button.setAttribute("aria-pressed", String(button.dataset.lang === lang));
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    document.querySelectorAll(".lang-toggle button").forEach((button) => {
      button.addEventListener("click", () => {
        saveLang(button.dataset.lang);
        apply(button.dataset.lang);
      });
    });
    apply(initialLang());
  });
})();
