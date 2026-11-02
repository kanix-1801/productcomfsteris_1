import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
//import getData from '@salesforce/apex/ModelQtyCoverageController.getData';
//import saveAll from '@salesforce/apex/ModelQtyCoverageController.saveAll';

const DEFAULT_ROWS = 2;
const INC_EXC_OPTIONS = [
    { label: 'Include', value: 'Include' },
    { label: 'Exclude', value: 'Exclude' }
];

// signature used to compare two model lists
const sig = (list) => JSON.stringify(list.map((m) => [m.model, m.qty]));

export default class ModelQtyConfigurator extends LightningElement {
    // Inputs from the RCA configurator screen flow (same mapping as the ES Service Assets Selected component)
    @api currentProductId;
    @api currentTransactionLineId;
    @api rootTransactionLineId;
    @api transactionId; // Quote Id - the Apex derives it from the line, kept for context/mapping parity
    // Optional direct input (e.g. when placed outside the configurator)
    @api quoteId;
    @api quoteLineItemId;

    // ----- page state -----
    isLoading = false;
    busy = false;
    isModalOpen = false;
    errorMessage;
    modalError;

    // committed = what is saved in Salesforce (drives the summary block)
    committed = { models: [], incExc: null, pricing: null };
    // staged = what each tile "Save" has applied inside the open modal (written on footer Save)
    staged = { models: [], incExc: null, pricing: null };

    // working values being edited in the tiles
    rows = [];
    wIncExc = null;
    wPricing = null;

    pricingOptions = [];
    incExcOptions = INC_EXC_OPTIONS;
    _seq = 0;
    _loadedFor;

    // The quote line the coverage belongs to: current line, else the root line of the configuration
    get lineId() {
        return this.currentTransactionLineId || this.rootTransactionLineId || this.quoteLineItemId;
    }
    get hasLineId() {
        return !!this.lineId;
    }
    get editDisabled() {
        return this.isLoading || !this.hasLineId;
    }

    // Flow inputs can arrive after the first render, so (re)load whenever the line id becomes known/changes
    renderedCallback() {
        if (this.lineId && this.lineId !== this._loadedFor) {
            this._loadedFor = this.lineId;
            this.load();
        }
    }

    @api
    refresh() {
        return this.load();
    }

    async load() {
        if (!this.lineId) return;
        this.isLoading = true;
        this.errorMessage = null;
        try {
            /*const d = await getData({ quoteLineItemId: this.lineId });
            this.committed = {
                models: (d.models || []).map((m) => ({
                    model: m.model,
                    qty: Number(m.coveredQuantity),
                    repaired: Number(m.quantityRepaired) || 0
                })),
                incExc: d.includeExclude || null,
                pricing: d.pricingProgram || null
            };
            this.pricingOptions = d.pricingOptions || [];*/
        } catch (e) {
            this.errorMessage = this.reduceError(e);
        } finally {
            this.isLoading = false;
        }
    }

    /* =====================  SUMMARY BLOCK  ===================== */

    get modelCount() {
        return this.committed.models.length;
    }
    get hasModels() {
        return this.committed.models.length > 0;
    }
    get hasData() {
        return this.hasModels || !!this.committed.incExc || !!this.committed.pricing;
    }
    get summaryModels() {
        return this.committed.models.map((m, i) => ({
            key: `s${i}`,
            number: i + 1,
            model: m.model,
            qty: m.qty,
            repaired: m.repaired
        }));
    }
    get totalCovered() {
        return this.committed.models.reduce((s, m) => s + m.qty, 0);
    }
    get totalRepaired() {
        return this.committed.models.reduce((s, m) => s + m.repaired, 0);
    }
    get incExcDisplay() {
        return this.committed.incExc || '—';
    }
    get pricingDisplay() {
        if (!this.committed.pricing) return '—';
        const o = this.pricingOptions.find((p) => p.value === this.committed.pricing);
        return o ? o.label : this.committed.pricing;
    }

    /* =====================  MODAL OPEN / CLOSE  ===================== */

