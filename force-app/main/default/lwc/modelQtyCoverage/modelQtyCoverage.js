// GW-4777 / GW-5676 - Contract Adjustments card for the RCA product configurator (IMS Service Agreement).
// Inclusions / Exclusions and Model Quantity are written into the configuration as JSON
// (QuoteLineItem.ModelQtyCoverage__c via a ContextFields update, like the ES Service asset components). When the
// configuration is saved, ContractModifierService creates the line's ContractModifier__c records from it:
// INC/EXC (one per inclusion and per exclusion) and MODEL QTY (one per row).
import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { publish, subscribe, unsubscribe, MessageContext, APPLICATION_SCOPE } from 'lightning/messageService';
import CONFIGURATOR_CHANNEL from '@salesforce/messageChannel/lightning__productConfigurator_notification';
import getAttributeIds from '@salesforce/apex/EsServiceProductConfigController.getAttributeIds';
import getCoverage from '@salesforce/apex/ModelQtyCoverageController.getCoverage';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';
import CONTRACT_MODIFIER_OBJECT from '@salesforce/schema/ContractModifier__c';
import PRODUCT_LINE_FIELD from '@salesforce/schema/ContractModifier__c.ProductLine__c';
import SUB_PRODUCT_LINE_FIELD from '@salesforce/schema/ContractModifier__c.SubProductLine__c';
import PRODUCT_TYPE_FIELD from '@salesforce/schema/ContractModifier__c.ProductType__c';
import getManufacturers from '@salesforce/apex/ModelQtyCoverageController.getManufacturers';
import getSubProductLines from '@salesforce/apex/ModelQtyCoverageController.getSubProductLines';
import getAssetCatalog from '@salesforce/apex/ModelQtyCoverageController.getAssetCatalog';
import { PRICING_PROGRAMS, PRICING_PROGRAM_SAMPLE_ROWS } from './pricingProgramsMockData';

const COVERAGE_FIELD = 'ModelQtyCoverage__c';
const MODEL_MAX_LENGTH = 100; // ContractModifier__c.Model__c
const QTY_MAX = 99999; // ContractModifier__c.ModelQty__c is Number(5, 0)
const ANY_OPTION = { label: 'Any', value: '' };

// The five fields that describe equipment, in order; a blank field means any value.
const FIELDS = ['productLine', 'subProductLine', 'productType', 'manufacturer', 'model'];
const FIELD_LABELS = {
    productLine: 'Product Line',
    subProductLine: 'Sub Product Line',
    productType: 'Device Type', // stored in ContractModifier__c.ProductType__c
    manufacturer: 'Manufacturer',
    model: 'Model'
};
// Inclusion / Exclusion fields picked from a list (Model is free text)
const PICKLIST_FIELDS = ['productLine', 'subProductLine', 'productType', 'manufacturer'];

const SECTION_INC_EXC = 'incExc';
const SECTION_MODEL_QTY = 'modelQty';
const SECTION_PRICING = 'pricingPrograms';
const MIN_PROGRAM_SEARCH_LENGTH = 3;
const EMPTY_ADJUSTMENTS = { inclusions: [], models: [], pricingPrograms: [], pricingProgram: null };

// A real, saved Quote Line Item Id. New lines in the configurator have temporary "ref_" Ids.
const isSavedLineId = (id) => typeof id === 'string' && id.startsWith('0QL') && (id.length === 15 || id.length === 18);
const clean = (value) => (value === undefined || value === null ? '' : String(value).trim());
const blankToNull = (value) => clean(value) || null;
const lower = (value) => clean(value).toLowerCase();
const reduceError = (e) => e?.body?.message || e?.message || 'Unexpected error.';
const pickCriteria = (source) => Object.fromEntries(FIELDS.map((f) => [f, blankToNull(source?.[f])]));
const hasAnyValue = (criteria) => FIELDS.some((f) => !!clean(criteria[f]));
const criteriaKey = (criteria) => FIELDS.map((f) => lower(criteria[f])).join('|');
const manufacturerKey = (row) => `${lower(row?.productLine)}|${lower(row?.subProductLine)}`;
// A program's CT codes (its child records) as { code, name }; an older single "ctCode" string is read as one code
const pickCtCodes = (source) => {
    const list = Array.isArray(source?.ctCodes) ? source.ctCodes : source?.ctCode ? [{ code: source.ctCode }] : [];
    return list
        .map((c) => ({ code: clean(c?.code), name: clean(c?.name) }))
        .filter((c) => c.code);
};
// Pricing Program row as stored in the JSON: program, description, CT codes
const pickProgram = (source) => ({
    program: blankToNull(source?.program),
    description: blankToNull(source?.description),
    ctCodes: pickCtCodes(source)
});
// CT Code pill: "3 CT Codes · 4410, 4412, 4415" (cut off with an ellipsis by CSS); hover/focus shows the full list
const ctCodeView = (ctCodes, keyPrefix) => {
    const codes = ctCodes || [];
    const count = codes.length;
    return {
        hasCtCodes: count > 0,
        ctCount: count,
        ctPillLabel: `${count} CT ${count === 1 ? 'Code' : 'Codes'} · ${codes.map((c) => c.code).join(', ')}`,
        ctCodeList: codes.map((c, i) => ({ key: `${keyPrefix}-ct-${i}`, code: c.code, name: c.name || '—' }))
    };
};

