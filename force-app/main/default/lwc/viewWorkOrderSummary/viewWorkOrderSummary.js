import { LightningElement, api, track, wire } from 'lwc';
import { loadScript } from 'lightning/platformResourceLoader';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import chartJs from '@salesforce/resourceUrl/FSL__ChartJS';
import getSummary from '@salesforce/apex/ViewWorkOrderSummaryController.getSummary';

const TAB_LABEL = 'View Work Order Summary';
const SCAN_FIELD_LABEL = 'Work Order Id / Number';
const SCAN_FIELD_PLACEHOLDER = 'Scan or enter Work Order Id / Number';
const RT_INSTRUMENTS = 'RepairCenterInstruments';
const CHART_COLORS = [
    '#0176d3',
    '#fe9339',
    '#2e844a',
    '#ba0517',
    '#9050e9',
    '#0b827c',
    '#5b5fc7'
];

/**
 * GW-5287 - View Work Order Summary: scan a Device/Instrument WO, then show parent + children.
 */
export default class ViewWorkOrderSummary extends LightningElement {
    @api showReturnToMenu = false;

    workOrderInput = '';
    workspace;
    isBusy = false;
    errorMessage = '';
    isConsoleNavigation = false;
    chartJsInitialized = false;
    _chart;
    _shouldRenderChart = false;
    @track parentExpanded = true;
    @track childExpandedByKey = {};

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
        this.updateWorkspaceTab();
    }

    connectedCallback() {
        this.updateWorkspaceTab();
    }

    disconnectedCallback() {
        this.destroyChart();
    }

    renderedCallback() {
        if (!this._shouldRenderChart || !this.workspace) {
            return;
        }
        this._shouldRenderChart = false;
        this.renderChart();
    }

    get isScanScreen() {
        return !this.workspace;
    }

    get isSummaryScreen() {
        return Boolean(this.workspace);
    }

    get rootClass() {
        const parts = ['view-wo-summary-root'];
        if (this.isScanScreen) {
            if (this.showReturnToMenu) {
                // Full RCA page-shell width — same as Assign Work Order scan-panel.
                parts.push('view-wo-summary-root_embedded');
            } else {
                parts.push('view-wo-summary-root_scan', 'slds-p-around_medium');
            }
        } else {
            parts.push('view-wo-summary-root_summary');
            // Nav-menu overview: center like RCA. Scan stays left (Joshua: "from Nav menu keep left").
            if (!this.showReturnToMenu) {
                parts.push('view-wo-summary-root_standalone');
            }
        }
        return parts.join(' ');
    }

    get scanFieldLabel() {
        return SCAN_FIELD_LABEL;
    }

    get scanFieldPlaceholder() {
        return SCAN_FIELD_PLACEHOLDER;
    }

    get overviewTitle() {
        return this.workspace
            ? `Work Order Overview ${this.workspace.parentWorkOrderNumber}`
            : 'Work Order Overview';
    }

    get parentSectionTitle() {
        return this.workspace
            ? `Parent Work Order ${this.workspace.parentWorkOrderNumber}`
            : 'Parent Work Order';
    }

    get parentSectionClass() {
        return this.parentExpanded
            ? 'slds-accordion__section slds-is-open'
            : 'slds-accordion__section';
    }

    get parentChevronIcon() {
        return this.parentExpanded ? 'utility:chevrondown' : 'utility:chevronright';
    }

    get scheduledShipDateDisplay() {
        return this.formatDate(this.workspace?.scheduledShipDate);
    }

    get quantityReceivedDisplay() {
        return this.workspace?.quantityReceived ?? '';
    }

    get showParentQuantityReceived() {
        return this.workspace?.parentRecordTypeDeveloperName === RT_INSTRUMENTS;
    }

    get totalChildLabel() {
        const total = this.workspace?.totalChildWorkOrders ?? 0;
        return `Total child work orders: ${total}`;
    }

    get statusLegend() {
        const counts = this.workspace?.statusCounts || [];
        return counts.map((entry, index) => ({
            key: `${entry.status}-${index}`,
            status: entry.status,
            count: entry.count,
            colorStyle: `background-color: ${CHART_COLORS[index % CHART_COLORS.length]}`
        }));
    }

    get childSections() {
        const children = this.workspace?.children || [];
        return children.map((child, index) => {
            const sectionKey = child.workOrderId || `child-${index}`;
            const isExpanded = this.childExpandedByKey[sectionKey] !== false;
            const assetRows = (child.assetRows || []).map((row, rowIndex) => ({
                ...row,
                rowKey: `${child.workOrderId}-asset-${rowIndex}`
            }));
            const instrumentRows = (child.instrumentRows || []).map((row, rowIndex) => ({
                ...row,
                rowKey: `${child.workOrderId}-instrument-${rowIndex}`
            }));
            return {
                ...child,
                sectionKey,
                sectionTitle: `Child Work Order ${child.workOrderNumber}`,
                isExpanded,
                sectionClass: isExpanded
                    ? 'slds-accordion__section slds-is-open'
                    : 'slds-accordion__section',
                chevronIcon: isExpanded ? 'utility:chevrondown' : 'utility:chevronright',
                showAssetTable: Boolean(child.hasAsset) && assetRows.length > 0,
                showInstrumentTable: !child.hasAsset && instrumentRows.length > 0,
                scheduledShipDateDisplay: this.formatDate(child.scheduledShipDate),
                quantityReceivedDisplay: child.quantityReceived ?? '',
                turnTimeDisplay: child.turnTime ?? '',
                assetRows,
                instrumentRows
            };
        });
    }

    initExpandedSections(workspace) {
        this.parentExpanded = true;
        const expandedByKey = {};
        for (const child of workspace?.children || []) {
            if (child.workOrderId) {
                expandedByKey[child.workOrderId] = true;
            }
        }
        this.childExpandedByKey = expandedByKey;
    }

    handleParentToggle() {
        const wasExpanded = this.parentExpanded;
        this.parentExpanded = !this.parentExpanded;
        if (this.parentExpanded && !wasExpanded) {
            this._shouldRenderChart = true;
        }
    }

    handleChildToggle(event) {
        const sectionKey = event.currentTarget?.dataset?.sectionKey;
        if (!sectionKey) {
            return;
        }
        const currentlyExpanded = this.childExpandedByKey[sectionKey] !== false;
        this.childExpandedByKey = {
            ...this.childExpandedByKey,
            [sectionKey]: !currentlyExpanded
        };
    }

    handleScanChange(event) {
        this.workOrderInput = event.detail?.value ?? '';
        this.errorMessage = '';
    }

    async handleScanContinue(event) {
        const value = (event.detail?.value ?? this.workOrderInput ?? '').trim();
        if (!value || this.isBusy) {
            if (!value) {
                this.errorMessage = 'Work Order Id / Number is required.';
            }
            return;
        }
        this.workOrderInput = value;
        this.isBusy = true;
        this.errorMessage = '';
        try {
            const workspace = await getSummary({ workOrderInput: value });
            this.workspace = workspace;
            this.initExpandedSections(workspace);
            this._shouldRenderChart = true;
            this.updateWorkspaceTab();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            this.workspace = undefined;
            this.parentExpanded = true;
            this.childExpandedByKey = {};
        } finally {
            this.isBusy = false;
        }
    }

    handleClose() {
        this.destroyChart();
        this.workspace = undefined;
        this.parentExpanded = true;
        this.childExpandedByKey = {};
        this.workOrderInput = '';
        this.errorMessage = '';
        this.updateWorkspaceTab();
    }

    handleReturnToMenu() {
        this.handleClose();
        this.dispatchEvent(new CustomEvent('returntomenu'));
    }

    formatDate(value) {
        if (!value) {
            return '';
        }
        try {
            const dateValue = typeof value === 'string' ? new Date(`${value}T00:00:00`) : value;
            return new Intl.DateTimeFormat(undefined, {
                month: 'short',
                day: 'numeric',
                year: 'numeric'
            }).format(dateValue);
        } catch (e) {
            return String(value);
        }
    }

    reduceError(error) {
        if (typeof error === 'string') {
            return error;
        }
        return (
            error?.body?.message ||
            error?.message ||
            'Unable to load Work Order Summary.'
        );
    }

    async ensureChartJs() {
        if (this.chartJsInitialized) {
            return;
        }
        await loadScript(this, chartJs);
        this.chartJsInitialized = true;
    }

    async renderChart() {
        const canvas = this.template.querySelector('canvas.status-pie');
        if (!canvas || !this.workspace) {
            return;
        }
        try {
            await this.ensureChartJs();
        } catch (error) {
            this.errorMessage = this.reduceError(error);
            return;
        }

        const ChartCtor = window.Chart;
        if (typeof ChartCtor !== 'function') {
            this.errorMessage = 'Chart library failed to load.';
            return;
        }

        this.destroyChart();
        const counts = this.workspace.statusCounts || [];
        const labels = counts.map((entry) => entry.status);
        const data = counts.map((entry) => entry.count);
        const colors = counts.map(
            (_entry, index) => CHART_COLORS[index % CHART_COLORS.length]
        );

        // Chart.js draws a segment border by default; with one slice that shows as a
        // white radius from 12 o'clock to the center. Hide it when there is only one status.
        const borderWidth = counts.length <= 1 ? 0 : 2;

        this._chart = new ChartCtor(canvas.getContext('2d'), {
            type: 'pie',
            data: {
                labels,
                datasets: [
                    {
                        data,
                        backgroundColor: colors,
                        borderColor: '#ffffff',
                        borderWidth
                    }
                ]
            },
            options: {
                responsive: true,
                maintainAspectRatio: false,
                layout: {
                    padding: 8
                },
                legend: {
                    display: false
                },
                plugins: {
                    legend: {
                        display: false
                    }
                }
            }
        });
    }

    destroyChart() {
        if (this._chart) {
            this._chart.destroy();
            this._chart = undefined;
        }
    }

    /**
     * Sets the browser title and Lightning console tab label.
     * Scan screen: "View Work Order Summary".
     * Open WO: "00001254 | View Work Order Summary".
     */
    async updateWorkspaceTab() {
        const workOrderNumber = (this.workspace?.parentWorkOrderNumber || '').toString().trim();
        const label = workOrderNumber ? `${workOrderNumber} | ${TAB_LABEL}` : TAB_LABEL;
        document.title = label;

        if (!this.isConsoleNavigation) {
            return;
        }

        try {
            const tabInfo = await getFocusedTabInfo();
            if (!tabInfo?.tabId) {
                return;
            }
            await setTabLabel(tabInfo.tabId, label);
        } catch (e) {
            // Non-console hosts may reject workspace APIs; page title still updates.
        }
    }
}