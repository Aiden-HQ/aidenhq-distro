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

  /* Home hero: the live board */
  var board = document.querySelector('.board');
  if (board) heroBoard(board);

  function heroBoard(board) {
    var msgs = document.getElementById('msgs');
    var typing = document.getElementById('typing');
    var cards = document.getElementById('cards');
    var apprCount = document.getElementById('appr-count');
    var fleetCount = document.getElementById('fleet-count');
    var docNew = document.getElementById('doc-new');
    var COMMENT = '@Researcher add EU pricing to the table, from our price list.';

    function el(tag, cls, html) { var n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; }
    function add(m) { msgs.appendChild(m); while (msgs.children.length > 9) msgs.removeChild(msgs.firstChild); return m; }
    function act(color, who, text) { var m = el('div', 'msg act'); m.style.setProperty('--c', color); m.appendChild(el('b', null, null)).textContent = who; m.appendChild(document.createTextNode(' ' + text)); return add(m); }
    function note(cls, who, text) { var m = el('div', 'msg ' + cls); m.setAttribute('data-who', who); m.textContent = text; return add(m); }
    function sys(text) { var m = el('div', 'msg sys'); m.textContent = text; return add(m); }
    function lane(k, status, pct, on) {
      var li = board.querySelector('.lanes [data-k="' + k + '"]');
      li.querySelector('small').textContent = status;
      li.querySelector('.bar i').style.width = (pct || 0) + '%';
      li.classList.toggle('on', !!on);
      fleetCount.textContent = board.querySelectorAll('.lanes li.on').length + ' working';
    }
    function chip(cls, text) { return '<span class="chip' + (cls ? ' ' + cls : '') + '">' + text + '</span>'; }
    function card(tier, title, sub, right) {
      var c = el('div', 'card ' + tier, '<div class="card-t"><b></b><small></small></div><div class="card-r">' + right + '</div>');
      c.querySelector('b').textContent = title; c.querySelector('small').textContent = sub;
      cards.insertBefore(c, cards.firstChild);
      var all = cards.querySelectorAll('.card:not(.leaving)');
      for (var i = 3; i < all.length; i++) {
        (function (old) { old.classList.add('leaving'); setTimeout(function () { old.remove(); }, 400); })(all[i]);
      }
      return c;
    }
    function setRight(c, html) { c.querySelector('.card-r').innerHTML = html; }

    function initial() {
      msgs.innerHTML = ''; cards.innerHTML = ''; typing.textContent = ''; docNew.classList.remove('on');
      sys('Overnight');
      act('var(--teal)', 'DevOps Engineer', 'rolled back a bad release and shipped the fix');
      act('var(--pink)', 'Follow-up Tracker', 'chased Sam: launch date confirmed');
      lane('eng', 'Building the sign-up flow', 40, true); lane('ops', 'Watching 6 apps', 0); lane('fu', 'Chasing 2 replies', 55, true); lane('res', 'Comparing regional prices', 30, true);
      card('t0', 'Update the launch checklist', 'Safe, ran by itself', chip('', 'Ran'));
      card('t1', 'Merge PR #42, checks green', 'Checked by a second AI', chip('', 'Approved'));
      apprCount.textContent = 'All clear';
    }
    function finalFrame() {
      initial();
      sys('Today');
      note('cmt', 'You', COMMENT);
      note('rep', 'Researcher', 'Added EU at €11 from the price list. Resolved.');
      docNew.classList.add('on');
      act('var(--violet)', 'Engineer', 'shipped the sign-up flow');
      lane('eng', 'Shipped the sign-up flow', 100); lane('ops', 'Watching 7 apps', 100, true); lane('fu', 'Waiting on 1 reply', 80, true); lane('res', 'Table updated', 100);
      card('t1', 'Deploy signup v1', 'Checked by a second AI', chip('', 'Approved'));
      card('t2', 'Email the launch note to 14 customers', 'You decide', chip('', 'You approved'));
    }

    if (reduce) { finalFrame(); return; }
    var wait = waiter(board);
    async function type(text) {
      for (var i = 1; i <= text.length; i++) { typing.textContent = text.slice(0, i); await wait(text[i - 1] === ' ' ? 34 : 22); }
    }
    async function review(c) {
      apprCount.textContent = '1 in review';
      await wait(1400);
      setRight(c, chip('', 'Approved'));
      apprCount.textContent = 'All clear';
    }

    async function run() {
      initial();
      await wait(1600);
      lane('eng', 'Opened PR #43: sign-up flow', 100, true);
      await wait(1000);
      sys('Today');
      await type(COMMENT);
      await wait(300);
      typing.textContent = '';
      note('cmt', 'You', COMMENT);
      await wait(700);
      lane('res', 'Editing Launch plan', 70, true);
      await wait(1500);
      docNew.classList.add('on');
      note('rep', 'Researcher', 'Added EU at €11 from the price list. Resolved.');
      lane('res', 'Table updated', 100, false);
      await wait(1000);
      lane('eng', 'Shipped the sign-up flow', 100, false);
      lane('ops', 'Deploying signup v1', 100, true);
      await review(card('t1', 'Deploy signup v1', 'Checked by a second AI', chip('shimmer', 'Reviewing')));
      act('var(--violet)', 'Engineer', 'shipped the sign-up flow');
      lane('ops', 'Watching 7 apps', 100, true);
      await wait(700);
      var c = card('t2', 'Email the launch note to 14 customers', 'You decide', '<span class="tap-btn">Approve</span>');
      apprCount.textContent = '1 needs you';
      lane('fu', 'Drafted the launch note', 100, true);
      await wait(1900);
      c.querySelector('.tap-btn').classList.add('tapped');
      await wait(600);
      setRight(c, chip('', 'You approved'));
      apprCount.textContent = 'All clear';
      act('var(--pink)', 'Follow-up Tracker', 'sent the launch note; tracking replies');
      lane('fu', 'Waiting on 1 reply', 80, true);
      await wait(5000);
      board.classList.add('resetting');
      await wait(500);
      board.classList.remove('resetting');
      run();
    }
    run();
  }
})();
