import { LightningElement, api } from 'lwc';

/**
 * GW-3400 - Shared Repair Center evaluation workspace chrome.
 */
export default class RepairCenterEvalWorkspace extends LightningElement {
    /** Nav items: { label, value }. */
    @api items = [];
    /** Currently selected nav value. */
    @api selectedValue;
    /** When true, left nav is hidden (e.g. Evaluation Summary). */
    @api hideNav = false;

    /**
     * GW-3400 - Whether the left nav should render.
     */
    get showNav() {
        return this.hideNav !== true;
    }

    /**
     * GW-3400 - Nav items with SLDS selected classes.
     */
    get navItems() {
        const selected = this.selectedValue;
        return (this.items || []).map((item) => ({
            ...item,
            itemClass:
                item.value === selected
                    ? 'slds-nav-vertical__item slds-is-active'
                    : 'slds-nav-vertical__item',
            ariaCurrent: item.value === selected ? 'page' : 'false'
        }));
    }

    /**
     * GW-3400 - Notifies the host that a nav item was selected.
     * @param {Event} event nav button click
     */
    handleNavClick(event) {
        const tab = event.currentTarget?.dataset?.tab;
        if (!tab || tab === this.selectedValue) {
            return;
        }
        this.dispatchEvent(
            new CustomEvent('navselect', {
                detail: { value: tab }
            })
        );
    }
}