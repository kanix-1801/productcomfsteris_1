import { LightningElement, api } from 'lwc';

/**
 * GW-4750 - Prominent [CIO] header cue when Continuous Improvement Opportunity is true.
 */
export default class RepairCenterCioIndicator extends LightningElement {
    /** Visual size: default (one-line headers) or large (two-line evaluation headers). */
    @api size = 'default';

    get indicatorClass() {
        return this.size === 'large'
            ? 'cio-indicator cio-indicator_large'
            : 'cio-indicator';
    }
}