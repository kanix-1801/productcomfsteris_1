import { LightningElement, api } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import getRequestContext from '@salesforce/apex/SampleService.getRequestContext';

/**
 * GC-3226 - Opportunity quick action to create Sample__c for Owner / Team Members.
 * Non team members receive a toast on click and the action closes immediately.
 * Eligibility is loaded imperatively (uncached) so Owner / Team changes apply on every click.
 */
export default class RequestCustomerSample extends NavigationMixin(LightningElement) {
    context;
    isLoading = true;
    isSaving = false;
    loadError;
    samplePurpose;
    accessDenied = false;
    customerContactId;

    _recordId;
    _isContextRequested = false;

    /**
     * Quick actions can set recordId after construction, so the load is triggered
     * from the setter instead of connectedCallback.
     */
    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        if (value && !this._isContextRequested) {
            this._isContextRequested = true;
            this.loadRequestContext();
        }
    }

    async loadRequestContext() {
        this.isLoading = true;
        try {
            const data = await getRequestContext({ opportunityId: this._recordId });
            this.context = data;
            this.loadError = undefined;

            if (data?.canCreate === false) {
                this.denyAccess(
                    data.blockReason ||
                        'Only Opportunity Team Members can create a Sample for this Opportunity.'
                );
            }
        } catch (error) {
            this.context = undefined;
            this.loadError =
                error?.body?.message ||
                error?.message ||
                'Unable to load Sample request.';
        } finally {
            this.isLoading = false;
        }
    }

    get isBusy() {
        return this.isLoading || this.isSaving;
    }

    get showForm() {
        return this.context?.canCreate === true && !this.accessDenied;
    }

    get opportunityId() {
        return this.context?.opportunityId || this.recordId;
    }

    get accountId() {
        return this.context?.accountId;
    }

    get showOtherPurpose() {
        return this.samplePurpose === 'Other';
    }

    /**
     * GC-3226 - Only Contacts related to the Opportunity Customer Account are selectable.
     * Apex returns the allowed Contacts, so no other Contact can be searched or chosen.
     */
    get contactOptions() {
        return this.context?.contactOptions || [];
    }

    get hasNoAccountContacts() {
        return this.contactOptions.length === 0;
    }

    get isContactLookupDisabled() {
        return this.hasNoAccountContacts || this.isSaving;
    }

    get contactPlaceholder() {
        return this.hasNoAccountContacts
            ? 'No Contacts on this Account'
            : 'Select a Contact';
    }

    handleContactChange(event) {
        this.customerContactId = event.detail.value;
    }

    denyAccess(message) {
        this.accessDenied = true;
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Not Allowed',
                message,
                variant: 'warning',
                mode: 'sticky'
            })
        );
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSamplePurposeChange(event) {
        this.samplePurpose = event.detail.value;
    }

    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    handleSubmit(event) {
        event.preventDefault();
        if (!this.customerContactId) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Error',
                    message: 'Customer Contact is required.',
                    variant: 'error'
                })
            );
            return;
        }
        const fields = event.detail.fields;
        fields.RelatedOpportunity__c = this.opportunityId;
        fields.CustomerAccount__c = this.accountId;
        fields.CustomerContact__c = this.customerContactId;
        this.isSaving = true;
        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    handleSuccess(event) {
        this.isSaving = false;
        const sampleId = event.detail.id;

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Success',
                message: 'Sample created successfully.',
                variant: 'success'
            })
        );

        this.dispatchEvent(new CloseActionScreenEvent());

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: sampleId,
                objectApiName: 'Sample__c',
                actionName: 'view'
            }
        });
    }

    handleError(event) {
        this.isSaving = false;
        const message =
            event.detail?.detail ||
            event.detail?.message ||
            'Unable to create Sample.';
        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error',
                mode: 'sticky'
            })
        );
    }
}