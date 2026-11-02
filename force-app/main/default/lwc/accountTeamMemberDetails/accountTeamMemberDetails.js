import { LightningElement, api } from 'lwc';
import getAccountTeamMembers from '@salesforce/apex/AccountTeamMemberDetailsController.getAccountTeamMembers';

const BASE_COLUMNS = [
    //{ label: 'Team Member', fieldName: 'teamMember', initialWidth: 150 },
    { label: 'Team Member', fieldName: 'teamMemberUrl', type: 'url',
      typeAttributes: { label: { fieldName: 'teamMember' }, target: '_self' },
      initialWidth: 150 },//ATM hyperlink
    { label: 'Job Title ', fieldName: 'teamJobTitle', initialWidth: 150},
    { label: 'Team Role', fieldName: 'teamRole' , initialWidth: 150 },
    { label: 'Assignment Type', fieldName: 'assignmentType', initialWidth: 140 },// GC-3112
    { label: 'Territory Code', fieldName: 'territoryCode', initialWidth: 140 },// GC-3352
    { label: 'Sales Category Code', fieldName: 'salesCategoryCode', initialWidth: 160 },// GC-3352
    { label: 'Sales Category Description', fieldName: 'salesCategoryDescription' , initialWidth: 180},
    { label: 'Email Address', fieldName: 'email', type: 'email' , initialWidth: 190 },
    { label: 'Phone Number', fieldName: 'phone', type: 'phone' , initialWidth: 150 },
    { label: 'Expiry Date', fieldName: 'expiryDate', type: 'date', initialWidth: 140,
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    }// GC-3109
   
];

// Shown only when the running user has SalesCustomerOpsSalesSupportSalesAdminPSG.
const ACCESS_COLUMNS = [
    { label: 'Account Access', fieldName: 'accountAccess' , initialWidth: 140 },
    { label: 'Case Access', fieldName: 'caseAccess' , initialWidth: 130 },
    { label: 'Contact Access', fieldName: 'contactAccess' , initialWidth: 130 },
    { label: 'Opportunity Access', fieldName: 'opportunityAccess' , initialWidth: 160 }
];

export default class AccountTeamMemberDetails extends LightningElement {
    @api recordId;

    columns = BASE_COLUMNS;
    accountTeamMembers = [];
    error;
    isLoading = true;

    connectedCallback() {
        this.loadAccountTeamMembers();
    }
    
    async loadAccountTeamMembers() {
        this.isLoading = true;
        try {
            const result = await getAccountTeamMembers({
                accountId: this.recordId,

            });

            const canViewAccessFields =
                result && result.length > 0 ? result[0].canViewAccessFields : false;

            this.columns = canViewAccessFields
                ? [...BASE_COLUMNS, ...ACCESS_COLUMNS]
                : BASE_COLUMNS;
            //this.accountTeamMembers = result;
            this.accountTeamMembers = result.map(row => ({
            ...row,
            teamMemberUrl: row.id ? `/lightning/r/AccountTeamMember/${row.id}/view` : null
        }));// ATM hyperlink

            
            this.error = undefined;
        } catch (error) {
            this.accountTeamMembers = [];
            this.columns = BASE_COLUMNS;
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