/**
 * @description LWC controller for custom Opportunity creation.
 *              Loads record type based field configuration, checks potential duplicate
 *              Opportunities, displays duplicate records, and creates the Opportunity.
 */
import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import checkDuplicateOpportunity from '@salesforce/apex/OpportunityCreateController.checkDuplicateOpportunity';
import getFieldConfigs from '@salesforce/apex/OpportunityCreateController.getFieldConfigs';
import DUPLICATE_WARNING_TITLE from '@salesforce/label/c.Opportunity_Duplicate_Warning_Title';
import DUPLICATE_WARNING_MESSAGE from '@salesforce/label/c.Opportunity_Duplicate_Warning_Message';

const OPEN_RECORD_ACTION = 'open_record';
const OPPORTUNITY_OBJECT_API_NAME = 'Opportunity';

export default class CreateOpportunity extends NavigationMixin(LightningElement) {
    selectedRecordTypeId;
    recordTypeOptions = [];
    recordTypeNameById = {};
    fieldConfigByRecordTypeName = {};
    fieldValues = {};
    duplicateRecords = [];
    showDuplicateModal = false;
    showDealerFlow = false;

    label = {
        duplicateWarningTitle: DUPLICATE_WARNING_TITLE,
        duplicateWarningMessage: DUPLICATE_WARNING_MESSAGE
    };

    duplicateColumns = [
        {
            label: 'Action',
            type: 'button',
            initialWidth: 100,
            typeAttributes: {
                label: 'Open',
                name: OPEN_RECORD_ACTION,
                variant: 'base'
            }
        },
        { label: 'Account', fieldName: 'AccountName', type: 'text' },
        { label: 'Address', fieldName: 'Address', type: 'text' },
        { label: 'Contact', fieldName: 'ContactName', type: 'text' },
        { label: 'Opportunity Type', fieldName: 'Type', type: 'text' },
        { label: 'Opportunity Owner', fieldName: 'OwnerName', type: 'text' },
        { label: 'Stage', fieldName: 'StageName', type: 'text' },
        { label: 'Close Date', fieldName: 'CloseDate', type: 'date' }
    ];

    /**
     * @description Loads Opportunity field configuration from Custom Metadata.
     */
    @wire(getFieldConfigs)
    handleFieldConfigs({ data, error }) {
        if (data) {
            const configs = {};
            data.forEach((config) => {
                configs[config.recordTypeName] = {
                    left: config.leftFields || [],
                    right: config.rightFields || []
                };
            });

            this.fieldConfigByRecordTypeName = configs;
        } else if (error) {
            this.showToast(
                'Error',
                'Unable to load Opportunity field configuration.',
                'error'
            );
        }
    }

    /**
     * @description Loads available Opportunity record types for the current user.
     */
    @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    handleObjectInfo({ data, error }) {
        if (data) {
            const options = [];
            const recordTypeMap = {};

            Object.keys(data.recordTypeInfos).forEach((recordTypeId) => {
                const recordTypeInfo = data.recordTypeInfos[recordTypeId];

                if (recordTypeInfo.available && !recordTypeInfo.master) {
                    options.push({
                        label: recordTypeInfo.name,
                        value: recordTypeId
                    });

                    recordTypeMap[recordTypeId] = recordTypeInfo.name;
                }
            });

            this.recordTypeOptions = options;
            this.recordTypeNameById = recordTypeMap;
        } else if (error) {
            this.showToast(
                'Error',
                'Unable to load Opportunity record types.',
                'error'
            );
        }
    }

    /**
     * @description Shows record type selector until the user selects one.
     */
    get showRecordTypeSelector() {
        return !this.selectedRecordTypeId;
    }

    /**
     * @description Shows the CMD-driven create form for non-Dealer record types.
     */
    get showCreateForm() {
        return !!this.selectedRecordTypeId && !this.showDealerFlow;
    }

    /**
     * @description Returns selected record type name from selected record type Id.
     */
    get selectedRecordTypeName() {
        return this.recordTypeNameById[this.selectedRecordTypeId];
    }

    /**
     * @description Returns configured left and right fields for the selected record type.
     */
    get selectedFieldConfig() {
        return (
            this.fieldConfigByRecordTypeName[this.selectedRecordTypeName] || {
                left: [],
                right: []
            }
        );
    }

    /**
     * @description Returns configured left section fields.
     */
    get leftFields() {
        return this.selectedFieldConfig.left;
    }

    /**
     * @description Returns configured right section fields.
     */
    get rightFields() {
        return this.selectedFieldConfig.right;
    }

