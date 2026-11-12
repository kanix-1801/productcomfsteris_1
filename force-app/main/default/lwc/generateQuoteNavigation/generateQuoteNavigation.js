/**
 * @description Preserves a user-gesture window.open across async Apex so Sales Connection URLs
 *              are not blocked as popups (common in Experience Cloud / quick actions).
 */
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
    } finally {
        pendingNavigationWindow = null;
    }

    return true;
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

    if (openWithTransientAnchor(resolvedUrl)) {
        return true;
    }

    return openWithWindowContexts(resolvedUrl);
}

function openBlankWindow() {
    const contexts = getWindowContexts();
    for (const context of contexts) {
        if (!context?.open) {
            continue;
        }

        try {
            const openedWindow = context.open('about:blank', '_blank');
            if (openedWindow) {
                return openedWindow;
            }
        } catch (error) {
            // Try the next window context.
        }
    }

    return null;
}

function openWithWindowContexts(resolvedUrl) {
    const contexts = getWindowContexts();
    for (const context of contexts) {
        if (!context?.open) {
            continue;
        }

        try {
            const openedWindow = context.open(resolvedUrl, '_blank');
            if (openedWindow) {
                return true;
            }
        } catch (error) {
            // Try the next window context.
        }
    }

    return false;
}

function openWithTransientAnchor(resolvedUrl) {
    try {
        const anchor = document.createElement('a');
        anchor.href = resolvedUrl;
        anchor.target = '_blank';
        anchor.rel = 'noopener noreferrer';
        anchor.style.display = 'none';
        document.body.appendChild(anchor);
        anchor.click();
        document.body.removeChild(anchor);
        return true;
    } catch (error) {
        return false;
    }
}

function getWindowContexts() {
    const contexts = [];
    if (typeof window !== 'undefined') {
        if (window.top && window.top !== window) {
            contexts.push(window.top);
        }
        contexts.push(window);
    }
    return contexts;
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