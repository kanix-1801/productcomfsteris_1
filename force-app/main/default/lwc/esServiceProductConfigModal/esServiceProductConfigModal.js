// ES Service Product Configurator: Asset & PM Visits modal.
import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import getLineContext from '@salesforce/apex/EsServiceProductConfigController.getLineContext';
import getAssetDetails from '@salesforce/apex/EsServiceProductConfigController.getAssetDetails';

const EMPTY_ASSET = { assetId: null, assetName: null, pfclId: null, pfclName: null };

export default class EsServiceProductConfigModal extends LightningModal {
    @api productName;
    @api productId;
    @api quoteId;
    @api lineId;
    @api cached; // values saved earlier this session (take priority over the record)
    @api saveAssetHandler;  // provided by the launcher; returns { error }
    @api saveVisitsHandler; // provided by the launcher; returns { error }

    loading = true;
    loadError;
    accountId;

    // Asset section
    assetSaved = { ...EMPTY_ASSET };
    assetDraft = { ...EMPTY_ASSET };
    assetStatus; // 'saved' after a successful save
    assetError;
    assetLoading = false;

    // Requested PM Visits section
    visitsSaved = null;
    visitsDraft = null;
    visitsStatus;
    visitsError;

    async connectedCallback() {
        try {
            const ctx = await getLineContext({ quoteId: this.quoteId, lineId: this.lineId });
            this.accountId = ctx?.accountId;
            const values = { ...(ctx?.line || {}), ...(this.cached || {}) };
            this.assetSaved = {
                assetId: values.assetId || null,
                assetName: values.assetName || null,
                pfclId: values.pfclId || null,
                pfclName: values.pfclName || null
            };
            this.assetDraft = { ...this.assetSaved };
            this.visitsSaved = values.requestedVisits ?? null;
            this.visitsDraft = this.visitsSaved;
        } catch (e) {
            this.loadError = this.message(e);
        } finally {
            this.loading = false;
        }
    }

    // ---------- Asset section ----------

    get assetDirty() {
        return this.assetDraft.assetId !== this.assetSaved.assetId;
    }

    get assetSaveDisabled() {
        return !this.assetDirty || this.assetLoading;
    }

    get pfclDisplay() {
        return this.assetLoading ? 'Loading…' : this.assetDraft.pfclName || '—';
    }

    async handleAssetSelect(event) {
        const { assetId, assetName } = event.detail;
        this.assetStatus = null;
        this.assetError = null;
        if (!assetId) {
            this.assetDraft = { ...EMPTY_ASSET };
            return;
        }
        this.assetDraft = { ...EMPTY_ASSET, assetId, assetName };
        this.assetLoading = true;
        try {
            const details = await getAssetDetails({ assetId });
            if (this.assetDraft.assetId === assetId) {
                this.assetDraft = {
                    assetId,
                    assetName: details?.assetName || assetName,
                    pfclId: details?.pfclId || null,
                    pfclName: details?.pfclName || null
                };
            }
        } catch (e) {
            this.assetError = this.message(e);
        } finally {
            this.assetLoading = false;
        }
    }

    handleAssetCancel() {
        this.assetDraft = { ...this.assetSaved };
        this.assetStatus = null;
        this.assetError = null;
    }

    handleAssetSave() {
        if (!this.assetDraft.assetId) {
            this.assetError = 'Select an asset.';
            return;
        }
        const result = this.saveAssetHandler
            ? this.saveAssetHandler({ ...this.assetDraft })
            : { error: 'Save is not available.' };
        if (result?.error) {
            this.assetError = result.error;
            return;
        }
        this.assetSaved = { ...this.assetDraft };
        this.assetStatus = 'saved';
        this.assetError = null;
    }

    // ---------- Requested PM Visits section ----------

    get visitsDirty() {
        return this.normalizeVisits(this.visitsDraft) !== this.normalizeVisits(this.visitsSaved);
    }

    get visitsSaveDisabled() {
        return !this.visitsDirty;
    }

    handleVisitsChange(event) {
        this.visitsDraft = event.detail.value;
        this.visitsStatus = null;
        this.visitsError = null;
    }

    handleVisitsStep(event) {
        const step = Number(event.currentTarget.dataset.step);
        const current = Number(this.visitsDraft) || 0;
        this.visitsDraft = Math.max(0, current + step);
        this.visitsStatus = null;
        this.visitsError = null;
    }

    handleVisitsCancel() {
        this.visitsDraft = this.visitsSaved;
        this.visitsStatus = null;
        this.visitsError = null;
    }

    handleVisitsSave() {
        const input = this.template.querySelector('lightning-input[data-id="visits"]');
        if (input && !input.reportValidity()) return;
        const requestedVisits = this.normalizeVisits(this.visitsDraft);
        const result = this.saveVisitsHandler
            ? this.saveVisitsHandler({ requestedVisits })
            : { error: 'Save is not available.' };
        if (result?.error) {
            this.visitsError = result.error;
            return;
        }
        this.visitsSaved = requestedVisits;
        this.visitsDraft = requestedVisits;
        this.visitsStatus = 'saved';
    }

    // ---------- Status helpers ----------

    get assetUnsaved() {
        return this.assetDirty;
    }

    get assetJustSaved() {
        return !this.assetDirty && this.assetStatus === 'saved';
    }

    get visitsUnsaved() {
        return this.visitsDirty;
    }

    get visitsJustSaved() {
        return !this.visitsDirty && this.visitsStatus === 'saved';
    }

    handleClose() {
        this.close();
    }

    normalizeVisits(v) {
        return v === '' || v === null || v === undefined ? null : Number(v);
    }

    message(e) {
        return e?.body?.message || e?.message || 'Something went wrong.';
    }
}