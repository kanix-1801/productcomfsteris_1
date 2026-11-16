import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import getStageDetails from '@salesforce/apex/DealerOpportunityPathController.getStageDetails';
import { getPicklistValues } from 'lightning/uiObjectInfoApi';
import { getFieldValue, getRecord, notifyRecordUpdateAvailable, updateRecord } from 'lightning/uiRecordApi';
import ID_FIELD from '@salesforce/schema/Opportunity.Id';
import NAME_FIELD from '@salesforce/schema/Opportunity.Name';
import PROBABILITY_FIELD from '@salesforce/schema/Opportunity.Probability';
import RECORD_TYPE_FIELD from '@salesforce/schema/Opportunity.RecordTypeId';
import LOST_REASON_FIELD from '@salesforce/schema/Opportunity.LostReason__c';
import CONFIDENCE_FIELD from '@salesforce/schema/Opportunity.ForecastConfidenceLevel__c';
import STAGE_FIELD from '@salesforce/schema/Opportunity.StageName';

const CLOSED_STAGE = 'Closed';
const CLOSED_LOST = 'Closed Lost';
const CONFIDENCE_BY_STAGE = {
    'Closed Won': 'Won',
    'Closed Lost': 'Lost'
};
const FIELDS = [STAGE_FIELD, RECORD_TYPE_FIELD, NAME_FIELD, LOST_REASON_FIELD];

/**
 * #GC-3598 Path for the dealer opportunity page.
 * Open stages stay in the record-type stage order. Closed stages collapse into one chevron, as on the standard Path.
 */
export default class DealerOpportunityPath extends LightningElement {
    @api recordId;

