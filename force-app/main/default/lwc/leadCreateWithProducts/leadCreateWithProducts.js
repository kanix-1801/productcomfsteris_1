import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import hasLeadCreateWithProducts from '@salesforce/customPermission/Lead_Create_With_Products';
import createLeadWithProducts from '@salesforce/apex/LeadCreateController.createLeadWithProducts';
import previewLeadDuplicate from '@salesforce/apex/LeadCreateController.previewLeadDuplicate';
import fieldRequiredMessage from '@salesforce/label/c.LeadCreateFieldRequiredMessage';
import emailOrPhoneMessage from '@salesforce/label/c.LeadCreateEmailOrPhoneMessage';
import sourceDetailMessage from '@salesforce/label/c.LeadCreateSourceDetailMessage';
import productRequiredMessage from '@salesforce/label/c.LeadCreateProductRequiredMessage';
import savedMessage from '@salesforce/label/c.LeadCreateSavedMessage';
import failedMessage from '@salesforce/label/c.LeadCreateFailedMessage';

export default class LeadCreateWithProducts extends NavigationMixin(LightningElement) {
    @api recordTypeId;

    collectProducts = false;
    step = 'lead';
    saving = false;
    leadRecord;
    products = [];
    selectedProductIds = {};
    rowKey = 0;
    picklistRecordTypeId;
    showDuplicateWarning = false;
    duplicateMessage;
    duplicateStatus;
    duplicateReason;
    duplicateMatches = [];
    duplicateUseLayout = false;
    duplicateCanContinue = false;
    duplicateConfirmed = false;
    pendingProducts = [];
    showLeadForm = true;
    formToken = 0;
    pendingFieldReset = false;
    pageRefKey;

    connectedCallback() {
        this.products = [this.createProductRow()];
        this.picklistRecordTypeId = this.recordTypeId || undefined;
        this.resetLeadForm();
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        if (!pageRef) {
            return;
        }
        const key = JSON.stringify(pageRef.state || {});
        if (this.pageRefKey === key) {
            return;
        }
        this.pageRefKey = key;
        this.resetLeadForm();
    }

    renderedCallback() {
        if (!this.pendingFieldReset || !this.showLeadForm) {
            return;
        }
        const fields = this.template.querySelectorAll('lightning-input-field');
        if (!fields.length) {
            return;
        }
        this.pendingFieldReset = false;
        fields.forEach((field) => field.reset());
    }

    resetLeadForm() {
        this.leadRecord = undefined;
        this.step = 'lead';
        this.saving = false;
        this.duplicateConfirmed = false;
        this.showDuplicateWarning = false;
        this.duplicateCanContinue = false;
        this.duplicateMessage = null;
        this.duplicateStatus = null;
        this.duplicateReason = null;
        this.duplicateMatches = [];
        this.duplicateUseLayout = false;
        this.products = [this.createProductRow()];
        this.selectedProductIds = {};
        this.formToken += 1;
        this.pendingFieldReset = true;
        this.showLeadForm = false;
        Promise.resolve().then(() => {
            this.showLeadForm = true;
        });
    }

    @wire(getObjectInfo, { objectApiName: LEAD_OBJECT })
    wiredLeadInfo({ data }) {
        if (data && !this.picklistRecordTypeId) {
            this.picklistRecordTypeId = data.defaultRecordTypeId;
        }
    }

    get showWizard() {
        return hasLeadCreateWithProducts === true;
    }

    get leadRecordTypeId() {
        return this.recordTypeId || undefined;
    }

    get leadStepClass() {
        return this.step === 'lead' ? '' : 'slds-hide';
    }

    get productStepClass() {
        return this.step === 'products' ? '' : 'slds-hide';
    }

    get canRemoveProduct() {
        return this.products.length < 2;
    }

    get leadActionLabel() {
        return this.collectProducts ? 'Next' : 'Save';
    }

    handleLeadNext(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        const message = this.validateLead(fields);
        if (message) {
            this.toast(message, 'error');
            return;
        }

        this.duplicateConfirmed = false;
        this.showDuplicateWarning = false;
        this.leadRecord = {
            Salutation: fields.Salutation,
            FirstName: fields.FirstName,
            MiddleName: fields.MiddleName,
            LastName: fields.LastName,
            Suffix: fields.Suffix,
            Company: fields.Company,
            Email: fields.Email,
            Phone: fields.Phone,
            Status: fields.Status,
            LeadSource: fields.LeadSource,
            LeadSourceDetail__c: fields.LeadSourceDetail__c,
            Street: fields.Street,
            City: fields.City,
            State: fields.State,
            StateCode: fields.StateCode,
            PostalCode: fields.PostalCode,
            Country: fields.Country,
            CountryCode: fields.CountryCode,
            Org_ID__c: fields.Org_ID__c,
            Class_Code__c: fields.Class_Code__c
        };
        if (this.recordTypeId) {
            this.leadRecord.RecordTypeId = this.recordTypeId;
        }
        if (this.collectProducts) {
            this.step = 'products';
            return;
        }
        this.persist([]);
    }

    handleBack() {
        this.step = 'lead';
    }

    handleAddProduct() {
        this.products = [...this.readProductRows(), this.createProductRow()];
    }

    handleRemoveProduct(event) {
        const key = event.currentTarget.dataset.key;
        const remaining = this.readProductRows().filter((row) => row.key !== key);
        this.products = remaining.length ? remaining : [this.createProductRow()];
    }

