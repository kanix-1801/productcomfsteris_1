/**
 * @description
 * Displays Account-Account Relationship records for the current Account on
 * Customer 360, branching on whether the Account is a Customer (Child side)
 * or an IDN/GPO (Parent side). Related story: GC-3126.
 * GC-3281 - Shows InverseRelationshipType__c when viewing from the Parent's
 *              (IDN/GPO) perspective, and RelationshipType__c when viewing
 *              from the Child's (Customer/Address) perspective.
 */
import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getRelationships from '@salesforce/apex/AccountAccountRelationshipController.getRelationships';
import getAccountType from '@salesforce/apex/AccountAccountRelationshipController.getAccountType';
import isSystemAdministrator from '@salesforce/apex/AccountAccountRelationshipController.isSystemAdministrator';

const ACCOUNT_TYPE_CUSTOMER = 'Customer';
const FIELD_CHILD_ACCOUNT = 'ChildAccount__c';
const FIELD_PARENT_ACCOUNT = 'ParentAccount__c';

export default class AccountAccountRelationshipTab extends NavigationMixin(LightningElement) {
    @api recordId;

    records = [];
    accountType;
    isLoading = true;
    isAdmin = false;

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

    @wire(getAccountType, { accountId: '$recordId' })
    wiredAccountType({ data, error }) {
        if (data) {
            this.accountType = data;
        } else if (error) {
            // eslint-disable-next-line no-console
            console.error('Account type fetch error', JSON.stringify(error));
        }
    }
    @wire(isSystemAdministrator)
    wiredIsSystemAdministrator({ data, error }) {
        if (data !== undefined) {
            this.isAdmin = data;
        } else if (error) {
            console.error('Admin check error', JSON.stringify(error));
        }
    }

    @wire(getRelationships, { accountId: '$recordId' })
    wiredRelationships({ data, error }) {
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

    handleNewRelationship() {
        const fieldName =
            this.accountType === ACCOUNT_TYPE_CUSTOMER ? FIELD_CHILD_ACCOUNT : FIELD_PARENT_ACCOUNT;

        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'AccountAccountRelationship__c',
                actionName: 'new'
            },
            state: {
                defaultFieldValues: `${fieldName}=${this.recordId}`
            }
        });
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