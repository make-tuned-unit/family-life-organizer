// Kinrows site — light progressive enhancement only.
// Mark JS active so reveal-on-scroll hiding only applies when JS can un-hide it.
document.documentElement.classList.add('js');

// Sticky nav: add backdrop once the hero starts scrolling away.
const nav = document.getElementById('nav');
const onScroll = () => nav.classList.toggle('scrolled', window.scrollY > 24);
onScroll();
window.addEventListener('scroll', onScroll, { passive: true });

// Mobile menu toggle.
const navToggle = document.querySelector('.nav-toggle');
if (navToggle) {
  const setOpen = (open) => {
    nav.classList.toggle('nav-open', open);
    navToggle.setAttribute('aria-expanded', open ? 'true' : 'false');
    navToggle.setAttribute('aria-label', open ? 'Close menu' : 'Open menu');
  };
  navToggle.addEventListener('click', () => setOpen(!nav.classList.contains('nav-open')));
  // Close after tapping a link.
  document.querySelectorAll('#primary-nav a').forEach((a) =>
    a.addEventListener('click', () => setOpen(false)));
  // Close on Escape and return focus to the toggle.
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape' && nav.classList.contains('nav-open')) {
      setOpen(false);
      navToggle.focus();
    }
  });
}

// Scroll-reveal via IntersectionObserver (graceful if unsupported).
const revealEls = document.querySelectorAll('.reveal');
if ('IntersectionObserver' in window) {
  const io = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (e.isIntersecting) {
        e.target.classList.add('in');
        io.unobserve(e.target);
      }
    }
  }, { rootMargin: '0px 0px -10% 0px', threshold: 0.08 });
  revealEls.forEach((el, i) => {
    // tiny stagger for elements that share a row
    el.style.transitionDelay = `${Math.min(i % 4, 3) * 60}ms`;
    io.observe(el);
  });
} else {
  revealEls.forEach((el) => el.classList.add('in'));
}

// App-screen choreography: build each mock screen in on scroll; type the Concierge brief.
const jsOn = document.documentElement.classList.contains('js');
const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
const briefParas = Array.from(document.querySelectorAll('.assist-brief p'));
const briefHTML = briefParas.map((p) => p.innerHTML);
// Empty the brief up front so it can type out (only when we'll actually animate it).
if (jsOn && !reduceMotion) briefParas.forEach((p) => { p.textContent = ''; });

function typeBrief() {
  let pi = 0;
  const nextPara = () => {
    if (pi >= briefParas.length) return;
    const p = briefParas[pi];
    const tmp = document.createElement('div');
    tmp.innerHTML = briefHTML[pi];
    const text = tmp.textContent; // plain text; bold is restored when the line finishes
    p.textContent = '';
    p.classList.add('typing');
    let c = 0;
    const tick = () => {
      p.textContent = text.slice(0, (c += 1));
      if (c < text.length) {
        setTimeout(tick, 16);
      } else {
        p.classList.remove('typing');
        p.innerHTML = briefHTML[pi]; // restore <b> emphasis
        pi += 1;
        setTimeout(nextPara, 220);
      }
    };
    tick();
  };
  nextPara();
}

