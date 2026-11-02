import { LightningElement } from 'lwc';
import getSalesforceUserEmails from '@salesforce/apex/RemoveToAddressController.getSalesforceUserEmails';

export default class RemoveToAddress extends LightningElement {

    observer;
    debounceTimer;
    isClearing = false;
    emailComposerOpen = false;

    connectedCallback() {
        console.debug('[RemoveToAddress] ✅ Component mounted on Case page. MutationObserver starting...');
        this.startObserving();
    }

    disconnectedCallback() {
        console.debug('[RemoveToAddress] ❌ Component unmounted. Cleaning up observer and timers.');
        this.cleanup();
    }

    cleanup() {
        if (this.observer) {
            this.observer.disconnect();
        }
        if (this.debounceTimer) {
            clearTimeout(this.debounceTimer);
        }
    }

    startObserving() {
        console.debug('[RemoveToAddress] 👁️ MutationObserver is now watching document.body.');

        this.observer = new MutationObserver((mutations) => {
            if (this.isClearing) return;

            // Inspect actual mutation records — works even under Locker Service
            // where document.querySelector is restricted to same namespace
            for (const mutation of mutations) {
                for (const node of mutation.addedNodes) {
                    if (node.nodeType !== 1) continue; // Element nodes only

                    const tag       = (node.tagName || '').toLowerCase();
                    const cls       = (typeof node.className === 'string') ? node.className : '';
                    const combined  = (tag + ' ' + cls).toLowerCase();

                    // ── DIAGNOSTIC: log EVERY node added to DOM ──────────────────────
                    // This helps identify the exact tag/class of the email composer.
                    // Remove this block once the correct selector is confirmed.
                    console.debug(`[RemoveToAddress] 🧩 Node added → <${tag}> class="${cls.substring(0, 100)}"`);
                    // ─────────────────────────────────────────────────────────────────

                    // Detect the email composer being added to the DOM
                    if (!this.emailComposerOpen && this.isEmailComposerNode(node, tag, cls)) {
                        console.debug(`[RemoveToAddress] 📬 Email composer node detected → <${tag}> class="${cls.substring(0, 80)}". Waiting 600ms...`);
                        this.emailComposerOpen = true;
                        clearTimeout(this.debounceTimer);
                        this.debounceTimer = setTimeout(() => {
                            this.removeInternalUserPills(node);
                        }, 600);
                        return;
                    }

                    // Also scan CHILDREN of the added node for email composer
                    if (!this.emailComposerOpen) {
                        const inner = this.findEmailComposerInSubtree(node);
                        if (inner) {
                            const innerTag = (inner.tagName || '').toLowerCase();
                            const innerCls = (typeof inner.className === 'string') ? inner.className : '';
                            console.debug(`[RemoveToAddress] 📬 Email composer found in subtree → <${innerTag}> class="${innerCls.substring(0, 80)}". Waiting 600ms...`);
                            this.emailComposerOpen = true;
                            clearTimeout(this.debounceTimer);
                            this.debounceTimer = setTimeout(() => {
                                this.removeInternalUserPills(inner);
                            }, 600);
                            return;
                        }
                    }
                }

                // Detect composer being removed (tab closed / navigated away)
                for (const node of mutation.removedNodes) {
                    if (node.nodeType !== 1) continue;
                    const tag = (node.tagName || '').toLowerCase();
                    const cls = (typeof node.className === 'string') ? node.className : '';
                    if (this.emailComposerOpen && this.isEmailComposerNode(node, tag, cls)) {
                        console.debug(`[RemoveToAddress] 📪 Email composer removed from DOM. Resetting state.`);
                        this.emailComposerOpen = false;
                    }
                }
            }
        });

        this.observer.observe(document.body, {
            childList  : true,
            subtree    : true,
            attributes : true
        });
    }

    /**
     * Returns true if the given node IS the email composer (or contains it).
     * Checks tag name and class against known Salesforce email composer patterns.
     */
    isEmailComposerNode(node, tag, cls) {
        const combined = (tag + ' ' + cls).toLowerCase();
        return (
            tag === 'recipients-input'           ||
            tag === 'c-recipients-input'         ||
            tag === 'force-email-composer'       ||
            tag === 'force-email-action'         ||
            /emailcomposer|emailaction|emailpublisher|emailbody/.test(combined)
        );
    }

    /**
     * Walks the subtree of a newly added node looking for the email composer.
     */
    findEmailComposerInSubtree(root) {
        try {
            return (
                root.querySelector('recipients-input')         ||
                root.querySelector('c-recipients-input')       ||
                root.querySelector('force-email-composer')     ||
                root.querySelector('force-email-action')       ||
                root.querySelector('[class*="emailComposer"]') ||
                root.querySelector('[class*="emailPublisher"]')||
                root.querySelector('[class*="emailAction"]')
            );
        } catch (e) {
            return null;
        }
    }

    handleMutations() {
        // Kept as a no-op fallback — main logic now runs in the MutationObserver callback
    }

