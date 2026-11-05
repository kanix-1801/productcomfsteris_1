import { LightningElement, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import AddClinicalParticipantModal from 'c/addClinicalParticipantModal';
import saveForReview from '@salesforce/apex/ClinicalParticipantService.saveForReview';

export default class ClinicalParticipantNew extends NavigationMixin(LightningElement) {
    processReviewId;
    errorMessage = '';
    opened = false;

    @wire(CurrentPageReference)
    setPageReference(pageRef) {
        this.processReviewId = this.readParentId(pageRef);
        if (pageRef && !this.opened) {
            this.opened = true;
            this.openSameScreen();
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

    async openSameScreen() {
        const result = await AddClinicalParticipantModal.open({
            size: 'small',
            label: 'Add Clinical Participant',
            description: 'Add one or more clinical participants',
            participantsJson: ''
        });
        if (!result) {
            this.goBack();
            return;
        }
        if (!this.processReviewId) {
            this.errorMessage = 'Open New from a Process Review to add a clinical participant.';
            this.opened = false;
            return;
        }
        try {
            await saveForReview({
                processReviewId: this.processReviewId,
                participantsJson: result
            });
            this.goBack();
        } catch (e) {
            this.errorMessage = e?.body?.message || 'The clinical participant could not be saved.';
            this.opened = false;
        }
    }

    goBack() {
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
}