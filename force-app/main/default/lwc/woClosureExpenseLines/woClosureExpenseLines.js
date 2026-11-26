/**
 * @description GW-6407: Expenses tab of the Work Order closure screen.
 *              Edit only: lines are not added or deleted here.
 * @author Sagar Anand
 */
import { LightningElement, api, wire } from 'lwc';
import { getObjectInfo, getPicklistValues } from 'lightning/uiObjectInfoApi';

import resolveExpenseTypes from '@salesforce/apex/WoDebriefRegionalExpenseController.resolveExpenseTypes';
import saveWorkOrderExpense from '@salesforce/apex/WorkOrderClosureController.saveWorkOrderExpense';

import EXPENSE_OBJECT from '@salesforce/schema/Expense';
import EXPENSE_EXPENSETYPE from '@salesforce/schema/Expense.ExpenseType';
import EXPENSE_DESCRIPTION from '@salesforce/schema/Expense.Description';
import EXPENSE_QUANTITY from '@salesforce/schema/Expense.Quantity';
import EXPENSE_UNITPRICE from '@salesforce/schema/Expense.UnitPrice';
import EXPENSE_AMOUNT from '@salesforce/schema/Expense.Amount';
import EXPENSE_TRANSACTIONDATE from '@salesforce/schema/Expense.TransactionDate';
import OVERRIDE_CODE from '@salesforce/schema/Expense.OverrideCode__c';
import EXPENSE_BILLABLE_AMOUNT from '@salesforce/schema/Expense.BillableAmount__c';
import EXPENSE_OVERRIDE_BILLABLE from '@salesforce/schema/Expense.OverrideBillableAmount__c';
import {
    filterLinesBySearch,
    fmtMoney,
    isTruthyFlag,
    openCardsWithErrors,
    saveEditsInOrder,
    todayDateString,
    validateEdits,
    withoutKey
} from 'c/woClosureUtils';

const EXPENSE_TYPE_OPTIONS = [
    { label: 'Billable', value: 'Billable' },
    { label: 'Non-Billable', value: 'Non-Billable' },
    { label: 'Airfare', value: 'Airfare' },
    { label: 'Chamber Cleaning', value: 'Chamber Cleaning' },
    { label: 'Control Program Uploading', value: 'Control Program Uploading' },
    { label: 'Kilometers', value: 'Kilometers' },
    { label: 'Loaner', value: 'Loaner' },
    { label: 'Local Purchase', value: 'Local Purchase' },
    { label: 'Meals', value: 'Meals' },
    { label: 'Mileage', value: 'Mileage' },
    { label: 'Misc.', value: 'Misc.' },
    { label: 'Parking', value: 'Parking' },
    { label: 'Shipping and Handling', value: 'Shipping and Handling' },
    { label: 'Specialty Billing', value: 'Specialty Billing' },
    { label: 'Specialty Item', value: 'Specialty Item' },
    { label: 'Sub Cost', value: 'Sub Cost' },
    { label: 'Supplies', value: 'Supplies' },
    { label: 'Tolls', value: 'Tolls' }
];

export default class WoClosureExpenseLines extends LightningElement {
    @api recordId;
    /** @description Work Order (GraphQL node) the lines belong to. */
    @api workOrder;
    /** @description Search text entered for this tab. */
    @api searchTerm = '';

    _edits = {};
    editStateMap = {};
    editErrors = {};
    _expenseRecords = [];
    _serverExpenses = [];
    /** @description Allowed Expense.ExpenseType values from Regional Control; null until loaded. */
    allowedExpenseTypes = null;
    /** @description Timestamp passed to Apex so Field Service does not reuse a stale response. */
    expenseTypeCacheBust = '0';
    /** @description True while an imperative expense-type request is in flight. */
    _expenseTypesLoading = false;
    /** @description True after the first expense-type request is started (prevents render loops). */
    _expenseTypesLoadStarted = false;
    /** @description Record type Id used for Expense.OverrideCode__c picklist values. */
    expensePicklistRecordTypeId;
    /** @description Override Code picklist options from Expense.OverrideCode__c. */
    overrideCodePicklistOptions = [];
    /** @description Reloads the expense types when the device comes back online. */
    _onlineHandler = () => {
        this._refreshAllowedExpenseTypes();
    };

    /**
     * @description Staged line edits keyed by line Id. Every change tells the parent how many lines are edited.
     */
    get _pendingEdits() {
        return this._edits;
    }
    set _pendingEdits(value) {
        this._edits = value;
        this.dispatchEvent(new CustomEvent('pendingchange', { detail: { count: Object.keys(value).length } }));
    }

