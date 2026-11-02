import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    openTab,
    setTabIcon,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import { refreshApex } from '@salesforce/apex';
import getPreferencesForWorkOrder from '@salesforce/apex/WorkOrderCustomerPreferencesController.getPreferencesForWorkOrder';

const PREVIEW_LIMIT = 3;
const FULL_PAGE_TAB_LABEL = 'Customer Preferences';

/**
 * GW-3983 — Related-list style Customer Preferences on Repair Center Work Order record pages.
 * Reuses c-customer-preferences-table. Visible only when Parent Work Order is populated.
 * Sidebar shows a short preview; "View All" opens an OOTB-style read-only full-page list.
 */
export default class WorkOrderCustomerPreferences extends NavigationMixin(LightningElement) {
    @api recordId;

    preferences = [];
    workOrderNumber = '';
    isVisible = false;
    isLoading = true;
    errorMessage = '';
    isFullPage = false;
    workOrderUrl = '';
    wiredResult;
    isConsoleNavigation = false;

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
    }

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const state = pageReference?.state || {};
        const hasFullPageState = state.c__view === 'all' && !!state.c__recordId;
        if (hasFullPageState) {
            this.recordId = state.c__recordId;
            this.isFullPage = true;
        } else if (pageReference?.type === 'standard__component') {
            this.isFullPage = state.c__view === 'all';
            if (state.c__recordId) {
                this.recordId = state.c__recordId;
            }
        } else {
            // Record-page host — never treat as full-page View All.
            this.isFullPage = false;
        }
        this.buildWorkOrderUrl();
        this.updateConsoleTab();
    }

    @wire(getPreferencesForWorkOrder, { workOrderId: '$recordId' })
    wiredPreferences(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.isLoading = false;

        if (data) {
            this.isVisible = data.isVisible === true;
            this.preferences = data.preferences || [];
            this.workOrderNumber = data.workOrderNumber || '';
            this.errorMessage = '';
            this.updateConsoleTab();
            return;
        }

        if (error) {
            this.isVisible = false;
            this.preferences = [];
            this.workOrderNumber = '';
            this.errorMessage = this.resolveErrorMessage(error);
        }
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get preferenceCount() {
        return (this.preferences || []).length;
    }

    get previewPreferences() {
        return (this.preferences || []).slice(0, PREVIEW_LIMIT);
    }

    get showViewAll() {
        // Match standard related lists (e.g. WO Status Histories): show whenever rows exist.
        return this.preferenceCount > 0 && !this.isLoading && !this.hasError;
    }

    get cardTitle() {
        return this.preferenceCount > 0
            ? `Customer Preferences (${this.preferenceCount})`
            : 'Customer Preferences';
    }

    get viewAllLabel() {
        return 'View All';
    }

    get itemCountLabel() {
        const count = this.preferenceCount;
        const itemWord = count === 1 ? 'item' : 'items';
        return `${count} ${itemWord} • Sorted by Preference Type`;
    }

    get workOrderBreadcrumbLabel() {
        return this.workOrderNumber || 'Work Order';
    }

    get shouldRenderCard() {
        return !this.isFullPage && this.isVisible;
    }

    get shouldRenderFullPage() {
        return this.isFullPage && this.isVisible;
    }

    async handleRefresh() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            await refreshApex(this.wiredResult);
        } catch (error) {
            this.errorMessage = this.resolveErrorMessage(error);
        } finally {
            this.isLoading = false;
        }
    }

    async handleViewAll(event) {
        event.preventDefault();
        const pageReference = {
            type: 'standard__component',
            attributes: {
                componentName: 'c__workOrderCustomerPreferences'
            },
            state: {
                c__recordId: this.recordId,
                c__view: 'all'
            }
        };

        // Open as its own console tab with a real label so the WO tab is untouched.
        if (this.isConsoleNavigation) {
            try {
                await openTab({
                    pageReference,
                    focus: true,
                    label: FULL_PAGE_TAB_LABEL,
                    icon: 'standard:related_list',
                    iconAlt: FULL_PAGE_TAB_LABEL
                });
                return;
            } catch (error) {
                // Fall through to standard navigation outside console-capable hosts.
            }
        }

        this[NavigationMixin.Navigate](pageReference);
    }

    handleBackToWorkOrder(event) {
        if (event) {
            event.preventDefault();
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }

    resolveErrorMessage(error) {
        if (error?.body?.message) {
            return error.body.message;
        }
        if (Array.isArray(error?.body) && error.body.length > 0 && error.body[0].message) {
            return error.body[0].message;
        }
        if (error?.message) {
            return error.message;
        }
        return 'Unable to load Customer Preferences.';
    }

    buildWorkOrderUrl() {
        if (!this.recordId) {
            this.workOrderUrl = '';
            return;
        }
        this[NavigationMixin.GenerateUrl]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        }).then((url) => {
            this.workOrderUrl = url;
        });
    }

    async updateConsoleTab() {
        // Only the full-page View All host may touch console tab chrome.
        // Never call EnclosingTabId / setTabLabel from the WO record-page sidebar instance.
        if (!this.isFullPage || !this.isConsoleNavigation) {
            return;
        }

        document.title = FULL_PAGE_TAB_LABEL;

        try {
            const tabInfo = await getFocusedTabInfo();
            if (!tabInfo?.tabId) {
                return;
            }
            await setTabLabel(tabInfo.tabId, FULL_PAGE_TAB_LABEL);
            await setTabIcon(tabInfo.tabId, 'standard:related_list', {
                iconAlt: FULL_PAGE_TAB_LABEL
            });
        } catch (error) {
            // Non-console hosts may not support workspace APIs; page title still updates.
        }
    }
}