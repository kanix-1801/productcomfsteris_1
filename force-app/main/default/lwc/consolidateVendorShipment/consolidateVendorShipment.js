import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getVendorWorkOrders from '@salesforce/apex/ConsolidateVendorShipmentController.getVendorWorkOrders';
import completeShipment from '@salesforce/apex/ConsolidateVendorShipmentController.completeShipment';

const PAGE_SELECT = 'select';
const PAGE_SUMMARY = 'summary';

/**
 * Consolidate Outside Vendor work orders into Vendor Return Orders and enqueue FedEx labels.
 */
export default class ConsolidateVendorShipment extends LightningElement {
    @track workOrders = [];
    @track selectedIds = [];
    @track summarySelectedIds = [];

    page = PAGE_SELECT;
    scanValue = '';
    repairCenterId;
    repairCenterName = '';
    hasRepairCenterAddress = true;
    errorMessage = '';
    infoMessage = '';
    isLoading = true;
    isBusy = false;
    _focusScanOnRender = true;

    get isSelectPage() {
        return this.page === PAGE_SELECT && !this.isLoading;
    }

    get isSummaryPage() {
        return this.page === PAGE_SUMMARY && !this.isLoading;
    }

    get selectedCount() {
        return this.selectedIds.length;
    }

    get isNextDisabled() {
        return this.isBusy || this.selectedIds.length === 0;
    }

    get isCompleteDisabled() {
        return this.isBusy || this.selectedIds.length === 0;
    }

    get isRemoveDisabled() {
        return this.isBusy || this.summarySelectedIds.length === 0;
    }

    get isRefreshDisabled() {
        return this.isLoading || this.isBusy;
    }

    get hasTableRows() {
        return this.workOrders.length > 0;
    }

    get selectAllChecked() {
        return (
            this.workOrders.length > 0 &&
            this.selectedIds.length === this.workOrders.length
        );
    }

    get summarySelectAllChecked() {
        return (
            this.summaryRows.length > 0 &&
            this.summarySelectedIds.length === this.summaryRows.length
        );
    }

    get tableRows() {
        const rows = [];
        let lastGroupKey = null;

        for (const wo of this.workOrders) {
            const groupKey = wo.groupKey || 'NO_VENDOR';
            if (groupKey !== lastGroupKey) {
                rows.push({
                    key: `group-${groupKey}`,
                    isGroupHeader: true,
                    rowClass: 'vendor-group-row',
                    vendorName: wo.vendorName || 'No Vendor'
                });
                lastGroupKey = groupKey;
            }
            rows.push({
                ...wo,
                key: wo.id,
                isGroupHeader: false,
                rowClass: '',
                selected: this.selectedIds.includes(wo.id),
                parentWorkOrderNumber: wo.parentWorkOrderNumber || '',
                subStatus: wo.subStatus || '',
                vendorAddress: wo.vendorAddress || ''
            });
        }
        return rows;
    }

    get summaryRows() {
        return this.workOrders
            .filter((wo) => this.selectedIds.includes(wo.id))
            .map((wo) => ({
                ...wo,
                summarySelected: this.summarySelectedIds.includes(wo.id),
                parentWorkOrderNumber: wo.parentWorkOrderNumber || '',
                subStatus: wo.subStatus || '',
                vendorAddress: wo.vendorAddress || ''
            }));
    }

    connectedCallback() {
        this.loadWorkOrders();
    }

    errorCallback(error) {
        this.errorMessage = this.normalizeError(error);
    }

