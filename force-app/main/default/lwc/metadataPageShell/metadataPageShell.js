/**
 * @description
 * Top-level metadata-driven page shell for Customer 360 and other configurable record pages.
 * This is the ONLY LWC placed on the Lightning record page in App Builder. It wires to
 * DynamicPageElementController.getPageLayout, receives the tab tree from Apex, and renders one
 * lightning-tab per CMDT Tab row. Each tab delegates rendering to metadataTabContent.
 *
 * @group Account Management
 * @date 2026/07/22
 * @see DynamicPageElementController.getPageLayout
 * @see metadataTabContent
 * GC-3183
 */
import { LightningElement, api, wire } from 'lwc';
import getPageLayout from '@salesforce/apex/DynamicPageElementController.getPageLayout';

export default class MetadataPageShell extends LightningElement {
    /** @description Account (or parent) record Id from the record page context. */
    @api recordId;

    /** @description Matches PageName__c in DynamicPageElement__mdt. Default: Customer360. */
    @api pageName = 'Customer360';

    /** @description SObject API name for the record page. Default: Account. */
    @api objectApiName = 'Account';

    /** @description Title displayed on the outer lightning-card wrapper. */
    @api cardTitle = 'Customer 360';

    /** @description Resolved access level returned by Apex: Base or Full. */
    accessLevel;

    /** @description Tab nodes built by DynamicPageElementService from CMDT records. */
    tabs = [];

    /** @description TRUE until the first wire response is received. */
    isLoading = true;

    /** @description Populated when the Apex wire call fails. */
    error;

    /**
     * @description
     * Cacheable wire to DynamicPageElementController. Loads the full layout tree for the
     * current record and configured page name. On success, stores accessLevel and tabs;
     * on failure, clears tabs and surfaces an error message in the template.
     *
     * @param data DynamicPageElementResponse from Apex (accessLevel + tabs).
     * @param error Wire error object when the Apex call fails.
     */
    @wire(getPageLayout, {
        recordId: '$recordId',
        objectApiName: '$objectApiName',
        pageName: '$pageName'
    })
    wiredPageLayout({ data, error }) {
        this.isLoading = false;

        if (data) {
            this.error = undefined;
            this.accessLevel = data.accessLevel;
            this.tabs = data.tabs || [];
        } else if (error) {
            this.error = error;
            this.tabs = [];
            // eslint-disable-next-line no-console
            console.error('Page layout load error', error);
        }
    }

    /** @description TRUE when at least one tab node exists in the Apex response. */
    get hasTabs() {
        return this.tabs.length > 0;
    }

    /** @description TRUE when the layout wire returned an error. */
    get hasError() {
        return this.error !== undefined;
    }

    /**
     * @description
     * User-facing error text extracted from the wire error body.
     *
     * @return Error message string for display in the template.
     */
    get errorMessage() {
        return this.error?.body?.message || 'Unable to load page layout configuration.';
    }
}