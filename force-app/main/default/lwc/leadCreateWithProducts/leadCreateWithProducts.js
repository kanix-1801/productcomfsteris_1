import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import LEAD_OBJECT from '@salesforce/schema/Lead';
import hasLeadCreateWithProducts from '@salesforce/customPermission/Lead_Create_With_Products';
import createLeadWithProducts from '@salesforce/apex/LeadCreateController.createLeadWithProducts';
import previewLeadDuplicate from '@salesforce/apex/LeadCreateController.previewLeadDuplicate';
import searchProducts from '@salesforce/apex/LeadCreateController.searchProducts';
import fieldRequiredMessage from '@salesforce/label/c.LeadCreateFieldRequiredMessage';
import emailOrPhoneMessage from '@salesforce/label/c.LeadCreateEmailOrPhoneMessage';
import sourceDetailMessage from '@salesforce/label/c.LeadCreateSourceDetailMessage';
import consentRequiredMessage from '@salesforce/label/c.LeadCreateConsentRequiredMessage';
import unqualifiedReasonMessage from '@salesforce/label/c.LeadCreateUnqualifiedReasonMessage';
import unqualifiedDetailsMessage from '@salesforce/label/c.LeadCreateUnqualifiedDetailsMessage';
import nurtureReasonMessage from '@salesforce/label/c.LeadCreateNurtureReasonMessage';
import nurtureDetailMessage from '@salesforce/label/c.LeadCreateNurtureDetailMessage';
import autoAssignProductMessage from '@salesforce/label/c.LeadAutoAssignNoProductMessage';
import savedMessage from '@salesforce/label/c.LeadCreateSavedMessage';
import savedNoRoutingMessage from '@salesforce/label/c.LeadCreateSavedNoRoutingMessage';
import failedMessage from '@salesforce/label/c.LeadCreateFailedMessage';

export default class LeadCreateWithProducts extends NavigationMixin(LightningElement) {
    @api recordTypeId;

    autoAssign = false;
    step = 'lead';
    saving = false;
    leadRecord;
    searchTerm = '';
    searchResults = [];
    selectedProducts = [];
    searching = false;
    searchToken = 0;
    searchTimer;
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
    leadStatus;
    unqualifiedReason;
    nurtureReason;

    productColumns = [
        { label: 'Product', fieldName: 'name', wrapText: true },
        { label: 'Product Code', fieldName: 'productCode', initialWidth: 140 },
        { label: 'Product Family', fieldName: 'productFamily' },
        { label: 'Class Code', fieldName: 'productClassCode', initialWidth: 110 }
    ];

    selectedColumns = [
        ...this.productColumns,
        {
            type: 'button-icon',
            initialWidth: 60,
            typeAttributes: {
                iconName: 'utility:delete',
                name: 'remove',
                title: 'Remove Product',
                alternativeText: 'Remove Product',
                variant: 'border-filled'
            }
        }
    ];

    connectedCallback() {
        this.picklistRecordTypeId = this.recordTypeId || undefined;
        this.resetLeadForm();
    }

    disconnectedCallback() {
        window.clearTimeout(this.searchTimer);
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
        this.searchTerm = '';
        this.searchResults = [];
        this.selectedProducts = [];
        this.searching = false;
        this.leadStatus = null;
        this.unqualifiedReason = null;
        this.nurtureReason = null;
        this.autoAssign = false;
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

    get hasSearchResults() {
        return this.searchResults.length > 0;
    }

    get hasSelectedProducts() {
        return this.selectedProducts.length > 0;
    }

    get selectedProductCount() {
        return this.selectedProducts.length;
    }

    get selectedRowIds() {
        return this.selectedProducts.map((product) => product.id);
    }

    get searchHint() {
        if (this.searching) {
            return 'Searching...';
        }
        const length = this.searchTerm.trim().length;
        if (length === 0) {
            return this.hasSearchResults
                ? 'Showing the products most used on Leads. Type to search all products by name, code, or family.'
                : 'Type at least 2 characters of the product name, code, or family.';
        }
        if (length === 1) {
            return 'Type at least 2 characters of the product name, code, or family.';
        }
        return this.hasSearchResults
            ? 'Showing the first 50 matches. Refine the search to narrow the list.'
            : 'No products match this search.';
    }

    get productStepHeading() {
        return this.autoAssign
            ? 'Select at least one product so Auto Assign Lead can route this Lead.'
            : 'Select the products this Lead is interested in. You can also save without products.';
    }

    handleAutoAssignChange(event) {
        this.autoAssign = event.detail.value === true;
    }

    handleLeadNext(event) {
        event.preventDefault();
        const fields = event.detail.fields;
        this.readStatusFields(fields);
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
            Class_Code__c: fields.Class_Code__c,
            Auto_Assign_Lead__c: this.autoAssign,
            Consent_Provided__c: fields.Status === 'Working' ? fields.Consent_Provided__c === true : false,
            UnqualifiedReason__c: fields.Status === 'Unqualified' ? fields.UnqualifiedReason__c : null,
            UnqualifiedDetails__c: this.requiresUnqualifiedDetails(fields) ? fields.UnqualifiedDetails__c : null,
            NurtureReason__c: fields.Status === 'Nurturing' ? fields.NurtureReason__c : null,
            Nurture_Reminder_Date__c: fields.Status === 'Nurturing' ? fields.Nurture_Reminder_Date__c : null,
            NurtureDetail__c: this.requiresNurtureDetail(fields) ? fields.NurtureDetail__c : null
        };
        if (this.recordTypeId) {
            this.leadRecord.RecordTypeId = this.recordTypeId;
        }
        this.step = 'products';
        if (!this.searchResults.length) {
            this.runSearch();
        }
    }

