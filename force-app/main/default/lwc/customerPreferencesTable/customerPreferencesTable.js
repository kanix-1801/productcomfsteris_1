import { LightningElement, api } from 'lwc';

const VARIANT_CARD = 'card';

export default class CustomerPreferencesTable extends LightningElement {
    @api preferences = [];

    /** Display variant: 'table' (default) or 'card' for narrow sidebar layouts. */
    @api variant = 'table';

    get hasPreferences() {
        return (this.preferences || []).length > 0;
    }

    get isCardVariant() {
        return this.variant === VARIANT_CARD;
    }
}