export default class ModelQtyCoverage extends LightningElement {
    // configuratorContext > transactionLineId: the configuration's root line
    @api rootTransactionLineId;
    // configuratorContext > transactionId: the Quote
    @api transactionId;
    // S01_DataManager > Product Details > Id (kept for flow mapping parity)
    @api currentProductId;

    // configuratorContext > currentTransactionLineId: the line the configurator opened on
    @api
    get currentTransactionLineId() {
        return this._currentLineId;
    }
    set currentTransactionLineId(value) {
        this._currentLineId = value;
        this.loadLine(this.lineId);
    }

    _currentLineId;
    currentKey; // line path from the configurator's "navigate" messages
    subscription;
    attributeId;

    // per line: values loaded from the saved record, and values saved this session (not yet on the record)
    savedByLine = {};
    sessionByLine = {};
    loadingLines = {};
    errorMessage;

    // modal state
    isModalOpen = false;
    modalError;
    activeSection = SECTION_INC_EXC;
    incRules = [];
    modelRows = [];
    pricingRows = [];
    _seq = 0;
 
    // Known Pricing Programs: name, description, CT code (dummy JSON for now, see pricingProgramsMockData.js)
    pricingPrograms = PRICING_PROGRAMS;
    // "Add pricing program" search bar
    programSearchTerm = '';
    selectedProgramNames = [];

    productLineValues = [];
    subProductLineValues = [];
    productTypeValues = [];
    // Product Line -> its valid Sub Product Lines (lower case), loaded on demand from product master data
    subProductLinesByLine = {};
    // "Product Line|Sub Product Line" -> manufacturers of the account's assets there, loaded on demand
    manufacturersByLine = {};
    // Repair assets on the account, grouped by the five fields: drives the Model Qty pickers and counts
    assetGroups = [];

    @wire(MessageContext) messageContext;

