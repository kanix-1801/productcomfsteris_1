import { LightningElement, wire } from 'lwc';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import NAME_FIELD from '@salesforce/schema/User.Name';
import PHOTO_FIELD from '@salesforce/schema/User.SmallPhotoUrl';
import basePath from '@salesforce/community/basePath';
import BRAND_LOGO from '@salesforce/resourceUrl/DealerPortalWordmark';

const PAGES = [
    { path: '/', label: 'Home', key: 'home' },
    { path: '/my-opportunities', label: 'My Opportunities', key: 'opportunities' },
    { path: '/reports', label: 'Reports', key: 'reports' }
];

export default class DealerPortalHeader extends NavigationMixin(LightningElement) {
    logoUrl = `${BRAND_LOGO}?v=3`;
    activeKey = 'home';
    userName = '';
    userPhoto;

    @wire(getRecord, { recordId: USER_ID, fields: [NAME_FIELD, PHOTO_FIELD] })
    wiredUser({ data }) {
        if (!data) {
            return;
        }
        this.userName = data.fields.Name.value || '';
        this.userPhoto = data.fields.SmallPhotoUrl.value;
    }

    @wire(CurrentPageReference)
    setPage(pageReference) {
        const pageName = `${pageReference?.attributes?.name || ''} ${window.location?.pathname || ''}`.toLowerCase();
        if (pageName.includes('opportunit') || pageName.includes('my-opportunities')) {
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

    get userInitial() {
        return (this.userName || 'U').charAt(0).toUpperCase();
    }

    get hasPhoto() {
        return Boolean(this.userPhoto);
    }

    openPage(event) {
        const path = event.currentTarget.dataset.path || '/';
        this[NavigationMixin.Navigate]({
            type: 'standard__webPage',
            attributes: {
                url: `${basePath}${path}`
            }
        });
    }

    logout() {
        window.location.href = `${basePath}/secur/logout.jsp`;
    }
}