// Chat screen: type a message into the composer and "send" it as a new bubble.
const wait = (ms) => new Promise((r) => setTimeout(r, ms));
function typeInto(el, text, speed) {
  return new Promise((res) => {
    el.textContent = '';
    let c = 0;
    const t = () => {
      el.textContent = text.slice(0, (c += 1));
      if (c < text.length) setTimeout(t, speed);
      else res();
    };
    t();
  });
}
async function runChatDemo() {
  const chat = document.querySelector('.app-chat .chat');
  const composer = document.querySelector('.app-chat .chat-composer');
  if (!chat || !composer) return;
  const span = composer.querySelector('span');
  const sendBtn = composer.querySelector('i');
  const placeholder = (span.textContent || '').trim() || 'Message the household…';

  // Keep the thread within the phone frame by dropping the oldest message.
  const trim = () => { while (chat.children.length > 5) chat.firstElementChild.remove(); };

  // A looping back-and-forth: you type & send, the household types back & replies.
  const convo = [
    { who: 'out', text: 'Sounds good — see you soon!' },
    { who: 'in', name: 'Grace', text: 'Perfect — see you at 3.' },
    { who: 'out', text: 'Grabbing milk on the way back.' },
    { who: 'in', name: 'Daniel', text: 'Legend, thank you.' },
  ];

  for (let i = 0; ; i += 1) {
    const turn = convo[i % convo.length];

    if (turn.who === 'out') {
      composer.classList.add('typing');
      await typeInto(span, turn.text, 46);
      await wait(360);
      if (sendBtn) {
        sendBtn.classList.add('sent');
        setTimeout(() => sendBtn.classList.remove('sent'), 170);
      }
      const bub = document.createElement('div');
      bub.className = 'bub out bub-new';
      bub.textContent = turn.text;
      chat.appendChild(bub);
      trim();
      composer.classList.remove('typing');
      span.textContent = placeholder;
      await wait(900);
    } else {
      // Show a "typing…" indicator, then swap it for the reply.
      const dots = document.createElement('div');
      dots.className = 'bub in typing-dots bub-new';
      dots.innerHTML = '<span></span><span></span><span></span>';
      chat.appendChild(dots);
      trim();
      await wait(1300);
      dots.remove();
      const bub = document.createElement('div');
      bub.className = 'bub in bub-new';
      bub.innerHTML = `<span class="bub-name">${turn.name}</span>${turn.text}`;
      chat.appendChild(bub);
      trim();
      await wait(1600);
    }
  }
}

// Hero: a live vote lands on the Clay paint option, with subtle nods to the action.
async function runHomeVote() {
  const clay = document.querySelector('.app-home .vote-clay');
  if (!clay) return;
  const n = clay.querySelector('.vo-n');
  const tile = document.querySelector('.app-home [data-tile="vote"]');
  await wait(200);
  clay.classList.add('tapped');           // the option is tapped
  await wait(170);
  clay.classList.remove('tapped');
  clay.classList.add('voted');            // it selects
  if (n) {
    const pop = document.createElement('span');
    pop.className = 'vote-pop';
    pop.textContent = '+1';
    clay.appendChild(pop);
    setTimeout(() => pop.remove(), 1000);
    n.textContent = String((parseInt(n.textContent, 10) || 1) + 1); // count ticks up
    n.classList.add('bump');
    setTimeout(() => n.classList.remove('bump'), 520);
  }
  await wait(440);
  if (tile) {                              // "need a vote" quietly drops by one
    tile.textContent = String(Math.max(0, (parseInt(tile.textContent, 10) || 3) - 1));
    tile.classList.add('bump');
    setTimeout(() => tile.classList.remove('bump'), 520);
  }
}

const appScreens = document.querySelectorAll('.app');
if ('IntersectionObserver' in window && jsOn && !reduceMotion) {
  const appIO = new IntersectionObserver((entries) => {
    for (const e of entries) {
      if (!e.isIntersecting) continue;
      e.target.classList.add('played');
      if (e.target.classList.contains('app-assist')) setTimeout(typeBrief, 520);
      if (e.target.classList.contains('app-chat')) setTimeout(runChatDemo, 900);
      if (e.target.classList.contains('app-home')) setTimeout(runHomeVote, 1400);
      appIO.unobserve(e.target);
    }
  }, { threshold: 0.35 });
  appScreens.forEach((a) => appIO.observe(a));
} else {
  // No observer / reduced motion: show everything statically.
  appScreens.forEach((a) => a.classList.add('played'));
  briefParas.forEach((p, i) => { p.innerHTML = briefHTML[i]; });
}

// Referral: capture ?ref= from the share link so we can credit the referrer,
// and clean it out of the URL so it isn't re-shared.
const REF = new URLSearchParams(location.search).get('ref');
if (REF && history.replaceState) {
  const u = new URL(location.href); u.searchParams.delete('ref');
  history.replaceState(null, '', u.pathname + u.search + u.hash);
}

