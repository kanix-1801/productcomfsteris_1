/**
 * @description
 * Displays Account-Account Relationship records for the current Account on
 * Customer 360, branching on whether the Account is a Customer (Child side)
 * or an IDN/GPO (Parent side). Related story: GC-3126.
 * GC-3281 - Shows InverseRelationshipType__c when viewing from the Parent's
 *              (IDN/GPO) perspective, and RelationshipType__c when viewing
 *              from the Child's (Customer/Address) perspective.
 * GC-3640 - New opens the IDN/GPO relationship flow for IDN/GPO Managers.
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { refreshApex } from '@salesforce/apex';
import getRelationships from '@salesforce/apex/AccountAccountRelationshipController.getRelationships';
import canManageIdnGpo from '@salesforce/customPermission/Manage_IDN_GPO';

export default class AccountAccountRelationshipTab extends NavigationMixin(LightningElement) {
    @api recordId;

    records = [];
    isLoading = true;
    showFlow = false;
    flowInputs = [];
    wiredRelationshipsResult;

    columns = [
        { label: 'Relationship Type', fieldName: 'relationshipType' },
        {
            type: 'action',
            typeAttributes: {
                rowActions: [
                    { label: 'View', name: 'view' }
                ]
            }
        },
        {
            label: 'Related Account',
            fieldName: 'relatedAccountUrl',
            type: 'url',
            typeAttributes: {
                label: { fieldName: 'relatedAccountName' },
                target: '_self'
            }
        }
    ];

    @wire(getRelationships, { accountId: '$recordId' })
    wiredRelationships(result) {
        this.wiredRelationshipsResult = result;
        const { data, error } = result;
        if (data) {
            const rowList = data.map((row) => {
                const isCurrentAccountParent = row.ParentAccount__c === this.recordId;
                const relatedAccountId = isCurrentAccountParent ? row.ChildAccount__c : row.ParentAccount__c;
                const relatedAccountName = isCurrentAccountParent
                    ? row.ChildAccount__r?.Name
                    : row.ParentAccount__r?.Name;
                const relationshipTypeLabel = isCurrentAccountParent
                    ? row.InverseRelationshipType__c
                    : row.RelationshipType__c;

                return {
                    id: row.Id,
                    relatedAccountId: relatedAccountId,
                    relatedAccountName: relatedAccountName,
                    relatedAccountUrl: null,
                    relationshipType: relationshipTypeLabel
                };
            });

            this.records = rowList;
            this.generateRelatedAccountUrls(rowList);
            this.isLoading = false;
        } else if (error) {
            this.records = [];
            this.isLoading = false;
            console.error('Account Account Relationship error', JSON.stringify(error));
        }
    }

    /**
     * @description
     * Builds a navigable record-page URL for each related Account using
     * NavigationMixin.GenerateUrl, then updates the datatable rows once
     * all URLs are resolved.
     *
     * @param rowList Array of row objects awaiting a relatedAccountUrl value
     */
    generateRelatedAccountUrls(rowList) {
        const urlPromiseList = rowList.map((row) => {
            if (!row.relatedAccountId) {
                return Promise.resolve({ id: row.id, url: null });
            }

            return this[NavigationMixin.GenerateUrl]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: row.relatedAccountId,
                    objectApiName: 'Account',
                    actionName: 'view'
                }
            }).then((generatedUrl) => ({ id: row.id, url: generatedUrl }));
        });

        Promise.all(urlPromiseList)
            .then((resolvedUrlList) => {
                const urlById = new Map(resolvedUrlList.map((entry) => [entry.id, entry.url]));
                this.records = this.records.map((row) => ({
                    ...row,
                    relatedAccountUrl: urlById.get(row.id) || null
                }));
            })
            .catch((error) => {
                // eslint-disable-next-line no-console
                console.error('Error generating related Account URLs', JSON.stringify(error));
            });
    }

    get hasRecords() {
        return this.records && this.records.length > 0;
    }

    get canCreateRelationship() {
        return canManageIdnGpo === true;
    }

    handleNewRelationship() {
        // Set once per open so lightning-flow is not re-initialised on every re-render.
        this.flowInputs = [
            {
                name: 'recordId',
                type: 'String',
                value: this.recordId
            }
        ];
        this.showFlow = true;
    }

    handleCloseFlow() {
        this.showFlow = false;
        if (this.wiredRelationshipsResult) {
            refreshApex(this.wiredRelationshipsResult);
        }
    }

    handleFlowStatusChange(event) {
        if (event.detail.status === 'FINISHED') {
            this.handleCloseFlow();
        }
    }

    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: row.id,
                objectApiName: 'AccountAccountRelationship__c',
                actionName: actionName
            }
        });
    }
}