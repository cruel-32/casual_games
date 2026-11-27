/* Small Party World 안내 페이지 공용: 좌우로 넘기는 슬라이드 (페이지가 세로로 너무 길어지지 않게)
 *
 *   <div data-slides>                 자식 하나하나가 슬라이드. data-title 이 있으면 위에 탭으로 보여 줌
 *   <div data-slides="dots">          탭 없이 아래 점만 (사진 넘기기 등)
 *   <main data-pages="all">           h2 마다 한 쪽으로 나눔 (약관·방침처럼 긴 글). h2 앞 내용은 그대로 위에. "all" 이면 '전체 보기' 단추
 *
 * 넘기기: 탭·좌우 단추·점·손가락 밀기·키보드 ←→. 주소의 #아이디가 어느 슬라이드 안에 있으면 그 슬라이드를 먼저 연다
 * 자바스크립트가 꺼져 있으면 아무것도 바뀌지 않고 원래대로 모두 펼쳐 보인다 (검색·스토어 심사에도 내용은 그대로 HTML 에 있음)
 * 높이: 지금 보이는 슬라이드 높이만 차지한다 (가장 긴 슬라이드에 맞춰 늘어나지 않음)
 */
(function () {
  var CSS = "" +
    ".sw{position:relative}" +
    ".sw-tabs{display:flex;gap:8px;overflow-x:auto;padding:4px 2px 12px;margin:0 0 6px;scrollbar-width:thin;-webkit-overflow-scrolling:touch}" +
    ".sw-tabs.center{justify-content:center}" +
    ".sw-tab{flex:0 0 auto;font:inherit;font-family:'Jua',system-ui,sans-serif;font-size:16px;cursor:pointer;border:2.5px solid #1d3557;background:#fffdf6;color:#1d3557;border-radius:999px;padding:6px 16px 7px;box-shadow:3px 3px 0 rgba(29,53,87,.18);white-space:nowrap}" +
    ".sw-tab[aria-selected=true]{background:#1d3557;color:#fff7e8}" +
    ".sw-view{overflow:hidden;touch-action:pan-y}" +
    ".sw-slide[hidden]{display:none!important}" +
    ".sw-in-r{animation:swInR .28s ease}.sw-in-l{animation:swInL .28s ease}" +
    "@keyframes swInR{from{opacity:0;transform:translateX(40px)}to{opacity:1;transform:none}}" +
    "@keyframes swInL{from{opacity:0;transform:translateX(-40px)}to{opacity:1;transform:none}}" +
    ".sw-bar{display:flex;align-items:center;justify-content:center;gap:14px;margin-top:16px}" +
    ".sw-btn{font:inherit;font-family:'Jua',system-ui,sans-serif;font-size:18px;cursor:pointer;min-width:46px;height:46px;padding:0 14px;border-radius:999px;border:3px solid #1d3557;background:#ffb703;color:#1d3557;box-shadow:3px 3px 0 rgba(29,53,87,.22)}" +
    ".sw-btn:disabled{opacity:.35;cursor:default}" +
    ".sw-dots{display:flex;gap:8px;align-items:center}" +
    ".sw-dot{width:12px;height:12px;border-radius:50%;border:2px solid #1d3557;background:transparent;padding:0;cursor:pointer}" +
    ".sw-dot[aria-selected=true]{background:#1d3557}" +
    ".sw-count{font-family:'Jua',system-ui,sans-serif;font-size:17px;min-width:64px;text-align:center}" +
    ".sw-all{font:inherit;font-size:14px;cursor:pointer;background:none;border:none;color:#457b9d;text-decoration:underline;margin-left:6px}" +
    ".sw.sw-open .sw-slide{display:block!important}.sw.sw-open .sw-tabs,.sw.sw-open .sw-arrows{display:none}" +
    ".sw-mini .sw-btn{min-width:38px;height:38px;font-size:16px}" +
    "@media print{.sw-tabs,.sw-bar{display:none}.sw-slide{display:block!important}}";

  function el(tag, cls, text) {
    var e = document.createElement(tag);
    if (cls) e.className = cls;
    if (text != null) e.textContent = text;
    return e;
  }

  // container 안에 slides 를 넣고 탭·단추를 단다
  function make(root, slides, opt) {
    if (slides.length < 2) return;
    root.classList.add("sw");
    if (opt.mini) root.classList.add("sw-mini");
    var cur = 0;
    var tabs = [], dots = [];
    var tabBar = null;
    if (opt.tabs) {
      tabBar = el("div", "sw-tabs" + (opt.center ? " center" : ""));
      tabBar.setAttribute("role", "tablist");
      slides.forEach(function (s, i) {
        var t = el("button", "sw-tab", s.getAttribute("data-title") || String(i + 1));
        t.type = "button";
        t.setAttribute("role", "tab");
        t.addEventListener("click", function () { go(i); });
        tabBar.appendChild(t);
        tabs.push(t);
      });
    }
    var view = el("div", "sw-view");
    slides.forEach(function (s) { s.classList.add("sw-slide"); view.appendChild(s); });
    var bar = el("div", "sw-bar");
    var arrows = el("div", "sw-bar sw-arrows");
    arrows.style.margin = "0";
    var prev = el("button", "sw-btn", "◀");
    prev.type = "button";
    prev.setAttribute("aria-label", "이전");
    var next = el("button", "sw-btn", "▶");
    next.type = "button";
    next.setAttribute("aria-label", "다음");
    var mid;
    if (opt.count) {
      mid = el("span", "sw-count");
    } else {
      mid = el("div", "sw-dots");
      slides.forEach(function (s, i) {
        var d = el("button", "sw-dot");
        d.type = "button";
        d.setAttribute("aria-label", (s.getAttribute("data-title") || "") + " " + (i + 1));
        d.addEventListener("click", function () { go(i); });
        mid.appendChild(d);
        dots.push(d);
      });
    }
    prev.addEventListener("click", function () { go(cur - 1); });
    next.addEventListener("click", function () { go(cur + 1); });
    arrows.appendChild(prev); arrows.appendChild(mid); arrows.appendChild(next);
    bar.appendChild(arrows);
    if (opt.all) {
      var all = el("button", "sw-all", "전체 보기");
      all.type = "button";
      all.addEventListener("click", function () {
        var open = root.classList.toggle("sw-open");
        all.textContent = open ? "한 쪽씩 보기" : "전체 보기";
        if (!open) go(cur, true);
      });
      bar.appendChild(all);
    }
    if (tabBar) root.appendChild(tabBar);
    root.appendChild(view);
    root.appendChild(bar);

    function go(i, quiet) {
      i = Math.max(0, Math.min(slides.length - 1, i));
      var dir = i >= cur ? "sw-in-r" : "sw-in-l";
      slides.forEach(function (s, k) {
        s.hidden = k !== i;
        s.classList.remove("sw-in-r", "sw-in-l");
      });
      if (!quiet && i !== cur) {
        void slides[i].offsetWidth;
        slides[i].classList.add(dir);
      }
      tabs.forEach(function (t, k) { t.setAttribute("aria-selected", k === i ? "true" : "false"); });
      dots.forEach(function (d, k) { d.setAttribute("aria-selected", k === i ? "true" : "false"); });
      if (opt.count) mid.textContent = (i + 1) + " / " + slides.length;
      prev.disabled = i === 0;
      next.disabled = i === slides.length - 1;
      if (tabs[i] && tabBar) {
        var t = tabs[i];
        tabBar.scrollLeft = t.offsetLeft - (tabBar.clientWidth - t.offsetWidth) / 2;
      }
      // 긴 글 쪽을 넘기면 그 쪽 처음이 보이도록 (탭 바로 위로)
      if (!quiet && opt.scrollTop) {
        var top = root.getBoundingClientRect().top + window.pageYOffset - 70;
        if (window.pageYOffset > top) window.scrollTo({ top: top, behavior: "smooth" });
      }
      cur = i;
    }

    // 손가락으로 밀기 (가로로 충분히 밀었을 때만, 세로 스크롤은 방해하지 않음)
    var sx = 0, sy = 0, tracking = false;
    view.addEventListener("touchstart", function (e) {
      if (e.touches.length !== 1) return;
      sx = e.touches[0].clientX; sy = e.touches[0].clientY; tracking = true;
    }, { passive: true });
    view.addEventListener("touchend", function (e) {
      if (!tracking) return;
      tracking = false;
      var t = e.changedTouches[0];
      var dx = t.clientX - sx, dy = t.clientY - sy;
      if (Math.abs(dx) > 50 && Math.abs(dx) > Math.abs(dy) * 1.5) {
        e.stopPropagation();          // 안쪽 슬라이드(사진)를 밀면 바깥은 그대로
        go(cur + (dx < 0 ? 1 : -1));
      }
    });
    root.tabIndex = -1;
    root.addEventListener("keydown", function (e) {
      if (e.target.closest && e.target.closest("input,textarea,select")) return;
      if (e.key === "ArrowRight") { go(cur + 1); e.preventDefault(); }
      if (e.key === "ArrowLeft") { go(cur - 1); e.preventDefault(); }
    });
    root._swGo = go;
    root._swSlides = slides;
    go(0, true);
  }

  // h2 마다 한 쪽: [h2, 그다음 형제들…] 을 div 로 묶는다
  function pages(main, opt) {
    var kids = Array.prototype.slice.call(main.children);
    var first = -1;
    for (var i = 0; i < kids.length; i++) if (kids[i].tagName === "H2") { first = i; break; }
    if (first < 0) return;
    var holder = el("div");
    main.insertBefore(holder, kids[first]);
    var slides = [], curSlide = null;
    for (var j = first; j < kids.length; j++) {
      var k = kids[j];
      if (k.tagName === "H2") {
        curSlide = el("section");
        curSlide.setAttribute("data-title", k.textContent.replace(/\s+/g, " ").trim());
        slides.push(curSlide);
      }
      curSlide.appendChild(k);
    }
    make(holder, slides, { tabs: true, count: true, all: opt === "all", scrollTop: true });
  }

  function openHash() {
    var id = decodeURIComponent((location.hash || "").slice(1));
    if (!id) return;
    var t = document.getElementById(id);
    if (!t) return;
    // 바깥 슬라이드부터 안쪽까지 차례로 연다
    var chain = [];
    for (var n = t; n; n = n.parentElement) {
      if (n.classList && n.classList.contains("sw-slide")) chain.unshift(n);
    }
    chain.forEach(function (s) {
      var root = s.parentElement.parentElement;      // .sw-view 의 부모
      if (root && root._swGo) root._swGo(root._swSlides.indexOf(s), true);
    });
    if (chain.length) setTimeout(function () { t.scrollIntoView({ block: "start" }); }, 0);
  }

  function init() {
    var st = document.createElement("style");
    st.textContent = CSS;
    document.head.appendChild(st);
    // 안쪽(사진)부터 만든다 — 바깥 슬라이드를 만들 때 안쪽은 이미 정리돼 있게
    var list = Array.prototype.slice.call(document.querySelectorAll("[data-slides]")).reverse();
    list.forEach(function (c) {
      var mode = c.getAttribute("data-slides");
      var slides = Array.prototype.slice.call(c.children);
      make(c, slides, { tabs: mode !== "dots", dots: true, mini: mode === "dots", center: true });
    });
    Array.prototype.forEach.call(document.querySelectorAll("[data-pages]"), function (m) {
      pages(m, m.getAttribute("data-pages"));
    });
    openHash();
    window.addEventListener("hashchange", openHash);
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();
