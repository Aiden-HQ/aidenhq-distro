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

  /* Nav border once scrolled */
  var nav = document.querySelector('.nav');
  var onScroll = function () { nav.classList.toggle('scrolled', window.scrollY > 8); };
  window.addEventListener('scroll', onScroll, { passive: true }); onScroll();

  /* Copy buttons */
  document.querySelectorAll('.copy').forEach(function (b) {
    b.addEventListener('click', function () {
      var text = b.getAttribute('data-copy');
      var done = function () {
        var label = b.querySelector('.copy-label');
        b.classList.add('done'); if (label) label.textContent = 'Copied';
        b.setAttribute('aria-label', 'Copied');
        setTimeout(function () { b.classList.remove('done'); if (label) label.textContent = 'Copy'; b.setAttribute('aria-label', 'Copy install command'); }, 1800);
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

  /* Module catalog filter */
  var catTabs = document.querySelectorAll('.cat-tabs button');
  var catItems = document.querySelectorAll('.cat-list li');
  catTabs.forEach(function (t) {
    t.addEventListener('click', function () {
      catTabs.forEach(function (o) { o.setAttribute('aria-pressed', String(o === t)); });
      catItems.forEach(function (li) { li.hidden = t.dataset.f !== 'all' && li.dataset.t !== t.dataset.f; });
    });
  });

  /* Hero: the live board */
  var board = document.querySelector('.board');
  if (!board) return;
  var msgs = document.getElementById('msgs');
  var typing = document.getElementById('typing');
  var cards = document.getElementById('cards');
  var apprCount = document.getElementById('appr-count');
  var fleetCount = document.getElementById('fleet-count');
  var ASK = 'Build a tracker for every open PR at acme and chase stale ones.';
  var REPLY = 'On it. The Agent Architect is planning it and an Engineer will build it.';
  var PROGRESS = 'PR #42 passed CI and AI review. DevOps is deploying it now.';
  var SHIPPED = 'Shipped. Live at <span class="lnk">prs.acme.example.com</span> · 14 PRs tracked, 3 owners nudged.';

  function el(tag, cls, html) { var n = document.createElement(tag); if (cls) n.className = cls; if (html != null) n.innerHTML = html; return n; }
  function say(cls, text, html) { var m = el('div', 'msg ' + cls); if (html) m.innerHTML = html; else m.textContent = text; msgs.appendChild(m); while (msgs.children.length > 11) msgs.removeChild(msgs.firstChild); return m; }
  function history() {
    say('sys', 'Monday');
    say('me', "Prep me for Thursday's board meeting.");
    say('them', "Done. Deck notes, open risks and last quarter's numbers are in your brief.");
    say('sys', 'Yesterday');
    say('me', 'Chase the vendor contract and tell me by Friday.');
    say('them', 'Done. The signed redlines are filed in Drive.');
    say('sys', 'Today 08:00');
    say('them', 'Morning brief: 3 replies chased, 1 PR merged overnight, nothing needs you.');
  }
  function lane(k, status, pct, on) {
    var li = board.querySelector('.lanes [data-k="' + k + '"]');
    li.querySelector('small').textContent = status;
    li.querySelector('.bar i').style.width = (pct || 0) + '%';
    li.classList.toggle('on', !!on);
    fleetCount.textContent = board.querySelectorAll('.lanes li.on').length + 1 + ' working';
  }
  function chip(cls, text, wait) { return '<span class="chip' + (wait ? ' wait' : '') + (cls ? ' ' + cls : '') + '">' + text + '</span>'; }
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
    msgs.innerHTML = ''; cards.innerHTML = ''; typing.textContent = '';
    history();
    lane('arch', 'Idle', 0); lane('eng', 'Idle', 0); lane('ops', 'Watching 6 apps', 0); lane('fu', 'Chasing 3 replies', 62, true);
    card('t0', 'Merge PR #117 in acme-agents/brief', 'Safe write, ran at once', chip('', 'Ran'));
    card('t1', 'Send reminder to an allowlisted teammate', 'AI reviewer', chip('', 'Reviewer approved'));
    apprCount.textContent = 'All clear';
  }

  function finalFrame() {
    msgs.innerHTML = ''; cards.innerHTML = '';
    history();
    say('me', ASK);
    say('them', REPLY);
    say('them', PROGRESS);
    say('them ship', null, SHIPPED);
    lane('arch', 'Plan handed to Engineer', 100); lane('eng', 'Done: PR #42 merged', 100); lane('ops', 'Watching 7 apps', 100, true);
    card('t0', 'Push feat/pr-tracker', 'Safe write, ran at once', chip('', 'Ran'));
    card('t1', 'Merge PR #42, CI green', 'AI reviewer', chip('', 'Reviewer approved'));
    card('t1', 'Deploy pr-tracker v1', 'AI reviewer', chip('', 'Reviewer approved'));
  }

  if (reduce) { finalFrame(); return; }

  var inView = true;
  if ('IntersectionObserver' in window) new IntersectionObserver(function (e) { inView = e[0].isIntersecting; }).observe(board);
  function wait(ms) {
    return new Promise(function (res) {
      var left = ms, last = performance.now();
      (function tick(now) {
        if (!document.hidden && inView) left -= (now - last);
        last = now;
        if (left <= 0) res(); else requestAnimationFrame(tick);
      })(last);
    });
  }
  async function type(text) {
    for (var i = 1; i <= text.length; i++) { typing.textContent = text.slice(0, i); await wait(text[i - 1] === ' ' ? 34 : 22); }
  }
  async function review(c) {
    apprCount.textContent = '1 in review';
    await wait(1400);
    setRight(c, chip('', 'Reviewer approved'));
    apprCount.textContent = 'All clear';
  }

  async function run() {
    initial();
    await wait(1400);
    await type(ASK);
    await wait(350);
    typing.textContent = '';
    say('me', ASK);
    await wait(900);
    say('them', REPLY);
    await wait(600);
    lane('arch', 'Planning pr-tracker', 100, true);
    await wait(1800);
    lane('arch', 'Plan handed to Engineer', 100, false);
    lane('eng', 'Building pr-tracker', 45, true);
    await wait(1300);
    card('t0', 'Push feat/pr-tracker', 'Safe write, ran at once', chip('', 'Ran'));
    lane('eng', 'Opened PR #42', 100, true);
    await wait(1400);
    await review(card('t1', 'Merge PR #42, CI green', 'AI reviewer', chip('shimmer', 'Reviewing')));
    lane('eng', 'Done: PR #42 merged', 100, false);
    lane('ops', 'Deploying pr-tracker', 100, true);
    say('them', PROGRESS);
    await wait(900);
    await review(card('t1', 'Deploy pr-tracker v1', 'AI reviewer', chip('shimmer', 'Reviewing')));
    await wait(500);
    lane('ops', 'Watching 7 apps', 100, true);
    say('them ship', null, SHIPPED);
    await wait(4800);
    board.classList.add('resetting');
    await wait(500);
    board.classList.remove('resetting');
    run();
  }
  run();
})();
