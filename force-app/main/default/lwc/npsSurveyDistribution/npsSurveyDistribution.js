import { LightningElement, api } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getWorkspaceContext from '@salesforce/apex/NpsSurveyDistributionController.getWorkspaceContext';
import startUploadFromFile from '@salesforce/apex/NpsSurveyDistributionController.startUploadFromFile';
import sendDistribution from '@salesforce/apex/NpsSurveyDistributionController.sendDistribution';
import generateAnonymousLink from '@salesforce/apex/NpsSurveyDistributionController.generateAnonymousLink';
import refreshSurveyAvailability from '@salesforce/apex/NpsSurveyDistributionController.refreshSurveyAvailability';
import getTracking from '@salesforce/apex/NpsSurveyDistributionController.getTracking';
import searchRecipients from '@salesforce/apex/NpsSurveyDistributionController.searchRecipients';
import setSurveyOptOut from '@salesforce/apex/NpsSurveyDistributionController.setSurveyOptOut';

export default class NpsSurveyDistribution extends LightningElement {
    @api recordId;
    canDistribute = false;
    blockedMessage;
    surveyName;
    businessUnit;
    anonymousLink;
    statusMessage;
    distributionId;
    recipientCount = 0;
    sentCount = 0;
    failedCount = 0;
    rows = [];
    searchRows = [];
    searchText = '';
    selectedContactId;
    expirationDays = 30;
    reminderCount = 2;
    reminderInterval = 7;
    acceptedFiles = ['.csv'];
    columns = [
        { label: 'Recipient', fieldName: 'recipientName' },
        { label: 'Email', fieldName: 'email' },
        { label: 'Survey', fieldName: 'surveyName' },
        { label: 'Distribution Date', fieldName: 'distributionDate', type: 'date' },
        { label: 'Reminder Dates', fieldName: 'reminderDates' },
        { label: 'Response Status', fieldName: 'responseStatus' },
        { label: 'Delivery Status', fieldName: 'deliveryStatus' },
        { label: 'Failure Reason', fieldName: 'failureReason' }
    ];
    searchColumns = [
        { label: 'Name', fieldName: 'name' },
        { label: 'Email', fieldName: 'email' },
        { label: 'Audience', fieldName: 'audience' }
    ];

    connectedCallback() {
        this.loadContext();
    }

    get noDistribution() {
        return !this.distributionId;
    }

    loadContext() {
        getWorkspaceContext({ approvedSurveyId: this.recordId })
            .then((context) => {
                this.canDistribute = context.canDistribute;
                this.blockedMessage = context.blockedMessage;
                this.surveyName = context.surveyName;
                this.businessUnit = context.businessUnit;
                this.anonymousLink = context.anonymousLink;
            })
            .catch((error) => this.toast(error));
    }

    handleExpiration(event) {
        this.expirationDays = this.numberValue(event);
    }

    handleReminderCount(event) {
        this.reminderCount = this.numberValue(event);
    }

    handleReminderInterval(event) {
        this.reminderInterval = this.numberValue(event);
    }

    handleSearchText(event) {
        this.searchText = event.target.value;
    }

    handleUploadFinished(event) {
        const uploaded = event.detail.files[0];
        startUploadFromFile({
            approvedSurveyId: this.recordId,
            contentDocumentId: uploaded.documentId,
            expirationDays: this.expirationDays,
            reminderCount: this.reminderCount,
            reminderIntervalDays: this.reminderInterval
        })
            .then((result) => {
                this.distributionId = result.distributionId;
                this.statusMessage = result.message;
                this.loadTracking();
            })
            .catch((error) => this.toast(error));
    }

    sendEmails() {
        sendDistribution({ distributionId: this.distributionId })
            .then((result) => {
                this.statusMessage = result.message || result.status;
                this.loadTracking();
            })
            .catch((error) => this.toast(error));
    }

    generateLink() {
        generateAnonymousLink({ approvedSurveyId: this.recordId })
            .then((result) => {
                this.anonymousLink = result.anonymousLink;
                this.statusMessage = result.message;
            })
            .catch((error) => this.toast(error));
    }

    refreshStatus() {
        refreshSurveyAvailability({ approvedSurveyId: this.recordId })
            .then((result) => {
                this.statusMessage = result.message;
                this.anonymousLink = result.anonymousLink;
            })
            .catch((error) => this.toast(error));
    }

    search() {
        searchRecipients({ searchText: this.searchText })
            .then((rows) => {
                this.searchRows = rows;
            })
            .catch((error) => this.toast(error));
    }

    selectContact(event) {
        const selected = event.detail.selectedRows;
        this.selectedContactId = selected.length ? selected[0].contactId : null;
    }

    recordOptOut() {
        setSurveyOptOut({ contactId: this.selectedContactId })
            .then(() => {
                this.statusMessage = 'Survey opt-out recorded. Future distributions will skip this Contact.';
            })
            .catch((error) => this.toast(error));
    }

    loadTracking() {
        getTracking({ distributionId: this.distributionId })
            .then((page) => {
                this.rows = page.rows;
                this.recipientCount = page.recipientCount;
                this.sentCount = page.sentCount;
                this.failedCount = page.failedCount;
            })
            .catch((error) => this.toast(error));
    }

    numberValue(event) {
        const value = parseInt(event.target.value, 10);
        return Number.isNaN(value) ? null : value;
    }

    toast(error) {
        const message = error && error.body && error.body.message ? error.body.message : 'The distribution could not be completed.';
        this.dispatchEvent(new ShowToastEvent({ title: 'NPS survey distribution', message, variant: 'error' }));
    }
}