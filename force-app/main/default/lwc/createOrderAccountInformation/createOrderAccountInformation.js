import { LightningElement, api } from 'lwc';
import userId from '@salesforce/user/Id';
import getInitialContext from '@salesforce/apex/CreateReturnOrderController.getInitialContext';
import getAccountDetails from '@salesforce/apex/CreateReturnOrderController.getAccountDetails';
import getActiveInternalUsers from '@salesforce/apex/CreateReturnOrderController.getActiveInternalUsers';

/**
 * GW-4348 / GW-5996 - Shared Account Information form for Create Order flows.
 * Parents own wizard chrome (progress, Cancel/Next). This component owns the
 * Account / Sales Rep / Legacy Customer ID / Operating Unit fields and defaults.
 */
export default class CreateOrderAccountInformation extends LightningElement {
    @api sectionTitle = 'ACCOUNT INFORMATION';
    @api lockAccount = false;

    accountId = '';
    accountName = '';
    legacyCustomerId = '';
    operatingUnit = '';
    salesRepId = userId;
    operatingUnitOptions = [];
    salesRepOptions = [];
    isLoading = true;
    errorMessage;
    _showSectionTitle = true;
    _accountPickerResetNonce = 0;
    _initialized = false;

    @api
    get showSectionTitle() {
        return this._showSectionTitle;
    }
    set showSectionTitle(value) {
        if (value === false || value === 'false') {
            this._showSectionTitle = false;
            return;
        }
        this._showSectionTitle = true;
    }

    /**
     * @description Snapshot of current field values for the parent wizard.
     * @return {Object} Account information values
     */
    @api
    getValues() {
        const salesRepOption = (this.salesRepOptions || []).find(
            (option) => option.value === this.salesRepId
        );
        const operatingUnitOption = (this.operatingUnitOptions || []).find(
            (option) => option.value === this.operatingUnit
        );
        return {
            accountId: this.accountId || '',
            accountName: this.accountName || '',
            legacyCustomerId: this.legacyCustomerId || '',
            operatingUnit: this.operatingUnit || '',
            operatingUnitLabel: operatingUnitOption?.label || this.operatingUnit || '',
            salesRepId: this.salesRepId || '',
            salesRepName: salesRepOption?.label || ''
        };
    }

    /**
     * @description Applies parent-owned values into the form (e.g. after init or Cancel).
     *              Does not re-query Account; use picker change for that.
     * @param {Object} values Field values to apply
     */
    @api
    applyValues(values = {}) {
        const nextAccountId = values.accountId || '';
        const accountChanged = (this.accountId || '') !== nextAccountId;
        this.accountId = nextAccountId;
        this.accountName = values.accountName || '';
        this.legacyCustomerId = values.legacyCustomerId || '';
        this.operatingUnit = values.operatingUnit || '';
        this.salesRepId = values.salesRepId || userId;
        this.errorMessage = undefined;
        if (accountChanged) {
            this._accountPickerResetNonce += 1;
        }
        this.dispatchChange('apply');
    }

    /**
     * @description Whether required Account Information fields are complete.
     * @return {boolean}
     */
    @api
    isValid() {
        return Boolean(this.accountId && this.operatingUnit && this.salesRepId);
    }

    /**
     * @description Validates required fields and surfaces an inline error when incomplete.
     * @return {boolean}
     */
    @api
    validate() {
        if (this.isValid()) {
            this.errorMessage = undefined;
            return true;
        }
        this.errorMessage = 'Account, Sales Rep, and Operating Unit are required.';
        return false;
    }

    /**
     * @description Resets the form and remounts the Account picker.
     */
    @api
    reset() {
        this.accountId = '';
        this.accountName = '';
        this.legacyCustomerId = '';
        this.operatingUnit = '';
        this.salesRepId = userId;
        this.errorMessage = undefined;
        this._accountPickerResetNonce += 1;
        this.dispatchChange('reset');
    }

    connectedCallback() {
        if (this._initialized) {
            return;
        }
        this._initialized = true;
        this.loadReferenceData();
    }

    get accountPickerInstances() {
        return [
            {
                key: `account-${this._accountPickerResetNonce}-${this.accountId || 'empty'}`
            }
        ];
    }

    get accountPickerValue() {
        return this.accountId || undefined;
    }

    async loadReferenceData() {
        this.isLoading = true;
        this.errorMessage = undefined;
        try {
            const [context, users] = await Promise.all([
                getInitialContext({
                    recordId: null,
                    objectApiName: null,
                    recordIds: null
                }),
                getActiveInternalUsers()
            ]);

            this.operatingUnitOptions = (context?.operatingUnitOptions || []).map((option) => ({
                label: option.label,
                value: option.value
            }));
            this.salesRepOptions = (users || []).map((user) => ({
                label: user.Name,
                value: user.Id
            }));
            if (!this.salesRepId && this.salesRepOptions.length > 0) {
                this.salesRepId = userId;
            }
            this.dispatchChange('init');
        } catch (error) {
            this.errorMessage = this.normalizeError(error, 'Unable to load account information.');
        } finally {
            this.isLoading = false;
        }
    }

    async handleAccountChange(event) {
        this.accountId = event.detail?.recordId || '';
        this.errorMessage = undefined;
        if (!this.accountId) {
            this.accountName = '';
            this.legacyCustomerId = '';
            this.operatingUnit = '';
            this.dispatchChange('account');
            return;
        }
        await this.loadAccountDefaults(this.accountId);
    }

    handleFieldChange(event) {
        const field = event.target?.dataset?.field;
        if (!field) {
            return;
        }
        this[field] = event.detail?.value || '';
        this.errorMessage = undefined;
        this.dispatchChange('field', field);
    }

    async loadAccountDefaults(requestedAccountId) {
        try {
            const account = await getAccountDetails({ accountId: requestedAccountId });
            if (this.accountId !== requestedAccountId) {
                return;
            }
            if (account) {
                this.accountName = account.Name || '';
                this.legacyCustomerId = account.SystemID__c || '';
                const accountOperatingUnit = account.OrgIDs__c
                    ? String(account.OrgIDs__c).trim()
                    : '';
                if (accountOperatingUnit) {
                    this.operatingUnit = accountOperatingUnit;
                }
            }
            this.dispatchChange('account');
        } catch (error) {
            if (this.accountId !== requestedAccountId) {
                return;
            }
            this.errorMessage = this.normalizeError(error, 'Failed to load account details.');
        }
    }

    dispatchChange(source, changedField) {
        this.dispatchEvent(
            new CustomEvent('change', {
                detail: {
                    ...this.getValues(),
                    source: source || 'change',
                    changedField: changedField || null
                }
            })
        );
    }

    normalizeError(error, fallbackMessage) {
        return (
            error?.body?.message ||
            error?.message ||
            fallbackMessage ||
            'Unexpected error.'
        );
    }
}