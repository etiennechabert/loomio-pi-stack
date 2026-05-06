/**
 * Cloudflare Worker: serves /impressum and /datenschutz from static assets,
 * and injects a small footer link into every Loomio HTML response so that the
 * legal pages are reachable from any page (TMG/DDG § 5 requirement).
 *
 * Bound to `loomio.lyckbo.de/*` via wrangler-legal.toml — runs at the edge
 * before the Cloudflare Tunnel hands the request to the Pi.
 */

const FOOTER_HTML = `
<div id="legal-footer" style="position:fixed;bottom:8px;right:12px;z-index:2147483647;font:11px/1.2 system-ui,-apple-system,sans-serif;background:rgba(255,255,255,0.88);color:#666;padding:4px 8px;border-radius:4px;backdrop-filter:blur(4px);box-shadow:0 1px 3px rgba(0,0,0,0.08);">
  <a href="/impressum" style="color:inherit;text-decoration:none;margin:0 3px;">Impressum</a>·<a href="/datenschutz" style="color:inherit;text-decoration:none;margin:0 3px;">Datenschutz</a>
</div>
`;

class FooterInjector {
  element(element) {
    element.append(FOOTER_HTML, { html: true });
  }
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (url.pathname === '/impressum' || url.pathname === '/impressum/') {
      return env.ASSETS.fetch(new Request(new URL('/impressum.html', request.url), request));
    }
    if (url.pathname === '/datenschutz' || url.pathname === '/datenschutz/') {
      return env.ASSETS.fetch(new Request(new URL('/datenschutz.html', request.url), request));
    }

    const response = await fetch(request);
    const contentType = response.headers.get('content-type') || '';

    if (!contentType.toLowerCase().includes('text/html')) {
      return response;
    }

    return new HTMLRewriter()
      .on('body', new FooterInjector())
      .transform(response);
  },
};
