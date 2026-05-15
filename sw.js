const BUILD = '20260514215202';
const CACHE = 'expresso-improved-' + BUILD;

self.addEventListener('install', () => self.skipWaiting());
self.addEventListener('activate', () => self.clients.claim());

self.addEventListener('fetch', event => {
  if (event.request.url.includes('stories.json') || event.request.mode === 'navigate') {
    event.respondWith(fetch(event.request, {cache: 'reload'}));
  }
});