// Waitlist forms — every .notify-form (hero + final CTA) posts to /api/waitlist
// (same origin as the marketing site). data-source tags where the signup came from.
document.querySelectorAll('.notify-form').forEach(initNotifyForm);
function initNotifyForm(form) {
  const input = form.querySelector('input');
  const btn = form.querySelector('button');

  // Inline status line for success / error, announced to screen readers.
  const status = document.createElement('p');
  status.className = 'notify-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  form.insertAdjacentElement('afterend', status);

  const setStatus = (msg, kind) => {
    status.textContent = msg;
    status.dataset.kind = kind || '';
  };

  form.addEventListener('submit', async (e) => {
    e.preventDefault();
    if (!input.value || !input.checkValidity()) {
      setStatus('Please enter a valid email.', 'error');
      input.focus();
      return;
    }

    const original = btn.textContent;
    btn.disabled = true;
    input.disabled = true;
    btn.textContent = 'Joining…';
    setStatus('', '');

    try {
      const res = await fetch('/api/waitlist', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email: input.value.trim(), source: form.dataset.source || 'site', ref: REF || undefined }),
      });
      const data = await res.json().catch(() => ({}));

      if (res.ok && data.success) {
        if (data.ref_code) {
          renderReferral(form, status, data);
        } else {
          btn.textContent = "You're on the list ✓";
          setStatus(data.already ? "You're already on the list — we'll be in touch."
                                 : 'Check your inbox — a little welcome is on its way.', 'success');
        }
      } else {
        throw new Error(data.error || 'Request failed');
      }
    } catch (err) {
      btn.textContent = original;
      btn.disabled = false;
      input.disabled = false;
      setStatus("Hmm, that didn't go through. Please try again.", 'error');
    }
  });
}

// The highest-intent moment: replace the form with a warm share card so the
// user can move up the list by inviting family. (Queue-position mechanic.)
function renderReferral(form, status, data) {
  status.remove();
  const link = location.origin + '/?ref=' + data.ref_code;
  const pos = data.position ? '#' + data.position.toLocaleString() : null;
  const head = pos
    ? `${data.already ? 'Welcome back &mdash; you&rsquo;re' : 'You&rsquo;re'} <b>${pos}</b> on the list &#10003;`
    : (data.already ? 'You&rsquo;re already on the list &#10003;' : 'You&rsquo;re on the list &#10003;');
  const friends = data.referrals === 1 ? '1 friend has joined' : `${data.referrals} friends have joined`;

  const card = document.createElement('div');
  card.className = 'wl-ref';
  card.setAttribute('role', 'status');
  card.setAttribute('aria-live', 'polite');
  card.innerHTML = `
    <p class="wl-ref-head">${head}</p>
    <p class="wl-ref-sub">Invite your partner or co-parent &mdash; every family who joins with your link moves you up.</p>
    <div class="wl-ref-row">
      <input class="wl-ref-link" type="text" readonly value="${link}" aria-label="Your invite link" />
      <button type="button" class="btn btn-primary wl-copy">Copy link</button>
    </div>
    <p class="wl-ref-count">${data.referrals > 0 ? '&#11088; ' + friends : 'Be the first in your family to invite someone.'}</p>
  `;
  form.replaceWith(card);

  const copyBtn = card.querySelector('.wl-copy');
  const linkEl = card.querySelector('.wl-ref-link');
  copyBtn.addEventListener('click', async () => {
    try {
      if (navigator.share) { await navigator.share({ title: 'Kinrows', text: 'Join me on the Kinrows waitlist', url: link }); return; }
      await navigator.clipboard.writeText(link);
      copyBtn.textContent = 'Copied ✓';
      setTimeout(() => (copyBtn.textContent = 'Copy link'), 2000);
    } catch (_) {
      linkEl.select();
    }
  });
}
