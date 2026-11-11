import { LightningElement, api, wire } from 'lwc';
import Toast from 'lightning/toast';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import OPPORTUNITY_NAME_FIELD from '@salesforce/schema/Opportunity.Name';
import loadOpportunityReferences from '@salesforce/apex/DealerReferencePickerController.loadOpportunityReferences';
import saveOpportunityReferences from '@salesforce/apex/DealerReferencePickerController.saveOpportunityReferences';

/**
 * #GC-3598 Project Details tab on the dealer community opportunity page.
 * End Customer stays on the opportunity record. This tab keeps the other references.
 * Save writes the names after required fields are checked.
 */
export default class DealerOpportunityReferences extends LightningElement {
    endCustomerName;
    architectId;
    architectName;
    mainContractorId;
    mainContractorName;
    equipmentPlannerId;
    equipmentPlannerName;
    competitorIds;
    competitorNames;
    isLoading = false;
    isReady = false;
    isSaving = false;
    errorMessage;

    _recordId;

    @wire(getRecord, { recordId: '$recordId', fields: [OPPORTUNITY_NAME_FIELD] })
    opportunityRecord;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        if (value) {
            this.load();
        }
    }

    load() {
        this.isLoading = true;
        this.isReady = false;
        this.errorMessage = null;
        loadOpportunityReferences({ opportunityId: this._recordId })
            .then((references) => {
                this.endCustomerName = references.endCustomerName;
                this.architectId = references.architectId;
                this.architectName = references.architectName;
                this.mainContractorId = references.mainContractorId;
                this.mainContractorName = references.mainContractorName;
                this.equipmentPlannerId = references.equipmentPlannerId;
                this.equipmentPlannerName = references.equipmentPlannerName;
                this.competitorIds = references.competitorIds;
                this.competitorNames = references.competitorNames;
                this.isReady = true;
            })
            .catch((error) => {
                this.errorMessage = reduceError(error);
            })
            .finally(() => {
                this.isLoading = false;
            });
    }

    handleSelectionChange() {
        this.errorMessage = null;
    }

    handleSave() {
        this.persist();
    }

    persist() {
        if (!this._recordId || this.isSaving) {
            return;
        }
        const errors = [];
        const pickers = Array.from(this.template.querySelectorAll('c-dealer-reference-picker'));
        for (const picker of pickers) {
            const result = picker.validate();
            if (result && result.isValid === false) {
                errors.push(result.errorMessage);
            }
        }
        if (errors.length > 0) {
            this.errorMessage = errors.join(' ');
            return;
        }
        const valueOf = (fieldName, outputName) => {
            const picker = this.template.querySelector(`[data-field="${fieldName}"]`);
            return picker ? picker[outputName] : null;
        };
        const architectName = valueOf('architect', 'selectedLabel');
        const mainContractorName = valueOf('mainContractor', 'selectedLabel');
        const equipmentPlannerName = valueOf('equipmentPlanner', 'selectedLabel');
        const competitorNames = valueOf('competitors', 'selectedLabels') || '';
        if (this.valuesMatchLoaded(architectName, mainContractorName, equipmentPlannerName, competitorNames)) {
            this.showSavedToast();
            return;
        }
        this.isSaving = true;
        this.errorMessage = null;
        saveOpportunityReferences({
            opportunityId: this._recordId,
            endCustomerToken: null,
            endCustomerName: this.endCustomerName,
            architectToken: valueOf('architect', 'selectedId'),
            architectName,
            mainContractorToken: valueOf('mainContractor', 'selectedId'),
            mainContractorName,
            equipmentPlannerToken: valueOf('equipmentPlanner', 'selectedId'),
            equipmentPlannerName,
            competitorTokens: valueOf('competitors', 'selectedIds'),
            competitorNames
        })
            .then(() => {
                this.architectName = architectName;
                this.mainContractorName = mainContractorName;
                this.equipmentPlannerName = equipmentPlannerName;
                this.competitorNames = competitorNames;
                this.showSavedToast();
            })
            .catch((error) => {
                this.errorMessage = reduceError(error);
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    valuesMatchLoaded(architectName, mainContractorName, equipmentPlannerName, competitorNames) {
        return sameText(this.architectName, architectName)
            && sameText(this.mainContractorName, mainContractorName)
            && sameText(this.equipmentPlannerName, equipmentPlannerName)
            && sameText(this.competitorNames, competitorNames);
    }

    showSavedToast() {
        const opportunityName = getFieldValue(this.opportunityRecord && this.opportunityRecord.data, OPPORTUNITY_NAME_FIELD);
        const message = opportunityName
            ? `Opportunity "${opportunityName}" was saved.`
            : 'Opportunity was saved.';
        Toast.show({
            label: message,
            mode: 'dismissible',
            variant: 'success'
        }, this);
    }
}

function sameText(left, right) {
    return (left || '').trim() === (right || '').trim();
}

function reduceError(error) {
    if (!error) {
        return 'Unexpected error.';
    }
    if (Array.isArray(error.body)) {
        return error.body.map((entry) => entry.message).join(', ');
    }
    if (error.body && typeof error.body.message === 'string') {
        return error.body.message;
    }
    return error.message || 'Unexpected error.';
}