/**
 * @description GW-6407: Work Order closure screen (woClosureES) for the Work Order owner. Shows the header and, in
 *              one child component per tab, the Time, Parts, Expense and Calibration lines of all technicians.
 *              Lines can be edited, not added or deleted. Save All validates and saves every tab.
 * @author Sagar Anand
 */
import { LightningElement, api, wire } from 'lwc';
import { gql, graphql, refreshGraphQL } from 'lightning/uiGraphQLApi';
import { updateRecord, notifyRecordUpdateAvailable } from 'lightning/uiRecordApi';
import LightningConfirm from 'lightning/confirm';
import { CloseActionScreenEvent } from 'lightning/actions';
import USER_ID from '@salesforce/user/Id';
import getWorkOrderExpenses from '@salesforce/apex/WorkOrderClosureController.getWorkOrderExpenses';
import getAssignedServiceResourceId from '@salesforce/apex/WoDebriefSkillCheckController.getAssignedServiceResourceId';
import WO_CYCLE_COUNT from '@salesforce/schema/WorkOrder.CycleCount__c';
import WO_CYCLE_COUNT_DATE from '@salesforce/schema/WorkOrder.CycleCountDate__c';
import { errorMessage, isSameSalesforceId, showToast } from 'c/woClosureUtils';

const WORK_ORDER_QUERY = gql`
    query GetWorkOrderClosureES($workOrderId: ID) {
        uiapi {
            query {
                WorkOrder(
                    where: { Id: { eq: $workOrderId } }
                    first: 1
                ) {
                    edges {
                        node {
                            Id
                            WorkOrderNumber { value }
                            Status { value }
                            OwnerId { value }
                            ContractLineItem__r {
                                LineItemNumber { value }
                            }
                            ServiceContract {
                                Name { value }
                            }
                            AssetWarranty {
                                AssetWarrantyNumber { value }
                            }
                            Account {
                                Name { value }
                            }
                            AssetId { value }
                            Asset {
                                Name { value }
                                SerialNumber { value }
                            }
                            NoEquipmentWorkOrder__c { value }
                            Model__c { value }
                            CycleCount__c { value }
                            CycleCountDate__c { value }
                            CurrencyIsoCode { value }
                            WorkTypeId { value }
                            WorkType {
                                Id
                                Name { value }
                            }
                            WorkOrderLineItems(first: 200) {
                                edges {
                                    node {
                                        Id
                                        LineItemNumber { value }
                                        LineType__c { value }
                                        WorkTypeId { value }
                                        WorkType {
                                            Id
                                            Name { value }
                                        }
                                        Rate__c { value }
                                        TravelType__c { value }
                                        StartDate { value }
                                        EndDate { value }
                                        Duration { value }
                                        ListPrice__c { value }
                                        UnitPrice__c { value }
                                        TotalPrice__c { value }
                                        UnitQty__c { value }
                                        AssignedResource__c { value }
                                        AssignedResource__r {
                                            Id
                                            Name { value }
                                        }
                                        AssetId { value }
                                        Asset {
                                            Id
                                            SerialNumber { value }
                                            Name { value }
                                        }
                                        ProductCode__c { value }
                                        ProductDescription__c { value }
                                        Description { value }
                                        ProductItem__c { value }
                                        ProductItem__r {
                                            Id
                                            Product2Id { value }
                                            ProductName { value }
                                            Product2 {
                                                Id
                                                Name { value }
                                                RefurbishedProduct__c { value }
                                                RefurbishedProduct__r {
                                                    Id
                                                    Name { value }
                                                }
                                            }
                                        }
                                        Product__c { value }
                                        Product__r {
                                            Id
                                            Name { value }
                                            RefurbishedProduct__c { value }
                                            RefurbishedProduct__r {
                                                Id
                                                Name { value }
                                            }
                                        }
                                        PartDescription__c { value }
                                        AllowedUnit__c { value }
                                        Returnable__c { value }
                                        ComponentTag__c { value }
                                        ComponentTag__r {
                                            Id
                                            Name { value }
                                        }
                                        RemovedPart__c { value }
                                        UsagesException__c { value }
                                        BillingType__c { value }
                                        RepairCode__c { value }
                                        PartsSource__c { value }
                                        RepairCode__r {
                                            Id
                                            ProductCode { value }
                                            Description { value }
                                            Name { value }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const CURRENT_USER_SERVICE_RESOURCE_QUERY = gql`
    query GetCurrentUserServiceResource($userId: ID) {
        uiapi {
            query {
                ServiceResource(
                    where: {
                        and: [
                            { RelatedRecordId: { eq: $userId } }
                            { IsActive: { eq: true } }
                        ]
                    }
                    first: 1
                ) {
                    edges {
                        node {
                            Id
                            Name { value }
                            LocationId { value }
                        }
                    }
                }
            }
        }
    }
