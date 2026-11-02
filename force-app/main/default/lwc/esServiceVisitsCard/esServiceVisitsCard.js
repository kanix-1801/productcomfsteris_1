// ES Service Product Configurator: card on a service product line's screen. Two modes:
//
// 1. Table ("PM Visits by Asset"): the line has no asset yet (new, or saved but not expanded).
//    Shows every asset selected on the bundle with a Requested Visits stepper per asset.
//    Save writes the visits per asset to the line as Asset_Visits__c (JSON map assetId -> visits).
//    When the configuration is saved, EsServiceLineExpansion creates one line per asset and
//    gives each line the visits entered here (default 2).
//
// 2. Single ("Asset & PM Visits"): the line already has its asset (after expansion).
//    Shows that asset, its PFCL, PM Plan and standard visits, and lets the rep change this
//    line's Requested Visits (Save writes Requested_Number_of_PM_Visits__c).
import { LightningElement, api, wire } from 'lwc';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getLineAsset from '@salesforce/apex/EsServiceAssetSelectionController.getLineAsset';
import getSavedSelection from '@salesforce/apex/EsServiceAssetSelectionController.getSavedSelection';
import getSavedVisits from '@salesforce/apex/EsServiceAssetSelectionController.getSavedVisits';
import getAssetsByIds from '@salesforce/apex/EsServiceAssetSelectionController.getAssetsByIds';
import getLineProductId from '@salesforce/apex/EsServiceAssetSelectionController.getLineProductId';

const SELECTION_FIELD = 'Selected_Assets__c';
const ASSET_VISITS_FIELD = 'Asset_Visits__c';
const LINE_VISITS_FIELD = 'Requested_Number_of_PM_Visits__c';
// TEMPORARY default until the PM Plan lookup supplies the standard number of visits.
const DEFAULT_VISITS = 2;
const EMPTY = '—';

export default class EsServiceVisitsCard extends LightningElement {
    @api rootLineId;   // configuratorContext > transactionLineId
    @api productName;  // S01_DataManager > Product Details > Name

    // configuratorContext > currentTransactionLineId: the line the configurator opened on.
    @api
    get currentLineId() {
        return this._currentLineId;
    }
    set currentLineId(value) {
        this._currentLineId = value;
        this.ensureLineLoaded();
    }

    // S01_DataManager > Product Details > Id. Used to tell the bundle screen from a child screen.
    @api
    get productId() {
        return this._productId;
    }
    set productId(value) {
        this._productId = value;
        if (!value) return;
        // Without a saved bundle line to look up, the first product is the bundle, but only
        // when the configurator opened on the bundle itself.
        if (!this.rootProductId && !this.currentKey && this.openedOnBundle) this.rootProductId = value;
        if (value === this.rootProductId) {
            this.currentKey = null;
            this.resetDrafts();
        }
        this.ensureLineLoaded();
    }

    _currentLineId;
    _productId;
    rootProductId; // the bundle's product
    currentKey;    // from the configurator's navigate messages

    attributeIds = {};
    error;
    subscription;
    savedNotice = false;

    // Single mode: lineId -> { assetId, assetName, serialNumber, pfclName, requestedVisits }
    lines = {};
    loadingLines = {};
    sessionLineVisits = {}; // lineId -> visits saved in this session
    draftLineVisits;        // undefined = no edit

    // Table mode
    assetIds = [];        // bundle selection
    assetsById = {};      // assetId -> asset row
    visitsByLine = {};    // lineId -> { assetId: visits }
    draft = {};           // assetId -> visits being edited (only changed assets)
    draftVersion = 0;
    filterText = '';
    showChangedOnly = false;

