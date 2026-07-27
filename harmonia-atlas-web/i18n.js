(() => {
  const supported = new Set(['zh-Hans', 'en']);
  const normalize = value => String(value || '').toLowerCase().startsWith('zh') ? 'zh-Hans' : 'en';
  const query = new URLSearchParams(location.search).get('lang');
  const saved = localStorage.getItem('harmoniaAtlasWebLanguage');
  const preferred = (navigator.languages && navigator.languages[0]) || navigator.language || 'en';
  const language = supported.has(query) ? query : supported.has(saved) ? saved : normalize(preferred);

  const apply = lang => {
    document.documentElement.dataset.activeLanguage = lang;
    document.documentElement.lang = lang === 'zh-Hans' ? 'zh-Hans' : 'en';
    document.querySelectorAll('[data-language-select]').forEach(select => { select.value = lang; });
    document.querySelectorAll('[data-title-zh][data-title-en]').forEach(element => {
      document.title = lang === 'zh-Hans' ? element.dataset.titleZh : element.dataset.titleEn;
    });
    localStorage.setItem('harmoniaAtlasWebLanguage', lang);
  };

  document.addEventListener('DOMContentLoaded', () => {
    apply(language);
    document.querySelectorAll('[data-language-select]').forEach(select => {
      select.addEventListener('change', event => apply(event.target.value));
    });
  });
})();