    /**
     * @description True when a search is entered and no line matches it.
     */
    get hasNoSearchResults() {
        return !!(this.searchTerm ?? '').trim() && this.lineModels.length === 0;
    }

    /**
     * @description Validates the staged edits and shows the errors on their lines.
     * @return {Promise<Boolean>} True when every edit can be saved
     */
    @api
    async validate() {
        const errors = validateEdits(this._pendingEdits, edit => this._validateForSchema(edit._schema ?? 'generic', edit));
        this.editErrors = { ...this.editErrors, ...errors };
        this.editStateMap = openCardsWithErrors(this.editStateMap, this._pendingEdits, this.editErrors);
        return Object.keys(errors).length === 0;
    }

    /**
     * @description Saves the staged edits; failed edits stay staged with their error.
     * @return {Promise<Object>} okIds, failedCount and firstError
     */
    @api
    async save() {
        const pendingEdits = { ...this._pendingEdits };
        this._pendingEdits = {};
        const result = await saveEditsInOrder(pendingEdits, (id, edit) => saveWorkOrderExpense({
            workOrderId: this.recordId,
            // Expenses can belong to other technicians; the owner saves them through the closure Apex.
            expense: { sobjectType: 'Expense', ...this._buildUpdateFields(id, edit) }
        }));
        this._pendingEdits = result.failedEdits;
        this.editStateMap = {};
        this.editErrors = { ...this.editErrors, ...result.errors };
        const errorList = Object.values(result.errors);
        return { okIds: result.okIds, failedCount: errorList.length, firstError: errorList[0] ?? null };
    }

    /**
     * @description Discards the staged edits.
     */
    @api
    reset() {
        this._pendingEdits = {};
        this.editStateMap = {};
        this.editErrors = {};
    }

    /**
     * @description Handle Edit Toggle.
     */
    handleEditToggle(e) {
        const id = e.currentTarget.dataset.id;
        const cur = this.editStateMap[id];
        const opening = !cur?.isEditing;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: opening } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Expenses of all technicians on the Work Order, as returned by WorkOrderClosureController.
     */
    @api
    get lines() {
        return this._expenseRecords;
    }
    set lines(value) {
        this._expenseRecords = value ?? [];
        this._serverExpenses = this._expenseRecords.map(record => this._toExpenseRecord(record));
    }

    /**
     * @description Reloads the Regional Control expense types (when the tab is opened).
     */
    @api
    refreshExpenseTypes() {
        this._refreshAllowedExpenseTypes();
    }

    /**
     * @description Lifecycle hook invoked when the component is inserted into the DOM.
     */
    connectedCallback() {
        window.addEventListener('online', this._onlineHandler);
        this._refreshAllowedExpenseTypes();
    }

    /**
     * @description Loads Regional Control expense types once recordId is available.
     *              Field Service Screen Actions often set recordId after connectedCallback.
     */
    renderedCallback() {
        if (this.recordId && this.allowedExpenseTypes == null && !this._expenseTypesLoadStarted) {
            this._refreshAllowedExpenseTypes();
        }
    }

    /**
     * @description Lifecycle hook invoked when the component is removed from the DOM.
     */
    disconnectedCallback() {
        window.removeEventListener('online', this._onlineHandler);
    }

    /**
     * @description Line models shown on the tab.
     */
    get lineModels() {
        const lines = this._serverExpenses.map(
            e => this._buildExpenseLineModel(e, this._pendingEdits[e.Id], this.editStateMap[e.Id] ?? {})
        );
        return filterLinesBySearch(lines, this.searchTerm);
    }

    /**
     * @description Handle Edit Field Change.
     */
    handleEditFieldChange(e) {
        const value = e.detail.checked !== undefined ? e.detail.checked : e.detail.value;
        this._stageEdit(e.currentTarget.dataset.id, e.currentTarget.dataset.field, value);
    }

    /**
     * @description Internal helper: Stage Edit.
     */
    _stageEdit(id, field, value) {
        const expense = this._serverExpenses.find(e => e.Id === id);
        if (!expense) return;
        let entry = this._mergeEdit(id, this._seedExpenseEditEntry(expense), field, value);
        if (field === 'unitPrice' || field === 'quantity') {
            entry = this._applyExpenseAmountToState(entry);
        }
        if (field === 'overrideBillableAmount') {
            entry = this._applyExpenseBillableSync(entry, field);
        }
        this._pendingEdits = { ...this._pendingEdits, [id]: entry };
    }

