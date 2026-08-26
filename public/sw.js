// Previously a cache-first service worker for / and /login. That is unsafe on
// a same-origin API host (stale login HTML, session cookies). If an old client
// still has it registered, unregister and drop caches on activate.
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    const keys = await caches.keys();
    await Promise.all(keys.map((k) => caches.delete(k)));
    await self.registration.unregister();
    const clients = await self.clients.matchAll({ type: 'window' });
    for (const client of clients) {
      if (client.navigate) client.navigate(client.url);
    }
  })());
});
