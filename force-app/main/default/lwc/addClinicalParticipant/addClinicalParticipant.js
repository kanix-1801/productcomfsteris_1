import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import { notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import AddClinicalParticipantModal from 'c/addClinicalParticipantModal';
import saveForReview from '@salesforce/apex/ClinicalParticipantService.saveForReview';

let screenOpen = false;

export default class AddClinicalParticipant extends NavigationMixin(LightningElement) {
    @api participantsJson = '';
    @api launchFromNew = false;
    summary = 'No clinical participants added.';
    processReviewId;
    errorMessage = '';
    opened = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        if (!this.isNewLaunch) {
            return;
        }
        this.pageRef = pageRef;
        this.processReviewId = this.readParentId(pageRef);
        if (pageRef && !this.opened && !screenOpen) {
            this.opened = true;
            this.openFromNew();
        }
    }

    connectedCallback() {
        if (this.isNewLaunch) {
            return;
        }
        this.refreshSummary();
    }

    get isNewLaunch() {
        return this.launchFromNew === true || this.launchFromNew === 'true';
    }

    async openPopup() {
        const result = await AddClinicalParticipantModal.open({
            size: 'small',
            label: 'Add Clinical Participant',
            description: 'Add one or more clinical participants',
            participantsJson: this.participantsJson
        });
        if (result === undefined) {
            return;
        }
        this.participantsJson = result;
        this.refreshSummary();
        this.dispatchEvent(new FlowAttributeChangeEvent('participantsJson', this.participantsJson));
    }

    async openFromNew() {
        if (screenOpen) {
            return;
        }
        screenOpen = true;
        let result;
        try {
            result = await AddClinicalParticipantModal.open({
                size: 'small',
                label: 'Add Clinical Participant',
                description: 'Add one or more clinical participants',
                participantsJson: ''
            });
        } finally {
            screenOpen = false;
        }
        if (!result) {
            this.returnToRelatedTab(false);
            return;
        }
        const processReviewId = this.readParentId(this.pageRef) || this.processReviewId;
        if (!processReviewId) {
            this.errorMessage = 'Open New from a Process Review to add a clinical participant.';
            return;
        }
        try {
            await saveForReview({
                processReviewId,
                participantsJson: result
            });
            this.returnToRelatedTab(true);
        } catch (e) {
            this.errorMessage = e?.body?.message || 'The clinical participant could not be saved.';
        }
    }

    readParentId(pageRef) {
        const state = pageRef?.state || {};
        const defaults = state.defaultFieldValues;
        if (defaults) {
            const parentId = new URLSearchParams(defaults).get('KeyAccountProcessReview__c');
            if (parentId) {
                return parentId;
            }
        }
        const raw = state.inContextOfRef;
        if (!raw) {
            return null;
        }
        try {
            const encoded = raw.startsWith('1.') ? raw.substring(2) : raw;
            const context = JSON.parse(window.atob(encoded));
            return context?.attributes?.recordId || null;
        } catch (e) {
            return null;
        }
    }

    async returnToRelatedTab(refreshParent) {
        if (refreshParent && this.processReviewId) {
            try {
                await notifyRecordUpdateAvailable([{ recordId: this.processReviewId }]);
            } catch (e) {
                // The record page still needs to open on the Related tab.
            }
        }
        if (window.history.length > 1) {
            window.history.back();
            return;
        }
        if (this.processReviewId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.processReviewId,
                    objectApiName: 'KeyAccountProcessReview__c',
                    actionName: 'view'
                }
            });
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'ClinicalParticipant__c',
                actionName: 'home'
            }
        });
    }

    refreshSummary() {
        let rows = [];
        try {
            rows = this.participantsJson ? JSON.parse(this.participantsJson) : [];
        } catch (e) {
            rows = [];
        }
        if (!Array.isArray(rows) || rows.length === 0) {
            this.summary = 'No clinical participants added.';
            return;
        }
        const labels = rows
            .map((row) => {
                if (row.name && row.email) {
                    return `${row.name} (${row.email})`;
                }
                return row.name || row.email;
            })
            .filter((label) => label);
        this.summary = `${rows.length} added: ${labels.join(', ')}`;
    }
}