    openModal() {
        this.staged = {
            models: this.committed.models.map((m) => ({ ...m })),
            incExc: this.committed.incExc,
            pricing: this.committed.pricing
        };
        this.rows = this.buildRows(this.staged.models);
        this.wIncExc = this.staged.incExc;
        this.wPricing = this.staged.pricing;
        this.modalError = null;
        this.isModalOpen = true;
    }

    handleCancelModal() {
        if (this.busy) return;
        this.isModalOpen = false; // discards anything not committed
    }

    handleKeydown(event) {
        if (event.key === 'Escape') this.handleCancelModal();
    }

    /* =====================  TILE 1: MODEL QTY  ===================== */

    newRow(model = '', qty = null, repaired = 0) {
        this._seq += 1;
        return { key: `r${this._seq}`, model, qty, repaired };
    }

    buildRows(models) {
        const list = models.map((m) => this.newRow(m.model, m.qty, m.repaired));
        if (!list.length) {
            for (let i = 0; i < DEFAULT_ROWS; i++) list.push(this.newRow());
        }
        return this.decorate(list);
    }

    decorate(list) {
        return list.map((r, i) => {
            const repaired = r.repaired || 0;
            const min = Math.max(1, repaired);
            return {
                ...r,
                number: i + 1,
                minQty: min,
                decDisabled: !(Number(r.qty) > min),
                deleteDisabled: repaired > 0, // models with repairs can't be removed
                modelDisabled: repaired > 0,
                hasRepaired: repaired > 0
            };
        });
    }

    normalizeRows() {
        return this.rows
            .filter((r) => (r.model || '').trim() || r.qty)
            .map((r) => ({
                model: (r.model || '').trim(),
                qty: Number(r.qty) || 0,
                repaired: r.repaired || 0
            }));
    }

    updateRow(key, patch) {
        this.rows = this.decorate(this.rows.map((r) => (r.key === key ? { ...r, ...patch } : r)));
    }

    handleModelChange(event) {
        this.updateRow(event.target.dataset.key, { model: event.target.value });
    }

    handleQtyChange(event) {
        const n = parseInt(event.target.value, 10);
        this.updateRow(event.target.dataset.key, { qty: Number.isNaN(n) ? null : n });
    }

    handleIncrement(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find((r) => r.key === key);
        this.updateRow(key, { qty: (Number(row.qty) || 0) + 1 });
    }

    handleDecrement(event) {
        const key = event.currentTarget.dataset.key;
        const row = this.rows.find((r) => r.key === key);
        const n = Number(row.qty) || 0;
        if (n > Math.max(1, row.repaired || 0)) this.updateRow(key, { qty: n - 1 });
    }

    handleAddRow() {
        this.rows = this.decorate([...this.rows, this.newRow()]);
    }

    handleRemoveRow(event) {
        const key = event.currentTarget.dataset.key;
        this.rows = this.decorate(this.rows.filter((r) => r.key !== key));
    }

    get modelsDirty() {
        return sig(this.normalizeRows()) !== sig(this.staged.models);
    }
    get modelsChanged() {
        return sig(this.staged.models) !== sig(this.committed.models);
    }
    get modelsUnsaved() {
        return this.modelsDirty;
    }
    get modelsReady() {
        return !this.modelsDirty && this.modelsChanged;
    }
    get modelsSaveDisabled() {
        return !this.modelsDirty || this.busy;
    }
    get modelsCancelDisabled() {
        return !this.modelsDirty || this.busy;
    }

    validateModels() {
        const filled = this.normalizeRows();
        if (!filled.length) return 'Enter at least one Model and Covered Quantity.';
        const seen = new Set();
        for (const r of filled) {
            if (!r.model || !Number.isInteger(r.qty) || r.qty < 1) {
                return 'Each row needs a Model and a whole-number Covered Quantity of at least 1.';
            }
            if (r.qty < r.repaired) {
                return `Model "${r.model}": Covered Quantity can't be less than the ${r.repaired} already repaired.`;
            }
            const k = r.model.toLowerCase();
            if (seen.has(k)) return `Model "${r.model}" is entered more than once.`;
            seen.add(k);
        }
        return null;
    }

