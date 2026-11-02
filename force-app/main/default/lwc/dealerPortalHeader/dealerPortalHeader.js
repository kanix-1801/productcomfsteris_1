import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import BRAND_LOGO from '@salesforce/resourceUrl/DealerPortalBrand';

const PAGES = [
    { name: 'Home', label: 'Home', key: 'home' },
    { name: 'My_Opportunities__c', label: 'My Opportunities', key: 'opportunities' },
    { name: 'Reports__c', label: 'Reports', key: 'reports' }
];

export default class DealerPortalHeader extends NavigationMixin(LightningElement) {
    logoUrl = BRAND_LOGO;
    activeKey = 'home';

    @wire(CurrentPageReference)
    setPage(pageReference) {
        const pageName = (pageReference?.attributes?.name || '').toLowerCase();
        if (pageName.includes('opportunit')) {
            this.activeKey = 'opportunities';
        } else if (pageName.includes('report')) {
            this.activeKey = 'reports';
        } else {
            this.activeKey = 'home';
        }
    }

    get tabs() {
        return PAGES.map((page) => ({
            ...page,
            className: page.key === this.activeKey ? 'tab tab-active' : 'tab'
        }));
    }

    openPage(event) {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: event.currentTarget.dataset.page
            }
        });
    }
}