    /**
     * @description Internal helper: Build Update Fields.
     */
    _buildUpdateFields(id, edit) {
        const next = this._applyExpenseAmountToState(edit);
        const billable = this._expenseBillableSaveValues({ ...next, ...edit });
        return {
            Id: id,
            [EXPENSE_EXPENSETYPE.fieldApiName]: next.expenseType,
            [EXPENSE_DESCRIPTION.fieldApiName]: next.description ?? '',
            [EXPENSE_QUANTITY.fieldApiName]: Number(next.quantity) || 0,
            [EXPENSE_UNITPRICE.fieldApiName]: Number(next.unitPrice) || 0,
            [EXPENSE_AMOUNT.fieldApiName]: this._computeExpenseAmount(next),
            [EXPENSE_TRANSACTIONDATE.fieldApiName]: next.transactionDate || todayDateString(),
            [OVERRIDE_CODE.fieldApiName]: billable.overrideCode || null,
            [EXPENSE_BILLABLE_AMOUNT.fieldApiName]: billable.billableAmount,
            [EXPENSE_OVERRIDE_BILLABLE.fieldApiName]: billable.overrideBillableAmount
        };
    }

    /**
     * @description Internal helper: Validate For Schema.
     */
    _validateForSchema(schema, payload) {
        return schema === 'expense' ? this._validateExpense(payload) : null;
    }