    renderedCallback() {
        if (!this._focusScanOnRender || this.isLoading || this.page !== PAGE_SELECT) {
            return;
        }
        this._focusScanOnRender = false;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => this.focusScanField(), 0);
    }

    async handleRefresh() {
        const previousSelectedIds = [...this.selectedIds];
        await this.loadWorkOrders();

        const availableIds = new Set(this.workOrders.map((wo) => wo.id));
        this.selectedIds = previousSelectedIds.filter((id) => availableIds.has(id));
        this.summarySelectedIds = this.summarySelectedIds.filter((id) =>
            this.selectedIds.includes(id)
        );

        if (this.page === PAGE_SUMMARY && this.selectedIds.length === 0) {
            this.page = PAGE_SELECT;
        }

        this.infoMessage = 'List refreshed.';
        this._focusScanOnRender = this.page === PAGE_SELECT;
    }

    async loadWorkOrders() {
        this.isLoading = true;
        this.errorMessage = '';
        this.infoMessage = '';
        try {
            const result = await getVendorWorkOrders();
            this.repairCenterId = result.repairCenterId;
            this.repairCenterName = result.repairCenterName || '—';
            this.hasRepairCenterAddress = result.hasRepairCenterAddress !== false;
            this.workOrders = result.workOrders || [];
            if (result.errorMessage) {
                this.errorMessage = result.errorMessage;
            }
            this._focusScanOnRender = true;
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
            this.workOrders = [];
        } finally {
            this.isLoading = false;
        }
    }

    handleScanChange(event) {
        this.scanValue = event.target.value || '';
        this.infoMessage = '';
    }

    handleScanKeyDown(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            this.processScan();
        }
    }

    processScan() {
        const raw = (this.scanValue || '').trim();
        if (!raw) {
            return;
        }

        const match = this.workOrders.find(
            (wo) =>
                wo.id === raw ||
                (wo.workOrderNumber &&
                    wo.workOrderNumber.toLowerCase() === raw.toLowerCase())
        );

        if (!match) {
            this.infoMessage = `Work Order "${raw}" was not found in the Outside Vendor list.`;
            this.scanValue = '';
            this.scheduleScanFocus();
            return;
        }

        if (!this.selectedIds.includes(match.id)) {
            this.selectedIds = [...this.selectedIds, match.id];
        }
        this.infoMessage = `Selected ${match.workOrderNumber}.`;
        this.scanValue = '';
        this.scheduleScanFocus();
    }

    handleSelectAllChange(event) {
        const checked = event.target.checked;
        this.selectedIds = checked ? this.workOrders.map((wo) => wo.id) : [];
    }

    handleRowSelectionChange(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        if (!id) {
            return;
        }
        if (checked) {
            if (!this.selectedIds.includes(id)) {
                this.selectedIds = [...this.selectedIds, id];
            }
        } else {
            this.selectedIds = this.selectedIds.filter((selectedId) => selectedId !== id);
        }
    }

    handleNext() {
        this.errorMessage = '';
        const validationMessage = this.validateSelectionForNext();
        if (validationMessage) {
            this.errorMessage = validationMessage;
            return;
        }
        this.summarySelectedIds = [...this.selectedIds];
        this.page = PAGE_SUMMARY;
    }

    /**
     * Next-button rules: at least one WO, same Vendor, Vendor + Repair Center addresses.
     */
    validateSelectionForNext() {
        if (!this.hasRepairCenterAddress) {
            const repairCenterName = this.repairCenterName || 'the Repair Center';
            return (
                `Repair Center "${repairCenterName}" address is incomplete ` +
                '(needs Street, City, State, and Postal Code). ' +
                'Add a full address on the Location before consolidating vendor shipments.'
            );
        }

        if (this.selectedIds.length === 0) {
            return 'Select at least one work order before continuing.';
        }

        const selected = this.workOrders.filter((wo) => this.selectedIds.includes(wo.id));
        if (selected.length === 0) {
            return 'Select at least one work order before continuing.';
        }

        const vendorIds = [
            ...new Set(selected.map((wo) => wo.vendorId).filter((id) => !!id))
        ];
        if (vendorIds.length === 0) {
            return 'All selected Work Orders must have a Vendor assigned.';
        }
        if (vendorIds.length > 1) {
            return 'All selected Work Orders must have the same Vendor.';
        }

        const missingAddress = selected.find((wo) => !wo.hasVendorAddress);
        if (missingAddress) {
            const vendorName = missingAddress.vendorName || 'the selected Vendor';
            return (
                `Vendor "${vendorName}" ship-to address is incomplete ` +
                '(needs Street, City, State, and Postal Code). ' +
                'Add a full Billing/Shipping address or related Address before continuing.'
            );
        }

        return null;
    }

    handleSummarySelectAllChange(event) {
        const checked = event.target.checked;
        this.summarySelectedIds = checked
            ? this.summaryRows.map((row) => row.id)
            : [];
    }

    handleSummaryRowSelectionChange(event) {
        const id = event.target.dataset.id;
        const checked = event.target.checked;
        if (!id) {
            return;
        }
        if (checked) {
            if (!this.summarySelectedIds.includes(id)) {
                this.summarySelectedIds = [...this.summarySelectedIds, id];
            }
        } else {
            this.summarySelectedIds = this.summarySelectedIds.filter(
                (selectedId) => selectedId !== id
            );
        }
    }

    handleRemoveSelected() {
        if (this.summarySelectedIds.length === 0) {
            return;
        }
        const removeSet = new Set(this.summarySelectedIds);
        this.selectedIds = this.selectedIds.filter((id) => !removeSet.has(id));
        this.summarySelectedIds = [];
        if (this.selectedIds.length === 0) {
            this.page = PAGE_SELECT;
            this._focusScanOnRender = true;
            this.infoMessage = 'All work orders were removed from the summary.';
        }
    }

    handleAddAdditional() {
        this.errorMessage = '';
        this.page = PAGE_SELECT;
        this._focusScanOnRender = true;
    }

    async handleComplete() {
        this.errorMessage = '';
        const validationMessage = this.validateSelectionForNext();
        if (validationMessage) {
            this.errorMessage = validationMessage;
            return;
        }

        this.isBusy = true;
        try {
            await completeShipment({ workOrderIds: this.selectedIds });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Success',
                    message: 'Return Order was generated.',
                    variant: 'success'
                })
            );
            this.page = PAGE_SELECT;
            this.selectedIds = [];
            this.summarySelectedIds = [];
            this.scanValue = '';
            this.infoMessage = '';
            await this.loadWorkOrders();
        } catch (error) {
            this.errorMessage = this.normalizeError(error);
        } finally {
            this.isBusy = false;
        }
    }

    focusScanField() {
        const input = this.template.querySelector('[data-id="scan-work-order"]');
        if (input) {
            input.focus();
        }
    }

    scheduleScanFocus() {
        this._focusScanOnRender = true;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => this.focusScanField(), 0);
    }

    normalizeError(error) {
        if (!error) {
            return 'An unexpected error occurred.';
        }
        if (typeof error === 'string') {
            return error;
        }
        if (error.body && error.body.message) {
            return error.body.message;
        }
        if (Array.isArray(error.body) && error.body.length && error.body[0].message) {
            return error.body[0].message;
        }
        return error.message || 'An unexpected error occurred.';
    }
}