    handleProductSelected(event) {
        const key = event.currentTarget.dataset.key;
        if (!key) {
            return;
        }
        this.selectedProductIds = {
            ...this.selectedProductIds,
            [key]: this.toId(event.detail ? event.detail.value : null)
        };
    }

    readProductRows() {
        const productFields = [...this.template.querySelectorAll('lightning-input-field[data-field="productId"]')];
        const parents = [...this.template.querySelectorAll('lightning-input-field[data-field="parentCategory"]')];
        const categories = [...this.template.querySelectorAll('lightning-input-field[data-field="productCategory"]')];
        return this.products.map((row, index) => ({
            key: row.key,
            productId: (productFields[index] && this.toId(productFields[index].value))
                || this.selectedProductIds[row.key]
                || row.productId
                || null,
            parentCategory: parents[index] ? parents[index].value : row.parentCategory,
            productCategory: categories[index] ? categories[index].value : row.productCategory
        }));
    }

    toId(value) {
        if (Array.isArray(value)) {
            return value.length ? value[0] : null;
        }
        return value || null;
    }

    handleSave() {
        const rows = this.readProductRows();
        const products = rows
            .filter((row) => row.productId)
            .map((row) => ({
                productId: row.productId,
                parentCategory: row.parentCategory,
                productCategory: row.productCategory
            }));
        if (!products.length) {
            this.toast(productRequiredMessage, 'error');
            return;
        }

        this.persist(products);
    }

    get duplicateHeading() {
        return this.duplicateCanContinue ? 'Possible duplicate' : 'Duplicate found';
    }

    get duplicateCloseLabel() {
        return this.duplicateCanContinue ? 'Cancel' : 'Close';
    }

    get showPhoneColumn() {
        return this.duplicateReason !== 'Exact Email Match';
    }

    get companyColumnLabel() {
        const matches = this.duplicateMatches || [];
        if (matches.length > 0 && matches.every((match) => match.accountId)) {
            return 'Customer Account';
        }
        return 'Company';
    }

    handleDuplicateCancel() {
        this.showDuplicateWarning = false;
        this.duplicateCanContinue = false;
        this.duplicateConfirmed = false;
    }

    showDuplicateDialog(message, canContinue, preview) {
        const matches = preview && preview.matches ? preview.matches : [];
        this.duplicateMessage = message;
        this.duplicateStatus = preview ? preview.status : null;
        this.duplicateReason = preview ? preview.reason : null;
        this.duplicateMatches = matches.map((match, index) => ({
            ...match,
            key: match.recordId || String(index)
        }));
        this.duplicateUseLayout = Boolean(this.duplicateStatus) && this.duplicateMatches.length > 0;
        this.duplicateCanContinue = canContinue === true;
        this.showDuplicateWarning = true;
    }

    openMatchedRecord(event) {
        const recordId = event.currentTarget.dataset.id;
        const recordType = event.currentTarget.dataset.type;
        if (!recordId) {
            return;
        }
        let objectApiName = 'Lead';
        if (recordType === 'Contact') {
            objectApiName = 'Contact';
        } else if (recordType === 'Account') {
            objectApiName = 'Account';
        }
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName,
                actionName: 'view'
            }
        }).then((url) => {
            window.open(url, '_blank');
        });
    }

    handleContinueDuplicate() {
        this.showDuplicateWarning = false;
        this.duplicateConfirmed = true;
        this.persist(this.pendingProducts);
    }

    async persist(products) {
        this.pendingProducts = products;
        this.saving = true;
        try {
            if (this.duplicateConfirmed !== true) {
                const preview = await previewLeadDuplicate({ leadRecord: this.leadRecord });
                if (preview && preview.blockSave) {
                    this.showDuplicateDialog(preview.message, false, preview);
                    return;
                }
                if (preview && preview.requiresConfirmation) {
                    this.showDuplicateDialog(preview.message, true, preview);
                    return;
                }
            }
            const leadId = await createLeadWithProducts({
                leadRecord: this.leadRecord,
                productsJson: JSON.stringify(products),
                duplicateConfirmed: this.duplicateConfirmed === true
            });
            this.duplicateConfirmed = false;
            this.toast(savedMessage, 'success');
            this.resetLeadForm();
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: leadId,
                    objectApiName: 'Lead',
                    actionName: 'view'
                }
            });
        } catch (error) {
            const message = error && error.body && error.body.message
                ? error.body.message
                : failedMessage;
            this.showDuplicateDialog(message, false, null);
        } finally {
            this.saving = false;
        }
    }

    handleStandardSuccess(event) {
        this.resetLeadForm();
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: event.detail.id,
                objectApiName: 'Lead',
                actionName: 'view'
            }
        });
    }

    handleCancel() {
        this.resetLeadForm();
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Lead',
                actionName: 'list'
            },
            state: {
                filterName: 'Recent'
            }
        });
    }

    validateLead(fields) {
        const country = fields.CountryCode || fields.Country;
        if (!fields.FirstName || !fields.LastName || !fields.Company || !country || !fields.LeadSource) {
            return fieldRequiredMessage;
        }
        if (!fields.Email && !fields.Phone) {
            return emailOrPhoneMessage;
        }
        if (fields.LeadSource === 'Other' && !fields.LeadSourceDetail__c) {
            return sourceDetailMessage;
        }
        return null;
    }

    createProductRow() {
        this.rowKey += 1;
        return {
            key: String(this.rowKey),
            productId: null,
            parentCategory: '',
            productCategory: ''
        };
    }

    toast(title, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            variant,
            mode: mode || 'dismissible'
        }));
    }
}