    /**
     * Extracts { email, pillElement } pairs from all rendered TO address pills.
     * Checks data-value, title, label text — in priority order.
     */
    extractPillEmails(pills) {
        const emailRegex = /[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}/;
        const result = [];

        pills.forEach((pill, index) => {
            const pillSpan  = pill.querySelector('.slds-pill') || pill;
            const label     = pill.querySelector('.slds-pill__label, [class*="pill__label"]');
            const labelText = label ? label.textContent.trim() : pill.textContent.trim();

            const sources = [
                pillSpan.getAttribute('data-value') || '',
                pill.getAttribute('data-value')     || '',
                pillSpan.getAttribute('title')       || '',
                pill.getAttribute('title')           || '',
                pill.querySelector('[data-value]')?.getAttribute('data-value') || '',
                pill.querySelector('a[title]')?.getAttribute('title')          || '',
                labelText
            ];

            let foundEmail = null;
            for (const src of sources) {
                const match = src.match(emailRegex);
                if (match) { foundEmail = match[0].toLowerCase(); break; }
            }

            console.debug(`[RemoveToAddress] 💊 Pill #${index + 1} — Label: "${labelText}" | Email found: ${foundEmail || 'NONE (name-only pill)'}`);
            result.push({ email: foundEmail, pill, labelText });
        });

        return result;
    }

    /**
     * Main entry — find all TO pills, call Apex to identify SF-user emails,
     * then click Remove only on those pills.
     *
     * @param {Element} composerNode — the email composer DOM node received directly
     *                                  from the MutationObserver addedNodes list.
     *                                  Using this reference bypasses Locker Service
     *                                  restrictions on document.querySelectorAll.
     */
    async removeInternalUserPills(composerNode) {
        this.isClearing = true;
        console.debug('[RemoveToAddress] 🔍 Scanning TO address pills...');
        console.debug('[RemoveToAddress] 🧱 Composer node received:', composerNode ? composerNode.tagName : 'NONE — falling back to document');

        try {
            // Use composerNode directly (from mutation record) — avoids Locker Service
            // document.querySelectorAll restriction. Fall back to document if not available.
            const root = composerNode || document;

            const pillSelectors = [
                '.slds-listbox__item',
                '.slds-pill_container .slds-pill',
                '.slds-pill',
                '[class*="pill"]'
            ];

            let pillNodes = [];
            for (const sel of pillSelectors) {
                const found = root.querySelectorAll(sel);
                if (found.length) {
                    pillNodes = Array.from(found);
                    console.debug(`[RemoveToAddress] 🎯 Pills found using selector "${sel}": ${found.length}`);
                    break;
                }
            }

            // Also check parent & sibling nodes of the composer if pills not found inside it
            if (!pillNodes.length && composerNode && composerNode.parentElement) {
                console.debug('[RemoveToAddress] 🔍 Pills not in composerNode — searching in parent...');
                const parentRoot = composerNode.parentElement;
                for (const sel of pillSelectors) {
                    const found = parentRoot.querySelectorAll(sel);
                    if (found.length) {
                        pillNodes = Array.from(found);
                        console.debug(`[RemoveToAddress] 🎯 Pills found in parent using selector "${sel}": ${found.length}`);
                        break;
                    }
                }
            }

            console.debug(`[RemoveToAddress] 📋 Total pills found in TO field: ${pillNodes.length}`);

            if (!pillNodes.length) {
                console.debug('[RemoveToAddress] ⚠️ No pills found. Exiting.');
                return;
            }

            const pillEmailData = this.extractPillEmails(Array.from(pillNodes));

            // Separate pills where email was found vs name-only pills
            const withEmail    = pillEmailData.filter(d => d.email);
            const withoutEmail = pillEmailData.filter(d => !d.email);

            console.debug(`[RemoveToAddress] 📧 Pills with email extracted : ${withEmail.length}`);
            console.debug(`[RemoveToAddress] 🏷️ Pills with name only (no email found): ${withoutEmail.length}`);

            let sfEmailSet = new Set();

            if (withEmail.length > 0) {
                const emailList = withEmail.map(d => d.email);
                console.debug('[RemoveToAddress] 🌐 Calling Apex getSalesforceUserEmails with:', emailList);

                const sfUserEmails = await getSalesforceUserEmails({ emails: emailList });
                console.debug('[RemoveToAddress] ✅ Apex returned SF user emails:', sfUserEmails);

                if (sfUserEmails && sfUserEmails.length) {
                    sfEmailSet = new Set(sfUserEmails.map(e => e.toLowerCase()));
                }
            }

            // Remove SF-user pills identified by email
            withEmail.forEach(({ email, labelText, pill }) => {
                if (sfEmailSet.has(email)) {
                    console.debug(`[RemoveToAddress] 🗑️ Removing SF user pill — Label: "${labelText}" | Email: ${email}`);
                    const removeBtn = pill.querySelector('button[title="Remove"]');
                    if (removeBtn) removeBtn.click();
                } else {
                    console.debug(`[RemoveToAddress] ✋ Keeping pill — not an SF user | Email: ${email}`);
                }
            });

            // For name-only pills: remove if they have an SF user icon (avatar/lightning-icon)
            withoutEmail.forEach(({ labelText, pill }) => {
                const hasIcon = pill.querySelector(
                    'lightning-icon, .slds-avatar, img.userPhotoImg, [class*="avatar"]'
                );
                if (hasIcon) {
                    console.debug(`[RemoveToAddress] 🗑️ Removing name-only pill with icon (likely SF user) — Label: "${labelText}"`);
                    const removeBtn = pill.querySelector('button[title="Remove"]');
                    if (removeBtn) removeBtn.click();
                } else {
                    console.debug(`[RemoveToAddress] ✋ Keeping name-only pill (no icon, likely external) — Label: "${labelText}"`);
                }
            });

        } catch (error) {
            console.error('[RemoveToAddress] ❌ Error:', error);
        } finally {
            setTimeout(() => {
                this.isClearing = false;
                console.debug('[RemoveToAddress] 🔓 isClearing reset. Ready for next trigger.');
            }, 500);
        }
    }
}