`;

const TAB_DEFS = [
    { key: 'Time', label: 'Time', searchPlaceholder: 'Search resource, dates, or rate…' },
    { key: 'Parts', label: 'Parts', searchPlaceholder: 'Search product, unit qty, or description…' },
    { key: 'Expense', label: 'Expenses', searchPlaceholder: 'Search type, description, or amount…' },
    { key: 'Calibration', label: 'Calibration', searchPlaceholder: 'Search resource, asset, or dates…' }
];
const TIME_LINE_TYPES = new Set(['Travel', 'Labor']);
const CLOSURE_STATUS = 'Closed';
const NOT_OWNER_MESSAGE = 'Only the Work Order Owner/Lead Technician is allowed to close the work order';
const HIDDEN_PANEL_CLASS = 'slds-hide';

export default class WoClosureES extends LightningElement {
    @api recordId;

    graphqlResult;
    _workOrder = null;
    /** @description Travel and Labor lines for the Time tab. */
    timeLines = [];
    /** @description Parts lines for the Parts tab. */
    partsLines = [];
    /** @description Calibration lines for the Calibration tab. */
    calibrationLines = [];
    /** @description Expenses of all technicians, loaded from Apex for the owner. */
    expenseRecords = [];
    /** @description True once the Expense load from Apex has started. */
    _expensesLoaded = false;
    /** @description True until the Expense load from Apex has finished. */
    _expensesLoading = true;
    /** @description Error from the Expense load, shown instead of the lines. */
    expensesError = null;

    /** @description Current user's active Service Resource (id, name and location) for the tabs. */
    currentUserResource;
    /** @description Service Resource assigned on the Work Order appointment, for the tabs. */
    workOrderAssignedResourceId;

    _pendingCycleCount;
    _pendingCycleCountDate;
    /** @description Number of edited lines per tab, reported by the tab components. */
    _pendingCountByTab = {};
    tabSearchTerms = { Time: '', Parts: '', Expense: '', Calibration: '' };
    _saving = false;
    activeTab = 'Time';

    isOffline = !navigator.onLine;
    _onlineHandler = () => { this.isOffline = false; };
    _offlineHandler = () => { this.isOffline = true; };

    /**
     * @description Lifecycle hook invoked when the component is inserted into the DOM.
     */
    connectedCallback() {
        window.addEventListener('online', this._onlineHandler);
        window.addEventListener('offline', this._offlineHandler);
    }

    /**
     * @description Lifecycle hook invoked when the component is removed from the DOM.
     */
    disconnectedCallback() {
        window.removeEventListener('online', this._onlineHandler);
        window.removeEventListener('offline', this._offlineHandler);
    }

    /**
     * @description Wire adapter handler: Work Order with its lines. Loads the Expenses once the owner is confirmed.
     */
    @wire(graphql, { query: WORK_ORDER_QUERY, variables: '$queryVariables' })
    wiredData(result) {
        this.graphqlResult = result;
        if (!result.data) return;
        const woEdge = result.data.uiapi.query.WorkOrder.edges[0];
        if (!woEdge) return;
        this._workOrder = woEdge.node;
        const lines = (woEdge.node.WorkOrderLineItems?.edges ?? []).map(e => e.node);
        this.timeLines = lines.filter(l => TIME_LINE_TYPES.has(l.LineType__c?.value));
        this.partsLines = lines.filter(l => l.LineType__c?.value === 'Parts');
        this.calibrationLines = lines.filter(l => l.LineType__c?.value === 'Calibration');
        if (!this.isNotOwner && !this._expensesLoaded) {
            this._loadExpenses();
        }
    }

    /**
     * @description Wire adapter handler: Current User Service Resource.
     */
    @wire(graphql, { query: CURRENT_USER_SERVICE_RESOURCE_QUERY, variables: '$currentUserQueryVariables' })
    wiredCurrentUserServiceResource(result) {
        const node = result.data?.uiapi?.query?.ServiceResource?.edges?.[0]?.node;
        if (!node) return;
        this.currentUserResource = {
            id: node.Id,
            name: node.Name?.value ?? '',
            locationId: node.LocationId?.value ?? null
        };
    }

    /**
     * @description Wire adapter handler: Work Order assigned Service Resource.
     */
    @wire(getAssignedServiceResourceId, { workOrderId: '$recordId' })
    wiredWorkOrderAssignedResource({ data }) {
        if (data) {
            this.workOrderAssignedResourceId = data;
        }
    }

    /**
     * @description Loads the Expenses of all technicians on the Work Order. Expense is private, so they come from
     *              Apex, which only returns them to the Work Order owner.
     */
    async _loadExpenses() {
        this._expensesLoaded = true;
        try {
            this.expenseRecords = await getWorkOrderExpenses({ workOrderId: this.recordId });
            this.expensesError = null;
        } catch (e) {
            this.expensesError = errorMessage(e);
        }
        this._expensesLoading = false;
    }

    /**
     * @description Query Variables.
     */
    get queryVariables() { return { workOrderId: this.recordId }; }
    /**
     * @description Current User Query Variables.
     */
    get currentUserQueryVariables() { return { userId: USER_ID }; }

    /**
     * @description True while the Work Order or, for the owner, its Expenses are loading.
     */
    get isLoading() {
        const woLoading = !this.graphqlResult?.data && !this.graphqlResult?.errors;
        return woLoading || (!!this._workOrder && !this.isNotOwner && this._expensesLoading);
    }

    /**
     * @description Has Error.
     */
    get hasError() { return !!this.graphqlResult?.errors || !!this.expensesError; }
    /**
     * @description Error Message.
     */
    get errorMessage() {
        return this.graphqlResult?.errors ? JSON.stringify(this.graphqlResult.errors) : this.expensesError;
    }

    /**
     * @description True when the running user is not the Work Order owner (only the owner can close it).
     */
    get isNotOwner() {
        return !isSameSalesforceId(this._workOrder?.OwnerId?.value, USER_ID);
    }

    /**
     * @description Message shown to users who are not the Work Order owner.
     */
    get notOwnerMessage() { return NOT_OWNER_MESSAGE; }

    /**
     * @description Status shown on the closure screen.
     */
    get closureStatus() { return CLOSURE_STATUS; }

    /**
     * @description Wo Number.
     */
    get woNumber() { return this._workOrder?.WorkOrderNumber?.value ?? ''; }
    /**
     * @description Wo Account Name.
     */
    get woAccountName() { return this._workOrder?.Account?.Name?.value ?? ''; }
    /**
     * @description Wo Asset Name (serial number, else name).
     */
    get woAssetName() {
        const asset = this._workOrder?.Asset;
        return asset?.SerialNumber?.value || asset?.Name?.value || '';
    }

    /**
     * @description Contract Line Item number.
     */
    get woContractLineItem() { return this._workOrder?.ContractLineItem__r?.LineItemNumber?.value ?? ''; }

    /**
     * @description Service Contract name.
     */
    get woContract() { return this._workOrder?.ServiceContract?.Name?.value ?? ''; }

    /**
     * @description Asset Warranty number.
     */
    get woAssetWarranty() { return this._workOrder?.AssetWarranty?.AssetWarrantyNumber?.value ?? ''; }

    /**
     * @description Wo Cycle Count.
     */
    get woCycleCount() {
        if (this._pendingCycleCount !== undefined) return this._pendingCycleCount;
        return this._workOrder?.CycleCount__c?.value ?? '';
    }

    /**
     * @description Wo Cycle Count Date.
     */
    get woCycleCountDate() {
        if (this._pendingCycleCountDate !== undefined) return this._pendingCycleCountDate;
        return this._workOrder?.CycleCountDate__c?.value ?? '';
    }

    /**
     * @description True when the Work Order has an Asset, or No Equipment Work Order is checked.
     */
    get hasValidEquipment() {
        const assetId = this._workOrder?.AssetId?.value ?? this._workOrder?.Asset?.Id ?? null;
        return !!assetId || this._workOrder?.NoEquipmentWorkOrder__c?.value === true;
    }

    /**
     * @description Message shown when the Work Order has neither an Asset nor the No Equipment checkbox.
     */
    get missingEquipmentMessage() {
        return 'This Work Order needs an Asset, or the No Equipment Work Order checkbox checked.';
    }

    /**
     * @description Save/Cancel footer is shown to the owner when the Work Order can be debriefed.
     */
    get showFooter() { return !!this._workOrder && !this.isNotOwner && this.hasValidEquipment; }

    /**
     * @description True when the header or any tab has unsaved changes.
     */
    get hasPendingChanges() {
        return this._pendingCycleCount !== undefined
            || this._pendingCycleCountDate !== undefined
            || Object.values(this._pendingCountByTab).some(count => count > 0);
    }

    /**
     * @description Save All Disabled.
     */
    get saveAllDisabled() { return !this.hasPendingChanges || this._saving; }
    /**
     * @description Cancel Disabled.
     */
    get cancelDisabled() { return this._saving; }
    /**
     * @description True while Save All validates and saves (shows the spinner).
     */
    get isSaving() { return this._saving; }

    /**
     * @description Tab buttons.
     */
    get tabs() {
        return TAB_DEFS.map(def => ({ key: def.key, label: def.label, isActive: this.activeTab === def.key }));
    }

    /**
     * @description Search text of the active tab.
     */
    get activeTabSearchTerm() { return this.tabSearchTerms[this.activeTab] ?? ''; }

    /**
     * @description Search placeholder of the active tab.
     */
    get activeTabSearchPlaceholder() {
        return TAB_DEFS.find(def => def.key === this.activeTab)?.searchPlaceholder ?? 'Search lines…';
    }

    /**
     * @description Time tab panel class (hidden tabs stay rendered so their edits are kept).
     */
    get timePanelClass() { return this._panelClass('Time'); }
    /**
     * @description Parts tab panel class.
     */
    get partsPanelClass() { return this._panelClass('Parts'); }
    /**
     * @description Expense tab panel class.
     */
    get expensePanelClass() { return this._panelClass('Expense'); }
    /**
     * @description Calibration tab panel class.
     */
    get calibrationPanelClass() { return this._panelClass('Calibration'); }

    /**
     * @description Handle Tab Select.
     */
    handleTabSelect(e) {
        this.activeTab = e.currentTarget.dataset.tab;
        if (this.activeTab === 'Expense') {
            this.template.querySelector('c-wo-closure-expense-lines')?.refreshExpenseTypes();
        }
    }

    /**
     * @description Handle Tab Search Change.
     */
    handleTabSearchChange(e) {
        this.tabSearchTerms = { ...this.tabSearchTerms, [this.activeTab]: e.detail.value ?? '' };
    }

    /**
     * @description Handle Cycle Count Change.
     */
    handleCycleCountChange(e) {
        this._pendingCycleCount = e.target.value ?? '';
    }

    /**
     * @description Handle Cycle Count Date Change.
     */
    handleCycleCountDateChange(e) {
        this._pendingCycleCountDate = e.target.value ?? '';
    }

    /**
     * @description Keeps the number of edited lines reported by a tab.
     */
    handlePendingChange(e) {
        this._pendingCountByTab = { ...this._pendingCountByTab, [e.target.dataset.tab]: e.detail.count };
    }

    /**
     * @description Save All: after confirmation, shows the spinner while every tab is validated and saved.
     */
    async handleSaveAll() {
        if (this._saving) return;
        const confirmed = await LightningConfirm.open({
            message: 'Save all changes to Salesforce?',
            variant: 'headerless',
            label: 'Confirm Save'
        });
        if (!confirmed) return;

        // The spinner covers validation (skill and part checks call Apex) and saving.
        this._saving = true;
        try {
            await this._validateAndSave();
        } catch (err) {
            showToast(this, 'Save failed', errorMessage(err), 'error');
        } finally {
            this._saving = false;
        }
    }

    /**
     * @description Validates every tab, then saves the header and the edited lines of each tab.
     */
    async _validateAndSave() {
        const tabComponents = [...this.template.querySelectorAll('[data-tab-lines]')];
        const validations = await Promise.all(tabComponents.map(tab => tab.validate()));
        const failedTabs = tabComponents.filter((tab, index) => !validations[index]).map(tab => tab.dataset.tab);
        if (failedTabs.length) {
            // Show the first tab with an error; its failing cards are opened by the tab.
            this.activeTab = failedTabs[0];
            const labels = TAB_DEFS.filter(def => failedTabs.includes(def.key)).map(def => def.label);
            showToast(this, 'Validation Error', `Fix the highlighted errors on the ${labels.join(', ')} tab before saving.`, 'error');
            return;
        }
        await this.template.querySelector('c-wo-closure-parts-lines')?.confirmReturnableParts();

        const okIds = [];
        let failedCount = 0;
        let firstError = null;
        let expenseSaved = false;

        if (this._pendingCycleCount !== undefined || this._pendingCycleCountDate !== undefined) {
            try {
                await this._saveHeader();
                okIds.push(this.recordId);
            } catch (err) {
                failedCount += 1;
                firstError = errorMessage(err);
            }
        }

        for (const tab of tabComponents) {
            // Tabs are saved one after the other, in tab order.
            // eslint-disable-next-line no-await-in-loop
            const result = await tab.save();
            okIds.push(...result.okIds);
            failedCount += result.failedCount;
            firstError = result.firstError ?? firstError;
            if (tab.dataset.tab === 'Expense' && result.okIds.length) {
                expenseSaved = true;
            }
        }

        try {
            notifyRecordUpdateAvailable([{ recordId: this.recordId }, ...okIds.map(id => ({ recordId: id }))]);
        } catch (e) { /* swallow */ }
        try { await refreshGraphQL(this.graphqlResult); } catch (e) { /* swallow */ }
        if (expenseSaved) {
            await this._loadExpenses();
        }

        if (failedCount === 0) {
            showToast(this, 'Saved', `${okIds.length} change(s) saved.`, 'success');
        } else {
            showToast(
                this,
                'Partial Save',
                firstError ? `${failedCount} change(s) failed: ${firstError}` : `${failedCount} change(s) failed.`,
                'warning'
            );
        }
    }

    /**
     * @description Closes the screen, or after confirmation discards all unsaved changes.
     */
    async handleDiscardAll() {
        if (!this.hasPendingChanges) {
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }
        const confirmed = await LightningConfirm.open({
            message: 'Discard all unsaved changes?',
            variant: 'headerless',
            label: 'Confirm Discard'
        });
        if (!confirmed) return;
        this._pendingCycleCount = undefined;
        this._pendingCycleCountDate = undefined;
        this.template.querySelectorAll('[data-tab-lines]').forEach(tab => tab.reset());
    }

    /**
     * @description Saves Cycle Count and Cycle Count Date; on failure they stay pending.
     */
    async _saveHeader() {
        const pendingCycleCount = this._pendingCycleCount;
        const pendingCycleCountDate = this._pendingCycleCountDate;
        const fields = { Id: this.recordId };
        if (pendingCycleCount !== undefined) {
            fields[WO_CYCLE_COUNT.fieldApiName] = pendingCycleCount ?? '';
        }
        if (pendingCycleCountDate !== undefined) {
            fields[WO_CYCLE_COUNT_DATE.fieldApiName] = pendingCycleCountDate || null;
        }
        await updateRecord({ fields });
        this._pendingCycleCount = undefined;
        this._pendingCycleCountDate = undefined;
        this._workOrder = {
            ...this._workOrder,
            ...(pendingCycleCount !== undefined ? { CycleCount__c: { value: pendingCycleCount ?? '' } } : {}),
            ...(pendingCycleCountDate !== undefined ? { CycleCountDate__c: { value: pendingCycleCountDate || null } } : {})
        };
    }

    /**
     * @description Panel class of a tab: hidden unless it is the active tab.
     * @param {string} key Tab key
     * @return {string}
     */
    _panelClass(key) {
        return this.activeTab === key ? '' : HIDDEN_PANEL_CLASS;
    }
}