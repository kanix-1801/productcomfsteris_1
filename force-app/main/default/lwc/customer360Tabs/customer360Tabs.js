import { LightningElement, api, wire } from 'lwc';
import getVisibilityConfig from '@salesforce/apex/AccountPageVisibilityController.getVisibilityConfig';

const PAGE_NAME = 'Customer360';

export default class Customer360Tabs extends LightningElement {
    @api recordId;

    accessLevel;
    configByComponent = {};
    isLoading = true;
    error;
    activeTabValue = 'AccountTeam';

    @wire(getVisibilityConfig, {
        accountId: '$recordId',
        pageName: PAGE_NAME
    })
    wiredConfig({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.error = undefined;
            this.accessLevel = data.accessLevel;
            this.configByComponent = {};

            data.configs.forEach(item => {
                this.configByComponent[item.componentApiName] = item;
            });
        } else if (error) {
            this.error = error;
            this.configByComponent = {};
            // Keep console log for admin troubleshooting.
            // Do not expose raw platform errors to business users.
            // eslint-disable-next-line no-console
            console.error('Customer360 visibility error', error);
        }
    }

    // -------------------------
    // Tab-level visibility
    // -------------------------

    get showDetailsTab() {
        return this.isVisible('DetailsTab');
    }

    get showAccountTeamTab() {
        return this.isVisible('AccountTeamTab');
    }

    get showOpportunityTab() {
        return this.isVisible('OpportunityTab');
    }
    get showDashboardTab() {
        return this.isVisible('DashboardTab');
    }
    get showAddressesTab() {
        return this.isVisible('AddressesTab');
    }
    get showGPOAffilicationsTab() {
        return this.isVisible('GPOAffiliationsTab');
    }
    get showRelatedTab() {
        return this.isVisible('RelatedTab');
    }

    // -------------------------
    // Details tab component visibility
    // -------------------------

    get showAccountDetailsForm() {
        return this.isVisible('AccountDetailsForm');
    }

    get showAccountHighlights() {
        return this.isVisible('AccountHighlights');
    }

    // // -------------------------
    // // Opportunity tab component visibility
    // // -------------------------

    // get showOpportunityHome() {
    //     return this.isVisible('OpportunityHome');
    // }

    // -------------------------
    // Component editability
    // -------------------------

   get accountDetailsEditable() {
        return this.isEditable('AccountDetailsForm');
    }

    get accountHighlightsEditable() {
        return this.isEditable('AccountHighlights');
    } 

      get accountDetailsReadOnly() {
                return !this.accountDetailsEditable;
            }
        

    // get opportunityHomeEditable() {
    //     return this.isEditable('OpportunityHome');
    // }

    // -------------------------
    // Common helpers
    // -------------------------

    isVisible(componentName) {
        return this.configByComponent[componentName]?.isVisible === true;
    }

    isEditable(componentName) {
        return this.configByComponent[componentName]?.isEditable === true;
    }

    resolveDefaultActiveTab() {
        const tabOrder = [
            { flag: 'OpportunityTab', value: 'opportunity' },
            { flag: 'DashboardTab', value: 'dashboard' },
            { flag: 'DetailsTab', value: 'details' },
            { flag: 'AddressesTab', value: 'addresses' },
            { flag: 'GPOAffiliationsTab', value: 'gpoAffiliations' }
        ];

        for (const tab of tabOrder) {
            if (this.isVisible(tab.flag)) {
                return tab.value;
            }
        }

        return 'related';
    }

    get hasError() {
        return this.error !== undefined;
    }

    get errorMessage() {
        return this.error?.body?.message || 'Unable to load page configuration.';
    }
}