    @wire(MessageContext) messageContext;

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                CONFIGURATOR_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
        this.loadAttributeIds();
        this.loadBundleSelection();
        this.loadRootProduct();
        this.ensureLineLoaded();
    }

    get openedOnBundle() {
        return !this._currentLineId || this._currentLineId === this.rootLineId;
    }

    async loadRootProduct() {
        if (!this.rootLineId || !this.rootLineId.startsWith('0QL')) return;
        try {
            const id = await getLineProductId({ lineId: this.rootLineId });
            if (id) {
                this.rootProductId = id;
                if (this._productId === id) this.currentKey = null;
                this.ensureLineLoaded();
            }
        } catch (e) {
            // Non-fatal: without the bundle product, the card falls back to openedOnBundle / navigate messages.
        }
    }

    // Load the asset of the line on screen, however we learned which line it is.
    ensureLineLoaded() {
        if (this.key.length > 1) this.loadLine(this.lineId);
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        // Track which line is on screen.
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
            this.resetDrafts();
            if (this.currentKey.length > 1) this.loadLine(this.lineId);
        }
        // Pick up the bundle's asset selection when the Assets Selected card saves it.
        if (message?.action === 'valueChanged' && Array.isArray(message.data)) {
            const change = message.data.find((d) => d && d.fieldName === SELECTION_FIELD);
            if (change) this.applySelection(this.parseList(change.value));
        }
    }

    // ---------- Loading ----------

    async loadAttributeIds() {
        try {
            this.attributeIds = (await getAttributeIds({ fieldNames: [ASSET_VISITS_FIELD, LINE_VISITS_FIELD] })) || {};
        } catch (e) {
            // Non-fatal: publishValue shows "Missing context attribute Id" if it's still unset on save.
        }
    }

    async loadBundleSelection() {
        if (!this.rootLineId || !this.rootLineId.startsWith('0QL')) return;
        try {
            const raw = await getSavedSelection({ lineId: this.rootLineId });
            await this.applySelection(this.parseList(raw));
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Could not load the bundle’s assets.';
        }
    }

    async applySelection(ids) {
        this.assetIds = ids;
        const missing = ids.filter((id) => !this.assetsById[id]);
        if (!missing.length) return;
        try {
            const rows = await getAssetsByIds({ assetIds: missing });
            const next = { ...this.assetsById };
            (rows || []).forEach((r) => {
                next[r.id] = r;
            });
            this.assetsById = next;
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Could not load asset details.';
        }
    }

    // Loads the line's asset (single mode) and, if it has none, its saved visits per asset (table mode).
    async loadLine(lineId) {
        if (!lineId || this.lines[lineId] || this.loadingLines[lineId]) return;
        if (!lineId.startsWith('0QL')) {
            this.lines = { ...this.lines, [lineId]: {} }; // unsaved line: no asset, nothing stored
            return;
        }
        this.loadingLines = { ...this.loadingLines, [lineId]: true };
        try {
            const data = (await getLineAsset({ lineId })) || {};
            if (!data.assetName) {
                const saved = this.parseMap(await getSavedVisits({ lineId }));
                this.visitsByLine = {
                    ...this.visitsByLine,
                    [lineId]: { ...saved, ...(this.visitsByLine[lineId] || {}) }
                };
            }
            this.lines = { ...this.lines, [lineId]: data };
        } catch (e) {
            this.error = e?.body?.message || e?.message || 'Could not load this line’s asset.';
        } finally {
            const next = { ...this.loadingLines };
            delete next[lineId];
            this.loadingLines = next;
        }
    }

    parseList(raw) {
        if (!raw) return [];
        try {
            const v = JSON.parse(raw);
            return Array.isArray(v) ? v.filter(Boolean) : [];
        } catch (e) {
            return [];
        }
    }

    parseMap(raw) {
        if (!raw) return {};
        try {
            const v = JSON.parse(raw);
            return v && typeof v === 'object' && !Array.isArray(v) ? v : {};
        } catch (e) {
            return {};
        }
    }

    // ---------- Shared state ----------

    // Path of line ids to the line on screen: [bundle] or [bundle, service line].
    get key() {
        if (this.currentKey?.length) return this.currentKey;
        const onBundle = this.rootProductId && this._productId === this.rootProductId;
        if (!onBundle && this._currentLineId && this._currentLineId !== this.rootLineId) {
            return [this.rootLineId, this._currentLineId]; // opened directly on a service line
        }
        return [this.rootLineId];
    }

    get lineId() {
        const k = this.key;
        return k[k.length - 1];
    }

    // Only on a service product's screen, never on the bundle screen.
    get showCard() {
        if (this.rootProductId && this._productId === this.rootProductId) return false;
        return this.key.length > 1 || this.onServiceLine;
    }

    // On a service product's screen (known from the product), whether or not we know which line.
    get onServiceLine() {
        return !!(this.rootProductId && this._productId && this._productId !== this.rootProductId);
    }

    // On a service product's screen but the configurator hasn't told us which line yet.
    get lineUnknown() {
        return this.key.length < 2;
    }

    get line() {
        return this.lines[this.lineId] || {};
    }

    get loading() {
        return !!this.loadingLines[this.lineId];
    }

    get isSingle() {
        return !!this.line.assetName;
    }

    get cardTitle() {
        return this.isSingle ? 'Asset & PM Visits' : 'PM Visits by Asset';
    }

    get cardSubtitle() {
        return this.isSingle
            ? 'The asset this line covers'
            : 'One line per asset is created when the configuration is saved';
    }

    get countLabel() {
        if (this.isSingle || this.loading || this.lineUnknown) return '';
        const n = this.assetCount;
        return `(${n} asset${n === 1 ? '' : 's'})`;
    }

    // ---------- Pricing note ----------
    // New lines show $0.00 until the configuration is saved: they get their asset and PFCL only then.

    // Only on new lines (the table): they have no asset/PFCL until the save.
    // Lines that already have their asset reprice on screen when visits change.
    get showPriceNote() {
        return !this.lineUnknown && !this.loading && !this.isSingle && this.hasAssets;
    }

    resetDrafts() {
        this.draftLineVisits = undefined;
        this.draft = {};
        this.draftVersion++;
        this.savedNotice = false;
    }

    publishValue(fieldName, value) {
        const attributeId = this.attributeIds?.[fieldName];
        if (!attributeId) {
            this.error = `Missing context attribute Id for ${fieldName}. Check the context definition.`;
            return false;
        }
        const payload = {
            action: 'valueChanged',
            data: [{ key: [...this.key], field: 'ContextFields', attributeId, fieldName, value }]
        };
        publish(this.messageContext, CONFIGURATOR_CHANNEL, payload);
        return true;
    }

    handleCancel() {
        this.resetDrafts();
    }

    handleSave() {
        this.error = null;
        if (this.isSingle) this.saveLineVisits();
        else this.saveAssetVisits();
    }

    // ---------- Single mode ----------

    get assetLabel() {
        return this.line.assetName || EMPTY;
    }

    get serialLabel() {
        return this.line.serialNumber || EMPTY;
    }

    get pfclLabel() {
        return this.line.pfclName || EMPTY;
    }

    get pmPlanLabel() {
        return EMPTY; // PM Plan lookup to come
    }

    get standardLabel() {
        return EMPTY; // from the PM Plan, to come
    }

    get savedLineVisits() {
        const v = this.sessionLineVisits[this.lineId] ?? this.line.requestedVisits;
        return v === null || v === undefined ? DEFAULT_VISITS : Number(v);
    }

    get lineVisits() {
        return this.draftLineVisits ?? this.savedLineVisits;
    }

    get lineChanged() {
        return this.draftLineVisits !== undefined && Number(this.draftLineVisits) !== this.savedLineVisits;
    }

    get lineInputClass() {
        return this.lineChanged ? 'visits-input visits-input-changed' : 'visits-input';
    }

    setLineVisits(value) {
        const n = Math.max(0, Math.floor(Number(value)));
        if (!Number.isFinite(n)) return;
        this.draftLineVisits = n === this.savedLineVisits ? undefined : n;
        this.savedNotice = false;
    }

    handleLineStep(event) {
        this.setLineVisits(this.lineVisits + Number(event.currentTarget.dataset.step));
    }

    handleLineInput(event) {
        if (event.target.value === '') return;
        this.setLineVisits(event.target.value);
    }

    saveLineVisits() {
        const value = Number(this.draftLineVisits);
        if (!this.publishValue(LINE_VISITS_FIELD, value)) return;
        this.sessionLineVisits = { ...this.sessionLineVisits, [this.lineId]: value };
        this.draftLineVisits = undefined;
        this.savedNotice = true;
    }

    // ---------- Table mode ----------

    get savedAssetVisits() {
        return this.visitsByLine[this.lineId] || {};
    }

    savedValue(id) {
        return Number(this.savedAssetVisits[id] ?? DEFAULT_VISITS);
    }

    currentValue(id) {
        return this.draft[id] !== undefined ? Number(this.draft[id]) : this.savedValue(id);
    }

    isChanged(id) {
        return this.draft[id] !== undefined && Number(this.draft[id]) !== this.savedValue(id);
    }

    get rows() {
        // eslint-disable-next-line no-unused-expressions
        this.draftVersion;
        const tokens = this.filterText.toLowerCase().split(/\s+/).filter(Boolean);
        return this.assetIds
            .map((id) => {
                const a = this.assetsById[id] || {};
                const changed = this.isChanged(id);
                const label = a.serialNumber || a.name || id;
                return {
                    id,
                    serialNumber: a.serialNumber || '',
                    name: a.name || '',
                    pmPlanLabel: EMPTY, // PM Plan lookup to come
                    standardLabel: EMPTY, // from the PM Plan, to come
                    requested: this.currentValue(id),
                    changed,
                    rowClass: changed ? 'row-changed' : '',
                    inputClass: changed ? 'visits-input visits-input-changed' : 'visits-input',
                    decreaseLabel: `Decrease visits for ${label}`,
                    increaseLabel: `Increase visits for ${label}`,
                    inputLabel: `Requested visits for ${label}`
                };
            })
            .filter((r) => {
                if (this.showChangedOnly && !r.changed) return false;
                if (!tokens.length) return true;
                const text = `${r.serialNumber} ${r.name}`.toLowerCase();
                return tokens.every((t) => text.includes(t));
            });
    }

    get changedCount() {
        // eslint-disable-next-line no-unused-expressions
        this.draftVersion;
        return this.assetIds.filter((id) => this.isChanged(id)).length;
    }

    get tableChanged() {
        return this.changedCount > 0;
    }

    get changedLabel() {
        const n = this.changedCount;
        return `${n} asset${n === 1 ? '' : 's'} changed · not saved yet`;
    }

    get assetCount() {
        return this.assetIds.length;
    }

    get hasAssets() {
        return this.assetCount > 0;
    }

    get showEmptyFilter() {
        return this.hasAssets && this.rows.length === 0;
    }

    get emptyFilterMessage() {
        return this.showChangedOnly ? 'No changed assets.' : 'No assets match your filter.';
    }

    setAssetVisits(id, value) {
        const n = Math.max(0, Math.floor(Number(value)));
        if (!Number.isFinite(n)) return;
        const next = { ...this.draft };
        if (n === this.savedValue(id)) delete next[id];
        else next[id] = n;
        this.draft = next;
        this.draftVersion++;
        this.savedNotice = false;
    }

    handleStep(event) {
        const { id, step } = event.currentTarget.dataset;
        this.setAssetVisits(id, this.currentValue(id) + Number(step));
    }

    handleInput(event) {
        if (event.target.value === '') return;
        this.setAssetVisits(event.target.dataset.id, event.target.value);
    }

    handleFilter(event) {
        this.filterText = event.target.value;
    }

    handleShowChangedOnly(event) {
        this.showChangedOnly = event.target.checked;
    }

    saveAssetVisits() {
        // Store a value for every selected asset, so each new line gets its own.
        const value = {};
        this.assetIds.forEach((id) => {
            value[id] = this.currentValue(id);
        });
        if (!this.publishValue(ASSET_VISITS_FIELD, JSON.stringify(value))) return;
        this.visitsByLine = { ...this.visitsByLine, [this.lineId]: value };
        this.draft = {};
        this.draftVersion++;
        this.savedNotice = true;
    }
}