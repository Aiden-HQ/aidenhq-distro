(function () {
  'use strict';
  var root = document.documentElement;
  var reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;

  /* Theme toggle: the system setting drives by default; the button overrides it. */
  var themeBtn = document.querySelector('.theme-btn');
  if (themeBtn) themeBtn.addEventListener('click', function () {
    var dark = root.dataset.theme ? root.dataset.theme === 'dark' : matchMedia('(prefers-color-scheme: dark)').matches;
    root.dataset.theme = dark ? 'light' : 'dark';
    try { localStorage.setItem('ahq-theme', root.dataset.theme); } catch (e) {}
  });

  /* Nav: border once scrolled, grouped dropdowns, the phone menu, and the current page marked. */
  var nav = document.querySelector('.nav');
  var onScroll = function () { nav.classList.toggle('scrolled', window.scrollY > 8); };
  window.addEventListener('scroll', onScroll, { passive: true }); onScroll();
  var groups = document.querySelectorAll('.grp');
  function closeGroups(except) {
    groups.forEach(function (g) { if (g !== except) { g.classList.remove('open'); g.querySelector('.grp-btn').setAttribute('aria-expanded', 'false'); } });
  }
  groups.forEach(function (g) {
    var b = g.querySelector('.grp-btn');
    b.addEventListener('click', function (e) {
      e.stopPropagation();
      var open = !g.classList.contains('open');
      closeGroups(g); g.classList.toggle('open', open); b.setAttribute('aria-expanded', String(open));
    });
  });
  document.addEventListener('click', function (e) { if (!e.target.closest('.grp')) closeGroups(); });
  document.addEventListener('keydown', function (e) {
    if (e.key === 'Escape') { closeGroups(); nav.classList.remove('menu-open'); if (burger) burger.setAttribute('aria-expanded', 'false'); }
  });
  var burger = document.querySelector('.burger');
  if (burger) burger.addEventListener('click', function () {
    var open = nav.classList.toggle('menu-open');
    burger.setAttribute('aria-expanded', String(open));
    burger.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  });
  document.querySelectorAll('.menu-bar a').forEach(function (a) {
    a.addEventListener('click', function () {
      closeGroups(); nav.classList.remove('menu-open');
      if (burger) { burger.setAttribute('aria-expanded', 'false'); burger.setAttribute('aria-label', 'Open menu'); }
    });
  });
  var here = location.pathname.replace(/index\.html$/, '');
  document.querySelectorAll('.menu-bar .drop a').forEach(function (a) {
    var u = new URL(a.href, location.href);
    if (u.origin === location.origin && !u.hash && u.pathname === here) {
      a.setAttribute('aria-current', 'page'); a.closest('.grp').classList.add('cur');
    }
  });

  /* Copy buttons */
  document.querySelectorAll('.copy').forEach(function (b) {
    b.addEventListener('click', function () {
      var text = b.getAttribute('data-copy');
      var done = function () {
        var label = b.querySelector('.copy-label');
        b.classList.add('done'); if (label) label.textContent = 'Copied';
        b.setAttribute('aria-label', 'Copied');
        setTimeout(function () { b.classList.remove('done'); if (label) label.textContent = 'Copy'; b.setAttribute('aria-label', 'Copy'); }, 1800);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(text).then(done, done); else done();
    });
  });

  /* Copy prompt for your agent: a one-line instruction that points the agent at /prompt.md. */
  document.querySelectorAll('[data-prompt]').forEach(function (b) {
    var label = b.querySelector('.agent-label');
    b.addEventListener('click', function () {
      var done = function () {
        b.classList.add('done'); label.textContent = 'Copied, paste it into your agent';
        setTimeout(function () { b.classList.remove('done'); label.textContent = 'Copy prompt for your agent'; }, 2600);
      };
      if (navigator.clipboard) navigator.clipboard.writeText(b.getAttribute('data-prompt')).then(done, done); else done();
    });
  });

  /* Scroll reveals */
  var reveals = document.querySelectorAll('.reveal');
  if (reduce || !('IntersectionObserver' in window)) {
    reveals.forEach(function (el) { el.classList.add('in'); });
  } else {
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (e) { if (e.isIntersecting) { e.target.classList.add('in'); io.unobserve(e.target); } });
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach(function (el) { io.observe(el); });
    var atEnd = function () {
      if (window.innerHeight + window.scrollY >= document.documentElement.scrollHeight - 60) {
        reveals.forEach(function (el) { el.classList.add('in'); });
        window.removeEventListener('scroll', atEnd);
      }
    };
    window.addEventListener('scroll', atEnd, { passive: true });
  }

  /* A wait that only counts down while the element is on screen and the tab is visible. */
  function waiter(el) {
    var visible = { v: false };
    if ('IntersectionObserver' in window) new IntersectionObserver(function (e) { visible.v = e[0].isIntersecting; }).observe(el);
    else visible.v = true;
    return function (ms) {
      return new Promise(function (res) {
        var left = ms, last = performance.now();
        (function tick(now) {
          if (!document.hidden && visible.v) left -= (now - last);
          last = now;
          if (left <= 0) res(); else requestAnimationFrame(tick);
        })(last);
      });
    };
  }

  /* Scenes: data-steps lists the wait before each step; the last number is how long the final frame holds.
     Each step adds class sN (cumulative); reduced motion shows the final frame only. */
  document.querySelectorAll('.sc[data-steps]').forEach(function (sc) {
    var steps = sc.getAttribute('data-steps').split(',').map(Number);
    var n = steps.length - 1;
    function set(k) { for (var i = 1; i <= n; i++) sc.classList.toggle('s' + i, i <= k); }
    if (reduce) { set(n); return; }
    var wait = waiter(sc);
    (async function loop() {
      for (;;) {
        set(0);
        for (var i = 1; i <= n; i++) { await wait(steps[i - 1]); set(i); }
        await wait(steps[n]);
        sc.classList.add('resetting'); await wait(450); set(0); sc.classList.remove('resetting');
      }
    })();
  });

  /* Home hero: messages arrive, Aiden sets the noise aside and the rest lands under "Needs you today".
     Without JS, or with reduced motion, the finished state shows. */
  var demo = document.getElementById('demo');
  if (demo && !reduce) (function () {
    var rows = demo.querySelectorAll('.h-stream li'), items = demo.querySelectorAll('.h-items li');
    var say = demo.querySelector('.h-say'), seen = document.getElementById('d-seen'), kept = document.getElementById('d-kept');
    var wait = waiter(demo);
    demo.classList.add('play');
    (async function loop() {
      for (;;) {
        var n = 0, k = 0;
        seen.textContent = '0'; kept.textContent = '0';
        await wait(500);
        for (var i = 0; i < rows.length; i++) {
          var r = rows[i];
          r.classList.add('on'); seen.textContent = String(++n);
          await wait(420);
          r.classList.add('sorted');
          if (r.classList.contains('keep')) {
            items[+r.getAttribute('data-item')].classList.add('on'); kept.textContent = String(++k);
            await wait(520);
          } else await wait(220);
        }
        await wait(300); say.classList.add('on');
        await wait(6500);
        demo.style.opacity = '.0'; demo.style.transition = 'opacity .4s';
        await wait(420);
        rows.forEach(function (r) { r.classList.remove('on', 'sorted'); });
        items.forEach(function (it) { it.classList.remove('on'); }); say.classList.remove('on');
        demo.style.opacity = '';
        await wait(400);
      }
    })();
  })();

  /* Home: example agents as tabs (arrow keys move between them). */
  var jobs = document.querySelector('.h-jobs');
  if (jobs) (function () {
    var tabs = Array.prototype.slice.call(jobs.querySelectorAll('[role="tab"]'));
    function pick(t, focus) {
      tabs.forEach(function (x) {
        var on = x === t;
        x.setAttribute('aria-selected', String(on)); x.tabIndex = on ? 0 : -1;
        document.getElementById(x.getAttribute('aria-controls')).classList.toggle('on', on);
      });
      if (focus) t.focus();
    }
    tabs.forEach(function (t, i) {
      t.tabIndex = i ? -1 : 0;
      t.addEventListener('click', function () { pick(t); });
      t.addEventListener('keydown', function (e) {
        var d = { ArrowDown: 1, ArrowRight: 1, ArrowUp: -1, ArrowLeft: -1 }[e.key];
        if (d) { e.preventDefault(); pick(tabs[(i + d + tabs.length) % tabs.length], true); }
      });
    });
  })();
})();