    currentStage;
    opportunityName;
    recordTypeId;
    picklistValues = [];
    stageByName = {};
    openStages = [];
    closedStages = [];
    selectedKey;
    closedChoice;
    lostReason;
    lostReasonOptions = [];
    editingClosedStage = false;
    syncedStage;
    isLoading = true;
    isSaving = false;
    errorMessage;

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: LOST_REASON_FIELD })
    wiredLostReasons({ data }) {
        if (data) {
            this.lostReasonOptions = data.values;
        }
    }

    @wire(getRecord, { recordId: '$recordId', fields: FIELDS })
    wiredOpportunity({ data, error }) {
        if (data) {
            this.currentStage = getFieldValue(data, STAGE_FIELD);
            this.recordTypeId = getFieldValue(data, RECORD_TYPE_FIELD);
            this.opportunityName = getFieldValue(data, NAME_FIELD);
            this.lostReason = getFieldValue(data, LOST_REASON_FIELD);
            this.syncSelection();
            this.isLoading = !this.hasPath;
            this.errorMessage = null;
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = reduceError(error);
        }
    }

    @wire(getPicklistValues, { recordTypeId: '$recordTypeId', fieldApiName: STAGE_FIELD })
    wiredStages({ data, error }) {
        if (data) {
            this.picklistValues = data.values;
            this.composeStages();
            this.errorMessage = null;
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = reduceError(error);
        }
    }

    @wire(getStageDetails)
    wiredStageDetails({ data, error }) {
        if (data) {
            const stageByName = {};
            data.forEach((stage) => {
                stageByName[stage.value] = stage;
            });
            this.stageByName = stageByName;
            this.composeStages();
            this.errorMessage = null;
        } else if (error) {
            this.isLoading = false;
            this.errorMessage = reduceError(error);
        }
    }

    composeStages() {
        if (!this.picklistValues.length || !Object.keys(this.stageByName).length) {
            return;
        }
        const openStages = [];
        const closedStages = [];
        this.picklistValues.forEach((entry) => {
            const detail = this.stageByName[entry.value];
            const stage = {
                label: entry.label,
                value: entry.value,
                closed: detail ? detail.closed === true : false,
                won: detail ? detail.won === true : false,
                probability: detail ? detail.probability : null
            };
            if (stage.closed) {
                closedStages.push(stage);
            } else {
                openStages.push(stage);
            }
        });
        this.openStages = openStages;
        this.closedStages = closedStages;
        this.syncSelection();
        this.isLoading = false;
    }

    get hasPath() {
        return this.openStages.length > 0;
    }

    get currentDetail() {
        return this.stageByName[this.currentStage];
    }

    get currentIsClosed() {
        return this.currentDetail ? this.currentDetail.closed === true : false;
    }

    get pathStages() {
        const currentIndex = this.openStages.findIndex((stage) => stage.value === this.currentStage);
        return this.openStages.map((stage, index) => {
            const current = stage.value === this.currentStage;
            const complete = this.currentIsClosed || (currentIndex > -1 && index < currentIndex);
            const selected = this.selectedKey === stage.value;
            return {
                label: stage.label,
                value: stage.value,
                className: itemClass({ complete, current, selected }),
                assistive: current ? 'Current Stage:' : complete ? 'Stage Complete' : '',
                selected: selected ? 'true' : 'false',
                tabIndex: selected ? '0' : '-1'
            };
        });
    }

    get closedClass() {
        const selected = this.selectedKey === CLOSED_STAGE;
        if (!this.currentIsClosed) {
            return itemClass({ complete: false, current: false, selected });
        }
        const won = this.currentDetail && this.currentDetail.won === true;
        const className = won
            ? 'slds-path__item slds-is-current slds-is-won'
            : 'slds-path__item slds-is-current slds-is-lost';
        return selected ? `${className} slds-is-active` : className;
    }

    get closedLabel() {
        if (!this.currentIsClosed) {
            return CLOSED_STAGE;
        }
        const current = this.closedStages.find((stage) => stage.value === this.currentStage);
        return current ? current.label : this.currentStage;
    }

    get closedAssistive() {
        return this.currentIsClosed ? 'Current Stage:' : '';
    }

    get closedSelected() {
        return this.selectedKey === CLOSED_STAGE ? 'true' : 'false';
    }

    get closedTabIndex() {
        return this.selectedKey === CLOSED_STAGE ? '0' : '-1';
    }

    get showClosedPicker() {
        if (this.selectedKey !== CLOSED_STAGE || !this.closedStages.length) {
            return false;
        }
        if (!this.currentIsClosed || this.editingClosedStage) {
            return true;
        }
        return this.currentStage === CLOSED_LOST && !this.lostReason;
    }

    get closedOptions() {
        return this.closedStages;
    }

    get showLostReason() {
        return this.showClosedPicker && this.closedChoice === CLOSED_LOST;
    }

    get actionLabel() {
        if (this.selectedKey === CLOSED_STAGE) {
            return this.closedChoice ? 'Change Closed Stage' : 'Select Closed Stage';
        }
        if (this.selectedKey && this.selectedKey !== this.currentStage) {
            return 'Mark as Current Stage';
        }
        return 'Mark Stage as Complete';
    }

    get actionDisabled() {
        if (this.isSaving || !this.selectedKey) {
            return true;
        }
        if (this.selectedKey === CLOSED_STAGE) {
            const savedClosed = this.currentIsClosed
                && !this.editingClosedStage
                && this.closedChoice === this.currentStage
                && (this.currentStage !== CLOSED_LOST || this.lostReason);
            if (savedClosed) {
                return false;
            }
            if (!this.closedChoice || this.closedChoice === this.currentStage) {
                return true;
            }
            return this.closedChoice === CLOSED_LOST && !this.lostReason;
        }
        return false;
    }

    handleSelect(event) {
        this.selectedKey = event.currentTarget.dataset.value;
        this.errorMessage = null;
    }

    handleClosedChange(event) {
        this.closedChoice = event.detail.value;
        this.errorMessage = null;
    }

    handleLostReasonChange(event) {
        this.lostReason = event.detail.value;
        this.errorMessage = null;
    }

    handleAction() {
        if (this.actionDisabled) {
            return;
        }
        if (this.selectedKey === CLOSED_STAGE) {
            const savedClosed = this.currentIsClosed
                && !this.editingClosedStage
                && this.closedChoice === this.currentStage
                && (this.currentStage !== CLOSED_LOST || this.lostReason);
            if (savedClosed) {
                this.editingClosedStage = true;
                return;
            }
            this.saveStage(this.closedChoice);
            return;
        }
        if (this.selectedKey === this.currentStage) {
            const currentIndex = this.openStages.findIndex((stage) => stage.value === this.currentStage);
            if (currentIndex < 0) {
                return;
            }
            const nextStage = this.openStages[currentIndex + 1];
            if (nextStage) {
                this.saveStage(nextStage.value);
                return;
            }
            this.selectedKey = CLOSED_STAGE;
            this.closedChoice = null;
            return;
        }
        this.saveStage(this.selectedKey);
    }

    saveStage(stageValue) {
        if (!this.recordId || !stageValue || this.isSaving) {
            return;
        }
        const fields = {};
        fields[ID_FIELD.fieldApiName] = this.recordId;
        fields[STAGE_FIELD.fieldApiName] = stageValue;
        const detail = this.stageByName[stageValue];
        if (detail && detail.probability !== null && detail.probability !== undefined) {
            fields[PROBABILITY_FIELD.fieldApiName] = detail.probability;
        }
        if (stageValue === CLOSED_LOST) {
            fields[LOST_REASON_FIELD.fieldApiName] = this.lostReason;
        }
        if (Object.prototype.hasOwnProperty.call(CONFIDENCE_BY_STAGE, stageValue)) {
            fields[CONFIDENCE_FIELD.fieldApiName] = CONFIDENCE_BY_STAGE[stageValue];
        } else if (detail && detail.closed) {
            fields[CONFIDENCE_FIELD.fieldApiName] = null;
        }
        this.isSaving = true;
        this.errorMessage = null;
        updateRecord({ fields })
            .then(() => notifyRecordUpdateAvailable([{ recordId: this.recordId }]))
            .then(() => {
                const label = this.opportunityName
                    ? `Opportunity "${this.opportunityName}" was saved.`
                    : 'Opportunity was saved.';
                Toast.show({ label, mode: 'dismissible', variant: 'success' }, this);
            })
            .catch((error) => {
                this.errorMessage = reduceError(error);
            })
            .finally(() => {
                this.isSaving = false;
                this.editingClosedStage = false;
            });
    }

    syncSelection() {
        if (!this.currentStage || this.currentStage === this.syncedStage) {
            return;
        }
        this.syncedStage = this.currentStage;
        if (this.currentIsClosed) {
            this.selectedKey = CLOSED_STAGE;
            this.closedChoice = this.currentStage;
            return;
        }
        this.selectedKey = this.currentStage;
        this.closedChoice = null;
    }
}

function itemClass({ complete, current, selected }) {
    const names = ['slds-path__item'];
    if (current) {
        names.push('slds-is-current');
    } else if (complete) {
        names.push('slds-is-complete');
    } else {
        names.push('slds-is-incomplete');
    }
    if (selected) {
        names.push('slds-is-active');
    }
    return names.join(' ');
}

function reduceError(error) {
    if (!error) {
        return 'Unexpected error.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((entry) => entry.message).filter(Boolean).join(', ');
    }
    const pageErrors = error.body && error.body.output && error.body.output.errors;
    if (Array.isArray(pageErrors) && pageErrors.length > 0) {
        return pageErrors.map((entry) => entry.message).filter(Boolean).join(', ');
    }
    if (error.body && error.body.output && error.body.output.fieldErrors) {
        const messages = Object.values(error.body.output.fieldErrors)
            .flat()
            .map((entry) => entry.message)
            .filter(Boolean);
        if (messages.length > 0) {
            return messages.join(', ');
        }
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    return error.message || 'Unexpected error.';
}