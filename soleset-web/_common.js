// 自动语言检测：优先 URL ?lang=，其次本地存储，最后浏览器语言。页面只渲染单一语言。
(function () {
  var saved = null;
  try { saved = localStorage.getItem('soleset-lang'); } catch (e) {}
  var url = new URLSearchParams(location.search).get('lang');
  var nav = (navigator.language || 'zh-CN').toLowerCase();
  var lang = url || saved || (nav.indexOf('zh') === 0 ? 'zh' : 'en');
  if (url) { try { localStorage.setItem('soleset-lang', lang); } catch (e) {} }
  document.documentElement.lang = lang === 'zh' ? 'zh-CN' : 'en';
  function toggle() {
    document.body.setAttribute('data-lang', lang);
    document.querySelectorAll('[data-zh]').forEach(function (el) {
      el.style.display = el.getAttribute('data-zh') === lang ? '' : 'none';
    });
    document.querySelectorAll('.lang-btn').forEach(function (b) {
      b.classList.toggle('active', b.getAttribute('data-lang-set') === lang);
    });
  }
  window.solesetSetLang = function (l) {
    lang = l;
    try { localStorage.setItem('soleset-lang', l); } catch (e) {}
    document.documentElement.lang = l === 'zh' ? 'zh-CN' : 'en';
    toggle();
  };
  document.addEventListener('DOMContentLoaded', toggle);
})();
