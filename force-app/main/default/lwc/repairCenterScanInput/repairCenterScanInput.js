import { LightningElement, api, wire } from 'lwc';
import { subscribe, unsubscribe, APPLICATION_SCOPE, MessageContext } from 'lightning/messageService';
import TAB_FOCUSED_CHANNEL from '@salesforce/messageChannel/lightning__tabFocused';

/**
 * Shared Repair Center scan field: auto-focus and Enter/line-feed continue.
 * GW-2891 / reusable for GW-4360.
 */
export default class RepairCenterScanInput extends LightningElement {
    @api label = 'Work Order Id / Number';
    @api placeholder = 'Scan or enter Work Order Id / Number';
    @api buttonLabel = 'Continue';
    @api disabled = false;
    @api value = '';

    inputId = 'repair-center-scan-input';
    errorMessage = '';
    _hasScheduledFocus = false;
    _focusTimeoutIds = [];
    _userTookFocus = false;
    _tabFocusedSubscription;

    @wire(MessageContext)
    messageContext;

    /**
     * GW-2891 - Registers focus listeners so the scan field claims focus in console.
     */
    connectedCallback() {
        this.inputId = `repair-center-scan-input-${Date.now()}`;
        this._onVisibilityChange = () => {
            if (document.visibilityState === 'visible') {
                this.focusScanField();
            }
        };
        this._onWindowFocus = () => {
            this.focusScanField();
        };
        this._onPointerDown = (event) => {
            if (this.isEventInsideHost(event)) {
                return;
            }
            this._userTookFocus = true;
            this.clearFocusTimeouts();
        };
        document.addEventListener('visibilitychange', this._onVisibilityChange);
        window.addEventListener('focus', this._onWindowFocus);
        window.addEventListener('pointerdown', this._onPointerDown, true);
        this.subscribeToTabFocused();
    }

    /**
     * GW-2891 - Removes focus listeners and pending timeouts.
     */
    disconnectedCallback() {
        this.clearFocusTimeouts();
        document.removeEventListener('visibilitychange', this._onVisibilityChange);
        window.removeEventListener('focus', this._onWindowFocus);
        window.removeEventListener('pointerdown', this._onPointerDown, true);
        if (this._tabFocusedSubscription) {
            unsubscribe(this._tabFocusedSubscription);
            this._tabFocusedSubscription = undefined;
        }
    }

    /**
     * GW-2891 - Retries auto-focus after Lightning console steals focus on first paint.
     */
    renderedCallback() {
        this.subscribeToTabFocused();
        if (this.disabled || this._hasScheduledFocus || !this.refs?.scanField) {
            return;
        }
        this._hasScheduledFocus = true;
        // Do not stop after the first successful focus: Lightning console steals
        // focus after the first paint on full refresh. Keep claiming it until
        // the workspace settles, or the user clicks elsewhere.
        [0, 50, 100, 250, 500, 800, 1200, 1800, 2500].forEach((delayMs) => {
            const timeoutId = window.setTimeout(() => {
                this.focusScanField();
            }, delayMs);
            this._focusTimeoutIds.push(timeoutId);
        });
    }

    /**
     * GW-2891 - Subscribes to tab-focused so the scan field refocuses when the tab is selected.
     */
    subscribeToTabFocused() {
        if (!this.messageContext || this._tabFocusedSubscription) {
            return;
        }
        this._tabFocusedSubscription = subscribe(
            this.messageContext,
            TAB_FOCUSED_CHANNEL,
            () => {
                this._userTookFocus = false;
                this.focusScanField();
            },
            { scope: APPLICATION_SCOPE }
        );
    }

    /**
     * GW-2891 - True when a pointer event originated inside this scan component.
     * @param {Event} event Pointer event
     * @returns {boolean}
     */
    isEventInsideHost(event) {
        const host = this.template.host;
        const path = typeof event.composedPath === 'function' ? event.composedPath() : [];
        return path.includes(host) || host.contains(event.target);
    }

    /**
     * GW-2891 - Focuses the scan input unless the user clicked elsewhere.
     */
    focusScanField() {
        if (this._userTookFocus || this.disabled) {
            return;
        }
        const input = this.refs?.scanField;
        if (!input) {
            return;
        }
        input.focus();
    }

    /**
     * GW-2891 - Cancels pending auto-focus timeouts.
     */
    clearFocusTimeouts() {
        this._focusTimeoutIds.forEach((timeoutId) => window.clearTimeout(timeoutId));
        this._focusTimeoutIds = [];
    }

    /**
     * GW-2891 - SLDS form-element class, including error state.
     */
    get formElementClass() {
        return this.errorMessage ? 'slds-form-element slds-has-error' : 'slds-form-element';
    }

    /**
     * GW-2891 - Forwards the typed scan value to the parent.
     * @param {Event} event input change
     */
    handleChange(event) {
        this.errorMessage = '';
        this.dispatchEvent(
            new CustomEvent('valuechange', {
                detail: { value: event.target.value }
            })
        );
    }

    /**
     * GW-2891 - Treats Enter as Continue for scanner line-feed.
     * @param {KeyboardEvent} event keydown
     */
    handleKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.handleContinue();
        }
    }

    /**
     * GW-2891 - Validates the scan value and fires continue to the parent.
     */
    handleContinue() {
        if (this.disabled) {
            return;
        }
        const input = this.template.querySelector('input');
        const currentValue = (input?.value || this.value || '').trim();
        if (!currentValue) {
            this.errorMessage = 'Complete this field.';
            input?.focus();
            return;
        }
        this.errorMessage = '';
        this.dispatchEvent(
            new CustomEvent('continue', {
                detail: { value: currentValue }
            })
        );
    }
}