import { api } from 'lwc';
import LightningModal from 'lightning/modal';
import labelConfirmed from '@salesforce/label/c.CIO_ConfirmedCustomerReportedIssue';
import labelRootCause from '@salesforce/label/c.CIO_IdentifiableRootCause';
import labelRootCauseDetails from '@salesforce/label/c.CIO_IdentifiableRootCauseDetails';
import labelPreviousRepair from '@salesforce/label/c.CIO_IssueRelatedToPreviousRepair';
import labelPreviousRepairDetails from '@salesforce/label/c.CIO_PreviousRepairDeficiencyDetails';
import labelDamage from '@salesforce/label/c.CIO_SignsOfDamageWearFailure';
import labelDamageDetails from '@salesforce/label/c.CIO_SignsOfDamageWearFailureDetails';
import labelUsage from '@salesforce/label/c.CIO_DetermineExtentOfUsage';
import labelUsesLogged from '@salesforce/label/c.CIO_UsesLogged';
import labelCorrectiveAction from '@salesforce/label/c.CIO_CorrectiveActionTaken';
import labelCorrectiveActionDetails from '@salesforce/label/c.CIO_CorrectiveActionAdditionalDetails';

/**
 * GW-4749 - Continuous Improvement Opportunity questionnaire popup.
 */
export default class CioEvaluationForm extends LightningModal {
    labelConfirmed = labelConfirmed;
    labelRootCause = labelRootCause;
    labelRootCauseDetails = labelRootCauseDetails;
    labelPreviousRepair = labelPreviousRepair;
    labelPreviousRepairDetails = labelPreviousRepairDetails;
    labelDamage = labelDamage;
    labelDamageDetails = labelDamageDetails;
    labelUsage = labelUsage;
    labelUsesLogged = labelUsesLogged;
    labelCorrectiveAction = labelCorrectiveAction;
    labelCorrectiveActionDetails = labelCorrectiveActionDetails;

    @api workOrderId;
    @api parentWorkOrderId;
    @api recordId;
    @api recordTypeId;
    @api technicianId;
    @api evaluationDate;

    isSaving = false;

    get isNew() {
        return !this.recordId;
    }

    get hasParentWorkOrder() {
        return !!this.parentWorkOrderId;
    }

    handleCancel() {
        if (this.isSaving) {
            return;
        }
        this.close();
    }

    handleSubmit() {
        this.isSaving = true;
    }

    handleSuccess() {
        this.isSaving = false;
        this.close('saved');
    }

    handleError() {
        this.isSaving = false;
    }
}