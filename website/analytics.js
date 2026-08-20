/**
 * Permagent first-party analytics. Canonical snippet (window.permagent).
 * The collect path is also inlined in each HTML file so install verification
 * can grep the document — not this file — for /api/permagent-analytics/collect.
 */
(function () {
  var E = "/api/permagent-analytics/collect";
  var S = null;
  try {
    S = sessionStorage.getItem("_pa_sid");
    if (!S) {
      S = Math.random().toString(36).slice(2) + Date.now().toString(36);
      sessionStorage.setItem("_pa_sid", S);
    }
  } catch (e) { /* private mode: sessions degrade, pageviews still count */ }
  function send(kind, name, props, ref) {
    var body = JSON.stringify({
      k: kind,
      p: location.pathname + location.search,
      r: ref || null,
      n: name || null,
      d: props || null,
      s: S
    });
    if (!(navigator.sendBeacon && navigator.sendBeacon(E, body))) {
      fetch(E, { method: "POST", body: body, keepalive: true }).catch(function () {});
    }
  }
  var lastPath = null;
  var sentRef = false;
  function pageview() {
    if (location.pathname === lastPath) return;
    lastPath = location.pathname;
    var ref = sentRef ? null : (document.referrer || null);
    sentRef = true;
    send("pv", null, null, ref);
  }
  pageview();
  ["pushState", "replaceState"].forEach(function (m) {
    var orig = history[m];
    history[m] = function () { orig.apply(this, arguments); pageview(); };
  });
  addEventListener("popstate", pageview);
  window.permagent = window.permagent || {};
  window.permagent.event = function (name, props) { send("ev", name, props, null); };
  window.permagent.autocapture = function () {
    addEventListener("click", function (e) {
      var a = e.target && e.target.closest && e.target.closest("a[href]");
      if (!a) return;
      var url;
      try { url = new URL(a.href, location.href); } catch (err) { return; }
      if (url.host === location.host) return;
      send("ev", "outbound_click", { host: url.host, href: url.href.slice(0, 256) }, null);
    }, true);
  };
})();
