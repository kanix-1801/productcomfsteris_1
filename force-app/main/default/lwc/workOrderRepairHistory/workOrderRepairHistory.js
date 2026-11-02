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
import getRepairHistoryForWorkOrder from '@salesforce/apex/WorkOrderRepairHistoryController.getRepairHistoryForWorkOrder';

const PREVIEW_LIMIT = 4;
const FULL_PAGE_TAB_LABEL = 'Repair Order History';

/**
 * GW-3954 — Related-list style Repair Order History on Repair Center Work Order record pages.
 * Visible only when Asset is populated. Sidebar shows 4 most recent; View All opens a full page.
 */
export default class WorkOrderRepairHistory extends NavigationMixin(LightningElement) {
    @api recordId;

    history = [];
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
            this.isFullPage = false;
        }
        this.buildWorkOrderUrl();
        this.updateConsoleTab();
    }

    @wire(getRepairHistoryForWorkOrder, { workOrderId: '$recordId' })
    wiredHistory(result) {
        this.wiredResult = result;
        const { data, error } = result;
        this.isLoading = false;

        if (data) {
            this.isVisible = data.isVisible === true;
            this.history = this.mapDisplayRows(data.history || []);
            this.workOrderNumber = data.workOrderNumber || '';
            this.errorMessage = '';
            this.updateConsoleTab();
            return;
        }

        if (error) {
            this.isVisible = false;
            this.history = [];
            this.workOrderNumber = '';
            this.errorMessage = this.resolveErrorMessage(error);
        }
    }

    get hasError() {
        return !!this.errorMessage;
    }

    get historyCount() {
        return (this.history || []).length;
    }

    get hasHistory() {
        return this.historyCount > 0;
    }

    get previewHistory() {
        return (this.history || []).slice(0, PREVIEW_LIMIT);
    }

    get displayHistory() {
        return this.history || [];
    }

    get showViewAll() {
        // Match standard related lists (e.g. WO Status Histories): show whenever rows exist.
        return this.historyCount > 0 && !this.isLoading && !this.hasError;
    }

    get cardTitle() {
        return this.historyCount > 0
            ? `Repair Order History (${this.historyCount})`
            : 'Repair Order History';
    }

    get viewAllLabel() {
        return 'View All';
    }

    get itemCountLabel() {
        const count = this.historyCount;
        const itemWord = count === 1 ? 'item' : 'items';
        return `${count} ${itemWord} • Sorted by Actual Ship Date`;
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
                componentName: 'c__workOrderRepairHistory'
            },
            state: {
                c__recordId: this.recordId,
                c__view: 'all'
            }
        };

        if (this.isConsoleNavigation) {
            try {
                await openTab({
                    pageReference,
                    focus: true,
                    label: FULL_PAGE_TAB_LABEL,
                    icon: 'standard:work_order',
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

    handleWorkOrderClick(event) {
        event.preventDefault();
        const workOrderId = event.currentTarget?.dataset?.id;
        if (!workOrderId) {
            return;
        }
        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: workOrderId,
                objectApiName: 'WorkOrder',
                actionName: 'view'
            }
        });
    }

    mapDisplayRows(rows) {
        return (rows || []).map((row) => ({
            ...row,
            actualShipDateDisplay: this.formatDate(row.actualShipDate),
            evaluatorDisplay: row.evaluatorName || '—'
        }));
    }

    formatDate(value) {
        if (!value) {
            return '—';
        }
        try {
            const dateValue = typeof value === 'string' ? value : String(value);
            // Apex Date serializes as YYYY-MM-DD
            const parts = dateValue.split('-');
            if (parts.length === 3) {
                const month = Number(parts[1]);
                const day = Number(parts[2]);
                const year = parts[0];
                return `${month}/${day}/${year}`;
            }
            return dateValue;
        } catch (error) {
            return String(value);
        }
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
        return 'Unable to load Repair Order History.';
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
            await setTabIcon(tabInfo.tabId, 'standard:work_order', {
                iconAlt: FULL_PAGE_TAB_LABEL
            });
        } catch (error) {
            // Non-console hosts may not support workspace APIs; page title still updates.
        }
    }
}