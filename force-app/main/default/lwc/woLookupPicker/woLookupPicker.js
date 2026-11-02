import { LightningElement, api, track } from 'lwc';

// Offline-safe typeahead picker driven by an in-memory `options` array.
// No live Salesforce API calls — works against pre-cached (e.g. briefcased)
// data passed in by the parent.
export default class WoLookupPicker extends LightningElement {
    @api label = 'Select';
    @api placeholder = 'Search…';
    @api fieldName = '';            // identifier echoed back via change event
    @api selectedValue = '';
    @api selectedLabel = '';
    @api disabled = false;
    @api maxResults = 50;

    @track _options = [];
    @track query    = '';
    @track open     = false;

    @api
    get options() { return this._options; }
    set options(v) { this._options = Array.isArray(v) ? v : []; }

    get hasSelection() { return !!this.selectedValue; }
    get displayLabel() { return this.selectedLabel || ''; }

    get filteredOptions() {
        const q = (this.query || '').trim().toLowerCase();
        const matched = q
            ? this._options.filter(o =>
                  (o.label    || '').toLowerCase().includes(q) ||
                  (o.sublabel || '').toLowerCase().includes(q))
            : this._options;
        return matched.slice(0, this.maxResults);
    }

    get hasOptions()  { return this.filteredOptions.length > 0; }
    get inputClass()  { return this.open ? 'picker-input picker-input_open' : 'picker-input'; }

    handleFocus()      { this.open = true; }
    handleBlur()       { setTimeout(() => { this.open = false; }, 150); }
    handleInput(e)     { this.query = e.target.value; this.open = true; }

    handleSelect(e) {
        const value = e.currentTarget.dataset.value;
        const label = e.currentTarget.dataset.label;
        this.query = '';
        this.open  = false;
        this.dispatchEvent(new CustomEvent('change', {
            detail: { fieldName: this.fieldName, value, label }
        }));
    }

    handleClear() {
        this.query = '';
        this.dispatchEvent(new CustomEvent('change', {
            detail: { fieldName: this.fieldName, value: '', label: '' }
        }));
    }
}