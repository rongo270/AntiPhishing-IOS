/**
 * AntiPhishing — background script.
 *
 * Decision pipeline for every page Safari opens (asked by content.js):
 *
 *   1. Normalize the destination host (same rules as the Swift
 *      DomainNormalizer — see note below).
 *   2. Safe-verdict cache in browser.storage.local — repeat visits to the
 *      same domain skip the native round-trip entirely, so navigating
 *      within a site costs nothing.
 *   3. Native message to SafariWebExtensionHandler (Swift), which checks the
 *      shared allowlist and the on-device SQLite malicious-domain database.
 *
 *   There are NO server calls here: the primary check is fully local for
 *   speed, privacy and offline protection. The database itself is downloaded
 *   and refreshed by the AntiPhishing app.
 *
 * Cache invalidation: the native handler returns the active database version
 * with every reply. Cached safe verdicts are tagged with the version they
 * were computed against and are dropped as soon as a newer database is
 * activated, so a stale "safe" can never override fresh threat data.
 *
 * Normalization parity: `new URL(...).hostname` already lowercases and
 * punycode-encodes; we add trailing-dot and leading-"www." stripping to
 * mirror DomainNormalizer.swift. The JS result is only used as the cache
 * key — the Swift side independently re-normalizes the full URL before the
 * database lookup, so a mismatch could only cause a cache miss, never a
 * wrong verdict.
 */

const SAFE_CACHE_TTL_MS = 12 * 60 * 60 * 1000; // re-verify a domain twice a day
const CACHE_LIMIT = 500;                       // max cached safe domains

// ── Host normalization (cache key; mirrors DomainNormalizer.swift) ──────────

function normalizeHost(rawUrl) {
    try {
        const u = new URL(rawUrl);
        if (u.protocol !== "http:" && u.protocol !== "https:") return null;
        let host = u.hostname.toLowerCase();
        while (host.endsWith(".")) host = host.slice(0, -1);
        if (host.startsWith("www.") && host.length > 4) host = host.slice(4);
        return host || null;
    } catch (_) {
        return null;
    }
}

// ── Safe-domain cache ────────────────────────────────────────────────────────

async function getCache() {
    const obj = await browser.storage.local.get("safeCache");
    return obj.safeCache || {};
}

async function setCache(cache) {
    await browser.storage.local.set({ safeCache: cache });
}

async function cachedSafeVerdict(host, dbVersion) {
    const cache = await getCache();
    const entry = cache[host];
    if (!entry) return null;
    const fresh = Date.now() - entry.ts < SAFE_CACHE_TTL_MS;
    const sameDb = dbVersion === null || entry.dbVersion === dbVersion;
    return fresh && sameDb ? { verdict: "safe", fromCache: true } : null;
}

async function storeSafeVerdict(host, dbVersion) {
    const cache = await getCache();
    cache[host] = { ts: Date.now(), dbVersion };
    // Drop entries computed against older database versions, then trim.
    for (const key of Object.keys(cache)) {
        if (cache[key].dbVersion !== dbVersion) delete cache[key];
    }
    const keys = Object.keys(cache);
    if (keys.length > CACHE_LIMIT) {
        keys.sort((a, b) => cache[a].ts - cache[b].ts)
            .slice(0, keys.length - CACHE_LIMIT)
            .forEach(k => delete cache[k]);
    }
    await setCache(cache);
}

// The last database version seen from the native side; kept in storage so a
// relaunched background page still invalidates correctly.
async function lastKnownDbVersion() {
    const obj = await browser.storage.local.get("dbVersion");
    return typeof obj.dbVersion === "number" ? obj.dbVersion : null;
}

async function rememberDbVersion(version) {
    await browser.storage.local.set({ dbVersion: version });
}

// ── Native bridge ────────────────────────────────────────────────────────────

async function nativeCheckDomain(url) {
    // "application.id" resolves to the containing app's extension handler.
    return browser.runtime.sendNativeMessage("application.id", { action: "checkDomain", url });
}

async function nativeAllowDomain(domain) {
    return browser.runtime.sendNativeMessage("application.id", { action: "allowDomain", domain });
}

async function nativeGetStatus() {
    return browser.runtime.sendNativeMessage("application.id", { action: "getStatus" });
}

// ── Verdict pipeline ─────────────────────────────────────────────────────────

/**
 * Returns the verdict object content.js acts on:
 *   { verdict: "safe" | "malicious" | "allowlisted" | "off" | "unprotected"
 *              | "unavailable",
 *     host, matchedDomain?, source?, threatType? }
 */
async function evaluateUrl(rawUrl) {
    const host = normalizeHost(rawUrl);
    if (!host) return { verdict: "unavailable" };

    // Fast path: recently confirmed safe against the current database.
    const knownVersion = await lastKnownDbVersion();
    const cached = await cachedSafeVerdict(host, knownVersion);
    if (cached) return cached;

    let native;
    try {
        native = await nativeCheckDomain(rawUrl);
    } catch (_) {
        // Native handler unreachable — fail open but silent (never break
        // browsing), the app shows the real protection status.
        return { verdict: "unavailable" };
    }
    if (!native || !native.ok) return { verdict: "unavailable" };

    if (typeof native.dbVersion === "number") {
        await rememberDbVersion(native.dbVersion);
    }

    switch (native.verdict) {
        case "safe":
            await storeSafeVerdict(host, native.dbVersion ?? 0);
            return { verdict: "safe", host };
        case "malicious":
            // Never cached in JS: allowlisting or a DB update must take
            // effect on the very next load.
            return {
                verdict: "malicious",
                host,
                matchedDomain: native.matchedDomain || host,
                source: native.source || null,
                threatType: native.threatType || null
            };
        case "allowlisted":
            return { verdict: "allowlisted", host };
        case "off":
            return { verdict: "off" };
        default:
            return { verdict: "unprotected" };
    }
}

// ── Message router ───────────────────────────────────────────────────────────

browser.runtime.onMessage.addListener((request, sender) => {
    switch (request && request.type) {

        // content.js asks for a verdict on the page it is loading.
        case "checkUrl":
            return evaluateUrl(request.url);

        // "Continue Anyway" on the warning page. Stores the approval in the
        // shared allowlist (visible in the app's Approved Domains screen).
        case "allowDomain":
            return (async () => {
                try {
                    const res = await nativeAllowDomain(request.domain);
                    return res && res.ok ? { ok: true, expiresAt: res.expiresAt } : { ok: false };
                } catch (_) {
                    return { ok: false };
                }
            })();

        // "Go Back" pressed on a tab with no history to return to.
        case "closeTab":
            return (async () => {
                if (sender.tab && sender.tab.id !== undefined) {
                    try { await browser.tabs.remove(sender.tab.id); } catch (_) {}
                }
                return { ok: true };
            })();

        // Popup status (protection switch, database version/size/age).
        case "getPopupStatus":
            return (async () => {
                try {
                    return await nativeGetStatus();
                } catch (_) {
                    return { ok: false };
                }
            })();

        default:
            return undefined;
    }
});