    handleBack() {
        this.step = 'lead';
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value || '';
        window.clearTimeout(this.searchTimer);
        this.searchTimer = window.setTimeout(() => this.runSearch(), 300);
    }

    async runSearch() {
        const term = this.searchTerm.trim();
        this.searchToken += 1;
        const token = this.searchToken;
        if (term.length === 1) {
            this.searchResults = [];
            this.searching = false;
            return;
        }
        this.searching = true;
        try {
            const results = await searchProducts({ searchTerm: term });
            if (token === this.searchToken) {
                this.searchResults = results || [];
            }
        } catch (error) {
            if (token === this.searchToken) {
                this.searchResults = [];
                this.toast(this.errorMessage(error), 'error');
            }
        } finally {
            if (token === this.searchToken) {
                this.searching = false;
            }
        }
    }

    // Keeps products picked in earlier searches and applies the ticks and un-ticks in the current results.
    handleRowSelection(event) {
        const pickedIds = new Set(event.detail.selectedRows.map((row) => row.id));
        const shownIds = new Set(this.searchResults.map((row) => row.id));
        const kept = this.selectedProducts.filter((product) => !shownIds.has(product.id) || pickedIds.has(product.id));
        const keptIds = new Set(kept.map((product) => product.id));
        const added = event.detail.selectedRows.filter((row) => !keptIds.has(row.id));
        this.selectedProducts = [...kept, ...added];
    }

    handleSelectedRowAction(event) {
        if (event.detail.action.name === 'remove') {
            const removedId = event.detail.row.id;
            this.selectedProducts = this.selectedProducts.filter((product) => product.id !== removedId);
        }
    }

    // Products are optional, except that Auto Assign Lead needs at least one so TAS can route the Lead.
    handleSave() {
        if (this.autoAssign && !this.selectedProducts.length) {
            this.toast(autoAssignProductMessage, 'error');
            return;
        }
        this.persist(this.selectedProducts.map((product) => ({ productId: product.id })));
    }

    errorMessage(error) {
        return error && error.body && error.body.message ? error.body.message : failedMessage;
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
            // Routing only starts when Auto Assign Lead is ticked, so only then say so.
            const routingStarted = this.leadRecord.Auto_Assign_Lead__c === true;
            this.toast(routingStarted ? savedMessage : savedNoRoutingMessage, 'success');
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
            this.showDuplicateDialog(this.errorMessage(error), false, null);
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
        if (fields.Status === 'Working' && fields.Consent_Provided__c !== true) {
            return consentRequiredMessage;
        }
        if (fields.Status === 'Unqualified' && !fields.UnqualifiedReason__c) {
            return unqualifiedReasonMessage;
        }
        if (this.requiresUnqualifiedDetails(fields) && this.blank(fields.UnqualifiedDetails__c)) {
            return unqualifiedDetailsMessage;
        }
        if (fields.Status === 'Nurturing' && !fields.NurtureReason__c) {
            return nurtureReasonMessage;
        }
        if (this.requiresNurtureDetail(fields) && this.blank(fields.NurtureDetail__c)) {
            return nurtureDetailMessage;
        }
        return null;
    }

    readStatusFields(fields) {
        const read = (fieldName) => {
            const input = this.template.querySelector(`lightning-input-field[data-name="${fieldName}"]`);
            return input ? input.value : fields[fieldName];
        };
        if (this.showUnqualifiedReason) {
            fields.UnqualifiedReason__c = read('UnqualifiedReason__c');
        }
        if (this.showUnqualifiedDetails) {
            fields.UnqualifiedDetails__c = read('UnqualifiedDetails__c');
        }
        if (this.showConsent) {
            fields.Consent_Provided__c = read('Consent_Provided__c');
        }
        if (this.showNurtureReason) {
            fields.NurtureReason__c = read('NurtureReason__c');
            fields.Nurture_Reminder_Date__c = read('Nurture_Reminder_Date__c');
        }
        if (this.showNurtureDetail) {
            fields.NurtureDetail__c = read('NurtureDetail__c');
        }
    }

    blank(value) {
        return value == null || String(value).trim() === '';
    }

    handleStatusChange(event) {
        this.leadStatus = event.detail.value;
        if (this.leadStatus !== 'Unqualified') {
            this.unqualifiedReason = null;
        }
        if (this.leadStatus !== 'Nurturing') {
            this.nurtureReason = null;
        }
    }

    handleUnqualifiedReasonChange(event) {
        this.unqualifiedReason = event.detail.value;
    }

    handleNurtureReasonChange(event) {
        this.nurtureReason = event.detail.value;
    }

    get showUnqualifiedReason() {
        return this.leadStatus === 'Unqualified';
    }

    get showUnqualifiedDetails() {
        return this.showUnqualifiedReason
            && (this.unqualifiedReason === 'Unresponsive' || this.unqualifiedReason === 'Other');
    }

    get showConsent() {
        return this.leadStatus === 'Working';
    }

    get showNurtureReason() {
        return this.leadStatus === 'Nurturing';
    }

    get showNurtureDetail() {
        return this.showNurtureReason && this.nurtureReason === 'Other';
    }

    requiresUnqualifiedDetails(fields) {
        return fields.Status === 'Unqualified'
            && (fields.UnqualifiedReason__c === 'Unresponsive' || fields.UnqualifiedReason__c === 'Other');
    }

    requiresNurtureDetail(fields) {
        return fields.Status === 'Nurturing' && fields.NurtureReason__c === 'Other';
    }

    toast(title, variant, mode) {
        this.dispatchEvent(new ShowToastEvent({
            title,
            variant,
            mode: mode || 'dismissible'
        }));
    }
}