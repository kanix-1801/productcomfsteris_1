/**
 * @description Preserves a user-gesture window.open across async Apex so Sales Connection URLs
 *              are not blocked as popups (common in Experience Cloud / quick actions).
 *              Named so a later open can reuse the same tab after the Apex round trip.
 */
const NAVIGATION_WINDOW_NAME = 'salesConnectionQuote';
let pendingNavigationWindow = null;

/**
 * @description Opens a placeholder tab during the original click event (must not use noopener).
 */
export function openPendingNavigationTab() {
    if (pendingNavigationWindow && !pendingNavigationWindow.closed) {
        return;
    }

    const openedWindow = openBlankWindow();
    if (openedWindow) {
        pendingNavigationWindow = openedWindow;
    }
}

export function navigatePendingTab(url) {
    const resolvedUrl = resolveAbsoluteUrl(url);
    if (!resolvedUrl) {
        return false;
    }

    const navigationWindow = pendingNavigationWindow;
    pendingNavigationWindow = null;
    if (!navigationWindow || navigationWindow.closed) {
        return false;
    }

    try {
        navigationWindow.location.href = resolvedUrl;
        navigationWindow.focus();
        try {
            navigationWindow.opener = null;
        } catch (error) {
            // Ignore when the browser already isolates the new tab.
        }
        return true;
    } catch (error) {
        closeWindow(navigationWindow);
        return false;
    }
}

export function clearPendingNavigationTab() {
    if (pendingNavigationWindow && !pendingNavigationWindow.closed) {
        closeWindow(pendingNavigationWindow);
    }
    pendingNavigationWindow = null;
}

/**
 * @description Opens external Sales Connection URLs using several strategies (LWR-safe).
 * @param url Absolute or site-relative URL.
 * @return True when a navigation attempt was made.
 */
export function openUrlInNewTab(url) {
    const resolvedUrl = resolveAbsoluteUrl(url);
    if (!resolvedUrl) {
        return false;
    }

    if (navigatePendingTab(resolvedUrl)) {
        return true;
    }

    if (openWithWindowContexts(resolvedUrl)) {
        return true;
    }

    return openWithTransientAnchor(resolvedUrl);
}

function openBlankWindow() {
    const contexts = getWindowContexts();
    const targets = ['', 'about:blank'];
    const sameOriginTarget = getSameOriginPlaceholder();
    if (sameOriginTarget) {
        targets.push(sameOriginTarget);
    }

    for (const target of targets) {
        for (const context of contexts) {
            const openedWindow = tryOpen(context, target);
            if (isScriptablePopup(openedWindow, context)) {
                return openedWindow;
            }
            closeWindow(openedWindow);
        }
    }

    return null;
}

function openWithWindowContexts(resolvedUrl) {
    const contexts = getWindowContexts();
    for (const context of contexts) {
        const openedWindow = tryOpen(context, resolvedUrl);
        if (isNewWindow(openedWindow, context)) {
            return true;
        }
    }

    return false;
}

function openWithTransientAnchor(resolvedUrl) {
    try {
        const anchor = document.createElement('a');
        anchor.href = resolvedUrl;
        anchor.target = NAVIGATION_WINDOW_NAME;
        anchor.rel = 'noopener noreferrer';
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
    } catch (error) {
        return false;
    }

    // A synthetic click after Apex does not report whether the browser opened a tab.
    return false;
}

function getWindowContexts() {
    const contexts = [];
    if (typeof window === 'undefined') {
        return contexts;
    }

    // Experience Builder renders the site inside a cross-origin frame. Opening from
    // window.top yields a tab this component cannot navigate, so use the site window first.
    contexts.push(window);

    try {
        if (window.top && window.top !== window && window.top.open) {
            contexts.push(window.top);
        }
    } catch (error) {
        // Ignore cross-origin access to the builder frame.
    }

    return contexts;
}

function tryOpen(context, target) {
    if (!context?.open) {
        return null;
    }

    try {
        return context.open(target, NAVIGATION_WINDOW_NAME);
    } catch (error) {
        return null;
    }
}

function isScriptablePopup(openedWindow, context) {
    if (!isNewWindow(openedWindow, context)) {
        return false;
    }

    try {
        return typeof openedWindow.location?.href === 'string';
    } catch (error) {
        return false;
    }
}

function isNewWindow(openedWindow, context) {
    if (!openedWindow || openedWindow.closed) {
        return false;
    }

    return openedWindow !== window && openedWindow !== context;
}

function getSameOriginPlaceholder() {
    try {
        return window.location?.href || null;
    } catch (error) {
        return null;
    }
}

function closeWindow(targetWindow) {
    try {
        targetWindow.close();
    } catch (error) {
        // Ignore close failures when the tab was already navigated or blocked.
    }
}

function resolveAbsoluteUrl(url) {
    if (!url) {
        return null;
    }

    const trimmedUrl = String(url).trim();
    if (!trimmedUrl) {
        return null;
    }

    if (trimmedUrl.startsWith('http://') || trimmedUrl.startsWith('https://')) {
        return trimmedUrl;
    }

    if (typeof window !== 'undefined' && window.location?.origin) {
        return `${window.location.origin}${trimmedUrl.startsWith('/') ? '' : '/'}${trimmedUrl}`;
    }

    return trimmedUrl;
}