    /**
     * @description Indicates whether duplicate records are available.
     */
    get hasDuplicates() {
        return this.duplicateRecords.length > 0;
    }

    /**
     * @description Handles record type selection and resets form state.
     */
    handleRecordTypeChange(event) {
        /*this.selectedRecordTypeId = event.detail.value;
        this.fieldValues = {};
        this.duplicateRecords = [];
        this.showDuplicateModal = false;*/
        this.selectedRecordTypeId = event.detail.value;
        this.showDealerFlow = false;

    /*if (this.selectedRecordTypeName === 'HC Sales - Consumables') {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            },
            state: {
                recordTypeId: this.selectedRecordTypeId
            }
        });

        return;
    }*/
        if (this.selectedRecordTypeName === 'HC Sales Consumables') {
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            },
            state: {
                nooverride: '1',
                useRecordTypeCheck: '1',
                recordTypeId: this.selectedRecordTypeId
            }
        });

        return;
    }

        // GC-3598: Dealer create uses CreateDealerOpportunity screen flow.
        if (this.selectedRecordTypeName === 'HC Sales - Dealer') {
            this.showDealerFlow = true;
            return;
        }

    this.fieldValues = {};
    this.duplicateRecords = [];
    this.showDuplicateModal = false;
    }

    /**
     * @description Tracks field changes and initiates duplicate check when enough values exist.
     */
    handleFieldChange(event) {
        const fieldName = event.target.dataset.fieldName;
        let value = event.detail.value;

        if (Array.isArray(value)) {
            value = value.length > 0 ? value[0] : null;
        }

        this.fieldValues = {
            ...this.fieldValues,
            [fieldName]: value
        };

        this.checkForDuplicate();
    }

    /**
     * @description Calls Apex to find duplicate Opportunities using selected Address,
     *              Primary Contact, and Opportunity Type.
     */
    async checkForDuplicate() {
        const addressId = this.fieldValues.Address__c;
        const primaryContactId = this.fieldValues.PrimaryContact__c;
        const opportunityType = this.fieldValues.Type;

        if (!addressId || !primaryContactId || !opportunityType) {
            this.duplicateRecords = [];
            return;
        }

        try {
            const records = await checkDuplicateOpportunity({
                addressId,
                primaryContactId,
                opportunityType
            });

            this.duplicateRecords = (records || []).map((opp) => ({
                Id: opp.Id,
                Name: opp.Name,
                AccountName: opp.Account ? opp.Account.Name : '',
                Address: opp.Address__r ? opp.Address__r.Street : '',
                ContactName: opp.PrimaryContact__r ? opp.PrimaryContact__r.Name : '',
                Type: opp.Type,
                OwnerName: opp.Owner ? opp.Owner.Name : '',
                StageName: opp.StageName,
                CloseDate: opp.CloseDate
            }));
        } catch (error) {
            this.duplicateRecords = [];
            this.showToast(
                'Error',
                'Unable to check duplicate Opportunities.',
                'error'
            );
        }
    }

    /**
     * @description Opens modal displaying duplicate Opportunity records.
     */
    openDuplicateModal(event) {
        event.preventDefault();
        this.showDuplicateModal = true;
    }

    /**
     * @description Closes duplicate Opportunity modal.
     */
    closeDuplicateModal() {
        this.showDuplicateModal = false;
    }

    /**
     * @description Navigates to selected duplicate Opportunity from the modal table.
     */
    handleDuplicateRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        if (actionName === OPEN_RECORD_ACTION) {
            this.navigateToOpportunity(row.Id);
        }
    }

    /**
     * @description Adds selected record type to submitted fields and submits the form.
     */
    handleSubmit(event) {
        event.preventDefault();

        const fields = event.detail.fields;
        fields.RecordTypeId = this.selectedRecordTypeId;

        this.template.querySelector('lightning-record-edit-form').submit(fields);
    }

    /**
     * @description Shows success message and navigates to the newly created Opportunity.
     */
    handleSuccess(event) {
        this.showToast(
            'Success',
            'Opportunity created successfully.',
            'success'
        );

        this.navigateToOpportunity(event.detail.id);
    }

    /**
     * @description Shows standard error message when Opportunity creation fails.
     */
    handleError() {
        this.showToast(
            'Error',
            'Unable to create Opportunity. Please review the errors on the form.',
            'error'
        );
    }

    /**
     * @description Navigates user to an Opportunity record detail page.
     */
    navigateToOpportunity(recordId) {
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                objectApiName: OPPORTUNITY_OBJECT_API_NAME,
                actionName: 'view'
            }
        });
    }

    /**
     * @description Displays a Lightning toast message.
     */
    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }
}