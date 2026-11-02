// ES Service Product Configurator: "PM Visits by Asset" modal.
// Lists the bundle's selected assets for one service product; requested visits are edited inline.
import { api } from 'lwc';
import LightningModal from 'lightning/modal';

export default class EsServiceVisitsModal extends LightningModal {
    @api productName;
    @api rows = []; // [{ id, serialNumber, name, pmPlan, standardVisits, requested }]

    filterText = '';
    showChangedOnly = false;
    draft = {};      // assetId -> requested visits being edited
    original = {};   // assetId -> requested visits when the modal opened
    version = 0;     // bumps on edits so getters re-render

    connectedCallback() {
        (this.rows || []).forEach((r) => {
            this.draft[r.id] = r.requested;
            this.original[r.id] = r.requested;
        });
    }

    get assetCount() {
        return (this.rows || []).length;
    }

    get changedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.version;
        return Object.keys(this.draft).filter((id) => this.isChanged(id)).length;
    }

    get changedLabel() {
        const n = this.changedCount;
        return `${n} asset${n === 1 ? '' : 's'} changed`;
    }

    get saveDisabled() {
        return this.changedCount === 0;
    }

    get displayRows() {
        // eslint-disable-next-line no-unused-expressions
        this.version;
        const tokens = this.filterText.toLowerCase().split(/\s+/).filter(Boolean);
        return (this.rows || [])
            .filter((r) => {
                if (this.showChangedOnly && !this.isChanged(r.id)) return false;
                if (!tokens.length) return true;
                const text = `${r.serialNumber || ''} ${r.name || ''}`.toLowerCase();
                return tokens.every((t) => text.includes(t));
            })
            .map((r) => {
                const changed = this.isChanged(r.id);
                return {
                    ...r,
                    value: this.draft[r.id],
                    changed,
                    rowClass: changed ? 'row row-changed' : 'row',
                    inputClass: changed ? 'visits-input visits-input-changed' : 'visits-input',
                    pmPlanLabel: r.pmPlan || '—',
                    standardLabel: r.standardVisits ?? '—',
                    decreaseLabel: `Decrease visits for ${r.serialNumber || r.name}`,
                    increaseLabel: `Increase visits for ${r.serialNumber || r.name}`,
                    inputLabel: `Requested visits for ${r.serialNumber || r.name}`
                };
            });
    }

    get showEmpty() {
        return this.displayRows.length === 0;
    }

    get emptyMessage() {
        if (!this.assetCount) return 'No assets are selected for the bundle yet.';
        return this.showChangedOnly ? 'No changed assets.' : 'No assets match your filter.';
    }

    isChanged(id) {
        return Number(this.draft[id]) !== Number(this.original[id]);
    }

    handleFilter(event) {
        this.filterText = event.target.value;
    }

    handleShowChangedOnly(event) {
        this.showChangedOnly = event.target.checked;
    }

    setVisits(id, value) {
        const n = Math.max(0, Math.floor(Number(value)));
        this.draft[id] = Number.isFinite(n) ? n : this.original[id];
        this.version++;
    }

    handleStep(event) {
        const { id, step } = event.currentTarget.dataset;
        this.setVisits(id, (Number(this.draft[id]) || 0) + Number(step));
    }

    handleInput(event) {
        const id = event.target.dataset.id;
        if (event.target.value === '') return; // let them finish typing
        this.setVisits(id, event.target.value);
    }

    handleCancel() {
        this.close();
    }

    handleSave() {
        this.close({ visits: { ...this.draft } });
    }
}