    handleSaveModelsTile() {
        this.modalError = null;
        const problem = this.validateModels();
        if (problem) {
            this.modalError = problem;
            return;
        }
        this.staged = { ...this.staged, models: this.normalizeRows() };
        this.rows = this.buildRows(this.staged.models);
    }

    handleCancelModelsTile() {
        this.modalError = null;
        this.rows = this.buildRows(this.staged.models);
    }

    /* =====================  TILE 2: INCLUDE / EXCLUDE  ===================== */

    handleIncExcChange(event) {
        this.wIncExc = event.detail.value;
    }
    get incExcDirty() {
        return (this.wIncExc || null) !== (this.staged.incExc || null);
    }
    get incExcChanged() {
        return (this.staged.incExc || null) !== (this.committed.incExc || null);
    }
    get incExcUnsaved() {
        return this.incExcDirty;
    }
    get incExcReady() {
        return !this.incExcDirty && this.incExcChanged;
    }
    get incExcSaveDisabled() {
        return !this.incExcDirty || this.busy;
    }
    get incExcCancelDisabled() {
        return !this.incExcDirty || this.busy;
    }
    handleSaveIncExcTile() {
        this.staged = { ...this.staged, incExc: this.wIncExc };
    }
    handleCancelIncExcTile() {
        this.wIncExc = this.staged.incExc;
    }

    /* =====================  TILE 3: PRICING PROGRAM  ===================== */

    handlePricingChange(event) {
        this.wPricing = event.detail.value;
    }
    get noPricingOptions() {
        return !this.pricingOptions || !this.pricingOptions.length;
    }
    get pricingDirty() {
        return (this.wPricing || null) !== (this.staged.pricing || null);
    }
    get pricingChanged() {
        return (this.staged.pricing || null) !== (this.committed.pricing || null);
    }
    get pricingUnsaved() {
        return this.pricingDirty;
    }
    get pricingReady() {
        return !this.pricingDirty && this.pricingChanged;
    }
    get pricingSaveDisabled() {
        return !this.pricingDirty || this.busy;
    }
    get pricingCancelDisabled() {
        return !this.pricingDirty || this.busy;
    }
    handleSavePricingTile() {
        this.staged = { ...this.staged, pricing: this.wPricing };
    }
    handleCancelPricingTile() {
        this.wPricing = this.staged.pricing;
    }

    /* =====================  MODAL FOOTER SAVE (commit)  ===================== */

    get anyDirty() {
        return this.modelsDirty || this.incExcDirty || this.pricingDirty;
    }
    get anyChanged() {
        return this.modelsChanged || this.incExcChanged || this.pricingChanged;
    }
    get commitDisabled() {
        return !this.anyChanged || this.anyDirty || this.busy;
    }
    get footerHint() {
        if (this.anyDirty) return 'Save or cancel each tile with unsaved changes first.';
        if (this.anyChanged) return 'Click Save to apply your changes to the quote line.';
        return '';
    }

    async handleCommit() {
        this.modalError = null;
        this.busy = true;
        try {
            /*await saveAll({
                quoteLineItemId: this.lineId,
                payload: {
                    updateModels: this.modelsChanged,
                    models: this.staged.models.map((m) => ({ model: m.model, coveredQuantity: m.qty })),
                    updateIncExc: this.incExcChanged,
                    includeExclude: this.staged.incExc,
                    updatePricing: this.pricingChanged,
                    pricingProgram: this.staged.pricing
                }
            });*/
            this.dispatchEvent(
                new ShowToastEvent({ title: 'Saved', message: 'Model coverage updated.', variant: 'success' })
            );
            this.isModalOpen = false;
            await this.load();
            this.dispatchEvent(new CustomEvent('save'));
        } catch (e) {
            this.modalError = this.reduceError(e); // stay in the modal so nothing is lost
        } finally {
            this.busy = false;
        }
    }

    reduceError(e) {
        return e?.body?.message || e?.message || 'Unexpected error.';
    }
}