    // Picklist values need field access to ContractModifier__c; without it the UI API answers
    // "The requested resource does not exist".
    @wire(getObjectInfo, { objectApiName: CONTRACT_MODIFIER_OBJECT })
    objectInfo;

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: PRODUCT_LINE_FIELD })
    wiredProductLines({ data, error }) {
        if (data) this.productLineValues = data.values;
        else if (error) this.errorMessage = reduceError(error);
    }

    @wire(getPicklistValues, {
        recordTypeId: '$objectInfo.data.defaultRecordTypeId',
        fieldApiName: SUB_PRODUCT_LINE_FIELD
    })
    wiredSubProductLineValues({ data, error }) {
        if (data) this.subProductLineValues = data.values;
        else if (error) this.errorMessage = reduceError(error);
    }

    @wire(getPicklistValues, { recordTypeId: '$objectInfo.data.defaultRecordTypeId', fieldApiName: PRODUCT_TYPE_FIELD })
    wiredProductTypes({ data, error }) {
        if (data) this.productTypeValues = data.values;
        else if (error) this.errorMessage = reduceError(error);
    }

    @wire(getAssetCatalog, { quoteId: '$transactionId' })
    wiredAssetCatalog({ data, error }) {
        if (data) this.assetGroups = data;
        else if (error) this.errorMessage = reduceError(error);
    }

    connectedCallback() {
        if (!this.subscription) {
            this.subscription = subscribe(
                this.messageContext,
                CONFIGURATOR_CHANNEL,
                (message) => this.handleMessage(message),
                { scope: APPLICATION_SCOPE }
            );
        }
        this.loadAttributeId();
        this.loadLine(this.lineId);
    }

    disconnectedCallback() {
        unsubscribe(this.subscription);
        this.subscription = null;
    }

    handleMessage(message) {
        if (message?.action === 'navigate' && Array.isArray(message.key) && message.key.length) {
            this.currentKey = [...message.key];
            this.loadLine(this.lineId);
        }
    }

    /* =====================  LINE ON SCREEN  ===================== */

    // Path of line ids to the line on screen: [root] or [root, child line]
    get key() {
        if (this.currentKey?.length) return this.currentKey;
        const root = this.rootTransactionLineId;
        const current = this._currentLineId;
        if (root && current && current !== root) return [root, current];
        const only = current || root;
        return only ? [only] : [];
    }

    get lineId() {
        const k = this.key;
        return k.length ? k[k.length - 1] : null;
    }

    async loadAttributeId() {
        try {
            const ids = await getAttributeIds({ fieldNames: [COVERAGE_FIELD] });
            this.attributeId = ids?.[COVERAGE_FIELD];
        } catch (e) {
            // Non-fatal: handleCommit shows "Missing context attribute Id" if it's still unset on save.
        }
    }

    // Saved adjustments for lines that exist as records (loaded once per line)
    async loadLine(lineId) {
        if (!lineId || this.savedByLine[lineId] || this.loadingLines[lineId]) return;
        if (!isSavedLineId(lineId)) {
            // new line: nothing stored (Pricing Programs start from the dummy sample rows)
            this.savedByLine = { ...this.savedByLine, [lineId]: this.fromJson(null) };
            return;
        }
        this.loadingLines = { ...this.loadingLines, [lineId]: true };
        this.errorMessage = null;
        try {
            const raw = await getCoverage({ lineId });
            this.savedByLine = { ...this.savedByLine, [lineId]: this.fromJson(raw) };
        } catch (e) {
            this.errorMessage = reduceError(e);
        } finally {
            const next = { ...this.loadingLines };
            delete next[lineId];
            this.loadingLines = next;
        }
    }

    fromJson(raw) {
        let data;
        try {
            data = raw ? JSON.parse(raw) : null;
        } catch (e) {
            data = null;
        }
        return {
            inclusions: (data?.inclusions || []).map((r) => ({
                ...pickCriteria(r),
                exclusions: (r.exclusions || []).map(pickCriteria)
            })),
            models: (data?.models || []).map((m) => ({ ...pickCriteria(m), qty: Number(m.qty) })),
            // Not returned by Apex yet: falls back to the dummy sample rows
            pricingPrograms: (data?.pricingPrograms || PRICING_PROGRAM_SAMPLE_ROWS).map(pickProgram),
            pricingProgram: data?.pricingProgram || null
        };
    }

    /* =====================  SUMMARY CARD  ===================== */

    // What the line has now: values saved this session take priority over the record
    get committed() {
        const lineId = this.lineId;
        return this.sessionByLine[lineId] || this.savedByLine[lineId] || EMPTY_ADJUSTMENTS;
    }

    get isLoading() {
        return !!this.loadingLines[this.lineId];
    }
    get editDisabled() {
        return this.isLoading || !this.lineId;
    }
    get isPendingSave() {
        return !!this.sessionByLine[this.lineId];
    }

    get summaryTypes() {
        const c = this.committed;
        const incExcCount = c.inclusions.reduce((n, r) => n + 1 + r.exclusions.length, 0);
        const incExcPreview = c.inclusions
            .flatMap((r) => [
                `Include ${this.describe(r)}`,
                ...r.exclusions.map((e) => `Exclude ${this.describe(e)}`)
            ])
            .join(' · ');
        const modelPreview = c.models.map((m) => `${m.model || this.describe(m)} · ${m.qty} max`).join(' · ');
        const pricingPreview = c.pricingPrograms
            .map((p) => (p.ctCode ? `${this.programLabel(p.program)} (${p.ctCode})` : this.programLabel(p.program)))
            .join(' · ');
        return [
            {
                key: SECTION_INC_EXC,
                label: 'Inclusions / Exclusions',
                count: incExcCount,
                preview: incExcPreview || 'None configured'
            },
            {
                key: SECTION_MODEL_QTY,
                label: 'Model Quantity',
                count: c.models.length,
                preview: modelPreview || 'None configured'
            },
            {
                key: SECTION_PRICING,
                label: 'Pricing Programs',
                count: c.pricingPrograms.length,
                preview: pricingPreview || 'None configured'
            }
        ];
    }

    // A Pricing Program is stored and shown by its name, e.g. "PP-ENDO-01"
    programLabel(value) {
        return value || 'No program';
    }

    // "Manufacturer: Pentax" for a single field, otherwise the values joined: "Flexible Endoscopy / Olympus"
    describe(criteria) {
        const set = FIELDS.filter((f) => clean(criteria[f]));
        if (!set.length) return 'Any equipment';
        if (set.length === 1) return `${FIELD_LABELS[set[0]]}: ${this.displayValue(set[0], criteria[set[0]])}`;
        return set.map((f) => this.displayValue(f, criteria[f])).join(' / ');
    }

    displayValue(field, value) {
        const values = this.picklistValuesFor(field);
        const match = values?.find((v) => v.value === value);
        return match ? match.label : value;
    }

    picklistValuesFor(field) {
        if (field === 'productLine') return this.productLineValues;
        if (field === 'subProductLine') return this.subProductLineValues;
        if (field === 'productType') return this.productTypeValues;
        return null;
    }

    /* =====================  MODAL OPEN / CLOSE  ===================== */

    handleManage() {
        this.openModal(SECTION_INC_EXC);
    }

    handleOpenType(event) {
        this.openModal(event.currentTarget.dataset.section);
    }

    openModal(section) {
        if (this.editDisabled) return;
        const c = this.committed;
        this.incRules = c.inclusions.map((r) => this.newRule(r, r.exclusions));
        this.modelRows = c.models.map((m) => this.newModelRow(m, m.qty));
        if (!this.modelRows.length) this.modelRows = [this.newModelRow()];
        this.pricingRows = c.pricingPrograms.map((p) => this.newPricingRow(p));
        this.resetProgramSearch();
        this.ensureManufacturers({}); // new rows start at Any / Any
        this.incRules.forEach((r) => {
            this.ensureSubProductLines(r.productLine);
            [r, ...r.exclusions].forEach((row) => this.ensureManufacturers(row));
        });
        this.activeSection = section || SECTION_INC_EXC;
        this.modalError = null;
        this.isModalOpen = true;
    }

    handleCancelModal() {
        this.isModalOpen = false; // discards anything not committed
    }

    handleKeydown(event) {
        if (event.key === 'Escape') this.handleCancelModal();
    }

    handleSectionClick(event) {
        this.activeSection = event.currentTarget.dataset.section;
    }

    get isIncExcSection() {
        return this.activeSection === SECTION_INC_EXC;
    }
    get isModelQtySection() {
        return this.activeSection === SECTION_MODEL_QTY;
    }
    get isPricingSection() {
        return this.activeSection === SECTION_PRICING;
    }

    get navItems() {
        const incExcCount = this.incRules.reduce(
            (n, r) => n + (hasAnyValue(r) ? 1 : 0) + r.exclusions.filter(hasAnyValue).length,
            0
        );
        const modelCount = this.modelRows.filter(hasAnyValue).length;
        const pricingCount = this.pricingRows.filter((r) => r.program).length;
        return [
            { key: SECTION_INC_EXC, label: 'Inclusions / Exclusions', count: incExcCount },
            { key: SECTION_MODEL_QTY, label: 'Model Quantity', count: modelCount },
            { key: SECTION_PRICING, label: 'Pricing Programs', count: pricingCount }
        ].map((item) => {
            const active = item.key === this.activeSection;
            return {
                ...item,
                ariaCurrent: active ? 'page' : null,
                itemClass: `ca-nav-item${active ? ' ca-nav-item_active' : ''}`,
                badgeClass: `ca-nav-count${active ? ' ca-nav-count_active' : ''}`
            };
        });
    }

    get footerSummary() {
        const total = this.navItems.reduce((n, item) => n + item.count, 0);
        const noun = total === 1 ? 'adjustment' : 'adjustments';
        return `${total} ${noun} across ${this.navItems.length} types · changes are saved with the configuration`;
    }

    /* =====================  PICKLIST OPTIONS  ===================== */

    // Options for a picklist field; the current value is kept even when it is no longer offered.
    withCurrent(options, value, field) {
        const list = [ANY_OPTION, ...options];
        if (value && !options.some((o) => o.value === value)) {
            list.push({ label: this.displayValue(field, value), value });
        }
        return list;
    }

    // Sub Product Lines valid for the Product Line (all values until the master data is loaded, or with no line)
    subProductLineOptionsFor(productLine) {
        const valid = productLine ? this.subProductLinesByLine[productLine] : undefined;
        return valid
            ? this.subProductLineValues.filter((v) => valid.includes(String(v.value).toLowerCase()))
            : this.subProductLineValues;
    }

    async ensureSubProductLines(productLine) {
        if (!productLine || this.subProductLinesByLine[productLine]) return;
        try {
            const data = await getSubProductLines({ productLine });
            this.subProductLinesByLine = {
                ...this.subProductLinesByLine,
                [productLine]: (data || []).map((v) => v.toLowerCase())
            };
        } catch (e) {
            this.modalError = reduceError(e);
        }
    }

    /* =====================  INCLUSIONS / EXCLUSIONS  ===================== */

    nextKey(prefix) {
        this._seq += 1;
        return `${prefix}${this._seq}`;
    }

    newCriteriaRow(prefix, source) {
        const row = { key: this.nextKey(prefix) };
        FIELDS.forEach((f) => {
            row[f] = clean(source?.[f]);
        });
        return row;
    }

    newRule(source, exclusions = []) {
        return {
            ...this.newCriteriaRow('inc', source),
            expanded: false,
            exclusions: exclusions.map((e) => this.newCriteriaRow('exc', e))
        };
    }

    get incExcRows() {
        return this.incRules.map((rule, i) => {
            const number = i + 1;
            const exclusionCount = rule.exclusions.length;
            return {
                key: rule.key,
                number,
                ruleLabel: `Include${number}`,
                expanded: rule.expanded,
                toggleIcon: rule.expanded ? 'utility:dash' : 'utility:add',
                toggleLabel: rule.expanded ? `Hide exclusions of Include ${number}` : `Show exclusions of Include ${number}`,
                exclusionText:
                    exclusionCount === 0 ? 'No exclusions' : `${exclusionCount} exclusion${exclusionCount === 1 ? '' : 's'}`,
                exclusionTextClass: exclusionCount ? 'ca-exc-count' : 'ca-exc-none',
                rowClass: rule.expanded ? 'ca-inc-row ca-inc-row_open' : 'ca-inc-row',
                cells: this.criteriaCells(rule, rule.key, '', `Include ${number}`),
                addExclusionLabel: `Add exclusion to Include ${number}`,
                exclusions: rule.exclusions.map((exc, j) => ({
                    key: exc.key,
                    cells: this.criteriaCells(exc, rule.key, exc.key, `Include ${number} exclusion ${j + 1}`),
                    deleteLabel: `Remove exclusion ${j + 1} of Include ${number}`
                })),
                deleteLabel: `Remove Include ${number}`
            };
        });
    }

    // Manufacturers of the account's assets in the row's Product Line and Sub Product Line (either may be Any),
    // from Apex; empty until loaded
    manufacturerOptionsFor(row) {
        const names = this.manufacturersByLine[manufacturerKey(row)] || [];
        return names.map((name) => ({ label: name, value: name }));
    }

    async ensureManufacturers(row) {
        const key = manufacturerKey(row);
        if (!row || key in this.manufacturersByLine) return;
        try {
            const data = await getManufacturers({
                quoteId: this.transactionId,
                productLine: clean(row.productLine) || null,
                subProductLine: clean(row.subProductLine) || null
            });
            this.manufacturersByLine = { ...this.manufacturersByLine, [key]: data || [] };
        } catch (e) {
            this.modalError = reduceError(e);
        }
    }

    // One cell per field: a picker for the picklist fields and Manufacturer, free text for Model
    criteriaCells(row, ruleKey, excKey, prefix) {
        return FIELDS.map((field) => {
            const isPicklist = PICKLIST_FIELDS.includes(field);
            let options;
            if (field === 'productLine') options = this.withCurrent(this.productLineValues, row[field], field);
            else if (field === 'subProductLine') {
                options = this.withCurrent(this.subProductLineOptionsFor(row.productLine), row[field], field);
            } else if (field === 'productType') options = this.withCurrent(this.productTypeValues, row[field], field);
            else if (field === 'manufacturer') options = this.withCurrent(this.manufacturerOptionsFor(row), row[field], field);
            return {
                key: `${row.key}-${field}`,
                field,
                isPicklist,
                options,
                value: row[field],
                label: `${prefix} ${FIELD_LABELS[field]}`,
                maxLength: MODEL_MAX_LENGTH, // Model is the only free-text field
                ruleKey,
                excKey
            };
        });
    }

    updateCriteria(ruleKey, excKey, patch) {
        this.incRules = this.incRules.map((rule) => {
            if (rule.key !== ruleKey) return rule;
            if (!excKey) return { ...rule, ...patch };
            return { ...rule, exclusions: rule.exclusions.map((e) => (e.key === excKey ? { ...e, ...patch } : e)) };
        });
    }

    findCriteria(ruleKey, excKey) {
        const rule = this.incRules.find((r) => r.key === ruleKey);
        return excKey ? rule?.exclusions.find((e) => e.key === excKey) : rule;
    }

    async handleIncFieldChange(event) {
        const { ruleKey, excKey, field } = event.target.dataset;
        const value = clean(event.detail.value);
        this.updateCriteria(ruleKey, excKey, { [field]: value });
        if (field !== 'productLine' && field !== 'subProductLine') return;

        if (field === 'productLine') {
            await this.ensureSubProductLines(value);
            // A Sub Product Line that does not belong to the new Product Line is cleared
            const row = this.findCriteria(ruleKey, excKey);
            if (row?.subProductLine && !this.subProductLineOptionsFor(value).some((o) => o.value === row.subProductLine)) {
                this.updateCriteria(ruleKey, excKey, { subProductLine: '' });
            }
        }
        // A Manufacturer with no assets in the new Product Line / Sub Product Line is cleared
        await this.ensureManufacturers(this.findCriteria(ruleKey, excKey));
        const row = this.findCriteria(ruleKey, excKey);
        if (row?.manufacturer && !this.manufacturerOptionsFor(row).some((o) => lower(o.value) === lower(row.manufacturer))) {
            this.updateCriteria(ruleKey, excKey, { manufacturer: '' });
        }
    }

    handleAddInclusion() {
        this.incRules = [...this.incRules, this.newRule()];
    }

    handleToggleRule(event) {
        const ruleKey = event.currentTarget.dataset.ruleKey;
        this.incRules = this.incRules.map((rule) => {
            if (rule.key !== ruleKey) return rule;
            const expanded = !rule.expanded;
            // Opening a rule without exclusions starts one, ready to fill in
            const exclusions =
                expanded && !rule.exclusions.length ? [this.newCriteriaRow('exc')] : rule.exclusions;
            return { ...rule, expanded, exclusions };
        });
    }

    handleAddExclusion(event) {
        const ruleKey = event.currentTarget.dataset.ruleKey;
        this.incRules = this.incRules.map((rule) =>
            rule.key === ruleKey
                ? { ...rule, expanded: true, exclusions: [...rule.exclusions, this.newCriteriaRow('exc')] }
                : rule
        );
    }

    handleRemoveInclusion(event) {
        const ruleKey = event.currentTarget.dataset.ruleKey;
        this.incRules = this.incRules.filter((r) => r.key !== ruleKey);
    }

    handleRemoveExclusion(event) {
        const { ruleKey, excKey } = event.currentTarget.dataset;
        this.incRules = this.incRules.map((rule) =>
            rule.key === ruleKey ? { ...rule, exclusions: rule.exclusions.filter((e) => e.key !== excKey) } : rule
        );
    }

    get noIncRules() {
        return this.incRules.length === 0;
    }

    /* =====================  MODEL QUANTITY  ===================== */

    newModelRow(source, qty = null) {
        return { ...this.newCriteriaRow('mq', source), qty: qty === null || qty === undefined ? null : Number(qty) };
    }

    // Asset groups that fit every field set on the row before `upTo` (all fields when not given)
    matchingGroups(row, upTo = FIELDS.length) {
        const fields = FIELDS.slice(0, upTo).filter((f) => clean(row[f]));
        return this.assetGroups.filter((g) => fields.every((f) => lower(g[f]) === lower(row[f])));
    }

    // Choices for a field: the values found on the assets that fit the fields to its left
    modelQtyOptionsFor(row, field) {
        const index = FIELDS.indexOf(field);
        const seen = new Map();
        this.matchingGroups(row, index).forEach((g) => {
            const value = clean(g[field]);
            if (value && !seen.has(value.toLowerCase())) {
                seen.set(value.toLowerCase(), { label: this.displayValue(field, value), value });
            }
        });
        const options = [...seen.values()].sort((a, b) => a.label.localeCompare(b.label));
        return this.withCurrent(options, row[field], field);
    }

    get modelQtyRows() {
        return this.modelRows.map((row, i) => {
            const number = i + 1;
            return {
                key: row.key,
                qty: row.qty,
                qtyLabel: `Row ${number} Max Covered Devices`,
                matchingCount: this.matchingGroups(row).reduce((n, g) => n + g.assetCount, 0),
                cells: FIELDS.map((field) => ({
                    key: `${row.key}-${field}`,
                    field,
                    value: row[field],
                    options: this.modelQtyOptionsFor(row, field),
                    label: `Row ${number} ${FIELD_LABELS[field]}`
                })),
                deleteLabel: `Remove row ${number}`,
                deleteDisabled: this.modelRows.length <= 1 // keep at least one row
            };
        });
    }

    updateModelRow(key, patch) {
        this.modelRows = this.modelRows.map((r) => (r.key === key ? { ...r, ...patch } : r));
    }

    // Each field narrows the choices to its right: values there that no longer fit are reset to Any
    handleModelFieldChange(event) {
        const { rowKey, field } = event.target.dataset;
        const row = { ...this.modelRows.find((r) => r.key === rowKey), [field]: clean(event.detail.value) };
        FIELDS.slice(FIELDS.indexOf(field) + 1).forEach((next) => {
            if (row[next] && !this.modelQtyOptionsFor({ ...row, [next]: '' }, next).some((o) => o.value === row[next])) {
                row[next] = '';
            }
        });
        this.updateModelRow(rowKey, row);
    }

    handleQtyChange(event) {
        const n = parseInt(event.detail.value, 10);
        this.updateModelRow(event.target.dataset.rowKey, { qty: Number.isNaN(n) ? null : n });
    }

    handleAddModelRow() {
        this.modelRows = [...this.modelRows, this.newModelRow()];
    }

    handleRemoveModelRow(event) {
        if (this.modelRows.length <= 1) return;
        const rowKey = event.currentTarget.dataset.rowKey;
        this.modelRows = this.modelRows.filter((r) => r.key !== rowKey);
    }

    /* =====================  PRICING PROGRAMS  ===================== */
    // One row per program: Program is the program name itself (e.g. "PP-ENDO-01"), shown as plain text.
    // Description and CT Code come from the program list for a known name.

    newPricingRow(source) {
        const p = pickProgram(source);
        return {
            key: this.nextKey('pp'),
            program: p.program || '',
            description: p.description || '',
            ctCode: p.ctCode || ''
        };
    }

    get pricingProgramRows() {
        return this.pricingRows.map((row, i) => {
            const number = i + 1;
            return {
                key: row.key,
                program: row.program,
                programLabel: `Pricing Program ${number} Program`,
                description: row.description || '—',
                ctCode: row.ctCode || '—',
                deleteLabel: `Remove Pricing Program ${number}`
            };
        });
    }

    get noPricingRows() {
        return this.pricingRows.length === 0;
    }

    /* ---------- Add pricing program: search + select ---------- */
    // Searches the known programs by program name, CT code or category once 3+ characters are typed.
    // Checked results are added as rows by the Add button; programs already in the table are not offered.

    get programSearchTooShort() {
        const len = this.programSearchTerm.length;
        return len > 0 && len < MIN_PROGRAM_SEARCH_LENGTH;
    }

    get isProgramSearchActive() {
        return this.programSearchTerm.length >= MIN_PROGRAM_SEARCH_LENGTH;
    }

    get programSearchResults() {
        if (!this.isProgramSearchActive) return [];
        const term = this.programSearchTerm.toLowerCase();
        const added = new Set(this.pricingRows.map((r) => r.program));
        return this.pricingPrograms
            .filter((p) => !added.has(p.program))
            .filter((p) =>
                [p.program, p.ctCode, p.category].some((v) => (v || '').toLowerCase().includes(term))
            )
            .map((p) => ({
                ...p,
                category: p.category || '—',
                selected: this.selectedProgramNames.includes(p.program),
                selectLabel: `Select ${p.program}`
            }));
    }

    get hasProgramSearchResults() {
        return this.programSearchResults.length > 0;
    }

    get noProgramSearchResults() {
        return this.isProgramSearchActive && !this.hasProgramSearchResults;
    }

    get addProgramsDisabled() {
        return this.selectedProgramNames.length === 0;
    }

    get addProgramsLabel() {
        const n = this.selectedProgramNames.length;
        return n ? `Add (${n})` : 'Add';
    }

    resetProgramSearch() {
        this.programSearchTerm = '';
        this.selectedProgramNames = [];
    }

    handlePricingProgramSearch(event) {
        this.programSearchTerm = clean(event.detail.value);
    }

    handleProgramSelect(event) {
        const program = event.target.dataset.program;
        const others = this.selectedProgramNames.filter((name) => name !== program);
        this.selectedProgramNames = event.target.checked ? [...others, program] : others;
    }

    handleAddSelectedPrograms() {
        const added = new Set(this.pricingRows.map((r) => r.program));
        const toAdd = this.pricingPrograms.filter(
            (p) => this.selectedProgramNames.includes(p.program) && !added.has(p.program)
        );
        this.pricingRows = [...this.pricingRows, ...toAdd.map((p) => this.newPricingRow(p))];
        this.resetProgramSearch();
    }

    handleRemovePricingProgram(event) {
        const ruleKey = event.currentTarget.dataset.ruleKey;
        this.pricingRows = this.pricingRows.filter((r) => r.key !== ruleKey);
    }

    /* =====================  SAVE (commit)  ===================== */

    // The adjustments as entered; fully blank rows are left out
    get workingValue() {
        const inclusions = this.incRules
            .map((rule) => ({
                ...pickCriteria(rule),
                exclusions: rule.exclusions.filter(hasAnyValue).map(pickCriteria)
            }))
            .filter((rule) => hasAnyValue(rule) || rule.exclusions.length);
        const models = this.modelRows
            .filter((row) => hasAnyValue(row) || row.qty)
            .map((row) => ({ ...pickCriteria(row), qty: row.qty }));
        const pricingPrograms = this.pricingRows.filter((row) => row.program).map(pickProgram);
        return { inclusions, models, pricingPrograms, pricingProgram: this.committed.pricingProgram || null };
    }

    get commitDisabled() {
        return JSON.stringify(this.workingValue) === JSON.stringify(this.toValue(this.committed));
    }

    toValue(adjustments) {
        return {
            inclusions: adjustments.inclusions.map((r) => ({
                ...pickCriteria(r),
                exclusions: r.exclusions.map(pickCriteria)
            })),
            models: adjustments.models.map((m) => ({ ...pickCriteria(m), qty: m.qty })),
            pricingPrograms: (adjustments.pricingPrograms || []).map(pickProgram),
            pricingProgram: adjustments.pricingProgram || null
        };
    }

    // First problem found, with the section it is in
    validate(value) {
        const seenRules = new Set();
        for (const [i, rule] of value.inclusions.entries()) {
            const name = `Include ${i + 1}`;
            if (!hasAnyValue(rule)) return { section: SECTION_INC_EXC, message: `${name} needs at least one field.` };
            if (seenRules.has(criteriaKey(rule))) {
                return { section: SECTION_INC_EXC, message: `${name} is the same as an earlier inclusion.` };
            }
            seenRules.add(criteriaKey(rule));
            const seenExclusions = new Set();
            for (const [j, exclusion] of rule.exclusions.entries()) {
                if (seenExclusions.has(criteriaKey(exclusion))) {
                    return {
                        section: SECTION_INC_EXC,
                        message: `${name}: exclusion ${j + 1} is the same as an earlier exclusion.`
                    };
                }
                seenExclusions.add(criteriaKey(exclusion));
            }
        }

        const seenModels = new Set();
        for (const [i, row] of value.models.entries()) {
            const name = `Model Quantity row ${i + 1}`;
            if (!hasAnyValue(row)) {
                return { section: SECTION_MODEL_QTY, message: `${name} needs at least one field other than Any.` };
            }
            if (!Number.isInteger(row.qty) || row.qty < 1 || row.qty > QTY_MAX) {
                return {
                    section: SECTION_MODEL_QTY,
                    message: `${name} needs Max Covered Devices as a whole number from 1 to ${QTY_MAX}.`
                };
            }
            if (seenModels.has(criteriaKey(row))) {
                return { section: SECTION_MODEL_QTY, message: `${name} is the same as an earlier row.` };
            }
            seenModels.add(criteriaKey(row));
        }

        const seenPrograms = new Set();
        for (const [i, row] of value.pricingPrograms.entries()) {
            if (seenPrograms.has(row.program)) {
                return {
                    section: SECTION_PRICING,
                    message: `Pricing Program ${i + 1}: ${this.programLabel(row.program)} is already added.`
                };
            }
            seenPrograms.add(row.program);
        }
        return null;
    }

    // Writes the adjustments into the configuration (ContextFields update on the line on screen)
    handleCommit() {
        this.modalError = null;
        const lineId = this.lineId;
        if (!lineId) {
            this.modalError = 'The quote line is not known yet. Close this window and try again.';
            return;
        }
        if (!this.attributeId) {
            this.modalError = `Missing context attribute Id for ${COVERAGE_FIELD}. Check the context definition.`;
            return;
        }
        const value = this.workingValue;
        const problem = this.validate(value);
        if (problem) {
            this.activeSection = problem.section;
            this.modalError = problem.message;
            return;
        }

        publish(this.messageContext, CONFIGURATOR_CHANNEL, {
            action: 'valueChanged',
            data: [
                {
                    key: [...this.key],
                    field: 'ContextFields',
                    attributeId: this.attributeId,
                    fieldName: COVERAGE_FIELD,
                    value: JSON.stringify(value)
                }
            ]
        });

        this.sessionByLine = { ...this.sessionByLine, [lineId]: value };
        this.isModalOpen = false;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Contract adjustments updated',
                message: 'The adjustments are stored when the configuration is saved.',
                variant: 'success'
            })
        );
    }
}