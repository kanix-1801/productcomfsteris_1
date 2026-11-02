import { LightningElement, api } from 'lwc';
import getLifeSciencesAccountTeamMembers from '@salesforce/apex/LSAccountTeamMemberDetailsController.getLifeSciencesAccountTeamMembers';

// No initialWidth so the datatable spreads the columns across the full region width.
const LS_COLUMNS = [
    { label: 'Team Member', fieldName: 'teamMemberUrl', type: 'url',
      typeAttributes: { label: { fieldName: 'teamMember' }, target: '_self' } },
    { label: 'Account Team Role', fieldName: 'teamRole' },
    { label: 'Assignment Type', fieldName: 'assignmentType' },
    { label: 'Temporary Access', fieldName: 'temporaryAccessIndicator', type: 'boolean' },
    { label: 'Sales Category Description', fieldName: 'salesCategoryDescription' }
];

export default class LsAccountTeamMemberDetails extends LightningElement {
    @api recordId;

    columns = LS_COLUMNS;
    accountTeamMembers = [];
    error;
    isLoading = true;

    connectedCallback() {
        this.loadAccountTeamMembers();
    }

    async loadAccountTeamMembers() {
        this.isLoading = true;
        try {
            const result = await getLifeSciencesAccountTeamMembers({
                accountId: this.recordId
            });

            this.accountTeamMembers = result.map(row => ({
                ...row,
                teamMemberUrl: row.id ? `/lightning/r/AccountTeamMember/${row.id}/view` : null
            }));
            this.error = undefined;
        } catch (error) {
            this.accountTeamMembers = [];
            this.error = error;
        }
        finally {
            this.isLoading = false;
        }
    }

    get hasRecords() {
        return this.accountTeamMembers.length > 0;
    }

    get hasError() {
        return this.error !== undefined;
    }
}