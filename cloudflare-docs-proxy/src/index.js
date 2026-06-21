const DEFAULT_DOCS_MOUNT_PATH = "/docs";
const DEFAULT_DOCS_PAGES_ORIGIN = "https://logister-docs.pages.dev";
const DEFAULT_OLD_DOCS_HOSTS = ["docs.logister.org"];
const DEFAULT_PUBLIC_DOCS_ORIGIN = "https://logister.org";
const REDIRECT_STATUSES = new Set([301, 302, 303, 307, 308]);

export default {
  async fetch(request, env) {
    const publicUrl = new URL(request.url);
    const mountPath = normalizeMountPath(env.DOCS_MOUNT_PATH || DEFAULT_DOCS_MOUNT_PATH);
    const oldDocsHosts = oldDocsHostsFor(env.OLD_DOCS_HOSTS);

    if (oldDocsHosts.has(publicUrl.hostname.toLowerCase())) {
      return redirectOldDocsHost(publicUrl, {
        mountPath,
        publicDocsOrigin: env.PUBLIC_DOCS_ORIGIN || DEFAULT_PUBLIC_DOCS_ORIGIN
      });
    }

    if (!isDocsRequest(publicUrl.pathname, mountPath)) {
      return new Response("Not found", { status: 404 });
    }

    const originBaseUrl = new URL(env.DOCS_PAGES_ORIGIN || DEFAULT_DOCS_PAGES_ORIGIN);
    const originUrl = proxiedOriginUrl(originBaseUrl, publicUrl, mountPath);
    const originRequest = new Request(originUrl.toString(), request);
    const originResponse = await fetch(originRequest);

    return rewriteOriginRedirect(originResponse, {
      originBaseUrl,
      publicOrigin: publicUrl.origin,
      mountPath
    });
  }
};

function normalizeMountPath(path) {
  const normalized = `/${String(path || "").trim().replace(/^\/+|\/+$/g, "")}`;
  return normalized === "/" ? DEFAULT_DOCS_MOUNT_PATH : normalized;
}

function oldDocsHostsFor(value) {
  const hosts = String(value || "")
    .split(",")
    .map((host) => host.trim().toLowerCase())
    .filter(Boolean);

  return new Set(hosts.length > 0 ? hosts : DEFAULT_OLD_DOCS_HOSTS);
}

function redirectOldDocsHost(url, options) {
  const publicOrigin = new URL(options.publicDocsOrigin);
  const targetUrl = new URL(publicOrigin.toString());
  targetUrl.pathname = mountedPublicPath(
    stripMountPath(url.pathname, options.mountPath),
    options.mountPath
  );
  targetUrl.search = url.search;
  targetUrl.hash = url.hash;

  return Response.redirect(targetUrl.toString(), 301);
}

function isDocsRequest(pathname, mountPath) {
  return pathname === mountPath || pathname.startsWith(`${mountPath}/`);
}

function stripMountPath(pathname, mountPath) {
  if (pathname === mountPath) return "/";
  if (pathname.startsWith(`${mountPath}/`)) return pathname.slice(mountPath.length);

  return pathname;
}

function proxiedOriginUrl(originBaseUrl, publicUrl, mountPath) {
  const originUrl = new URL(originBaseUrl.toString());
  const proxiedPath = publicUrl.pathname === mountPath
    ? "/"
    : publicUrl.pathname.slice(mountPath.length);

  originUrl.pathname = joinPaths(originBaseUrl.pathname, proxiedPath || "/");
  originUrl.search = publicUrl.search;
  return originUrl;
}

function joinPaths(basePath, path) {
  const base = basePath.replace(/\/+$/g, "");
  const nextPath = path.startsWith("/") ? path : `/${path}`;
  return `${base}${nextPath}` || "/";
}

function rewriteOriginRedirect(response, options) {
  if (!REDIRECT_STATUSES.has(response.status)) return response;

  const location = response.headers.get("Location");
  if (!location) return response;

  const redirectUrl = new URL(location, options.originBaseUrl);
  if (redirectUrl.origin !== options.originBaseUrl.origin) return response;

  const headers = new Headers(response.headers);
  const publicPath = mountedPublicPath(
    redirectPathWithoutOriginBase(redirectUrl.pathname, options.originBaseUrl.pathname),
    options.mountPath
  );
  headers.set("Location", `${options.publicOrigin}${publicPath}${redirectUrl.search}${redirectUrl.hash}`);

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

function redirectPathWithoutOriginBase(pathname, originBasePath) {
  const basePath = originBasePath.replace(/\/+$/g, "");
  if (!basePath) return pathname;
  if (pathname === basePath) return "/";
  if (pathname.startsWith(`${basePath}/`)) return pathname.slice(basePath.length);

  return pathname;
}

function mountedPublicPath(pathname, mountPath) {
  const normalizedPath = pathname.startsWith("/") ? pathname : `/${pathname}`;
  return `${mountPath}${normalizedPath}`.replace(/\/{2,}/g, "/");
}
