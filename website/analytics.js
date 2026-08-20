/**
 * Permagent self-hosted analytics snippet
 * Sends pageview and event beacons to /api/permagent-analytics/collect
 */
(function analyticsInit() {
  // Configuration
  const COLLECT_URL = '/api/permagent-analytics/collect';
  const SESSION_KEY = 'permagent_session_id';
  const SESSION_STORAGE_KEY = 'permagent_session_storage';
  
  // Generate or retrieve session ID
  function getSessionId() {
    let sessionId = sessionStorage.getItem(SESSION_STORAGE_KEY);
    if (!sessionId) {
      sessionId = 'session_' + Math.random().toString(36).substring(2, 18) + '_' + Date.now();
      sessionStorage.setItem(SESSION_STORAGE_KEY, sessionId);
    }
    return sessionId;
  }
  
  // Send beacon to collector
  function sendBeacon(kind, path, extra) {
    if (!navigator.sendBeacon) return; // fallback for old browsers
    
    const payload = {
      k: kind === 'pageview' ? 'pv' : 'ev', // short keys to reduce size
      p: path,
      r: document.referrer || null,
      n: extra?.name || null,
      d: extra?.properties || null,
      s: getSessionId()
    };
    
    const url = new URL(COLLECT_URL, window.location.origin);
    navigator.sendBeacon(url.toString(), JSON.stringify(payload));
  }
  
  // Track pageview on load
  function trackPageview() {
    const path = window.location.pathname + window.location.search;
    sendBeacon('pageview', path);
  }
  
  // Expose global event tracking function
  window.permagentAnalytics = {
    trackEvent: function(name, properties) {
      const path = window.location.pathname + window.location.search;
      sendBeacon('event', path, { name, properties });
    }
  };
  
  // Track pageview when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', trackPageview);
  } else {
    trackPageview();
  }
  
  // Track SPAs (pushState / replaceState)
  const originalPushState = history.pushState;
  const originalReplaceState = history.replaceState;
  
  history.pushState = function(...args) {
    originalPushState.apply(this, args);
    trackPageview();
  };
  
  history.replaceState = function(...args) {
    originalReplaceState.apply(this, args);
    trackPageview();
  };
})();
