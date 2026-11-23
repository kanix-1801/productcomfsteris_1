// Pricing Program Manager
// Runs as a Lightning tab (add it to the Price Management app). Lists PricingProgram__c records and edits one
// program in guided steps:
//   Pricing Program            Program & Category Codes  >  Inclusions & Exclusions  >  Review & Save
//   On Location - Mobile Van   Program & Service Codes   >  Review & Save
//   any other type             Program                   >  Review & Save
// Everything is kept in one in-memory draft until Save Program, so moving between steps never loses work.
import { LightningElement, wire } from 'lwc';
import { getObjectInfo, getPicklistValuesByRecordType } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import LightningConfirm from 'lightning/confirm';
import PROGRAM_OBJECT from '@salesforce/schema/PricingProgram__c';
import RULE_OBJECT from '@salesforce/schema/PricingProgramIncExc__c';
import listPrograms from '@salesforce/apex/PricingProgramController.listPrograms';
import getProgram from '@salesforce/apex/PricingProgramController.getProgram';
import searchCodes from '@salesforce/apex/PricingProgramController.searchCodes';
import saveProgram from '@salesforce/apex/PricingProgramController.saveProgram';
import PricingProgramPaste from 'c/pricingProgramPaste';

const TYPE_PRICING = 'Pricing Program';
const TYPE_ONL = 'On Location - Mobile Van';
const CODE_CATEGORY = { [TYPE_PRICING]: 'Category Code', [TYPE_ONL]: 'Service Code' };
const CODE_TITLE = { [TYPE_PRICING]: 'Category Codes', [TYPE_ONL]: 'Service Codes' };
const INCLUSION = 'Inclusion';
const EXCLUSION = 'Exclusion';

// Rule form key -> PricingProgramIncExc__c picklist field (options come from the org, dependencies honoured).
const RULE_PICKLISTS = {
    productLine: 'ProductLine__c',
    subProductLine: 'SubProductLine__c',
    productType: 'ProductType__c',
    manufacturer: 'Manufacturer__c'
};

const COLUMNS = [
    { label: 'Program Name', fieldName: 'programName', type: 'button',
      typeAttributes: { label: { fieldName: 'programName' }, name: 'open', variant: 'base' } },
    { label: 'Number', fieldName: 'recordNumber', initialWidth: 130 },
    { label: 'Type', fieldName: 'programType', initialWidth: 240 },
    { label: 'Status', fieldName: 'status', initialWidth: 110 },
    { label: 'Start Date', fieldName: 'startDate', type: 'date-local', initialWidth: 130 },
    { label: 'End Date', fieldName: 'endDate', type: 'date-local', initialWidth: 130 }
];

let keySeq = 0;
const newKey = (prefix) => `${prefix}-${Date.now()}-${++keySeq}`;
const emptyRule = () => ({
    clientId: null, id: null, kind: INCLUSION, parentId: null,
    productLine: '', subProductLine: '', productType: '', manufacturer: '',
    model: '', department: '', maxQuantity: null, startDate: null, endDate: null
});
const errorText = (e) => (e && e.body && e.body.message) || (e && e.message) || 'Something went wrong.';
const formatDate = (iso) => {
    if (!iso) return '';
    const [y, m, d] = iso.split('-');
    return `${Number(m)}/${Number(d)}/${y}`;
};

export default class PricingProgramManager extends LightningElement {
    columns = COLUMNS;

    // list view
    view = 'list';
    programs = [];
    searchTerm = '';
    typeFilter = '';
    statusFilter = '';

    // editor
    draft = null;
    step = 'main';
    visited = ['main'];
    dirty = false;
    ruleForm = emptyRule();
    editClientId = null;
    codeTerm = '';
    codeResults = [];
    searchTimer;
    busy = false;
    errorMessage = '';

    // org metadata
    programRtId;
    ruleRtId;
    ruleInfo;
    programPicklists = {};
    rulePicklists = {};

    connectedCallback() {
        this.loadPrograms();
    }

    @wire(getObjectInfo, { objectApiName: PROGRAM_OBJECT })
    wiredProgramInfo({ data }) {
        if (data) this.programRtId = data.defaultRecordTypeId;
    }