/* Modules marketplace: filter by search and category tab, and open a module's detail dialog. */
(function () {
  'use strict';
  var q = document.getElementById('mk-q');
  var dlg = document.getElementById('mk-dlg');
  if (!q || !dlg) return;
  var cards = document.querySelectorAll('.mg .mc');
  var groups = document.querySelectorAll('.mg');
  var tabs = document.querySelectorAll('.mt');
  var featured = document.getElementById('mk-featured');
  var empty = document.getElementById('mk-empty');
  var cat = 'all';
  function apply() {
    var term = q.value.trim().toLowerCase();
    var shown = 0;
    cards.forEach(function (c) {
      var ok = (cat === 'all' || c.dataset.cat === cat) && (!term || c.dataset.q.indexOf(term) !== -1);
      c.hidden = !ok; if (ok) shown++;
    });
    groups.forEach(function (g) { g.hidden = !g.querySelector('.mc:not([hidden])'); });
    featured.hidden = cat !== 'all' || !!term;
    empty.textContent = shown ? '' : 'No module matches. Try a tool name such as Slack, or an agent such as Engineer.';
  }
  tabs.forEach(function (t) {
    t.addEventListener('click', function (e) {
      e.preventDefault();
      cat = t.dataset.cat;
      tabs.forEach(function (x) { var on = x === t; x.classList.toggle('on', on); if (on) x.setAttribute('aria-current', 'true'); else x.removeAttribute('aria-current'); });
      apply();
    });
  });
  q.addEventListener('input', apply);
  var body = document.getElementById('mk-dlg-b');
  document.querySelectorAll('.mc').forEach(function (c) {
    c.querySelector('.mc-btn').addEventListener('click', function () {
      body.innerHTML = '<span class="pi"><svg viewBox="0 0 24 24" aria-hidden="true">' + c.querySelector('.pi svg').innerHTML + '</svg></span><h3 id="mk-dlg-t">' + c.querySelector('h3').innerHTML + '</h3>' + c.querySelector('.mc-more').innerHTML;
      dlg.style.setProperty('--c', getComputedStyle(c).getPropertyValue('--c'));
      dlg.showModal();
    });
  });
  dlg.addEventListener('click', function (e) { if (e.target === dlg || e.target.closest('.mk-x')) dlg.close(); });
})();