    /**
     * @description Wire: Expense object info for Override Code picklist record type.
     */
    @wire(getObjectInfo, { objectApiName: EXPENSE_OBJECT })
    wiredExpenseObjectInfo({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woClosureES getObjectInfo Expense failed', error);
            return;
        }
        if (data?.defaultRecordTypeId) {
            this.expensePicklistRecordTypeId = data.defaultRecordTypeId;
        }
    }
    @wire(getPicklistValues, {
        recordTypeId: '$expensePicklistRecordTypeId',
        fieldApiName: OVERRIDE_CODE
    })
    wiredOverrideCodePicklist({ data, error }) {
        if (error) {
            // eslint-disable-next-line no-console
            console.error('woClosureES getPicklistValues OverrideCode__c failed', error);
            return;
        }
        if (data?.values) {
            this.overrideCodePicklistOptions = data.values.map(({ label, value }) => ({ label, value }));
        }
    }
    /**
     * @description Imperatively loads Regional Control expense types.
     *              Field Service mobile often does not run @wire Apex on Screen Actions;
     *              this matches the Rate List fallback used on Travel.
     */
    async _refreshAllowedExpenseTypes() {
        if (!this.recordId || this._expenseTypesLoading) {
            return;
        }
        this._expenseTypesLoadStarted = true;
        this._expenseTypesLoading = true;
        this.expenseTypeCacheBust = String(Date.now());
        try {
            const data = await resolveExpenseTypes({
                workOrderId: this.recordId,
                cacheBust: this.expenseTypeCacheBust
            });
            this.allowedExpenseTypes = Array.isArray(data) ? data : [];
        } catch (e) {
            // No Regional Control match and Apex failures both show all types.
            this.allowedExpenseTypes = [];
            // eslint-disable-next-line no-console
            console.error('woClosureES resolveExpenseTypes failed', e);
        } finally {
            this._expenseTypesLoading = false;
        }
    }
    /**
     * @description Converts an Apex Expense to the field/value shape used by the line models.
     * @param {Object} record Expense from Apex
     * @return {Object}
     */
    _toExpenseRecord(record) {
        return {
            Id: record.Id,
            ExpenseType: { value: record.ExpenseType ?? '' },
            Description: { value: record.Description ?? '' },
            Quantity: { value: record.Quantity ?? null },
            UnitPrice: { value: record.UnitPrice ?? null },
            TotalPrice: { value: record.TotalPrice ?? null },
            Amount: { value: record.Amount ?? null },
            TransactionDate: { value: record.TransactionDate ?? '' },
            OverrideCode__c: { value: record.OverrideCode__c ?? '' },
            BillableAmount__c: { value: record.BillableAmount__c ?? null },
            OverrideBillableAmount__c: { value: record.OverrideBillableAmount__c === true }
        };
    }
    /**
     * @description Expense Type Options. Restricted by Regional Control when a match is found.
     */
    get expenseTypeOptions() {
        const allowedList = Array.isArray(this.allowedExpenseTypes)
            ? this.allowedExpenseTypes
            : [];
        if (!allowedList.length) {
            return EXPENSE_TYPE_OPTIONS;
        }
        const allowed = new Set(allowedList);
        const filtered = EXPENSE_TYPE_OPTIONS.filter((option) => allowed.has(option.value));
        for (const value of allowedList) {
            if (!filtered.some((option) => option.value === value)) {
                filtered.push({ label: value, value });
            }
        }
        return filtered.length ? filtered : EXPENSE_TYPE_OPTIONS;
    }
    /**
     * @description Override Code picklist options.
     */
    get overrideCodeOptions() { return this.overrideCodePicklistOptions; }
    /**
     * @description Handle Edit Close.
     */
    handleEditClose(e) {
        const id = e.currentTarget.dataset.id;
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: false } };
        const errs = { ...this.editErrors };
        delete errs[id];
        this.editErrors = errs;
    }

    /**
     * @description Cancel Changes: discards the staged edit and error of one line; the card shows the saved values.
     */
    handleRevertLine(e) {
        const id = e.currentTarget.dataset.id;
        this._pendingEdits = withoutKey(this._pendingEdits, id);
        this.editErrors = withoutKey(this.editErrors, id);
        this.editStateMap = { ...this.editStateMap, [id]: { isEditing: true } };
    }
    /**
     * @description Internal helper: Build Expense Line Model.
     */
    _buildExpenseLineModel(e, edit, state) {
        const expenseType = edit?.expenseType ?? e.ExpenseType?.value ?? '';
        const description = edit?.description ?? e.Description?.value ?? '';
        const transactionDate = edit?.transactionDate
            ?? e.TransactionDate?.value
            ?? todayDateString();
        const quantity = edit?.quantity ?? e.Quantity?.value ?? 0;
        const unitPrice = edit?.unitPrice ?? e.UnitPrice?.value ?? 0;
        const totalPrice = fmtMoney(this._computeTotalPrice(unitPrice, quantity));
        const overrideBillableAmount = isTruthyFlag(
            edit?.overrideBillableAmount ?? e.OverrideBillableAmount__c?.value
        );
        const computedAmount = this._computeTotalPrice(
            state.unitPrice ?? edit?.unitPrice ?? unitPrice,
            state.quantity ?? edit?.quantity ?? quantity
        );
        const billableAmount = overrideBillableAmount
            ? (edit?.billableAmount ?? e.BillableAmount__c?.value ?? computedAmount)
            : (edit?.billableAmount ?? computedAmount);
        const overrideCode = edit?.overrideCode ?? e.OverrideCode__c?.value ?? '';
        return {
            Id: e.Id,
            schema: 'expense',
            isTravelSchema: false,
            isLaborSchema: false,
            isCalibrationSchema: false,
            isExpenseSchema: true,
            title: expenseType || 'Unspecified Expense',
            metaLine: this._fmtExpenseMeta(description, quantity, unitPrice, totalPrice),
            expenseType,
            description,
            transactionDate,
            quantity,
            unitPrice,
            totalPrice,
            overrideCode,
            billableAmount,
            isEditing: state.isEditing ?? false,
            editExpenseType: state.expenseType ?? edit?.expenseType ?? expenseType,
            editDescription: state.description ?? edit?.description ?? description,
            editTransactionDate: state.transactionDate ?? edit?.transactionDate ?? transactionDate,
            editQuantity: state.quantity ?? edit?.quantity ?? quantity,
            editUnitPrice: state.unitPrice ?? edit?.unitPrice ?? unitPrice,
            editTotalPrice: fmtMoney(computedAmount),
            editOverrideCode: state.overrideCode ?? overrideCode,
            editBillableAmount: state.billableAmount ?? billableAmount,
            editBillableAmountDisplay: fmtMoney(state.billableAmount ?? billableAmount),
            editOverrideBillableAmount: isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isBillableAmountReadOnly: !isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            isOverrideCodeRequired: isTruthyFlag(
                state.overrideBillableAmount ?? overrideBillableAmount
            ),
            editError: this.editErrors[e.Id] ?? '',
            isDirty: !!edit
        };
    }
    /**
     * @description Internal helper: Merge Edit.
     */
    _mergeEdit(id, seed, field, value) {
        const existing = this._pendingEdits[id];
        return existing ? { ...existing, [field]: value } : { ...seed, [field]: value };
    }
    /**
     * @description Internal helper: Seed Expense Edit Entry.
     */
    _seedExpenseEditEntry(e) {
        const amount = e.TotalPrice?.value ?? e.Amount?.value ?? 0;
        const overrideBillableAmount = isTruthyFlag(e.OverrideBillableAmount__c?.value);
        return {
            _schema: 'expense',
            _entity: 'Expense',
            expenseType: e.ExpenseType?.value ?? '',
            description: e.Description?.value ?? '',
            transactionDate: e.TransactionDate?.value ?? todayDateString(),
            quantity: e.Quantity?.value ?? 0,
            unitPrice: e.UnitPrice?.value ?? 0,
            totalPrice: amount,
            overrideCode: e.OverrideCode__c?.value ?? '',
            overrideBillableAmount,
            billableAmount: overrideBillableAmount
                ? (e.BillableAmount__c?.value ?? amount)
                : amount
        };
    }
    /**
     * @description Internal helper: Validate Expense.
     */
    _validateExpense({
        expenseType,
        transactionDate,
        quantity,
        unitPrice,
        overrideCode,
        overrideBillableAmount,
        billableAmount
    }) {
        if (!expenseType) return 'Expense Type is required.';
        if (!transactionDate) return 'Transaction Date is required.';
        if (unitPrice === '' || unitPrice == null || Number(unitPrice) < 0) return 'Unit Price must be 0 or greater.';
        if (!quantity || Number(quantity) <= 0) return 'Quantity must be greater than 0.';
        if (isTruthyFlag(overrideBillableAmount)) {
            if (!overrideCode) {
                return 'Override Code is required when Override Billable Amount is selected.';
            }
            if (billableAmount === '' || billableAmount == null || Number.isNaN(Number(billableAmount))) {
                return 'Billable Amount is required when Override Billable Amount is selected.';
            }
        }
        return null;
    }
    /**
     * @description Internal helper: Compute Total Price.
     */
    _computeTotalPrice(unitPrice, quantity) {
        return (Number(unitPrice) || 0) * (Number(quantity) || 0);
    }
    /**
     * @description Expense Amount for display and save: Quantity × Unit Price.
     * @param {object} state Add or edit expense state
     * @return {number}
     */
    _computeExpenseAmount(state = {}) {
        return this._computeTotalPrice(state.unitPrice, state.quantity);
    }
    /**
     * @description Recalculates Total Price and synced Billable Amount from Quantity × Unit Price.
     * @param {object} state Add or edit expense state
     * @return {object}
     */
    _applyExpenseAmountToState(state = {}) {
        const qty = Number(state.quantity);
        if (!qty || qty <= 0) {
            const next = { ...state, totalPrice: null };
            if (!isTruthyFlag(next.overrideBillableAmount)) {
                next.billableAmount = next.totalPrice;
            }
            return next;
        }
        const amount = this._computeExpenseAmount(state);
        const next = {
            ...state,
            totalPrice: amount
        };
        if (!isTruthyFlag(next.overrideBillableAmount)) {
            next.billableAmount = amount;
        }
        return next;
    }
    /**
     * @description Copies Total Price into Billable Amount unless Override is selected.
     */
    _applyExpenseBillableSync(state, changedField) {
        const next = { ...state };
        if (changedField === 'overrideBillableAmount') {
            next.overrideBillableAmount = isTruthyFlag(next.overrideBillableAmount);
        }
        const override = isTruthyFlag(next.overrideBillableAmount);
        if (changedField === 'overrideBillableAmount' && !override) {
            next.billableAmount = this._computeExpenseAmount(next);
        }
        return next;
    }
    /**
     * @description Resolves Billable Amount, Override, and Override Code for save.
     */
    _expenseBillableSaveValues({
        billableAmount,
        overrideBillableAmount,
        overrideCode,
        quantity,
        unitPrice,
        expenseType,
        totalPrice
    }) {
        const override = isTruthyFlag(overrideBillableAmount);
        const amount = this._computeExpenseAmount({
            quantity,
            unitPrice,
            expenseType,
            totalPrice
        });
        const resolvedBillable = override ? Number(billableAmount) : amount;
        return {
            billableAmount: Number.isNaN(resolvedBillable) ? amount : resolvedBillable,
            overrideBillableAmount: override,
            overrideCode: overrideCode || ''
        };
    }
    /**
     * @description Internal helper: Fmt Expense Meta.
     */
    _fmtExpenseMeta(description, quantity, unitPrice, totalPrice) {
        const parts = [];
        if (description) parts.push(description);
        parts.push(`${quantity} × $${fmtMoney(unitPrice)} = $${totalPrice}`);
        return parts.join(' · ') || 'Expense';
    }
}