    @wire(getObjectInfo, { objectApiName: RULE_OBJECT })
    wiredRuleInfo({ data }) {
        if (data) {
            this.ruleInfo = data;
            this.ruleRtId = data.defaultRecordTypeId;
        }
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: PROGRAM_OBJECT, recordTypeId: '$programRtId' })
    wiredProgramPicklists({ data }) {
        if (data) this.programPicklists = data.picklistFieldValues || {};
    }

    @wire(getPicklistValuesByRecordType, { objectApiName: RULE_OBJECT, recordTypeId: '$ruleRtId' })
    wiredRulePicklists({ data }) {
        if (data) this.rulePicklists = data.picklistFieldValues || {};
    }

    // ================================================================ LIST

    async loadPrograms() {
        this.busy = true;
        try {
            this.programs = await listPrograms();
        } catch (e) {
            this.toast('Could not load pricing programs', errorText(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    get isList() {
        return this.view === 'list';
    }

    get filteredPrograms() {
        const term = this.searchTerm.trim().toLowerCase();
        return this.programs.filter((p) => {
            if (this.typeFilter && p.programType !== this.typeFilter) return false;
            if (this.statusFilter && p.status !== this.statusFilter) return false;
            if (!term) return true;
            return [p.programName, p.displayName, p.recordNumber].some((v) => v && v.toLowerCase().includes(term));
        });
    }

    get filteredCount() {
        return this.filteredPrograms.length;
    }

    get typeOptions() {
        const pf = this.programPicklists.Type__c;
        const values = pf ? pf.values.map((v) => ({ label: v.label, value: v.value })) : [TYPE_PRICING, TYPE_ONL].map((v) => ({ label: v, value: v }));
        return values;
    }

    get statusOptions() {
        const pf = this.programPicklists.Status__c;
        return pf ? pf.values.map((v) => ({ label: v.label, value: v.value })) : [{ label: 'Draft', value: 'Draft' }, { label: 'Active', value: 'Active' }];
    }

    get typeFilterOptions() {
        return [{ label: 'All types', value: '' }, ...this.typeOptions];
    }

    get statusFilterOptions() {
        return [{ label: 'All statuses', value: '' }, ...this.statusOptions];
    }

    handleSearch(event) {
        this.searchTerm = event.detail.value || '';
    }

    handleTypeFilter(event) {
        this.typeFilter = event.detail.value;
    }

    handleStatusFilter(event) {
        this.statusFilter = event.detail.value;
    }

    handleRowAction(event) {
        if (event.detail.action.name === 'open') this.openProgram(event.detail.row.id);
    }

    async openProgram(programId) {
        this.busy = true;
        try {
            const d = await getProgram({ programId });
            this.startEditing({
                id: d.id,
                recordNumber: d.recordNumber,
                programType: d.programType,
                programName: d.programName || '',
                displayName: d.displayName || '',
                status: d.status,
                startDate: d.startDate,
                endDate: d.endDate,
                codes: (d.codes || []).map((c) => ({ key: c.id || newKey('c'), id: c.id, productId: c.productId, code: c.code, name: c.name })),
                rules: (d.rules || []).map((r) => ({ ...emptyRule(), ...this.cleanRule(r), clientId: r.clientId || r.id }))
            });
        } catch (e) {
            this.toast('Could not open the program', errorText(e), 'error');
        } finally {
            this.busy = false;
        }
    }

    handleNew() {
        const firstType = this.typeOptions.length ? this.typeOptions[0].value : TYPE_PRICING;
        this.startEditing({
            id: null, recordNumber: null, programType: firstType, programName: '', displayName: '',
            status: 'Draft', startDate: null, endDate: null, codes: [], rules: []
        });
    }

    startEditing(draft) {
        this.draft = draft;
        this.step = 'main';
        this.visited = ['main'];
        this.dirty = false;
        this.errorMessage = '';
        this.resetRuleForm();
        this.codeTerm = '';
        this.codeResults = [];
        this.view = 'edit';
    }

    cleanRule(r) {
        const out = {};
        Object.keys(emptyRule()).forEach((k) => {
            out[k] = r[k] === undefined || r[k] === null ? emptyRule()[k] : r[k];
        });
        return out;
    }

    // ================================================================ EDITOR: shared

    get isNew() {
        return this.draft && !this.draft.id;
    }

    get programType() {
        return this.draft ? this.draft.programType : null;
    }

    get hasCodes() {
        return !!CODE_CATEGORY[this.programType];
    }

    get hasRules() {
        return this.programType === TYPE_PRICING;
    }

    get codesTitle() {
        return CODE_TITLE[this.programType] || 'Codes';
    }

    get steps() {
        const s = ['main'];
        if (this.hasRules) s.push('rules');
        s.push('review');
        return s;
    }

    stepLabel(step) {
        if (step === 'main') return this.hasCodes ? `Program & ${this.codesTitle}` : 'Program';
        if (step === 'rules') return 'Inclusions & Exclusions';
        return 'Review & Save';
    }

    get currentStep() {
        return this.steps.includes(this.step) ? this.step : 'main';
    }

    get pathSteps() {
        const cur = this.currentStep;
        return this.steps.map((s) => {
            const now = s === cur;
            const done = !now && this.visited.includes(s);
            return {
                key: s,
                label: (done ? '✓ ' : '') + this.stepLabel(s),
                current: now ? 'step' : 'false',
                cls: 'path-btn ' + (now ? 'is-current' : done ? 'is-complete' : 'is-incomplete')
            };
        });
    }

    get onMain() {
        return this.currentStep === 'main';
    }

    get onRules() {
        return this.currentStep === 'rules';
    }

    get onReview() {
        return this.currentStep === 'review';
    }

    get titleText() {
        return this.isNew ? 'New Pricing Program' : this.draft.programName || this.draft.recordNumber;
    }

    get subText() {
        return this.isNew ? this.programType : `${this.draft.recordNumber} · ${this.programType}`;
    }

    get statusText() {
        return this.isNew ? 'New' : this.draft.status;
    }

    get statusClass() {
        const s = this.statusText;
        return 'status-pill ' + (s === 'Active' ? 'is-active' : s === 'New' ? 'is-new' : 'is-draft');
    }

    get hasBack() {
        return this.steps.indexOf(this.currentStep) > 0;
    }

    get nextLabel() {
        const i = this.steps.indexOf(this.currentStep);
        return i < this.steps.length - 1 ? `Next: ${this.stepLabel(this.steps[i + 1])}` : 'Save Program';
    }

    go(step) {
        this.errorMessage = '';
        this.step = step;
        if (!this.visited.includes(step)) this.visited = [...this.visited, step];
    }

    handleStepClick(event) {
        this.go(event.currentTarget.dataset.step);
    }

    handleBack() {
        const i = this.steps.indexOf(this.currentStep);
        if (i > 0) this.go(this.steps[i - 1]);
    }

    handleNext() {
        const i = this.steps.indexOf(this.currentStep);
        if (this.currentStep === 'main' && !this.checkMain(true)) return;
        if (i < this.steps.length - 1) {
            this.go(this.steps[i + 1]);
        } else {
            this.save();
        }
    }

    async handleCancel() {
        if (this.dirty) {
            const ok = await LightningConfirm.open({
                label: 'Discard changes?',
                message: 'You have unsaved changes to this program. Discard them?',
                theme: 'warning'
            });
            if (!ok) return;
        }
        this.view = 'list';
        this.draft = null;
    }

    markDirty() {
        this.dirty = true;
    }

    // ================================================================ STEP 1: program + codes

    handleTypeChange(event) {
        const next = event.detail.value;
        const sameCodes = CODE_CATEGORY[next] === CODE_CATEGORY[this.programType];
        this.draft = {
            ...this.draft,
            programType: next,
            codes: sameCodes ? this.draft.codes : [],
            rules: next === TYPE_PRICING ? this.draft.rules : []
        };
        this.codeTerm = '';
        this.codeResults = [];
        this.markDirty();
    }

    handleHeaderChange(event) {
        const field = event.target.dataset.field;
        this.draft = { ...this.draft, [field]: event.detail.value || (field === 'startDate' || field === 'endDate' ? null : '') };
        this.markDirty();
    }

    /** Display Name defaults to Program Name when it is blank, once focus leaves Program Name. */
    handleProgramNameBlur() {
        const name = (this.draft.programName || '').trim();
        if (name && !(this.draft.displayName || '').trim()) {
            this.draft = { ...this.draft, displayName: name };
            this.markDirty();
        }
    }

    /** Data checks used before Next and Save; showUi also lights up the field errors on step 1. */
    checkMain(showUi) {
        let ok = true;
        if (showUi) {
            this.template.querySelectorAll('.hdr').forEach((el) => {
                if (!el.reportValidity()) ok = false;
            });
        }
        const d = this.draft;
        let msg = '';
        if (!d.programType || !d.programName || !d.programName.trim() || !d.startDate || !d.status) {
            msg = 'Complete the required program fields.';
        } else if (d.endDate && d.endDate < d.startDate) {
            msg = 'End Date can’t be before Start Date.';
        } else if (this.hasCodes && !d.codes.length) {
            msg = `Add at least one ${CODE_CATEGORY[d.programType]}.`;
        }
        this.errorMessage = msg;
        return ok && !msg;
    }

    get addLabel() {
        return `Add ${this.codesTitle.toLowerCase()}: type a code or name, Enter adds`;
    }

    get codeCount() {
        return this.draft.codes.length;
    }

    get codeRows() {
        return this.draft.codes.map((c) => ({ ...c, removeLabel: `Remove ${c.code}` }));
    }

    get showCodeResults() {
        return this.codeResults.length > 0;
    }

    get codeResultRows() {
        return this.codeResults.map((m, i) => ({ ...m, cls: 'result' + (i === 0 ? ' is-top' : '') }));
    }

    handleCodeTerm(event) {
        this.codeTerm = event.detail.value || '';
        clearTimeout(this.searchTimer);
        if (this.codeTerm.trim().length < 2) {
            this.codeResults = [];
            return;
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        this.searchTimer = setTimeout(() => this.runCodeSearch(), 250);
    }

    async runCodeSearch() {
        this.searchTimer = null;
        const term = this.codeTerm;
        try {
            const found = await searchCodes({ term, programType: this.programType });
            if (term !== this.codeTerm) return; // a newer search is coming
            const have = new Set(this.draft.codes.map((c) => c.productId));
            this.codeResults = (found || []).filter((f) => !have.has(f.productId)).map((f) => ({ ...f, id: f.productId }));
        } catch (e) {
            this.codeResults = [];
            this.errorMessage = errorText(e);
        }
    }

    async handleCodeKeyDown(event) {
        if (event.key === 'Escape') {
            this.codeResults = [];
            return;
        }
        if (event.key !== 'Enter') return;
        event.preventDefault();
        if (this.searchTimer) {
            clearTimeout(this.searchTimer);
            await this.runCodeSearch();
        }
        if (this.codeResults.length) this.addCode(this.codeResults[0]);
    }

    handleAddResult(event) {
        const match = this.codeResults.find((m) => m.id === event.currentTarget.dataset.id);
        if (match) this.addCode(match);
    }

    addCode(product) {
        if (this.draft.codes.some((c) => c.productId === product.productId)) return;
        this.draft = {
            ...this.draft,
            codes: [...this.draft.codes, { key: newKey('c'), id: null, productId: product.productId, code: product.code, name: product.name }]
        };
        this.codeTerm = '';
        this.codeResults = [];
        this.errorMessage = '';
        this.markDirty();
        const box = this.template.querySelector('.code-input');
        if (box) box.focus();
    }

    handleRemoveCode(event) {
        const key = event.currentTarget.dataset.key;
        this.draft = { ...this.draft, codes: this.draft.codes.filter((c) => c.key !== key) };
        this.markDirty();
    }

    async handlePaste() {
        const added = await PricingProgramPaste.open({
            size: 'medium',
            label: `Paste ${this.codesTitle}`,
            programType: this.programType,
            codesLabel: this.codesTitle,
            existingProductIds: this.draft.codes.map((c) => c.productId)
        });
        if (!Array.isArray(added) || !added.length) return;
        const have = new Set(this.draft.codes.map((c) => c.productId));
        const fresh = added.filter((a) => !have.has(a.productId))
            .map((a) => ({ key: newKey('c'), id: null, productId: a.productId, code: a.code, name: a.name }));
        this.draft = { ...this.draft, codes: [...this.draft.codes, ...fresh] };
        this.errorMessage = '';
        this.markDirty();
    }

    // ================================================================ STEP 2: inclusions & exclusions

    get inclusions() {
        return this.draft.rules.filter((r) => r.kind !== EXCLUSION);
    }

    inclusionName(clientId) {
        return `Inclusion ${this.inclusions.findIndex((r) => r.clientId === clientId) + 1}`;
    }

    get orderedRules() {
        const out = [];
        this.inclusions.forEach((inc) => {
            out.push(inc);
            this.draft.rules.filter((r) => r.kind === EXCLUSION && r.parentId === inc.clientId).forEach((x) => out.push(x));
        });
        return out;
    }

    get ruleSummary() {
        const inc = this.inclusions.length;
        const exc = this.draft.rules.length - inc;
        return `${inc} inclusion${inc === 1 ? '' : 's'}, ${exc} exclusion${exc === 1 ? '' : 's'}`;
    }

    get isEditingRule() {
        return !!this.editClientId;
    }

    get ruleFormTitle() {
        const f = this.ruleForm;
        if (this.isEditingRule) {
            return f.kind === EXCLUSION ? `Edit Exclusion under ${this.inclusionName(f.parentId)}` : `Edit ${this.inclusionName(f.clientId)}`;
        }
        return f.kind === EXCLUSION ? `New Exclusion under ${this.inclusionName(f.parentId)}` : 'New Inclusion';
    }

    get ruleSaveLabel() {
        return this.isEditingRule ? 'Save Changes' : 'Add Rule';
    }

    get ruleCancelLabel() {
        return this.isEditingRule ? 'Cancel' : 'Clear';
    }

    picklistOptions(key) {
        const field = RULE_PICKLISTS[key];
        const pf = this.rulePicklists[field];
        if (!pf) return [{ label: 'Any', value: '' }];
        let values = pf.values;
        const ctrlField = this.ruleInfo && this.ruleInfo.fields[field] ? this.ruleInfo.fields[field].controllerName : null;
        if (ctrlField && pf.controllerValues) {
            const ctrlKey = Object.keys(RULE_PICKLISTS).find((k) => RULE_PICKLISTS[k] === ctrlField);
            const ctrlValue = ctrlKey ? this.ruleForm[ctrlKey] : null;
            if (ctrlValue && pf.controllerValues[ctrlValue] !== undefined) {
                const idx = pf.controllerValues[ctrlValue];
                values = values.filter((v) => v.validFor.includes(idx));
            }
        }
        return [{ label: 'Any', value: '' }, ...values.map((v) => ({ label: v.label, value: v.value }))];
    }

    get productLineOptions() {
        return this.picklistOptions('productLine');
    }

    get subProductLineOptions() {
        return this.picklistOptions('subProductLine');
    }

    get productTypeOptions() {
        return this.picklistOptions('productType');
    }

    get manufacturerOptions() {
        return this.picklistOptions('manufacturer');
    }

    handleRuleField(event) {
        const field = event.target.dataset.field;
        let value = event.detail.value;
        if (value === undefined || value === '') value = field === 'startDate' || field === 'endDate' || field === 'maxQuantity' ? null : '';
        const next = { ...this.ruleForm, [field]: value };
        // A changed controlling picklist clears its dependents.
        if (RULE_PICKLISTS[field] && this.ruleInfo) {
            Object.keys(RULE_PICKLISTS).forEach((k) => {
                const info = this.ruleInfo.fields[RULE_PICKLISTS[k]];
                if (info && info.controllerName === RULE_PICKLISTS[field]) next[k] = '';
            });
        }
        this.ruleForm = next;
    }

    handleRuleSave() {
        const f = this.ruleForm;
        if (f.maxQuantity !== null && f.maxQuantity !== '' && Number(f.maxQuantity) < 0) {
            this.errorMessage = 'Max Quantity can’t be negative.';
            return;
        }
        const allValid = [...this.template.querySelectorAll('.rule-field')].reduce((ok, el) => el.reportValidity() && ok, true);
        if (!allValid) return;
        const rec = { ...f, maxQuantity: f.maxQuantity === '' || f.maxQuantity === null ? null : Number(f.maxQuantity) };
        let rules;
        let savedId;
        if (this.isEditingRule) {
            savedId = this.editClientId;
            rules = this.draft.rules.map((r) => (r.clientId === savedId ? { ...rec, clientId: r.clientId, id: r.id, kind: r.kind, parentId: r.parentId } : r));
        } else {
            savedId = newKey('r');
            rules = [...this.draft.rules, { ...rec, clientId: savedId, id: null }];
        }
        // Dates: this rule, plus the exclusions under it when it is an inclusion.
        const saved = rules.find((r) => r.clientId === savedId);
        const toCheck = rules.filter((r) => r.clientId === savedId || (saved.kind !== EXCLUSION && r.parentId === savedId));
        for (const r of toCheck) {
            const err = this.ruleDateError(r, rules);
            if (err) {
                this.errorMessage = err;
                return;
            }
        }
        this.draft = { ...this.draft, rules };
        this.errorMessage = '';
        this.resetRuleForm();
        this.markDirty();
    }

    // ---- date rules (all inclusive; a blank rule date takes its parent's date) ----

    ruleLabel(rule, rules) {
        const incs = rules.filter((r) => r.kind !== EXCLUSION);
        const n = (id) => `Inclusion ${incs.findIndex((r) => r.clientId === id) + 1}`;
        return rule.kind === EXCLUSION ? `Exclusion under ${n(rule.parentId)}` : n(rule.clientId);
    }

    /** The window a rule must sit in: the program for inclusions, the related inclusion for exclusions. */
    ruleWindow(rule, rules) {
        const d = this.draft;
        if (rule.kind !== EXCLUSION) return { start: d.startDate, end: d.endDate, whose: 'the program’s dates' };
        const parent = rules.find((r) => r.clientId === rule.parentId) || {};
        const incs = rules.filter((r) => r.kind !== EXCLUSION);
        return {
            start: parent.startDate || d.startDate,
            end: parent.endDate || d.endDate,
            whose: `Inclusion ${incs.findIndex((r) => r.clientId === rule.parentId) + 1}’s dates`
        };
    }

    ruleDateError(rule, rules) {
        const who = this.ruleLabel(rule, rules);
        if (rule.startDate && rule.endDate && rule.endDate < rule.startDate) {
            return `${who}: End Date can’t be before Start Date.`;
        }
        const w = this.ruleWindow(rule, rules);
        const range = `${formatDate(w.start) || 'no start'} – ${formatDate(w.end) || 'no end'}`;
        const outside = (v) => !!v && ((w.start && v < w.start) || (w.end && v > w.end));
        if (outside(rule.startDate)) return `${who}: Start Date must be within ${w.whose} (${range}).`;
        if (outside(rule.endDate)) return `${who}: End Date must be within ${w.whose} (${range}).`;
        return '';
    }

    rulesDateError(rules) {
        for (const r of rules) {
            const err = this.ruleDateError(r, rules);
            if (err) return err;
        }
        return '';
    }

    handleRuleCancel() {
        this.resetRuleForm();
    }

    handleNewInclusion() {
        this.resetRuleForm();
    }

    resetRuleForm() {
        this.ruleForm = emptyRule();
        this.editClientId = null;
    }

    handleAddExclusion(event) {
        this.editClientId = null;
        this.ruleForm = { ...emptyRule(), kind: EXCLUSION, parentId: event.currentTarget.dataset.id };
    }

    handleEditRule(event) {
        const rule = this.draft.rules.find((r) => r.clientId === event.currentTarget.dataset.id);
        if (!rule) return;
        this.editClientId = rule.clientId;
        this.ruleForm = { ...rule };
    }

    handleDeleteRule(event) {
        const id = event.currentTarget.dataset.id;
        this.draft = { ...this.draft, rules: this.draft.rules.filter((r) => r.clientId !== id && r.parentId !== id) };
        if (this.editClientId === id || this.ruleForm.parentId === id) this.resetRuleForm();
        this.markDirty();
    }

    get ruleRows() {
        return this.orderedRules.map((r) => {
            const inc = r.kind !== EXCLUSION;
            const editing = r.clientId === this.editClientId;
            const keys = inc
                ? [r.productLine || 'Any product line', r.subProductLine || 'any sub product line', r.productType || 'any product type',
                    r.manufacturer || 'any manufacturer', r.model ? `Model ${r.model}` : 'any model'].join(' · ')
                : [r.productLine, r.subProductLine, r.productType, r.manufacturer].filter(Boolean)
                    .concat(r.model ? [`Model ${r.model}`] : []).join(' · ') || `All equipment under ${this.inclusionName(r.parentId)}`;
            return {
                key: r.clientId,
                id: r.clientId,
                isInclusion: inc,
                label: inc ? this.inclusionName(r.clientId) : 'Exclusion',
                keys,
                details: `Department: ${r.department || 'Any'}   ·   Max Qty: ${r.maxQuantity === null || r.maxQuantity === undefined || r.maxQuantity === '' ? 'No limit' : r.maxQuantity}   ·   ${formatDate(r.startDate) || 'Program start'} – ${formatDate(r.endDate) || 'no end'}`,
                cls: 'rule-row' + (inc ? '' : ' is-exclusion') + (editing ? ' is-editing' : ''),
                labelCls: inc ? 'rule-label inc' : 'rule-label exc',
                aria: inc ? this.inclusionName(r.clientId) : 'exclusion'
            };
        });
    }

    get noRules() {
        return this.draft.rules.length === 0;
    }

    // ================================================================ REVIEW

    get reviewDetails() {
        const d = this.draft;
        return [
            { label: 'Type', value: d.programType },
            { label: 'Program Name', value: d.programName || '—' },
            { label: 'Display Name', value: d.displayName || '—' },
            { label: 'Status', value: d.status || '—' },
            { label: 'Start Date', value: formatDate(d.startDate) || '—' },
            { label: 'End Date', value: formatDate(d.endDate) || 'No end date' }
        ];
    }

    get reviewRuleRows() {
        return this.orderedRules.map((r) => {
            const inc = r.kind !== EXCLUSION;
            const vals = [r.productLine, r.subProductLine, r.productType, r.manufacturer, r.model, r.department,
                r.maxQuantity === null || r.maxQuantity === undefined ? '' : String(r.maxQuantity), formatDate(r.startDate), formatDate(r.endDate)];
            const blanks = ['Any', 'Any', 'Any', 'Any', 'Any', 'Any', '—', 'Program start', 'No end'];
            return {
                key: r.clientId,
                rowCls: inc ? '' : 'is-exclusion',
                label: inc ? this.inclusionName(r.clientId) : 'Exclusion',
                labelCls: inc ? 'cell rule-label inc' : 'cell rule-label exc indent',
                cells: vals.map((v, i) => ({
                    key: `${r.clientId}-${i}`,
                    text: v || blanks[i],
                    cls: 'cell' + (v ? '' : ' muted') + (i === 6 ? ' num' : '') + (i >= 7 ? ' nowrap' : '')
                }))
            };
        });
    }

    // ================================================================ SAVE

    async save() {
        if (!this.checkMain(false)) {
            const msg = this.errorMessage;
            this.go('main');
            this.errorMessage = msg;
            return;
        }
        if (this.hasRules) {
            const err = this.rulesDateError(this.draft.rules);
            if (err) {
                this.go('rules');
                this.errorMessage = err;
                return;
            }
        }
        const d = this.draft;
        const payload = {
            id: d.id,
            programType: d.programType,
            programName: d.programName,
            displayName: d.displayName,
            status: d.status,
            startDate: d.startDate,
            endDate: d.endDate,
            codes: this.hasCodes ? d.codes.map((c) => ({ id: c.id, productId: c.productId })) : [],
            rules: this.hasRules
                ? d.rules.map((r) => ({
                    id: r.id,
                    clientId: r.clientId,
                    kind: r.kind,
                    parentId: r.parentId,
                    productLine: r.productLine || null,
                    subProductLine: r.subProductLine || null,
                    productType: r.productType || null,
                    manufacturer: r.manufacturer || null,
                    model: r.model || null,
                    department: r.department || null,
                    maxQuantity: r.maxQuantity === '' || r.maxQuantity === undefined ? null : r.maxQuantity,
                    startDate: r.startDate || null,
                    endDate: r.endDate || null
                }))
                : []
        };
        this.busy = true;
        try {
            await saveProgram({ programJson: JSON.stringify(payload) });
            this.toast('Pricing program saved', `${d.programName} was saved.`, 'success');
            this.dirty = false;
            this.view = 'list';
            this.draft = null;
            await this.loadPrograms();
        } catch (e) {
            this.errorMessage = errorText(e);
        } finally {
            this.busy = false;
        }
    }

    toast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }
}