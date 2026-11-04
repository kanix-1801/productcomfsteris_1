import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin, CurrentPageReference } from 'lightning/navigation';
import {
    IsConsoleNavigation,
    getFocusedTabInfo,
    setTabLabel
} from 'lightning/platformWorkspaceApi';
import userId from '@salesforce/user/Id';

import getInitialContext from '@salesforce/apex/CreateReturnOrderController.getInitialContext';
import getAccountDetails from '@salesforce/apex/CreateReturnOrderController.getAccountDetails';
import getContactsForAccount from '@salesforce/apex/CreateReturnOrderController.getContactsForAccount';
import getShipToAddressesForAccount from '@salesforce/apex/CreateReturnOrderController.getShipToAddressesForAccount';
import getRepairCenterLocations from '@salesforce/apex/CreateReturnOrderController.getRepairCenterLocations';
import getAssetsForAccount from '@salesforce/apex/CreateReturnOrderController.getAssetsForAccount';
import getAssetsByIds from '@salesforce/apex/CreateReturnOrderController.getAssetsByIds';
import findAssetsBySerial from '@salesforce/apex/CreateReturnOrderController.findAssetsBySerial';
import getDepartmentsForAccount from '@salesforce/apex/CreateReturnOrderController.getDepartmentsForAccount';
import getProductDetails from '@salesforce/apex/CreateReturnOrderController.getProductDetails';
import getProductsForReturnOrderLine from '@salesforce/apex/CreateReturnOrderController.getProductsForReturnOrderLine';
import getDefaultProduct from '@salesforce/apex/CreateReturnOrderController.getDefaultProduct';
import buildReturnOrderPlan from '@salesforce/apex/CreateReturnOrderController.buildReturnOrderPlan';
import validateLineRoutingMatches from '@salesforce/apex/CreateReturnOrderController.validateLineRoutingMatches';
import createReturnOrders from '@salesforce/apex/CreateReturnOrderController.createReturnOrders';
import createAccountContact from '@salesforce/apex/CreateReturnOrderController.createAccountContact';
import updateContactEmail from '@salesforce/apex/CreateReturnOrderController.updateContactEmail';
import checkOpenReturnOrdersForAsset from '@salesforce/apex/CreateReturnOrderController.checkOpenReturnOrdersForAsset';
import getSiteVisitRepairCenterLines from '@salesforce/apex/CreateReturnOrderController.getSiteVisitRepairCenterLines';
import generatePaperworkForReturnOrder from '@salesforce/apex/ReturnOrdersService.generatePaperworkForReturnOrder';
import attachCombinedPdf from '@salesforce/apex/ReturnOrdersService.attachCombinedPdf';
import { loadScript } from 'lightning/platformResourceLoader';
import pdfLibResource from '@salesforce/resourceUrl/pdfLib';
/* paperwork-toast-v2 */

const PAGE_HEADER = 'header';
const PAGE_LINES = 'lines';
const PAGE_SUMMARY = 'summary';
const PAGE_ORDER_HEADERS = 'orderHeaders';
const PAGE_CREATED = 'created';
const BROWSER_TAB_LABEL = 'Create Return Order';
const RETURN_ORDER_TYPE_INSTRUMENTS = 'Instruments';
const ESTIMATE_REQUIRED_QUOTE_VALUE = 'Estimate Required';
const REPORTED_PROBLEM_SUMMARY_MAX_LENGTH = 120;
const LINE_TYPE_SERIALIZED = 'serialized';
const LINE_TYPE_INSTRUMENTS = 'instruments';
const LINE_TYPE_OTHER_SERIALIZED = 'other-serialized';
const LINE_TYPE_OTHER_NON_SERIALIZED = 'other-non-serialized';
const LINE_TYPE_OTHER = 'other';
const LINE_TYPE_SERIALIZED_LABEL =
    'Serialized - Flexible, Rigid, Power, Video, Endocam, Ultrasound';
const LINE_TYPE_INSTRUMENTS_LABEL = 'Instruments';
const LINE_TYPE_OTHER_SERIALIZED_LABEL = 'Other (Serialized)';
const LINE_TYPE_OTHER_NON_SERIALIZED_LABEL = 'Other (Non-Serialized)';
const LINE_TYPE_ADD_OPTIONS = [
    {
        key: LINE_TYPE_SERIALIZED,
        lineType: LINE_TYPE_SERIALIZED,
        typeLabel: 'Serialized',
        description: 'Flexible, Rigid, Power, Video, Endocam, Ultrasound'
    },
    {
        key: LINE_TYPE_INSTRUMENTS,
        lineType: LINE_TYPE_INSTRUMENTS,
        typeLabel: LINE_TYPE_INSTRUMENTS_LABEL,
        description: 'Surgical instruments returned as trays or individual items'
    },
    {
        key: LINE_TYPE_OTHER_SERIALIZED,
        lineType: LINE_TYPE_OTHER_SERIALIZED,
        typeLabel: LINE_TYPE_OTHER_SERIALIZED_LABEL,
        description: 'Dental, Phaco, Stirrup, Probes, and similar serialized items'
    },
    {
        key: LINE_TYPE_OTHER_NON_SERIALIZED,
        lineType: LINE_TYPE_OTHER_NON_SERIALIZED,
        typeLabel: LINE_TYPE_OTHER_NON_SERIALIZED_LABEL,
        description: 'Fiber optic cable, lighted retractor, and similar items'
    }
];
const RO_CATEGORY_SERIALIZED = 'Other (Serialized)';
const RO_CATEGORY_NON_SERIALIZED = 'Other (Non-Serialized)';
const ROLI_LINE_TYPE_SERIALIZED = 'Serialized';
const ROLI_LINE_TYPE_INSTRUMENT = 'Instrument';
const ROLI_LINE_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
const ROLI_LINE_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
const INSTRUMENT_PRODUCT_LINE = 'INSTRUMENT';
const FLEXIBLE_SCOPE_PRODUCT_LINE = 'FLEXIBLE SCOPE';
const SERVICE_ASSET_PRODUCT_TYPE = 'Service Asset';
const STIRRUP_ITEM_TYPE = 'Stirrup';
const HEADER_SERIAL_FOCUS_SELECTOR = '[data-id="header-serial-number"]';
const YES_NO_OPTIONS = [
    { label: 'Yes', value: 'Yes' },
    { label: 'No', value: 'No' }
];
const QUANTITY_RETURNED_DEFAULT = 1;
const CREATION_SOURCE_DEFAULT = 'Salesforce';
const LINE_MEDIA_ACCEPT = '.png,.jpg,.jpeg,.gif,.bmp,.webp,.heic,.mp4,.mov,.avi,.wmv,.mkv,.webm,.m4v,.3gp';
const MOD_FORM_ACCEPT = '.pdf,.png,.jpg,.jpeg,.gif,.tif,.tiff,.bmp,.webp';
const INSULATION_POWDER_COATING_OPTIONS = [
    { label: 'Black', value: 'Black' },
    { label: 'Blue', value: 'Blue' },
    { label: 'Light Blue', value: 'Light Blue' },
    { label: 'Navy Blue', value: 'Navy Blue' },
    { label: 'Green', value: 'Green' },
    { label: 'Yellow', value: 'Yellow' },
    { label: 'Orange', value: 'Orange' },
    { label: 'Light Gray', value: 'Light Gray' },
    { label: 'Purple', value: 'Purple' },
    { label: 'Salmon Orange', value: 'Salmon Orange' },
    { label: 'Lavender', value: 'Lavender' },
    { label: 'Brown', value: 'Brown' },
    { label: 'Red', value: 'Red' }
];
const COLOR_DIPPING_OPTIONS = [
    { label: 'Black', value: 'Black' },
    { label: 'Medium Blue', value: 'Medium Blue' },
    { label: 'Light Blue', value: 'Light Blue' },
    { label: 'Navy Blue', value: 'Navy Blue' },
    { label: 'Hunter Green', value: 'Hunter Green' },
    { label: 'Mint Green', value: 'Mint Green' },
    { label: 'Yellow', value: 'Yellow' },
    { label: 'Salmon Orange', value: 'Salmon Orange' },
    { label: 'Red', value: 'Red' },
    { label: 'Brown', value: 'Brown' },
    { label: 'Light Gray', value: 'Light Gray' },
    { label: 'Violet', value: 'Violet' },
    { label: 'Lavender', value: 'Lavender' },
    { label: 'Purple', value: 'Purple' },
    { label: 'Pink', value: 'Pink' },
    { label: 'White', value: 'White' }
];
const LEG_POSITIONERS_STIRRUP_OPTIONS = [
    { label: 'Repair', value: 'Repair' },
    { label: 'Replace Pads - Right', value: 'Replace Pads - Right' },
    { label: 'Replace Pads - Left', value: 'Replace Pads - Left' },
    {
        label: 'Replace Pads - Right and Left',
        value: 'Replace Pads - Right and Left'
    }
];
const NUMBER_OF_RINGS_OPTIONS = [
    { label: '1', value: '1' },
    { label: '2', value: '2' }
];
const DEFAULT_NUMBER_OF_RINGS = '1';

function formatMultiPicklistValue(value) {
    if (Array.isArray(value)) {
        return value.filter((entry) => entry).join(';');
    }
    return value || '';
}

function clearInstrumentAdditionalServiceFields(line) {
    line.insulationPowderCoating = '';
    line.legPositionersStirrup = [];
    line.additionalServiceRepair = false;
    line.laserMarking = '';
    line.colorDipping = [];
    line.numberOfRings = DEFAULT_NUMBER_OF_RINGS;
}

function clearNonModAdditionalServiceFields(line) {
    line.legPositionersStirrup = [];
    line.additionalServiceRepair = false;
    line.laserMarking = '';
    line.colorDipping = [];
    line.numberOfRings = DEFAULT_NUMBER_OF_RINGS;
}

function clearSerialAdditionalServiceFields(line) {
    line.legPositionersStirrup = [];
}

function clearNoSerialAdditionalServiceFields(line) {
    line.additionalServiceRepair = false;
    line.laserMarking = '';
    line.colorDipping = [];
    line.numberOfRings = DEFAULT_NUMBER_OF_RINGS;
}

const PRODUCT_MATCHING_INFO = {
    primaryField: { fieldPath: 'Name' },
    additionalFields: [{ fieldPath: 'ProductCode' }, { fieldPath: 'Model__c' }]
};

const PRODUCT_DISPLAY_INFO = {
    primaryField: 'Name',
    additionalFields: ['ProductCode', 'Model__c']
};

let lineKeyCounter = 0;
let lineNumberCounter = 0;
const productSearchTimers = {};
const assetSearchTimers = {};

function nextLineKey() {
    lineKeyCounter += 1;
    return `line-${lineKeyCounter}`;
}

function nextLineNumber() {
    lineNumberCounter += 1;
    return lineNumberCounter;
}

export default class CreateReturnOrder extends NavigationMixin(LightningElement) {
    _recordId;
    _objectApiName;
    _recordIds;
    _contextInitialized = false;
    _initScheduled = false;
    _deferHomeInit = false;
    _pageReference;
    _assetLaunchAwaitingHeader = false;
    _pendingTabSerialAssetId = null;
    _pendingTabSerialAsset = null;
    _focusHeaderSerialPending = false;
    _headerSerialLookupGeneration = 0;
    _skipNextHeaderSerialCommit = false;
    isConsoleNavigation = false;

    @api
    get recordId() {
        return this._recordId;
    }
    set recordId(value) {
        this._recordId = value;
        this.scheduleInitialize();
    }

    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        this.scheduleInitialize();
    }

    @api embeddedMode = false;

    /**
     * @description GW-1353 - Site visit launch. Keeps the work order header path and
     *              prefills Instruments lines from child lines marked Send to Repair Center.
     */
    _useSiteVisitRepairCenterLines = false;

    @api
    get useSiteVisitRepairCenterLines() {
        return this._useSiteVisitRepairCenterLines;
    }
    set useSiteVisitRepairCenterLines(value) {
        const nextValue = value === true || value === 'true';
        if (nextValue === this._useSiteVisitRepairCenterLines) {
            return;
        }
        this._useSiteVisitRepairCenterLines = nextValue;
        if (this._contextInitialized && nextValue) {
            this._contextInitialized = false;
            this.scheduleInitialize();
        }
    }

    @api
    get recordIds() {
        return this._recordIds;
    }
    set recordIds(value) {
        this._recordIds = value;
        if (this.normalizeRecordIds(value).length > 0) {
            this._deferHomeInit = false;
        }
        this.scheduleInitialize();
    }

    currentPage = PAGE_HEADER;
    isLoading = true;
    isSaving = false;
    showManualSiteVisitEntry = false;

    accountId;
    accountName = '';
    caseId;
    caseLabel = '';
    lockCase = false;
    lockAccount = false;
    workOrderId = '';
    workOrderLabel = '';
    lockWorkOrder = false;
    defaultLineContactId = '';
    legacyCustomerId = '';
    operatingUnit = '';
    creationSource = CREATION_SOURCE_DEFAULT;
    salesRepId = userId;
    headerSerialNumber = '';
    isLookingUpHeaderSerial = false;

    creationSourceOptions = [];
    disinfectedOptions = [];
    itemTypeOptions = [];
    estimateRequiredOptions = [];
    itemTypeToProductLine = {};
    itemTypeToROCategory = {};
    defaultProductId = '';
    addLineFromSummary = false;
    eligibleContactIds = [];
    contactEmailById = {};
    shipToAddresses = [];
    contactNameById = {};
    activeSections = [];
    repairCenterOptions = [];
    accountAssets = [];
    departmentOptions = [];

    lineItems = [];
    proposedReturnOrderGroups = [];

    showNewContactModal = false;
    isCreatingContact = false;
    newContactTargetType = 'line';
    newContactLineKey = '';
    newContactGroupKey = '';
    newContactFirstName = '';
    newContactLastName = '';
    newContactEmail = '';
    newContactPhone = '';
    newContactTitle = '';

    showUpdateContactEmailModal = false;
    isUpdatingContactEmail = false;
    updateEmailContactId = '';
    updateEmailGroupKey = '';
    updateEmailLineKey = '';
    updateEmailContactName = '';
    updateEmailValue = '';

    showLineTypeModal = false;

    showDuplicateWarningModal = false;
    duplicateReturnOrders = [];
    duplicateWarningAssetLabel = '';
    warnedAssetIds = new Set();

    createdReturnOrders = [];
    isGeneratingPaperwork = false;
    _pdfLibInitialized = false;
    originRecordId;
    originObjectApiName;

    @wire(IsConsoleNavigation)
    wiredIsConsoleNavigation(result) {
        this.isConsoleNavigation = result?.data === true;
        this.updateWorkspaceTab();
    }

    @wire(CurrentPageReference)
    handlePageReference(pageRef) {
        this._pageReference = pageRef;
        if (this.isTabLaunch && this.isHeaderPage && !this.isLoading) {
            this._focusHeaderSerialPending = true;
        }

        const recordIdsParam = pageRef?.state?.c__recordIds;
        if (!recordIdsParam) {
            return;
        }

        const ids = recordIdsParam.split(',').map((id) => id.trim()).filter(Boolean);
        if (ids.length === 0) {
            return;
        }

        this._deferHomeInit = false;
        this._contextInitialized = false;
        this._initScheduled = false;
        this.objectApiName = 'Asset';
        this.recordIds = ids;
        this.scheduleInitialize();
    }

    connectedCallback() {
        this.updateWorkspaceTab();
        Promise.resolve().then(() => {
            if (!this.normalizeRecordIds(this._recordIds).length && !this._recordId) {
                this._deferHomeInit = true;
            }
            this.scheduleInitialize();
        });
    }

    /**
     * GW-5867 - Sets the browser and console tab titles for Create Return Order.
     */
    async updateWorkspaceTab() {
        document.title = BROWSER_TAB_LABEL;

        if (!this.isConsoleNavigation) {
            return;
        }

        try {
            const tabInfo = await getFocusedTabInfo();
            if (!tabInfo?.tabId) {
                return;
            }
            await setTabLabel(tabInfo.tabId, BROWSER_TAB_LABEL);
        } catch (error) {
            // Non-console hosts may not support workspace APIs; page title still updates.
        }
    }

    disconnectedCallback() {
        if (this.productSearchViewportListenersAttached && this._boundRepositionProductSearch) {
            window.removeEventListener('scroll', this._boundRepositionProductSearch, true);
            window.removeEventListener('resize', this._boundRepositionProductSearch);
            this.productSearchViewportListenersAttached = false;
        }
    }

    scheduleInitialize() {
        if (this._contextInitialized || this._initScheduled) {
            return;
        }
        if (!this.isReadyToInitialize()) {
            return;
        }

        this._initScheduled = true;
        Promise.resolve().then(() => {
            this._initScheduled = false;
            if (this._contextInitialized || !this.isReadyToInitialize()) {
                return;
            }
            this._contextInitialized = true;
            this.loadInitialContext();
        });
    }

    isReadyToInitialize() {
        if (this.normalizeRecordIds(this._recordIds).length > 0) {
            return true;
        }
        if (this._recordId) {
            return true;
        }
        return this._deferHomeInit;
    }

    resolveDefaultCreationSource(options) {
        if (!options || options.length === 0) {
            return '';
        }

        const salesforceOption = options.find(
            (option) => option.value === CREATION_SOURCE_DEFAULT || option.label === CREATION_SOURCE_DEFAULT
        );
        if (salesforceOption) {
            return salesforceOption.value;
        }

        return options.length === 1 ? options[0].value : '';
    }

    normalizeRecordIds(recordIds) {
        if (!recordIds) {
            return [];
        }
        return Array.isArray(recordIds) ? recordIds.filter((id) => !!id) : [recordIds];
    }

    async loadInitialContext() {
        this.isLoading = true;
        let checkDuplicatesOnLines = false;
        if (!this.originRecordId && this.recordId && this.objectApiName) {
            this.originRecordId = this.recordId;
            this.originObjectApiName = this.objectApiName;
        }
        try {
            const ctx = await getInitialContext({
                recordId: this.recordId,
                objectApiName: this.objectApiName,
                recordIds: this.recordIds
            });

            this.accountId = ctx.accountId || '';
            this.accountName = ctx.accountName || '';
            this.caseId = ctx.caseId || '';
            this.caseLabel = ctx.caseLabel || '';
            this.lockCase = ctx.lockCase === true;
            this.lockAccount = ctx.lockAccount === true;
            this.workOrderId = ctx.workOrderId || '';
            this.workOrderLabel = ctx.workOrderLabel || '';
            this.lockWorkOrder = ctx.lockWorkOrder === true;
            this.defaultLineContactId = ctx.contactId || '';
            this.legacyCustomerId = ctx.legacyCustomerId || '';
            this.operatingUnit = ctx.defaultOperatingUnit || '';
            this.creationSourceOptions = ctx.creationSourceOptions || [];
            this.disinfectedOptions = ctx.disinfectedOptions || [];
            this.itemTypeOptions = ctx.itemTypeOptions || [];
            this.estimateRequiredOptions = ctx.estimateRequiredOptions || ctx.estReqOptions || [];
            this.itemTypeToProductLine = ctx.itemTypeToProductLine || {};
            this.itemTypeToROCategory = ctx.itemTypeToROCategory || {};
            this.defaultProductId = ctx.defaultProductId || '';
            this.creationSource =
                this.resolveDefaultCreationSource(this.creationSourceOptions) ||
                CREATION_SOURCE_DEFAULT;

            await this.refreshAccountDependencies();
            this.ensureDefaultLineContactEligible();

            if (this.useSiteVisitRepairCenterLines) {
                await this.initializeLinesFromSiteVisitRepairCenter();
                this.showManualSiteVisitEntry = this.lineItems.length === 0;
                if (this.lineItems.length > 0) {
                    this.currentPage = PAGE_LINES;
                    this.showLineTypeModal = false;
                }
            } else if (ctx.assetIds && ctx.assetIds.length > 0) {
                await this.initializeLinesFromAssets(ctx.assetIds);
                this.setDefaultExpandedSections();
                if (this.lockWorkOrder || this.shouldSkipToLinesAfterAssetLaunch()) {
                    this.currentPage = PAGE_LINES;
                    this.showLineTypeModal = false;
                    checkDuplicatesOnLines = true;
                    this._assetLaunchAwaitingHeader = false;
                } else if (this.normalizeRecordIds(this._recordIds).length > 0) {
                    this._assetLaunchAwaitingHeader = true;
                }
            }
        } catch (error) {
            this.showError('Failed to initialize', error);
        } finally {
            this.isLoading = false;
            if (this.isTabLaunch && this.isHeaderPage) {
                this._focusHeaderSerialPending = true;
            }
            // Child mounts after isLoading clears; sync parent header values into shared form.
            // eslint-disable-next-line @lwc/lwc/no-async-operation
            window.setTimeout(() => this.syncAccountInformationToChild(), 0);
        }

        if (checkDuplicatesOnLines) {
            await this.checkDuplicateReturnOrdersForLoadedLines();
        }
    }

    async refreshAccountDependencies({
        skipAccountDefaults = false,
        skipChildSync = false
    } = {}) {
        const promises = [
            this.loadAccountAssets(),
            this.loadDepartments(),
            this.loadPicklists()
        ];

        if (this.accountId) {
            if (!skipAccountDefaults) {
                promises.push(this.loadAccountDefaults());
            }
            promises.push(this.loadEligibleContacts(), this.loadShipToAddresses());
        } else {
            this.eligibleContactIds = [];
            this.shipToAddresses = [];
        }

        await Promise.all(promises);
        if (!skipChildSync) {
            this.syncAccountInformationToChild();
        }
    }

    /**
     * Pushes parent-owned Account Information fields into the shared form component.
     */
    syncAccountInformationToChild() {
        const accountInfo = this.refs?.createOrderAccountInfo;
        if (!accountInfo || typeof accountInfo.applyValues !== 'function') {
            return;
        }
        accountInfo.applyValues({
            accountId: this.accountId || '',
            accountName: this.accountName || '',
            legacyCustomerId: this.legacyCustomerId || '',
            operatingUnit: this.operatingUnit || '',
            salesRepId: this.salesRepId || userId
        });
    }

    resolveOperatingUnitFromAccount(account) {
        if (!account) {
            return '';
        }
        return account.OrgIDs__c || '';
    }

    async loadAccountDefaults() {
        const requestedAccountId = this.accountId;
        if (!requestedAccountId) {
            return;
        }
        try {
            const account = await getAccountDetails({ accountId: requestedAccountId });
            // Cancel / account change may have cleared selection while Apex was in flight.
            if (this.accountId !== requestedAccountId) {
                return;
            }
            if (account) {
                this.accountName = account.Name || this.accountName;
                this.legacyCustomerId = account.SystemID__c || this.legacyCustomerId;
                const accountOperatingUnit = this.resolveOperatingUnitFromAccount(account);
                if (accountOperatingUnit) {
                    this.operatingUnit = accountOperatingUnit;
                }
            }
        } catch (error) {
            if (this.accountId !== requestedAccountId) {
                return;
            }
            this.showError('Failed to load account details', error);
        }
    }

    async loadPicklists() {
        try {
            const locations = await getRepairCenterLocations();
            this.repairCenterOptions = (locations || []).map((loc) => ({
                label: loc.name,
                value: loc.id
            }));
        } catch (error) {
            this.showError('Failed to load reference data', error);
        }
    }

    async loadEligibleContacts() {
        if (!this.accountId) {
            this.eligibleContactIds = [];
            this.contactEmailById = {};
            this.contactNameById = {};
            return;
        }

        try {
            const contacts = await getContactsForAccount({ accountId: this.accountId });
            this.eligibleContactIds = (contacts || []).map((contact) => contact.Id);
            const emailById = {};
            const nameById = {};
            (contacts || []).forEach((contact) => {
                emailById[contact.Id] = contact.Email || '';
                nameById[contact.Id] = contact.Name || '';
            });
            this.contactEmailById = emailById;
            this.contactNameById = nameById;
            this.ensureDefaultLineContactEligible();
        } catch (error) {
            this.eligibleContactIds = [];
            this.contactEmailById = {};
            this.contactNameById = {};
            this.showError('Failed to load contacts', error);
        }
    }

    /**
     * GW-5320 - Loads Address accounts that match the Ship-To lookup filter.
     */
    async loadShipToAddresses() {
        if (!this.accountId) {
            this.shipToAddresses = [];
            return;
        }

        try {
            this.shipToAddresses = (await getShipToAddressesForAccount({
                accountId: this.accountId
            })) || [];
            const defaultShipToId = this.defaultShipToAccountId;
            this.lineItems = this.lineItems.map((line) =>
                line.shipToAccountId ? line : { ...line, shipToAccountId: defaultShipToId }
            );
        } catch (error) {
            this.shipToAddresses = [];
            this.showError('Failed to load Ship-To addresses', error);
        }
    }

    get defaultShipToAccountId() {
        const primary = (this.shipToAddresses || []).find((option) => option.isPrimary);
        return primary?.id || '';
    }

    get shipToComboboxOptions() {
        return (this.shipToAddresses || []).map((option) => ({
            label: option.label || option.name,
            value: option.id
        }));
    }

    resolveShipToAddressDisplay(shipToAccountId) {
        const selected = (this.shipToAddresses || []).find(
            (option) => option.id === shipToAccountId
        );
        return selected?.addressDisplay || '';
    }

    ensureDefaultLineContactEligible() {
        if (
            this.defaultLineContactId &&
            !this.eligibleContactIds.includes(this.defaultLineContactId)
        ) {
            this.eligibleContactIds = [...this.eligibleContactIds, this.defaultLineContactId];
        }
    }

    async loadAccountAssets() {
        if (!this.accountId) {
            this.accountAssets = [];
            return;
        }

        try {
            this.accountAssets = await getAssetsForAccount({ accountId: this.accountId });
        } catch (error) {
            this.showError('Failed to load assets', error);
        }
    }

    getAdditionalDepartmentIds() {
        return [
            ...new Set(
                this.lineItems.map((line) => line.departmentId).filter((departmentId) => !!departmentId)
            )
        ];
    }

    async loadDepartments() {
        if (!this.accountId) {
            this.departmentOptions = [];
            return;
        }

        try {
            this.departmentOptions = await getDepartmentsForAccount({
                accountId: this.accountId,
                additionalDepartmentIds: this.getAdditionalDepartmentIds()
            });
        } catch (error) {
            this.showError('Failed to load departments', error);
            this.departmentOptions = [];
        }
    }

    async ensureDepartmentOptionAvailable(departmentId) {
        if (!departmentId || !this.accountId) {
            return;
        }

        if ((this.departmentOptions || []).some((option) => option.value === departmentId)) {
            return;
        }

        try {
            this.departmentOptions = await getDepartmentsForAccount({
                accountId: this.accountId,
                additionalDepartmentIds: [departmentId]
            });
        } catch (error) {
            this.showError('Failed to load department', error);
        }
    }

    async initializeLinesFromAssets(assetIds) {
        const requestedIds = (assetIds || []).filter((assetId) => !!assetId);
        try {
            const assets = await getAssetsByIds({ assetIds: requestedIds });
            this.lineItems = (assets || []).map((asset) => this.buildLineFromAsset(asset));

            for (const line of this.lineItems) {
                if (line.departmentId) {
                    await this.ensureDepartmentOptionAvailable(line.departmentId);
                }
            }

            if (requestedIds.length > 0 && this.lineItems.length === 0) {
                this.showToast(
                    'Warning',
                    this.lockWorkOrder
                        ? 'Work Order assets could not be loaded into return order items.'
                        : 'Scanned asset could not be loaded into return order items.',
                    'warning'
                );
            }
        } catch (error) {
            this.showError('Failed to load selected assets', error);
        }
    }

    /**
     * GW-5867 — apply the tab serial-scan match to lines without relying on a second Id round-trip
     * that can race with serial input clearing `_pendingTabSerialAssetId`.
     */
    async applyPendingTabSerialAssetToLines() {
        const scannedAsset = this._pendingTabSerialAsset;
        const assetId =
            this._pendingTabSerialAssetId || scannedAsset?.id || scannedAsset?.Id || '';

        if (scannedAsset && assetId) {
            this.lineItems = [
                this.buildLineFromAsset({
                    id: assetId,
                    serialNumber: scannedAsset.serialNumber,
                    model: scannedAsset.model,
                    departmentId: scannedAsset.departmentId,
                    product2Id: scannedAsset.product2Id,
                    productLine: scannedAsset.productLine,
                    productName: scannedAsset.productName
                })
            ];
            for (const line of this.lineItems) {
                if (line.departmentId) {
                    await this.ensureDepartmentOptionAvailable(line.departmentId);
                }
            }
        } else if (assetId) {
            await this.initializeLinesFromAssets([assetId]);
        }

        this._pendingTabSerialAssetId = null;
        this._pendingTabSerialAsset = null;
        this.setDefaultExpandedSections();
    }

    async checkDuplicateReturnOrdersForLoadedLines() {
        const uniqueAssetIds = [
            ...new Set(
                this.lineItems.map((line) => line.assetId).filter((assetId) => !!assetId)
            )
        ];

        for (const assetId of uniqueAssetIds) {
            await this.promptDuplicateReturnOrderWarning(assetId);
        }
    }

    async promptDuplicateReturnOrderWarning(assetId) {
        if (!assetId || this.warnedAssetIds.has(assetId)) {
            return;
        }

        try {
            const result = await checkOpenReturnOrdersForAsset({ assetId });
            if (!result?.hasOpenReturnOrders || !result.returnOrders?.length) {
                return;
            }

            this.warnedAssetIds.add(assetId);
            this.duplicateReturnOrders = result.returnOrders;
            this.duplicateWarningAssetLabel = this.getAssetLabelForWarning(assetId);
            this.showDuplicateWarningModal = true;
        } catch (error) {
            this.showError('Failed to check for open return orders', error);
        }
    }

    getAssetLabelForWarning(assetId) {
        const asset = (this.accountAssets || []).find((row) => row.id === assetId);
        if (!asset) {
            return 'the selected asset';
        }
        return this.buildAssetSerialLabel(asset);
    }

    buildAssetDisplayLabel(asset) {
        if (!asset) {
            return '';
        }
        const parts = [asset.name, asset.productName, asset.model].filter((part) =>
            Boolean(String(part || '').trim())
        );
        return parts.length > 0 ? parts.join(' · ') : asset.id;
    }

    buildAssetSerialLabel(asset) {
        return this.buildAssetDisplayLabel(asset);
    }

    handleCloseDuplicateWarningModal() {
        this.showDuplicateWarningModal = false;
        this.duplicateReturnOrders = [];
        this.duplicateWarningAssetLabel = '';
    }

    isOtherLineType(lineType) {
        return (
            lineType === LINE_TYPE_OTHER_SERIALIZED ||
            lineType === LINE_TYPE_OTHER_NON_SERIALIZED ||
            lineType === LINE_TYPE_OTHER
        );
    }

    isOtherSerializedLineType(lineType) {
        return lineType === LINE_TYPE_OTHER_SERIALIZED;
    }

    isOtherNonSerializedLineType(lineType) {
        return lineType === LINE_TYPE_OTHER_NON_SERIALIZED;
    }

    isFlexibleScopeProductLine(productLine) {
        return (productLine || '').trim().toUpperCase() === FLEXIBLE_SCOPE_PRODUCT_LINE;
    }

    getItemTypeOptionsForLine(line) {
        let roCategory;
        if (this.isOtherSerializedLineType(line?.lineType)) {
            roCategory = RO_CATEGORY_SERIALIZED;
        } else if (this.isOtherNonSerializedLineType(line?.lineType)) {
            roCategory = RO_CATEGORY_NON_SERIALIZED;
        } else {
            return this.itemTypeOptions || [];
        }

        return (this.itemTypeOptions || []).filter(
            (option) => this.itemTypeToROCategory?.[option.value] === roCategory
        );
    }

    buildEmptyLine(lineType = LINE_TYPE_SERIALIZED) {
        const isInstruments = lineType === LINE_TYPE_INSTRUMENTS;
        return {
            key: nextLineKey(),
            lineNumber: nextLineNumber(),
            lineType,
            sourceWorkOrderLineItemId: '',
            assetId: '',
            product2Id: '',
            serialNumber: '',
            assetSerialPick: '',
            assetSearchText: '',
            showAssetResults: false,
            assetSearchDropdownStyle: '',
            model: '',
            productLine: isInstruments ? INSTRUMENT_PRODUCT_LINE : '',
            itemDescription: '',
            departmentId: '',
            disinfected: '',
            itemType: '',
            contactId: '',
            estimateContactId: '',
            estimateRequired: '',
            customerPo: '',
            isLoanerAsset: false,
            loanerRequested: false,
            reportedProblem: '',
            customerReference: '',
            shipToAccountId: this.defaultShipToAccountId,
            repairWarranty: '',
            previousReturnOrder: '',
            warrantyNotes: '',
            hospitalReferencedTrayName: '',
            modRequest: false,
            additionalServices: false,
            insulationPowderCoating: '',
            legPositionersStirrup: [],
            additionalServiceRepair: false,
            laserMarking: '',
            colorDipping: [],
            numberOfRings: DEFAULT_NUMBER_OF_RINGS,
            status: 'Created',
            quantityReturned: QUANTITY_RETURNED_DEFAULT,
            attachments: [],
            modFormAttachments: [],
            productOptions: [],
            productSearchText: '',
            showProductResults: false,
            productSearchDropdownStyle: ''
        };
    }

    /**
     * @description GW-1353 - Prefill Instruments lines from site visit child WOLIs
     *              marked Send to Repair Center.
     */
    async initializeLinesFromSiteVisitRepairCenter() {
        const rows = await getSiteVisitRepairCenterLines({
            workOrderId: this.workOrderId || this.recordId
        });
        this.lineItems = (rows || []).map((row) => this.buildInstrumentLineFromWorkOrderLine(row));

        for (const line of this.lineItems) {
            if (line.departmentId) {
                await this.ensureDepartmentOptionAvailable(line.departmentId);
            }
            if (!line.product2Id) {
                await this.applyInstrumentLineDefaults(line.key);
            }
        }

        this.setDefaultExpandedSections();
    }

    /**
     * @description Maps a site visit child work order line onto an Instruments RO line.
     * @param {object} row SiteVisitInstrumentLine from Apex
     * @returns {object} Line item for the wizard
     */
    buildInstrumentLineFromWorkOrderLine(row) {
        const line = this.buildEmptyLine(LINE_TYPE_INSTRUMENTS);
        const insulation = row?.insulationPowderCoating || '';
        line.sourceWorkOrderLineItemId = row?.workOrderLineItemId || '';
        line.product2Id = row?.product2Id || '';
        line.productSearchText = row?.productName || '';
        line.itemDescription = row?.itemDescription || row?.productName || '';
        line.serialNumber = row?.serialNumber || '';
        line.model = row?.model || '';
        line.departmentId = row?.departmentId || '';
        line.reportedProblem = row?.reportedProblem || '';
        line.quantityReturned = row?.quantityReturned ?? QUANTITY_RETURNED_DEFAULT;
        line.additionalServices = row?.additionalServices === true;
        line.insulationPowderCoating = line.additionalServices ? insulation : '';
        line.modRequest = line.additionalServices && !!line.insulationPowderCoating;
        if (this.defaultLineContactId) {
            line.contactId = this.defaultLineContactId;
        }
        return line;
    }

    isExtendedLineType(lineType) {
        return (
            lineType === LINE_TYPE_INSTRUMENTS || this.isOtherLineType(lineType)
        );
    }

    usesProductSearchLookup(lineType) {
        return (
            lineType === LINE_TYPE_SERIALIZED ||
            lineType === LINE_TYPE_INSTRUMENTS ||
            this.isOtherLineType(lineType)
        );
    }

    buildLineFromAsset(asset) {
        const assetId = asset?.id || asset?.Id || '';
        const line = this.buildEmptyLine(LINE_TYPE_SERIALIZED);
        line.assetId = assetId;
        line.product2Id = asset.product2Id;
        line.serialNumber = this.normalizeUppercaseText(asset.serialNumber || '');
        line.assetSerialPick = asset.serialNumber || assetId || '';
        line.assetSearchText = this.buildAssetSerialLabel({
            ...asset,
            id: assetId,
            name: asset.name || asset.productName || asset.serialNumber || assetId
        });
        line.model = this.normalizeUppercaseText(asset.model || '');
        line.departmentId = asset.departmentId || '';
        line.productLine = asset.productLine || '';
        line.productSearchText = asset.productName || '';
        if (this.defaultLineContactId) {
            line.contactId = this.defaultLineContactId;
        }
        return line;
    }

    setDefaultExpandedSections() {
        if (this.lineItems.length > 0) {
            this.expandLineSection(this.lineItems[0].key, { collapseOthers: true });
        }
    }

    get isHeaderPage() {
        return this.currentPage === PAGE_HEADER;
    }

    /**
     * @description GW-1353 - Site visit had no Send to Repair Center lines, so items are entered here.
     */
    get showManualSiteVisitEntryNotice() {
        return this.showManualSiteVisitEntry && this.isHeaderPage;
    }

    get isTabLaunch() {
        return (
            this._pageReference?.type === 'standard__navItemPage' &&
            !this._recordId &&
            this.normalizeRecordIds(this._recordIds).length === 0
        );
    }

    get showMergedTabHeader() {
        return this.isHeaderPage && this.isTabLaunch;
    }

    get showStandardHeader() {
        return this.isHeaderPage && !this.isTabLaunch;
    }

    /**
     * Tab launch is full-page; shrink the white card to content width and pin it
     * to the left so it reads like the Account quick-action popup.
     */
    get wizardFrameClass() {
        return this.isTabLaunch ? 'wizard-frame wizard-frame--tab' : 'wizard-frame';
    }

    get wizardShellClass() {
        return this.isTabLaunch ? 'wizard-shell wizard-shell--tab' : 'wizard-shell';
    }

    get wizardFooterClass() {
        const align = this.isTabLaunch ? 'slds-grid_align-center' : 'slds-grid_align-end';
        return `slds-m-horizontal_medium slds-m-bottom_medium slds-grid ${align} wizard-footer`;
    }

    get mergedHeaderInstruction() {
        return (
            'Scan/Enter the device serial number or enter the necessary account information ' +
            'to initiate creation of the return order.'
        );
    }

    get isLinesPage() {
        return this.currentPage === PAGE_LINES;
    }

    get isSummaryPage() {
        return this.currentPage === PAGE_SUMMARY;
    }

    get isOrderHeadersPage() {
        return this.currentPage === PAGE_ORDER_HEADERS;
    }

    get isCreatedPage() {
        return this.currentPage === PAGE_CREATED;
    }

    get cardTitle() {
        if (this.isCreatedPage) {
            return 'Return Orders Created';
        }
        if (this.isOrderHeadersPage) {
            return 'Instrument Return Order Details';
        }
        return 'Create Return Order';
    }

    get createdReturnOrdersDisplay() {
        return (this.createdReturnOrders || []).map((order, index) => {
            const lineCount = order.lineCount ?? 0;
            const returnOrderNumber = order.returnOrderNumber || '';
            return {
                ...order,
                rowKey: order.returnOrderId || `created-ro-${index}`,
                returnOrderNumberLabel:
                    lineCount > 0
                        ? `${returnOrderNumber} (${lineCount})`
                        : returnOrderNumber
            };
        });
    }

    get hasCreatedReturnOrders() {
        return this.createdReturnOrdersDisplay.length > 0;
    }

    get currentStepValue() {
        if (this.isHeaderPage) {
            return '1';
        }
        if (this.isLinesPage) {
            return '2';
        }
        if (this.isOrderHeadersPage) {
            return '4';
        }
        return '3';
    }

    get progressSteps() {
        const steps = [
            { label: 'Header Information', value: '1' },
            { label: 'Items', value: '2' },
            { label: 'Review', value: '3' }
        ];
        if (this.hasInstrumentReturnOrderGroups) {
            steps.push({ label: 'Order Details', value: '4' });
        }
        return steps;
    }

    get hasInstrumentReturnOrderGroups() {
        return (this.proposedReturnOrderGroups || []).some(
            (group) => group.returnOrderType === RETURN_ORDER_TYPE_INSTRUMENTS
        );
    }

    get instrumentReturnOrderGroups() {
        return (this.proposedReturnOrderGroups || []).filter(
            (group) => group.returnOrderType === RETURN_ORDER_TYPE_INSTRUMENTS
        );
    }

    get orderHeaderGroups() {
        return this.instrumentReturnOrderGroups.map((group, index) => {
            const reportedProblemsSummary = (group.lineSummaries || [])
                .map((line) => String(line.reportedProblem || '').trim())
                .filter(Boolean)
                .join(' | ');

            return {
                ...group,
                displayIndex: index + 1,
                estimateRequiredReadOnly: Boolean(group.hasModRequest),
                estimateRequiredHelpText: group.hasModRequest
                    ? 'Set automatically because this return order includes a Mod Request.'
                    : '',
                showEstimateContact: group.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE,
                showModRequestContact: Boolean(group.hasModRequest),
                reportedProblemsSummary,
                reportedProblemsDisplay: this.truncateSummaryText(
                    reportedProblemsSummary,
                    REPORTED_PROBLEM_SUMMARY_MAX_LENGTH
                ),
                showRepairWarrantyYes: group.repairWarranty === 'Yes',
                shipToAddressDisplay: this.resolveShipToAddressDisplay(group.shipToAccountId),
                warrantyNotesRequired:
                    group.repairWarranty === 'Yes' &&
                    !String(group.previousReturnOrder || '').trim(),
                warrantyNotesHelpText:
                    group.repairWarranty === 'Yes' &&
                    !String(group.previousReturnOrder || '').trim()
                        ? 'Required when Previous Return Order is not provided.'
                        : ''
            };
        });
    }

    truncateSummaryText(value, maxLength) {
        const text = String(value || '').trim();
        if (!text || text.length <= maxLength) {
            return text;
        }

        return `${text.substring(0, Math.max(0, maxLength - 3))}...`;
    }

    get summaryContinueLabel() {
        return this.hasInstrumentReturnOrderGroups ? 'Continue' : 'Approve and Create';
    }

    buildEmptyInstrumentOrderHeaderFields() {
        const defaultContactId = this.defaultLineContactId || '';
        return {
            contactId: defaultContactId,
            estimateContactId: '',
            estimateRequired: '',
            modRequestContactId: '',
            hasModRequest: false,
            repairWarranty: '',
            warrantyNotes: '',
            previousReturnOrder: '',
            customerPo: '',
            customerReference: '',
            hospitalReferencedTrayName: '',
            shipToAccountId: this.defaultShipToAccountId
        };
    }

    groupHasModRequest(group) {
        try {
            const lines = JSON.parse(group?.lineItemsJson || '[]');
            if (Array.isArray(lines) && lines.some((line) => Boolean(line?.modRequest))) {
                return true;
            }
        } catch (e) {
            // Fall through to lineItems lookup by summary keys.
        }

        const lineKeys = new Set(
            (group?.lineSummaries || [])
                .map((line) => line?.lineKey)
                .filter((key) => Boolean(key))
        );
        if (lineKeys.size === 0) {
            return false;
        }
        return (this.lineItems || []).some(
            (line) => lineKeys.has(line.key) && Boolean(line.modRequest)
        );
    }

    get summaryGroups() {
        return (this.proposedReturnOrderGroups || []).map((group, index) => ({
            ...group,
            displayIndex: index + 1,
            isInstruments: group.returnOrderType === RETURN_ORDER_TYPE_INSTRUMENTS,
            showRepairCenterPicker: group.requiresRepairCenterSelection === true,
            selectedRepairCenterId: group.selectedRepairCenterId || '',
            lines: (group.lineSummaries || []).map((line, lineIndex) => ({
                ...line,
                rowKey: `${group.groupKey}-${line.lineKey || lineIndex}`,
                quantityLabel:
                    line.quantityReturned != null ? String(line.quantityReturned) : '1'
            }))
        }));
    }

    get yesNoOptions() {
        return YES_NO_OPTIONS;
    }

    get insulationPowderCoatingOptions() {
        return INSULATION_POWDER_COATING_OPTIONS;
    }

    get colorDippingOptions() {
        return COLOR_DIPPING_OPTIONS;
    }

    get lineTypeAddOptions() {
        return LINE_TYPE_ADD_OPTIONS;
    }

    get legPositionersStirrupOptions() {
        return LEG_POSITIONERS_STIRRUP_OPTIONS;
    }

    get numberOfRingsOptions() {
        return NUMBER_OF_RINGS_OPTIONS;
    }

    get hasLineItems() {
        return this.lineItems.length > 0;
    }

    get showLineTypePickerOnLinesPage() {
        return this.showLineTypeModal;
    }

    get showLineTypePickerCancel() {
        return this.showLineTypeModal && this.hasLineItems;
    }

    get lineDisplayItems() {
        return this.lineItems.map((line, index) => {
            const isOther = this.isOtherLineType(line.lineType);
            const isOtherSerialized = this.isOtherSerializedLineType(line.lineType);
            const isOtherNonSerialized = this.isOtherNonSerializedLineType(line.lineType);
            const isSerialized = line.lineType === LINE_TYPE_SERIALIZED;
            const quantityLocked =
                isSerialized ||
                isOtherSerialized ||
                this.isFlexibleScopeProductLine(line.productLine);

            return {
            ...line,
            // GW-5554 — Serial Number and Model always display in ALL CAPS.
            serialNumber: this.normalizeUppercaseText(line.serialNumber),
            model: this.normalizeUppercaseText(line.model),
            isSerialized,
            isInstruments: line.lineType === LINE_TYPE_INSTRUMENTS,
            isOther,
            isOtherSerialized,
            isOtherNonSerialized,
            modelReadOnly: isOther,
            serialNumberRequired: isSerialized || isOtherSerialized,
            serialNumberPlaceholder:
                isSerialized || isOtherSerialized ? 'Enter serial number' : '',
            modelRequired: isSerialized,
            showItemType: isOther,
            showOtherSerialNumber: isOtherSerialized,
            itemTypeOptions: this.getItemTypeOptionsForLine(line),
            showAssetSerialPick: isSerialized,
            showItemDescription:
                line.lineType === LINE_TYPE_INSTRUMENTS || isOther,
            showHospitalTrayName: false,
            showModRequest: line.lineType === LINE_TYPE_INSTRUMENTS,
            showModFormUpload:
                line.lineType === LINE_TYPE_INSTRUMENTS && Boolean(line.modRequest),
            showAdditionalServicesCheckbox: line.lineType === LINE_TYPE_INSTRUMENTS,
            showAdditionalServicesSection:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                Boolean(line.additionalServices),
            showInsulationPowderCoating:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                Boolean(line.additionalServices) &&
                Boolean(line.modRequest),
            showLegPositionersStirrup:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                Boolean(line.additionalServices) &&
                !Boolean(line.modRequest) &&
                Boolean(String(line.serialNumber || '').trim()),
            showNoSerialAdditionalServices:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                Boolean(line.additionalServices) &&
                !Boolean(line.modRequest) &&
                !String(line.serialNumber || '').trim(),
            showLoanerSection: isSerialized,
            showQuantity: !quantityLocked,
            quantityReadOnly: quantityLocked,
            showCustomerReference: isSerialized || isOther,
            shipToAddressDisplay: this.resolveShipToAddressDisplay(line.shipToAccountId),
            showEstimateContact:
                line.lineType !== LINE_TYPE_INSTRUMENTS &&
                line.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE,
            showRepairWarrantyYes: line.repairWarranty === 'Yes',
            hasPreviousReturnOrder: Boolean(String(line.previousReturnOrder || '').trim()),
            warrantyNotesRequired:
                line.repairWarranty === 'Yes' &&
                !String(line.previousReturnOrder || '').trim(),
            warrantyNotesHelpText:
                line.repairWarranty === 'Yes' &&
                !String(line.previousReturnOrder || '').trim()
                    ? 'Required when Previous Return Order is not provided.'
                    : '',
            attachmentItems: line.attachments || [],
            hasAttachments: (line.attachments || []).length > 0,
            modFormAttachmentItems: line.modFormAttachments || [],
            hasModFormAttachments: (line.modFormAttachments || []).length > 0,
            sectionLabel: this.buildLineSectionLabel(line),
            productRecordFilter: this.buildProductRecordFilter(line),
            isProductSearchDisabled: this.isProductSearchDisabled(line),
            productPickerPlaceholder: this.getProductPickerPlaceholder(line),
            productOptions: line.productOptions || [],
            productSearchText: line.productSearchText || '',
            showProductResults: Boolean(line.showProductResults),
            productSearchLookupClass: line.showProductResults
                ? 'product-search-lookup slds-form-element product-search-lookup--open'
                : 'product-search-lookup slds-form-element',
            productSearchDropdownStyle: line.productSearchDropdownStyle || '',
            assetOptions: this.filterAccountAssets(line.assetSearchText),
            assetSearchText: line.assetSearchText || '',
            showAssetResults: Boolean(line.showAssetResults),
            isAssetSearchDisabled:
                !this.accountId || !(this.accountAssets || []).length,
            assetSearchLookupClass: line.showAssetResults
                ? 'product-search-lookup slds-form-element product-search-lookup--open'
                : 'product-search-lookup slds-form-element',
            assetSearchDropdownStyle: line.assetSearchDropdownStyle || ''
        };
        });
    }

    get productMatchingInfo() {
        return PRODUCT_MATCHING_INFO;
    }

    get productDisplayInfo() {
        return PRODUCT_DISPLAY_INFO;
    }

    get acceptedMediaTypes() {
        return LINE_MEDIA_ACCEPT;
    }

    get acceptedModFormTypes() {
        return MOD_FORM_ACCEPT;
    }

    get productRecordFilter() {
        return this.buildBaseProductRecordFilter();
    }

    buildBaseProductRecordFilter(productLine, requireServiceAssetType = true) {
        const criteria = [
            {
                fieldPath: 'IsActive',
                operator: 'eq',
                value: true
            }
        ];
        let filterLogic = '1';

        if (requireServiceAssetType) {
            criteria.unshift({
                fieldPath: 'ProductType__c',
                operator: 'eq',
                value: SERVICE_ASSET_PRODUCT_TYPE
            });
            filterLogic = '1 AND 2';
        }

        if (productLine) {
            criteria.push({
                fieldPath: 'ProductLine__c',
                operator: 'eq',
                value: productLine
            });
            filterLogic = requireServiceAssetType
                ? '1 AND 2 AND 3'
                : '1 AND 2';
        }

        return {
            criteria,
            filterLogic
        };
    }

    buildProductRecordFilter(line) {
        if (line.lineType === LINE_TYPE_SERIALIZED) {
            return this.buildBaseProductRecordFilter(null, true);
        }

        if (line.lineType === LINE_TYPE_INSTRUMENTS) {
            return this.buildBaseProductRecordFilter(INSTRUMENT_PRODUCT_LINE, false);
        }

        if (this.isOtherLineType(line.lineType)) {
            if (!line.productLine) {
                return null;
            }
            return this.buildBaseProductRecordFilter(line.productLine, false);
        }

        return this.buildBaseProductRecordFilter();
    }

    isProductSearchDisabled(line) {
        return (
            this.isOtherLineType(line.lineType) &&
            !String(line.productLine || '').trim()
        );
    }

    getProductPickerPlaceholder(line) {
        if (this.isProductSearchDisabled(line)) {
            return 'Select item type first';
        }
        if (this.usesProductSearchLookup(line.lineType)) {
            return 'Search or select product';
        }
        return 'Search products...';
    }

    resolveProductLineForLine(line) {
        if (!line) {
            return '';
        }
        if (line.lineType === LINE_TYPE_INSTRUMENTS) {
            return INSTRUMENT_PRODUCT_LINE;
        }
        if (this.isOtherLineType(line.lineType)) {
            return line.productLine || '';
        }
        return '';
    }

    resolveRequireServiceAssetTypeForLine(line) {
        return line?.lineType === LINE_TYPE_SERIALIZED;
    }

    formatProductOptionLabel(product) {
        if (!product) {
            return '';
        }

        const parts = [product.Name, product.ProductCode, product.Model__c].filter((value) =>
            Boolean(String(value || '').trim())
        );
        return parts.length ? parts.join(' · ') : product.Name || '';
    }

    applyProductFieldsToLine(lineKey, { product2Id, description, model, name, productCode }) {
        const productSearchText =
            this.formatProductOptionLabel({
                Name: name,
                ProductCode: productCode,
                Model__c: model
            }) || name || '';

        this.lineItems = this.lineItems.map((item) =>
            item.key === lineKey
                ? {
                      ...item,
                      product2Id: product2Id || '',
                      itemDescription: description || '',
                      model: this.normalizeUppercaseText(model || ''),
                      productSearchText
                  }
                : item
        );
    }

    async applyInstrumentLineDefaults(lineKey) {
        const line = this.lineItems.find((item) => item.key === lineKey);
        if (!line || line.lineType !== LINE_TYPE_INSTRUMENTS) {
            return;
        }

        try {
            let product = null;

            if (this.defaultProductId) {
                product = await getProductDetails({
                    productId: this.defaultProductId,
                    requireServiceAssetType: false
                });
            }

            if (!product?.Id) {
                product = await getDefaultProduct();
            }

            if (!product?.Id) {
                return;
            }

            this.defaultProductId = product.Id;
            this.applyProductFieldsToLine(lineKey, {
                product2Id: product.Id,
                description: product.Description,
                model: product.Model__c,
                name: product.Name,
                productCode: product.ProductCode
            });
        } catch (error) {
            this.showError('Failed to load default product', error);
        }
    }

    async loadProductOptionsForLine(lineKey, searchTerm = '', showResults = false) {
        const line = this.lineItems.find((item) => item.key === lineKey);
        if (!line || !this.usesProductSearchLookup(line.lineType)) {
            return;
        }

        const productLine = this.resolveProductLineForLine(line);
        const requireServiceAssetType = this.resolveRequireServiceAssetTypeForLine(line);
        if (!requireServiceAssetType && !productLine) {
            this.lineItems = this.lineItems.map((item) =>
                item.key === lineKey
                    ? { ...item, productOptions: [], showProductResults: false }
                    : item
            );
            return;
        }

        try {
            const products = await getProductsForReturnOrderLine({
                productLine: productLine || '',
                requireServiceAssetType,
                searchTerm: searchTerm || '',
                deviceType: this.resolveDeviceTypeFilterForLine(line)
            });
            const excludeDefaultProduct =
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                this.instrumentLineHasSerialNumber(line);
            const productOptions = (products || [])
                .filter(
                    (product) =>
                        !excludeDefaultProduct ||
                        product.value !== this.defaultProductId
                )
                .map((product) => ({
                label: product.label,
                value: product.value,
                model: product.model || '',
                name: product.name || '',
                productCode: product.productCode || '',
                description: product.description || ''
            }));
            this.lineItems = this.lineItems.map((item) =>
                item.key === lineKey
                    ? { ...item, productOptions, showProductResults: showResults }
                    : item
            );
            if (showResults) {
                // eslint-disable-next-line @lwc/lwc/no-async-operation
                window.setTimeout(() => {
                    this.updateProductSearchDropdownPosition(lineKey);
                    this.ensureProductSearchViewportListeners();
                }, 0);
            }
        } catch (error) {
            this.showError('Failed to load products', error);
        }
    }

    scheduleProductSearch(lineKey, searchTerm) {
        if (productSearchTimers[lineKey]) {
            clearTimeout(productSearchTimers[lineKey]);
        }

        // eslint-disable-next-line @lwc/lwc/no-async-operation
        productSearchTimers[lineKey] = window.setTimeout(() => {
            this.loadProductOptionsForLine(lineKey, searchTerm, true);
        }, 300);
    }

    handleProductSearchFocus(event) {
        const lineKey = event.target.dataset.key;
        const line = this.lineItems.find((item) => item.key === lineKey);
        if (!line || this.isProductSearchDisabled(line)) {
            return;
        }

        const searchTerm = line.productSearchText || '';
        this.loadProductOptionsForLine(lineKey, searchTerm, true);
    }

    handleProductSearchInput(event) {
        const lineKey = event.target.dataset.key;
        const searchTerm = event.target.value || '';

        this.lineItems = this.lineItems.map((item) => {
            if (item.key !== lineKey) {
                return item;
            }

            const updated = {
                ...item,
                productSearchText: searchTerm,
                product2Id: '',
                model: '',
                itemDescription: '',
                showProductResults: true
            };

            if (item.lineType === LINE_TYPE_SERIALIZED) {
                updated.productLine = '';
            }

            return updated;
        });

        this.scheduleProductSearch(lineKey, searchTerm);
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.updateProductSearchDropdownPosition(lineKey);
            this.ensureProductSearchViewportListeners();
        }, 0);
    }

    handleProductSearchBlur(event) {
        const lineKey = event.target.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.lineItems = this.lineItems.map((item) =>
                item.key === lineKey
                    ? { ...item, showProductResults: false, productSearchDropdownStyle: '' }
                    : item
            );
            this.removeProductSearchViewportListenersIfIdle();
        }, 200);
    }

    updateProductSearchDropdownPosition(lineKey) {
        const control = this.template.querySelector(
            `[data-product-search-control="${lineKey}"]`
        );
        if (!control) {
            return;
        }

        const rect = control.getBoundingClientRect();
        const top = Math.round(rect.bottom + 2);
        const left = Math.round(rect.left);
        const width = Math.max(Math.round(rect.width), 280);
        const dropdownStyle = `top: ${top}px; left: ${left}px; width: ${width}px;`;

        this.lineItems = this.lineItems.map((item) =>
            item.key === lineKey ? { ...item, productSearchDropdownStyle: dropdownStyle } : item
        );
    }

    ensureProductSearchViewportListeners() {
        if (this.productSearchViewportListenersAttached) {
            return;
        }

        this.productSearchViewportListenersAttached = true;
        this._boundRepositionProductSearch = () => {
            this.lineItems
                .filter((line) => line.showProductResults)
                .forEach((line) => this.updateProductSearchDropdownPosition(line.key));
        };
        window.addEventListener('scroll', this._boundRepositionProductSearch, true);
        window.addEventListener('resize', this._boundRepositionProductSearch);
    }

    removeProductSearchViewportListenersIfIdle() {
        if (this.lineItems.some((line) => line.showProductResults)) {
            return;
        }

        if (!this.productSearchViewportListenersAttached) {
            return;
        }

        window.removeEventListener('scroll', this._boundRepositionProductSearch, true);
        window.removeEventListener('resize', this._boundRepositionProductSearch);
        this.productSearchViewportListenersAttached = false;
    }

    async handleProductOptionSelect(event) {
        event.preventDefault();
        const lineKey = event.currentTarget.dataset.key;
        const product2Id = event.currentTarget.dataset.value || '';
        const line = this.lineItems.find((item) => item.key === lineKey);
        const selectedOption = (line?.productOptions || []).find(
            (option) => option.value === product2Id
        );

        if (
            line?.lineType === LINE_TYPE_INSTRUMENTS &&
            this.instrumentLineHasSerialNumber(line) &&
            this.isDefaultProductSelected(product2Id)
        ) {
            this.showToast(
                'Validation',
                'Default Product cannot be selected when a Serial Number is provided.',
                'error'
            );
            return;
        }

        this.lineItems = this.lineItems.map((item) => {
            if (item.key !== lineKey) {
                return item;
            }

            return {
                ...item,
                product2Id,
                productSearchText: selectedOption?.label || '',
                itemDescription: product2Id ? selectedOption?.description || '' : '',
                model: product2Id
                    ? this.normalizeUppercaseText(selectedOption?.model || '')
                    : '',
                showProductResults: false,
                productSearchDropdownStyle: ''
            };
        });

        if (line?.lineType === LINE_TYPE_SERIALIZED && product2Id) {
            try {
                const product = await getProductDetails({
                    productId: product2Id,
                    requireServiceAssetType: true
                });
                this.lineItems = this.lineItems.map((item) =>
                    item.key === lineKey
                        ? {
                              ...item,
                              productLine: product?.ProductLine__c || item.productLine
                          }
                        : item
                );
            } catch (error) {
                this.showError('Failed to load product details', error);
            }
        }

        this.removeProductSearchViewportListenersIfIdle();
    }

    buildLineSectionLabel(line) {
        const lineNumber = line.lineNumber;
        if (line.lineType === LINE_TYPE_INSTRUMENTS) {
            return `Item ${lineNumber}: ${LINE_TYPE_INSTRUMENTS_LABEL}`;
        }
        if (this.isOtherSerializedLineType(line.lineType)) {
            return `Item ${lineNumber}: ${LINE_TYPE_OTHER_SERIALIZED_LABEL}`;
        }
        if (this.isOtherNonSerializedLineType(line.lineType)) {
            return `Item ${lineNumber}: ${LINE_TYPE_OTHER_NON_SERIALIZED_LABEL}`;
        }
        if (this.isOtherLineType(line.lineType)) {
            return `Item ${lineNumber}: Other`;
        }
        if (line.serialNumber) {
            return `Item ${lineNumber}: ${this.normalizeUppercaseText(line.serialNumber)}`;
        }
        return `Item ${lineNumber}: ${LINE_TYPE_SERIALIZED_LABEL}`;
    }

    filterAccountAssets(searchTerm) {
        const assets = this.accountAssets || [];
        const term = String(searchTerm || '').trim().toLowerCase();
        const filtered = !term
            ? assets
            : assets.filter((asset) => {
                  const assetName = String(asset.name || '').toLowerCase();
                  const productName = String(asset.productName || '').toLowerCase();
                  const model = String(asset.model || '').toLowerCase();
                  const serial = String(asset.serialNumber || '').toLowerCase();
                  return (
                      assetName.includes(term) ||
                      productName.includes(term) ||
                      model.includes(term) ||
                      serial.includes(term)
                  );
              });
        return filtered.slice(0, 20).map((asset) => ({
            label: this.buildAssetDisplayLabel(asset),
            value: asset.serialNumber || asset.id
        }));
    }

    handleAssetSearchFocus(event) {
        const lineKey = event.target.dataset.key;
        const line = this.lineItems.find((item) => item.key === lineKey);
        if (!line || !this.accountId || !(this.accountAssets || []).length) {
            return;
        }

        this.lineItems = this.lineItems.map((item) =>
            item.key === lineKey ? { ...item, showAssetResults: true } : item
        );
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.updateAssetSearchDropdownPosition(lineKey);
            this.ensureProductSearchViewportListeners();
        }, 0);
    }

    handleAssetSearchInput(event) {
        const lineKey = event.target.dataset.key;
        const searchTerm = event.target.value || '';

        this.lineItems = this.lineItems.map((item) =>
            item.key === lineKey
                ? {
                      ...item,
                      assetSearchText: searchTerm,
                      showAssetResults: true
                  }
                : item
        );

        if (assetSearchTimers[lineKey]) {
            clearTimeout(assetSearchTimers[lineKey]);
        }
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        assetSearchTimers[lineKey] = window.setTimeout(() => {
            this.updateAssetSearchDropdownPosition(lineKey);
            this.ensureProductSearchViewportListeners();
        }, 0);
    }

    handleAssetSearchBlur(event) {
        const lineKey = event.target.dataset.key;
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.lineItems = this.lineItems.map((item) =>
                item.key === lineKey
                    ? { ...item, showAssetResults: false, assetSearchDropdownStyle: '' }
                    : item
            );
            this.removeProductSearchViewportListenersIfIdle();
        }, 200);
    }

    updateAssetSearchDropdownPosition(lineKey) {
        const control = this.template.querySelector(
            `[data-asset-search-control="${lineKey}"]`
        );
        if (!control) {
            return;
        }

        const rect = control.getBoundingClientRect();
        const top = Math.round(rect.bottom + 2);
        const left = Math.round(rect.left);
        const width = Math.max(Math.round(rect.width), 280);
        const dropdownStyle = `top: ${top}px; left: ${left}px; width: ${width}px;`;

        this.lineItems = this.lineItems.map((item) =>
            item.key === lineKey ? { ...item, assetSearchDropdownStyle: dropdownStyle } : item
        );
    }

    handleAssetOptionSelect(event) {
        event.preventDefault();
        const lineKey = event.currentTarget.dataset.key;
        const assetValue = event.currentTarget.dataset.value || '';

        this.lineItems = this.lineItems.map((line) => {
            if (line.key !== lineKey) {
                return line;
            }

            const updated = {
                ...line,
                assetSerialPick: assetValue,
                serialNumber: this.normalizeUppercaseText(assetValue),
                showAssetResults: false,
                assetSearchDropdownStyle: ''
            };
            this.applyAssetToLine(updated, this.findAssetBySerial(assetValue));
            updated.assetSearchText = this.buildAssetSerialLabel(
                this.findAssetBySerial(assetValue)
            );
            return updated;
        });

        const updatedLine = this.lineItems.find((line) => line.key === lineKey);
        if (updatedLine?.assetId) {
            this.promptDuplicateReturnOrderWarning(updatedLine.assetId);
        }
        if (updatedLine?.departmentId) {
            this.ensureDepartmentOptionAvailable(updatedLine.departmentId);
        }
    }

    get contactRecordFilter() {
        if (!this.accountId || !this.eligibleContactIds.length) {
            return null;
        }

        return {
            criteria: [
                {
                    fieldPath: 'Id',
                    operator: 'in',
                    value: this.eligibleContactIds
                }
            ]
        };
    }

    get isContactSearchDisabled() {
        return !this.accountId || !this.eligibleContactIds.length;
    }

    get isNewContactEmailRequired() {
        return (
            this.newContactTargetType === 'orderHeaderEstimateContact' ||
            this.newContactTargetType === 'lineEstimateContact' ||
            this.newContactTargetType === 'orderHeaderModRequestContact'
        );
    }

    get newContactModalDescription() {
        if (
            this.newContactTargetType === 'orderHeaderEstimateContact' ||
            this.newContactTargetType === 'lineEstimateContact'
        ) {
            return 'Estimate Contact will be linked to ' + this.accountName + '. Email is required.';
        }
        if (this.newContactTargetType === 'orderHeaderModRequestContact') {
            return (
                'Mod Request Contact will be linked to ' +
                this.accountName +
                '. Email is required.'
            );
        }
        return 'Contact will be linked to ' + this.accountName + ' and available on all lines.';
    }

    cacheContactDetails(contactId, contactName, contactEmail) {
        if (!contactId) {
            return;
        }

        this.contactEmailById = {
            ...this.contactEmailById,
            [contactId]: contactEmail || ''
        };
        if (contactName) {
            this.contactNameById = {
                ...this.contactNameById,
                [contactId]: contactName
            };
        }
    }

    isEstimateContactEmailMissing(estimateContactId) {
        if (!estimateContactId) {
            return false;
        }

        return !String(this.contactEmailById[estimateContactId] || '').trim();
    }

    promptEstimateContactEmailIfNeeded(groupKey) {
        const group = (this.proposedReturnOrderGroups || []).find(
            (entry) => entry.groupKey === groupKey
        );
        if (
            !group ||
            group.estimateRequired !== ESTIMATE_REQUIRED_QUOTE_VALUE ||
            !group.estimateContactId
        ) {
            return;
        }

        if (this.isEstimateContactEmailMissing(group.estimateContactId)) {
            this.openUpdateContactEmailModal(group.estimateContactId, { groupKey });
        }
    }

    promptLineEstimateContactEmailIfNeeded(lineKey) {
        const line = this.lineItems.find((entry) => entry.key === lineKey);
        if (
            !line ||
            line.lineType === LINE_TYPE_INSTRUMENTS ||
            line.estimateRequired !== ESTIMATE_REQUIRED_QUOTE_VALUE ||
            !line.estimateContactId
        ) {
            return;
        }

        if (this.isEstimateContactEmailMissing(line.estimateContactId)) {
            this.openUpdateContactEmailModal(line.estimateContactId, { lineKey });
        }
    }

    openUpdateContactEmailModal(contactId, { groupKey = '', lineKey = '' } = {}) {
        this.updateEmailContactId = contactId;
        this.updateEmailGroupKey = groupKey;
        this.updateEmailLineKey = lineKey;
        this.updateEmailContactName = this.contactNameById[contactId] || 'Contact';
        this.updateEmailValue = this.contactEmailById[contactId] || '';
        this.showUpdateContactEmailModal = true;
    }

    handleCloseUpdateContactEmailModal() {
        this.showUpdateContactEmailModal = false;
        this.updateEmailContactId = '';
        this.updateEmailGroupKey = '';
        this.updateEmailLineKey = '';
        this.updateEmailContactName = '';
        this.updateEmailValue = '';
    }

    handleUpdateContactEmailFieldChange(event) {
        this.updateEmailValue = event.detail.value;
    }

    async handleSaveContactEmailUpdate() {
        const emailInput = this.template.querySelector(
            'lightning-input[data-form="update-contact-email"]'
        );
        if (emailInput && !emailInput.reportValidity()) {
            return;
        }

        this.isUpdatingContactEmail = true;
        try {
            await updateContactEmail({
                contactId: this.updateEmailContactId,
                email: this.updateEmailValue
            });

            this.cacheContactDetails(
                this.updateEmailContactId,
                this.updateEmailContactName,
                this.updateEmailValue
            );
            this.handleCloseUpdateContactEmailModal();
            this.showToast('Success', 'Contact email was updated.', 'success');
        } catch (error) {
            this.showError('Failed to update contact email', error);
        } finally {
            this.isUpdatingContactEmail = false;
        }
    }

    resolveProductLineForItemType(itemType) {
        if (!itemType) {
            return '';
        }
        return this.itemTypeToProductLine?.[itemType] || '';
    }

    resolveRoliLineType(lineType) {
        if (lineType === LINE_TYPE_SERIALIZED) {
            return ROLI_LINE_TYPE_SERIALIZED;
        }
        if (this.isOtherSerializedLineType(lineType)) {
            return ROLI_LINE_TYPE_OTHER_SERIALIZED;
        }
        if (this.isOtherNonSerializedLineType(lineType) || this.isOtherLineType(lineType)) {
            return ROLI_LINE_TYPE_OTHER_NON_SERIALIZED;
        }
        return ROLI_LINE_TYPE_INSTRUMENT;
    }

    resolveDeviceTypeFilterForLine(line) {
        if (!line || !this.isOtherLineType(line.lineType)) {
            return '';
        }
        const itemType = String(line.itemType || '').trim();
        return itemType.toLowerCase() === STIRRUP_ITEM_TYPE.toLowerCase() ? itemType : '';
    }

    expandLineSection(sectionKey, options = {}) {
        const { collapseOthers = false } = options;
        const nextSections = collapseOthers
            ? [sectionKey]
            : [...new Set([...this.activeSections, sectionKey])];
        this.activeSections = [];
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        window.setTimeout(() => {
            this.activeSections = nextSections;
        }, 0);
    }

    get disableNext() {
        return !this.accountId || !this.operatingUnit || !this.salesRepId;
    }

    get disableContinueToSummary() {
        return this.isSaving;
    }

    get disableApprove() {
        return this.isSaving;
    }

    get isRecordActionLaunch() {
        if (this.embeddedMode || this.isHomePageLaunch || this.isUrlAddressableLaunch) {
            return false;
        }
        return Boolean(this._recordId);
    }

    get isUrlAddressableLaunch() {
        return this._pageReference?.type === 'standard__component';
    }

    get isHomePageLaunch() {
        const pageRef = this._pageReference;
        return (
            pageRef?.type === 'standard__namedPage' &&
            pageRef?.attributes?.pageName === 'home'
        );
    }

    get showAssetLaunchHeaderPrompt() {
        return this._assetLaunchAwaitingHeader && this.showStandardHeader;
    }

    /** Merged tab header already has its own title; hide the shared form section heading. */
    get showMergedAccountSectionTitle() {
        return false;
    }

    renderedCallback() {
        if (!this._focusHeaderSerialPending || !this.showMergedTabHeader) {
            return;
        }
        this._focusHeaderSerialPending = false;
        this.focusHeaderSerialInput();
    }

    /**
     * Focuses the tab-launch Serial Number field, with short retries so console tab
     * APIs and other Lightning controls do not permanently steal focus on load.
     */
    focusHeaderSerialInput() {
        const tryFocus = () => {
            if (!this.showMergedTabHeader) {
                return;
            }
            const serialInput = this.template.querySelector(HEADER_SERIAL_FOCUS_SELECTOR);
            if (serialInput) {
                serialInput.focus();
            }
        };

        tryFocus();
        window.setTimeout(tryFocus, 0);
        window.setTimeout(tryFocus, 100);
    }

    /**
     * Syncs Account Information from the shared form into parent wizard state.
     * Account changes refresh contacts/assets; OU changes may advance asset-launch.
     */
    async handleAccountInformationChange(event) {
        const values = event.detail || {};
        const source = values.source;

        // apply is an echo from syncAccountInformationToChild; ignore.
        if (source === 'apply') {
            return;
        }
        // Child finished loading picklists — push any parent header defaults into the form.
        if (source === 'init') {
            this.syncAccountInformationToChild();
            return;
        }

        const previousAccountId = this.accountId || '';
        this.accountId = values.accountId || '';
        this.accountName = values.accountName || '';
        this.legacyCustomerId = values.legacyCustomerId || '';
        this.operatingUnit = values.operatingUnit || '';
        this.salesRepId = values.salesRepId || this.salesRepId;

        if (source === 'reset') {
            return;
        }

        const accountChanged =
            source === 'account' || previousAccountId !== (this.accountId || '');
        if (accountChanged) {
            if (!this.lockCase) {
                this.caseId = '';
            }
            this.lineItems = this.lineItems.map((line) => ({
                ...line,
                contactId: '',
                departmentId: '',
                shipToAccountId: ''
            }));
            await this.refreshAccountDependencies({
                skipAccountDefaults: true,
                skipChildSync: true
            });
            return;
        }

        if (
            source === 'field' &&
            values.changedField === 'operatingUnit' &&
            this._assetLaunchAwaitingHeader
        ) {
            Promise.resolve().then(() => this.tryAdvanceAssetLaunchAfterHeader());
        }
    }

    async tryAdvanceAssetLaunchAfterHeader() {
        if (!this._assetLaunchAwaitingHeader || !this.isHeaderPage) {
            return;
        }
        if (!this.validateHeader()) {
            return;
        }

        this._assetLaunchAwaitingHeader = false;
        await this.goToLinesPage();
    }

    handleLineFieldChange(event) {
        const { key, field } = event.target.dataset;
        let value =
            event.target.type === 'checkbox' ? event.target.checked : event.detail.value;

        if (field === 'serialNumber' || field === 'model') {
            value = this.normalizeUppercaseText(value);
        }

        if (field === 'quantityReturned') {
            value = this.normalizeQuantity(value);
        }

        this.lineItems = this.lineItems.map((line) => {
            if (line.key !== key) {
                return line;
            }

            if (
                field === 'quantityReturned' &&
                (line.lineType === LINE_TYPE_SERIALIZED ||
                    this.isOtherSerializedLineType(line.lineType) ||
                    this.isFlexibleScopeProductLine(line.productLine))
            ) {
                return { ...line, quantityReturned: QUANTITY_RETURNED_DEFAULT };
            }

            const updated = { ...line, [field]: value };

            if (field === 'itemType' && this.isOtherLineType(line.lineType)) {
                updated.productLine = this.resolveProductLineForItemType(value);
                updated.product2Id = '';
                updated.model = '';
                updated.itemDescription = '';
                updated.productSearchText = '';
                updated.showProductResults = false;
                updated.productOptions = [];
            }

            if (field === 'serialNumber') {
                updated.assetSerialPick = value
                    ? this.getAssetSerialPickValue(value)
                    : '';
                this.applyAssetToLine(updated, this.findAssetBySerial(value));
                if (line.lineType === LINE_TYPE_INSTRUMENTS) {
                    if (String(value || '').trim()) {
                        clearNoSerialAdditionalServiceFields(updated);
                        if (this.isDefaultProductSelected(updated.product2Id)) {
                            this.clearDefaultProductFromLine(updated);
                        }
                    } else {
                        clearSerialAdditionalServiceFields(updated);
                    }
                }
            }

            if (field === 'additionalServices' && line.lineType === LINE_TYPE_INSTRUMENTS) {
                if (!value) {
                    clearInstrumentAdditionalServiceFields(updated);
                }
            }

            if (field === 'modRequest' && line.lineType === LINE_TYPE_INSTRUMENTS) {
                if (value) {
                    updated.insulationPowderCoating = updated.insulationPowderCoating || '';
                    clearNonModAdditionalServiceFields(updated);
                } else {
                    updated.insulationPowderCoating = '';
                    updated.modFormAttachments = [];
                }
            }

            if (field === 'estimateRequired' && line.lineType !== LINE_TYPE_INSTRUMENTS) {
                if (value === ESTIMATE_REQUIRED_QUOTE_VALUE) {
                    updated.estimateContactId =
                        updated.estimateContactId || updated.contactId || '';
                } else {
                    updated.estimateContactId = '';
                }
            }

            return updated;
        });

        if (field === 'itemType') {
            this.loadProductOptionsForLine(key);
        }

        if (field === 'estimateRequired' && value === ESTIMATE_REQUIRED_QUOTE_VALUE) {
            this.promptLineEstimateContactEmailIfNeeded(key);
        }

        if (field === 'serialNumber') {
            const updatedLine = this.lineItems.find((line) => line.key === key);
            if (updatedLine?.assetId) {
                this.promptDuplicateReturnOrderWarning(updatedLine.assetId);
            }
            if (updatedLine?.departmentId) {
                this.ensureDepartmentOptionAvailable(updatedLine.departmentId);
            }
            if (
                updatedLine?.lineType === LINE_TYPE_INSTRUMENTS &&
                !this.instrumentLineHasSerialNumber(updatedLine) &&
                !updatedLine.product2Id
            ) {
                void this.applyInstrumentLineDefaults(key);
            }
        }
    }

    getAssetSerialPickValue(serialNumber) {
        const asset = this.findAssetBySerial(serialNumber);
        if (!asset) {
            return '';
        }
        return asset.serialNumber || asset.id;
    }

    normalizeUppercaseText(value) {
        return typeof value === 'string' ? value.trim().toUpperCase() : value;
    }

    normalizeQuantity(value) {
        const parsed = Number.parseInt(value, 10);
        if (Number.isNaN(parsed) || parsed < 1) {
            return QUANTITY_RETURNED_DEFAULT;
        }
        return parsed;
    }

    handleLineContactChange(event) {
        const key = event.target.dataset.key;
        const contactId = event.detail.recordId || '';

        this.lineItems = this.lineItems.map((line) => {
            if (line.key !== key) {
                return line;
            }

            const defaultEstimateContact =
                line.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                !line.estimateContactId
                    ? contactId
                    : line.estimateContactId;

            return {
                ...line,
                contactId,
                estimateContactId: defaultEstimateContact
            };
        });

        this.promptLineEstimateContactEmailIfNeeded(key);
    }

    handleLineEstimateContactChange(event) {
        const key = event.target.dataset.key;
        const estimateContactId = event.detail.recordId || '';

        this.lineItems = this.lineItems.map((line) =>
            line.key === key ? { ...line, estimateContactId } : line
        );

        this.promptLineEstimateContactEmailIfNeeded(key);
    }

    async handleLineProductChange(event) {
        const key = event.target.dataset.key;
        const product2Id = event.detail.recordId || '';

        let productLineUpdate = '';
        let productModelUpdate = '';
        const line = this.lineItems.find((item) => item.key === key);
        const requireServiceAssetType = !this.isOtherLineType(line?.lineType);

        if (product2Id) {
            try {
                const product = await getProductDetails({
                    productId: product2Id,
                    requireServiceAssetType
                });
                productLineUpdate = product?.ProductLine__c || '';
                productModelUpdate = product?.Model__c || '';
            } catch (error) {
                this.showError('Failed to load product details', error);
            }
        }

        this.lineItems = this.lineItems.map((line) => {
            if (line.key !== key) {
                return line;
            }

            const updated = { ...line, product2Id };
            if (line.lineType === LINE_TYPE_SERIALIZED && productLineUpdate) {
                updated.productLine = productLineUpdate;
            }
            if (this.isExtendedLineType(line.lineType)) {
                updated.model = product2Id
                    ? this.normalizeUppercaseText(productModelUpdate)
                    : '';
            }
            return updated;
        });
    }

    handleOpenNewContact(event) {
        this.openNewContactModal(event.currentTarget.dataset.key, 'line');
    }

    handleOpenNewContactForLineEstimateContact(event) {
        this.openNewContactModal(event.currentTarget.dataset.key, 'lineEstimateContact');
    }

    handleOpenNewContactForOrderHeader(event) {
        this.openNewContactModal(event.currentTarget.dataset.groupKey, 'orderHeader');
    }

    handleOpenNewContactForEstimateContact(event) {
        this.openNewContactModal(event.currentTarget.dataset.groupKey, 'orderHeaderEstimateContact');
    }

    handleOpenNewContactForModRequestContact(event) {
        this.openNewContactModal(
            event.currentTarget.dataset.groupKey,
            'orderHeaderModRequestContact'
        );
    }

    openNewContactModal(targetKey, targetType = 'line') {
        if (!this.accountId) {
            this.showToast('Validation', 'Select an account before creating a contact.', 'error');
            return;
        }

        this.newContactTargetType = targetType;
        if (
            targetType === 'orderHeader' ||
            targetType === 'orderHeaderEstimateContact' ||
            targetType === 'orderHeaderModRequestContact'
        ) {
            this.newContactGroupKey = targetKey;
            this.newContactLineKey = '';
        } else {
            this.newContactLineKey = targetKey;
            this.newContactGroupKey = '';
        }
        this.newContactFirstName = '';
        this.newContactLastName = '';
        this.newContactEmail = '';
        this.newContactPhone = '';
        this.newContactTitle = '';
        this.showNewContactModal = true;
    }

    handleCloseNewContactModal() {
        this.showNewContactModal = false;
        this.newContactTargetType = 'line';
        this.newContactLineKey = '';
        this.newContactGroupKey = '';
    }

    handleNewContactFieldChange(event) {
        const field = event.target.dataset.field;
        this[field] = event.detail.value;
    }

    validateNewContactForm() {
        const inputs = this.template.querySelectorAll(
            'lightning-input[data-form="new-contact"][required]'
        );
        let isValid = true;

        inputs.forEach((input) => {
            if (!input.reportValidity()) {
                isValid = false;
            }
        });

        return isValid;
    }

    async handleSaveNewContact() {
        if (!this.validateNewContactForm()) {
            return;
        }

        this.isCreatingContact = true;
        try {
            const result = await createAccountContact({
                accountId: this.accountId,
                firstName: this.newContactFirstName,
                lastName: this.newContactLastName,
                email: this.newContactEmail,
                phone: this.newContactPhone,
                title: this.newContactTitle,
                requireEmail: this.isNewContactEmailRequired
            });

            this.cacheContactDetails(
                result.contactId,
                result.contactName,
                result.contactEmail || this.newContactEmail
            );
            if (!this.eligibleContactIds.includes(result.contactId)) {
                this.eligibleContactIds = [...this.eligibleContactIds, result.contactId];
            }

            const lineKey = this.newContactLineKey;
            const groupKey = this.newContactGroupKey;
            if (this.newContactTargetType === 'orderHeader') {
                this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) => {
                    if (group.groupKey !== groupKey) {
                        return group;
                    }

                    const defaultEstimateContact =
                        group.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                        !group.estimateContactId
                            ? result.contactId
                            : group.estimateContactId;

                    const defaultModRequestContact =
                        group.hasModRequest && !group.modRequestContactId
                            ? result.contactId
                            : group.modRequestContactId;

                    return {
                        ...group,
                        contactId: result.contactId,
                        estimateContactId: defaultEstimateContact,
                        modRequestContactId: defaultModRequestContact
                    };
                });
                this.handleCloseNewContactModal();
                this.showToast(
                    'Success',
                    `Contact ${result.contactName} was created and selected for this return order.`,
                    'success'
                );
                this.promptEstimateContactEmailIfNeeded(groupKey);
                return;
            }

            if (this.newContactTargetType === 'orderHeaderEstimateContact') {
                this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) =>
                    group.groupKey === groupKey
                        ? { ...group, estimateContactId: result.contactId }
                        : group
                );
                this.handleCloseNewContactModal();
                this.showToast(
                    'Success',
                    `Estimate Contact ${result.contactName} was created and selected.`,
                    'success'
                );
                this.promptEstimateContactEmailIfNeeded(groupKey);
                return;
            }

            if (this.newContactTargetType === 'orderHeaderModRequestContact') {
                this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) =>
                    group.groupKey === groupKey
                        ? { ...group, modRequestContactId: result.contactId }
                        : group
                );
                this.handleCloseNewContactModal();
                this.showToast(
                    'Success',
                    `Mod Request Contact ${result.contactName} was created and selected.`,
                    'success'
                );
                return;
            }

            if (this.newContactTargetType === 'lineEstimateContact') {
                this.lineItems = this.lineItems.map((line) =>
                    line.key === lineKey ? { ...line, estimateContactId: result.contactId } : line
                );
                this.handleCloseNewContactModal();
                this.showToast(
                    'Success',
                    `Estimate Contact ${result.contactName} was created and selected.`,
                    'success'
                );
                this.promptLineEstimateContactEmailIfNeeded(lineKey);
                return;
            }

            this.lineItems = this.lineItems.map((line) => {
                if (line.key !== lineKey) {
                    return line;
                }

                const defaultEstimateContact =
                    line.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                    !line.estimateContactId
                        ? result.contactId
                        : line.estimateContactId;

                return {
                    ...line,
                    contactId: result.contactId,
                    estimateContactId: defaultEstimateContact
                };
            });

            this.handleCloseNewContactModal();
            this.showToast(
                'Success',
                `Contact ${result.contactName} was created and selected for this item.`,
                'success'
            );
            this.promptLineEstimateContactEmailIfNeeded(lineKey);
        } catch (error) {
            this.showError('Failed to create contact', error);
        } finally {
            this.isCreatingContact = false;
        }
    }

    findAssetBySerial(serialValue) {
        if (!serialValue) {
            return null;
        }

        // Entered serials are upper-cased, so match assets whose serial is stored mixed case.
        const normalizedSerial = this.normalizeUppercaseText(serialValue);
        return (this.accountAssets || []).find(
            (asset) =>
                this.normalizeUppercaseText(asset.serialNumber || asset.id) === normalizedSerial
        );
    }

    applyAssetToLine(line, asset) {
        const isInstruments = line.lineType === LINE_TYPE_INSTRUMENTS;

        if (!asset) {
            line.assetId = '';
            line.assetSearchText = '';
            if (!isInstruments) {
                line.product2Id = '';
                line.productSearchText = '';
            }
            return line;
        }

        line.assetId = asset.id;
        line.product2Id = asset.product2Id;
        line.model = this.normalizeUppercaseText(asset.model || '');
        line.productLine = asset.productLine || '';
        line.productSearchText = asset.productName || '';
        if (asset.departmentId) {
            line.departmentId = asset.departmentId;
        }
        line.assetSerialPick = asset.serialNumber || asset.id;
        line.assetSearchText = this.buildAssetSerialLabel(asset);
        return line;
    }

    clearDefaultProductFromLine(line) {
        if (line.product2Id !== this.defaultProductId) {
            return line;
        }

        line.product2Id = '';
        line.productSearchText = '';
        line.model = '';
        line.itemDescription = '';
        return line;
    }

    instrumentLineHasSerialNumber(line) {
        return Boolean(String(line?.serialNumber || '').trim());
    }

    isDefaultProductSelected(product2Id) {
        return Boolean(this.defaultProductId && product2Id === this.defaultProductId);
    }

    handleAddLine() {
        this.addLineFromSummary = false;
        this.showLineTypeModal = true;
    }

    handleAddLineFromSummary() {
        this.addLineFromSummary = true;
        this.showLineTypeModal = true;
    }

    handleCloseLineTypeModal() {
        this.showLineTypeModal = false;
        this.addLineFromSummary = false;
    }

    async handleSelectLineType(event) {
        const lineType = event.currentTarget.dataset.lineType;
        if (!lineType) {
            return;
        }

        const newLine = this.buildEmptyLine(lineType);
        if (this.defaultLineContactId) {
            newLine.contactId = this.defaultLineContactId;
        }
        this.lineItems = [newLine, ...this.lineItems];
        this.showLineTypeModal = false;

        if (lineType === LINE_TYPE_INSTRUMENTS) {
            await this.applyInstrumentLineDefaults(newLine.key);
        }

        if (this.usesProductSearchLookup(lineType)) {
            await this.loadProductOptionsForLine(newLine.key, '', false);
        }

        if (this.addLineFromSummary) {
            this.addLineFromSummary = false;
            this.currentPage = PAGE_LINES;
        }

        this.expandLineSection(newLine.key, { collapseOthers: true });
    }

    handleRemoveLine(event) {
        const key = event.target.dataset.key;
        this.lineItems = this.lineItems.filter((line) => line.key !== key);
        this.activeSections = this.activeSections.filter((section) => section !== key);
    }

    handleSectionToggle(event) {
        this.activeSections = event.detail.openSections;
    }

    handleLineFileUploadFinished(event) {
        const lineKey = event.target.dataset.key;
        const uploadedFiles = event.detail.files || [];
        if (!lineKey || uploadedFiles.length === 0) {
            return;
        }

        const newAttachments = uploadedFiles.map((file) => ({
            contentDocumentId: file.documentId,
            name: file.name
        }));

        this.lineItems = this.lineItems.map((line) =>
            line.key === lineKey
                ? {
                      ...line,
                      attachments: [...(line.attachments || []), ...newAttachments]
                  }
                : line
        );
    }

    handleRemoveLineAttachment(event) {
        const lineKey = event.target.dataset.key;
        const contentDocumentId = event.target.dataset.documentId;
        if (!lineKey || !contentDocumentId) {
            return;
        }

        this.lineItems = this.lineItems.map((line) =>
            line.key === lineKey
                ? {
                      ...line,
                      attachments: (line.attachments || []).filter(
                          (attachment) => attachment.contentDocumentId !== contentDocumentId
                      )
                  }
                : line
        );
    }

    handleLineModFormUploadFinished(event) {
        const lineKey = event.target.dataset.key;
        const uploadedFiles = event.detail.files || [];
        if (!lineKey || uploadedFiles.length === 0) {
            return;
        }

        const newAttachments = uploadedFiles.map((file) => ({
            contentDocumentId: file.documentId,
            name: file.name
        }));

        this.lineItems = this.lineItems.map((line) =>
            line.key === lineKey
                ? {
                      ...line,
                      modFormAttachments: [...(line.modFormAttachments || []), ...newAttachments]
                  }
                : line
        );
    }

    handleRemoveLineModFormAttachment(event) {
        const lineKey = event.target.dataset.key;
        const contentDocumentId = event.target.dataset.documentId;
        if (!lineKey || !contentDocumentId) {
            return;
        }

        this.lineItems = this.lineItems.map((line) =>
            line.key === lineKey
                ? {
                      ...line,
                      modFormAttachments: (line.modFormAttachments || []).filter(
                          (attachment) => attachment.contentDocumentId !== contentDocumentId
                      )
                  }
                : line
        );
    }

    openLineTypePickerIfNoItems() {
        if (!this.hasLineItems) {
            this.showLineTypeModal = true;
        }
    }

    async goToLinesPage() {
        this.currentPage = PAGE_LINES;
        this.openLineTypePickerIfNoItems();
        await this.checkDuplicateReturnOrdersForLoadedLines();
    }

    async handleNext() {
        if (!this.validateHeader()) {
            return;
        }
        this._assetLaunchAwaitingHeader = false;

        if (this.isTabLaunch) {
            const serialNumber = this.normalizeUppercaseText(this.headerSerialNumber);
            if (serialNumber && !this._pendingTabSerialAssetId && !this._pendingTabSerialAsset) {
                const found = await this.lookupHeaderSerialAsset({ autoAdvance: false });
                if (!found) {
                    return;
                }
            }
            if (this._pendingTabSerialAssetId || this._pendingTabSerialAsset) {
                await this.applyPendingTabSerialAssetToLines();
            }
        }

        await this.goToLinesPage();
    }

    handleBack() {
        this.currentPage = PAGE_HEADER;
        if (this.isTabLaunch) {
            this._focusHeaderSerialPending = true;
        }
    }

    handleHeaderSerialInput(event) {
        const nextSerial = this.normalizeUppercaseText(event.target.value || '');
        if (nextSerial !== this.headerSerialNumber) {
            this._pendingTabSerialAssetId = null;
            this._pendingTabSerialAsset = null;
        }
        this.headerSerialNumber = nextSerial;
    }

    async handleHeaderSerialCommit() {
        // Blur must not navigate — only Enter / Next advance. Skip when Enter already handled.
        if (this._skipNextHeaderSerialCommit) {
            this._skipNextHeaderSerialCommit = false;
            return;
        }
        await this.lookupHeaderSerialAsset({ autoAdvance: false });
    }

    async handleHeaderSerialKeydown(event) {
        if (event.key !== 'Enter') {
            return;
        }
        event.preventDefault();
        this._skipNextHeaderSerialCommit = true;
        await this.lookupHeaderSerialAsset({ autoAdvance: true });
    }

    async lookupHeaderSerialAsset({ autoAdvance = false } = {}) {
        const lookupGeneration = this._headerSerialLookupGeneration;
        const serialNumber = this.normalizeUppercaseText(this.headerSerialNumber);
        if (!serialNumber) {
            this._pendingTabSerialAssetId = null;
            this._pendingTabSerialAsset = null;
            return true;
        }

        this.isLookingUpHeaderSerial = true;
        try {
            const matches = await findAssetsBySerial({ serialNumber });
            if (!this.isHeaderSerialLookupCurrent(lookupGeneration)) {
                return false;
            }
            if (!matches || matches.length === 0) {
                this._pendingTabSerialAssetId = null;
                this._pendingTabSerialAsset = null;
                this.showToast(
                    'Validation',
                    'No asset record exists for the entered Serial Number.',
                    'error'
                );
                return false;
            }

            const asset = matches[0];
            const assetId = asset.id || asset.Id;
            if (!assetId) {
                this._pendingTabSerialAssetId = null;
                this._pendingTabSerialAsset = null;
                this.showToast(
                    'Warning',
                    'Scanned asset could not be loaded into return order items.',
                    'warning'
                );
                return false;
            }

            // Capture before awaits — serial input change can clear pending fields mid-lookup.
            this._pendingTabSerialAssetId = assetId;
            this._pendingTabSerialAsset = asset;
            this.accountId = asset.accountId || this.accountId || '';
            this.accountName = asset.accountName || this.accountName || '';
            this.lockAccount = false;

            if (this.accountId) {
                await this.refreshAccountDependencies();
            }
            if (!this.isHeaderSerialLookupCurrent(lookupGeneration)) {
                return false;
            }

            if (
                autoAdvance &&
                this.isHeaderSerialLookupCurrent(lookupGeneration) &&
                this.validateHeader({ quiet: true })
            ) {
                this._assetLaunchAwaitingHeader = false;
                await this.applyPendingTabSerialAssetToLines();
                if (!this.isHeaderSerialLookupCurrent(lookupGeneration)) {
                    // Cancel won the race mid-apply — drop any lines the stale lookup wrote.
                    this.lineItems = [];
                    this.activeSections = [];
                    return false;
                }
                await this.goToLinesPage();
            }
            return true;
        } catch (error) {
            if (!this.isHeaderSerialLookupCurrent(lookupGeneration)) {
                return false;
            }
            this.showError('Failed to look up serial number', error);
            return false;
        } finally {
            this.isLookingUpHeaderSerial = false;
        }
    }

    /**
     * True when this async serial lookup is still the active header-page request
     * (Cancel / reset bumps generation so stale blur lookups cannot re-apply state).
     */
    isHeaderSerialLookupCurrent(lookupGeneration) {
        return (
            lookupGeneration === this._headerSerialLookupGeneration && this.isHeaderPage
        );
    }

    /**
     * Tab-launch Cancel: clear wizard state and return to the empty header screen
     * with focus on Serial Number (GW-5867). Used from step 1 and later steps.
     */
    clearMergedTabHeaderFields() {
        this._headerSerialLookupGeneration += 1;
        this.headerSerialNumber = '';
        this._pendingTabSerialAssetId = null;
        this._pendingTabSerialAsset = null;
        this.accountId = undefined;
        this.accountName = '';
        this.legacyCustomerId = '';
        this.operatingUnit = '';
        this.lockAccount = false;
        this.lineItems = [];
        this.proposedReturnOrderGroups = [];
        this.createdReturnOrders = [];
        this.activeSections = [];
        this.addLineFromSummary = false;
        this.showLineTypeModal = false;
        this.showDuplicateWarningModal = false;
        this.duplicateReturnOrders = [];
        this.duplicateWarningAssetLabel = '';
        this.warnedAssetIds = new Set();
        this.shipToAddresses = [];
        this.eligibleContactIds = [];
        this.contactEmailById = {};
        this.contactNameById = {};
        this.accountAssets = [];
        this.departmentOptions = [];
        this.salesRepId = userId;
        this.creationSource =
            this.resolveDefaultCreationSource(this.creationSourceOptions) ||
            CREATION_SOURCE_DEFAULT;
        lineKeyCounter = 0;
        lineNumberCounter = 0;
        this.currentPage = PAGE_HEADER;
        this._focusHeaderSerialPending = true;

        const accountInfo = this.refs?.createOrderAccountInfo;
        if (accountInfo && typeof accountInfo.reset === 'function') {
            accountInfo.reset();
        }
    }

    handleBackFromSummary() {
        this.currentPage = PAGE_LINES;
    }

    handleSummaryRepairCenterChange(event) {
        const groupKey = event.target.dataset.groupKey;
        const repairCenterId = event.detail.value || '';

        this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) =>
            group.groupKey === groupKey
                ? { ...group, selectedRepairCenterId: repairCenterId, repairCenterId }
                : group
        );
    }

    buildHeaderPayload() {
        return {
            accountId: this.accountId,
            operatingUnit: this.operatingUnit,
            creationSource: this.creationSource,
            salesRepId: this.salesRepId,
            caseId: this.caseId,
            workOrderId: this.workOrderId
        };
    }

    buildLineItemsPayload() {
        return this.lineItems.map((line) => ({
            lineKey: line.key,
            lineNumber: line.lineNumber,
            sourceWorkOrderLineItemId: line.sourceWorkOrderLineItemId || '',
            lineType: line.lineType,
            roliLineType: this.resolveRoliLineType(line.lineType),
            serialized: line.lineType === LINE_TYPE_SERIALIZED,
            serialNumber: this.normalizeUppercaseText(line.serialNumber),
            assetId: line.assetId,
            product2Id: line.product2Id,
            model: this.normalizeUppercaseText(line.model),
            productLine: line.productLine,
            itemDescription: line.itemDescription,
            departmentId: line.departmentId,
            disinfected: line.disinfected,
            itemType: line.itemType,
            contactId: line.contactId,
            estimateContactId: line.estimateContactId,
            estimateRequired: line.estimateRequired,
            customerPo: line.customerPo,
            isLoanerAsset: line.isLoanerAsset,
            loanerRequested: line.loanerRequested,
            reportedProblem: line.reportedProblem,
            customerReference: line.customerReference,
            shipToAccountId: line.shipToAccountId,
            repairWarranty: line.repairWarranty,
            previousReturnOrder: line.previousReturnOrder,
            warrantyNotes: line.warrantyNotes,
            hospitalReferencedTrayName:
                line.lineType === LINE_TYPE_INSTRUMENTS
                    ? line.hospitalReferencedTrayName
                    : '',
            modRequest:
                line.lineType === LINE_TYPE_INSTRUMENTS
                    ? Boolean(line.modRequest)
                    : false,
            additionalServices:
                line.lineType === LINE_TYPE_INSTRUMENTS
                    ? Boolean(line.additionalServices)
                    : false,
            insulationPowderCoating:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                line.modRequest
                    ? line.insulationPowderCoating || ''
                    : '',
            legPositionersStirrup:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                !line.modRequest &&
                String(line.serialNumber || '').trim()
                    ? formatMultiPicklistValue(line.legPositionersStirrup)
                    : '',
            additionalServiceRepair:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                !line.modRequest &&
                !String(line.serialNumber || '').trim()
                    ? Boolean(line.additionalServiceRepair)
                    : false,
            laserMarking:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                !line.modRequest &&
                !String(line.serialNumber || '').trim()
                    ? line.laserMarking || ''
                    : '',
            colorDipping:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                !line.modRequest &&
                !String(line.serialNumber || '').trim()
                    ? formatMultiPicklistValue(line.colorDipping)
                    : '',
            numberOfRings:
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                line.additionalServices &&
                !line.modRequest &&
                !String(line.serialNumber || '').trim()
                    ? line.numberOfRings || DEFAULT_NUMBER_OF_RINGS
                    : '',
            status: line.status,
            quantityReturned: line.quantityReturned ?? QUANTITY_RETURNED_DEFAULT,
            contentDocumentIds: (line.attachments || []).map(
                (attachment) => attachment.contentDocumentId
            ),
            modFormContentDocumentIds: (line.modFormAttachments || []).map(
                (attachment) => attachment.contentDocumentId
            )
        }));
    }

    handleCancel() {
        // Tab launch: Cancel always returns to a cleared first screen (not Home).
        if (this.isTabLaunch) {
            this.clearMergedTabHeaderFields();
            return;
        }
        this.closeLaunchSurface();
    }

    closeLaunchSurface() {
        if (this.embeddedMode) {
            this.dispatchEvent(new CustomEvent('exit', { bubbles: true, composed: true }));
            return;
        }

        if (this.isRecordActionLaunch) {
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }

        if (this.isHomePageLaunch) {
            this.resetStandaloneWizard();
            return;
        }

        if (this.isUrlAddressableLaunch) {
            this[NavigationMixin.Navigate]({
                type: 'standard__namedPage',
                attributes: { pageName: 'home' }
            });
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__namedPage',
            attributes: { pageName: 'home' }
        });
    }

    resetStandaloneWizard() {
        this.currentPage = PAGE_HEADER;
        this.lineItems = [];
        this.proposedReturnOrderGroups = [];
        this.createdReturnOrders = [];
        this.activeSections = [];
        this.addLineFromSummary = false;
        this.warnedAssetIds = new Set();
        lineKeyCounter = 0;
        lineNumberCounter = 0;

        this.accountId = '';
        this.accountName = '';
        this.caseId = '';
        this.caseLabel = '';
        this.lockCase = false;
        this.lockAccount = false;
        this.workOrderId = '';
        this.workOrderLabel = '';
        this.lockWorkOrder = false;
        this.defaultLineContactId = '';
        this.legacyCustomerId = '';
        this.operatingUnit = '';
        this._recordId = undefined;
        this._objectApiName = undefined;
        this._recordIds = undefined;

        this._contextInitialized = false;
        this._initScheduled = false;
        this._deferHomeInit = true;
        this.scheduleInitialize();
    }

    shouldSkipToLinesAfterAssetLaunch() {
        return (
            this.normalizeRecordIds(this._recordIds).length > 0 &&
            Boolean(this.accountId) &&
            Boolean(this.operatingUnit)
        );
    }

    validateHeader({ quiet = false } = {}) {
        if (!this.accountId) {
            if (!quiet) {
                this.showToast('Validation', 'Account is required.', 'error');
            }
            return false;
        }
        if (!this.salesRepId) {
            if (!quiet) {
                this.showToast('Validation', 'Sales Rep is required.', 'error');
            }
            return false;
        }
        if (!this.operatingUnit) {
            if (!quiet) {
                this.showToast('Validation', 'Operating Unit is required.', 'error');
            }
            return false;
        }
        return true;
    }

    validateLines() {
        if (!this.lineItems.length) {
            this.showToast('Validation', 'Add at least one item.', 'error');
            return false;
        }

        const requiredInputs = this.template.querySelectorAll(
            'lightning-input[required], lightning-combobox[required], lightning-record-picker[required], lightning-textarea[required]'
        );
        let inputsValid = true;

        requiredInputs.forEach((input) => {
            if (!input.reportValidity()) {
                inputsValid = false;
            }
        });

        if (!inputsValid) {
            return false;
        }

        for (let index = 0; index < this.lineItems.length; index++) {
            const line = this.lineItems[index];
            const lineNumber = line.lineNumber || index + 1;
            const isSerialized = line.lineType === LINE_TYPE_SERIALIZED;

            if (!line.product2Id) {
                this.showToast('Validation', `Product is required on Item ${lineNumber}.`, 'error');
                return false;
            }

            if (
                line.lineType === LINE_TYPE_INSTRUMENTS &&
                this.instrumentLineHasSerialNumber(line) &&
                this.isDefaultProductSelected(line.product2Id)
            ) {
                this.showToast(
                    'Validation',
                    `Select a product other than Default Product on Item ${lineNumber} when Serial Number is provided.`,
                    'error'
                );
                return false;
            }

            if (!line.productLine) {
                this.showToast(
                    'Validation',
                    `Product Line is required on Item ${lineNumber}.`,
                    'error'
                );
                return false;
            }

            if (!line.departmentId) {
                this.showToast(
                    'Validation',
                    `Department is required on Item ${lineNumber}.`,
                    'error'
                );
                return false;
            }

            if (!line.contactId && line.lineType !== LINE_TYPE_INSTRUMENTS) {
                this.showToast('Validation', `Contact is required on Item ${lineNumber}.`, 'error');
                return false;
            }

            if (
                line.lineType !== LINE_TYPE_INSTRUMENTS &&
                this.shipToComboboxOptions.length > 0 &&
                !line.shipToAccountId
            ) {
                this.showToast(
                    'Validation',
                    `Ship-To is required on Item ${lineNumber}.`,
                    'error'
                );
                return false;
            }

            if (!line.estimateRequired && line.lineType !== LINE_TYPE_INSTRUMENTS) {
                this.showToast(
                    'Validation',
                    `Estimate Required is required on Item ${lineNumber}.`,
                    'error'
                );
                return false;
            }

            if (
                line.lineType !== LINE_TYPE_INSTRUMENTS &&
                line.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE
            ) {
                if (!line.estimateContactId) {
                    this.showToast(
                        'Validation',
                        `Estimate Contact is required on Item ${lineNumber}.`,
                        'error'
                    );
                    return false;
                }

                if (this.isEstimateContactEmailMissing(line.estimateContactId)) {
                    this.openUpdateContactEmailModal(line.estimateContactId, {
                        lineKey: line.key
                    });
                    return false;
                }
            }

            const quantity = this.normalizeQuantity(line.quantityReturned);
            const quantityLocked =
                isSerialized ||
                this.isOtherSerializedLineType(line.lineType) ||
                this.isFlexibleScopeProductLine(line.productLine);
            if (!quantityLocked && (!quantity || quantity < 1)) {
                this.showToast(
                    'Validation',
                    `Quantity must be at least 1 on Item ${lineNumber}.`,
                    'error'
                );
                return false;
            }

            if (isSerialized) {
                if (!line.serialNumber) {
                    this.showToast(
                        'Validation',
                        `Serial Number is required on Item ${lineNumber}.`,
                        'error'
                    );
                    return false;
                }
                if (!line.disinfected) {
                    this.showToast(
                        'Validation',
                        `Disinfected is required on Item ${lineNumber}.`,
                        'error'
                    );
                    return false;
                }
                if (!line.model) {
                    this.showToast('Validation', `Model is required on Item ${lineNumber}.`, 'error');
                    return false;
                }
                if (!line.reportedProblem) {
                    this.showToast(
                        'Validation',
                        `Reported Problem is required on Item ${lineNumber}.`,
                        'error'
                    );
                    return false;
                }
            } else {
                if (
                    line.lineType === LINE_TYPE_INSTRUMENTS ||
                    this.isOtherLineType(line.lineType)
                ) {
                    if (!line.disinfected) {
                        this.showToast(
                            'Validation',
                            `Disinfected is required on Item ${lineNumber}.`,
                            'error'
                        );
                        return false;
                    }
                }
                if (this.isOtherLineType(line.lineType)) {
                    if (!line.itemType) {
                        this.showToast(
                            'Validation',
                            `Item Type is required on Item ${lineNumber}.`,
                            'error'
                        );
                        return false;
                    }
                    if (!line.productLine) {
                        this.showToast(
                            'Validation',
                            `Product Line could not be resolved for Item Type on Item ${lineNumber}.`,
                            'error'
                        );
                        return false;
                    }
                    if (
                        this.isOtherSerializedLineType(line.lineType) &&
                        !String(line.serialNumber || '').trim()
                    ) {
                        this.showToast(
                            'Validation',
                            `Serial Number is required on Item ${lineNumber}.`,
                            'error'
                        );
                        return false;
                    }
                }
                if (!line.reportedProblem) {
                    this.showToast(
                        'Validation',
                        `Reported Problem is required on Item ${lineNumber}.`,
                        'error'
                    );
                    return false;
                }
            }

            if (line.repairWarranty === 'Yes' && line.lineType !== LINE_TYPE_INSTRUMENTS) {
                const hasPreviousReturnOrder = Boolean(
                    String(line.previousReturnOrder || '').trim()
                );
                const hasWarrantyNotes = Boolean(String(line.warrantyNotes || '').trim());

                if (!hasPreviousReturnOrder && !hasWarrantyNotes) {
                    this.showToast(
                        'Validation',
                        `Warranty Notes is required on Item ${lineNumber} when Previous Return Order is not provided.`,
                        'error'
                    );
                    return false;
                }
            }
        }

        return true;
    }

    async handleContinueToSummary() {
        if (!this.validateHeader()) {
            this.currentPage = PAGE_HEADER;
            return;
        }
        if (!this.validateLines()) {
            return;
        }

        this.isSaving = true;
        try {
            const routingValidation = await validateLineRoutingMatches({
                headerJson: JSON.stringify(this.buildHeaderPayload()),
                lineItemsJson: JSON.stringify(this.buildLineItemsPayload())
            });

            if (!routingValidation?.isValid) {
                const messages = routingValidation?.messages || [];
                this.showToast(
                    'Routing rule required',
                    messages.length > 0
                        ? messages.join(' ')
                        : 'No matching repair center was found in Routing Rules. Update the item data or routing rules before continuing.',
                    'error'
                );
                return;
            }

            const groups = await buildReturnOrderPlan({
                headerJson: JSON.stringify(this.buildHeaderPayload()),
                lineItemsJson: JSON.stringify(this.buildLineItemsPayload())
            });

            this.proposedReturnOrderGroups = (groups || []).map((group) => {
                const isInstruments = group.returnOrderType === RETURN_ORDER_TYPE_INSTRUMENTS;
                const headerFields = isInstruments
                    ? this.buildEmptyInstrumentOrderHeaderFields()
                    : {};
                const hasModRequest = isInstruments && this.groupHasModRequest(group);

                if (hasModRequest) {
                    headerFields.hasModRequest = true;
                    headerFields.estimateRequired = ESTIMATE_REQUIRED_QUOTE_VALUE;
                    headerFields.estimateContactId =
                        headerFields.estimateContactId || headerFields.contactId || '';
                    headerFields.modRequestContactId =
                        headerFields.modRequestContactId || headerFields.contactId || '';
                }

                return {
                    ...group,
                    selectedRepairCenterId: group.repairCenterId || '',
                    ...headerFields,
                    hasModRequest
                };
            });
            this.currentPage = PAGE_SUMMARY;
        } catch (error) {
            this.showError('Failed to build return order plan', error);
        } finally {
            this.isSaving = false;
        }
    }

    validateSummary() {
        const missingRepairCenter = (this.proposedReturnOrderGroups || []).find(
            (group) =>
                group.requiresRepairCenterSelection === true &&
                !group.selectedRepairCenterId
        );

        if (missingRepairCenter) {
            this.showToast(
                'Validation',
                'Select a repair center for items without a routing rule match.',
                'error'
            );
            return false;
        }

        return true;
    }

    validateOrderHeaders() {
        const instrumentGroups = this.instrumentReturnOrderGroups;
        for (let index = 0; index < instrumentGroups.length; index++) {
            const group = instrumentGroups[index];
            const orderNumber = index + 1;

            if (!group.contactId) {
                this.showToast(
                    'Validation',
                    `Contact is required on Instrument Return Order ${orderNumber}.`,
                    'error'
                );
                return false;
            }

            if (this.shipToComboboxOptions.length > 0 && !group.shipToAccountId) {
                this.showToast(
                    'Validation',
                    `Ship-To is required on Instrument Return Order ${orderNumber}.`,
                    'error'
                );
                return false;
            }

            if (!group.estimateRequired) {
                this.showToast(
                    'Validation',
                    `Estimate Required is required on Instrument Return Order ${orderNumber}.`,
                    'error'
                );
                return false;
            }

            if (group.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE) {
                if (!group.estimateContactId) {
                    this.showToast(
                        'Validation',
                        `Estimate Contact is required on Instrument Return Order ${orderNumber}.`,
                        'error'
                    );
                    return false;
                }

                if (this.isEstimateContactEmailMissing(group.estimateContactId)) {
                    this.openUpdateContactEmailModal(group.estimateContactId, {
                        groupKey: group.groupKey
                    });
                    this.showToast(
                        'Validation',
                        `Estimate Contact email is required on Instrument Return Order ${orderNumber}.`,
                        'error'
                    );
                    return false;
                }
            }

            if (group.hasModRequest) {
                if (!group.modRequestContactId) {
                    this.showToast(
                        'Validation',
                        `Mod Request Contact is required on Instrument Return Order ${orderNumber}.`,
                        'error'
                    );
                    return false;
                }

                if (this.isEstimateContactEmailMissing(group.modRequestContactId)) {
                    this.openUpdateContactEmailModal(group.modRequestContactId, {
                        groupKey: group.groupKey
                    });
                    this.showToast(
                        'Validation',
                        `Mod Request Contact email is required on Instrument Return Order ${orderNumber}.`,
                        'error'
                    );
                    return false;
                }
            }

            if (group.repairWarranty === 'Yes') {
                const hasPreviousReturnOrder = Boolean(
                    String(group.previousReturnOrder || '').trim()
                );
                const hasWarrantyNotes = Boolean(String(group.warrantyNotes || '').trim());

                if (!hasPreviousReturnOrder && !hasWarrantyNotes) {
                    this.showToast(
                        'Validation',
                        `Warranty Notes is required on Instrument Return Order ${orderNumber} when Previous Return Order is not provided.`,
                        'error'
                    );
                    return false;
                }
            }
        }

        return true;
    }

    handleSummaryContinue() {
        if (!this.validateHeader() || !this.validateSummary()) {
            return;
        }

        if (this.hasInstrumentReturnOrderGroups) {
            this.currentPage = PAGE_ORDER_HEADERS;
            return;
        }

        this.handleApproveAndCreate();
    }

    handleBackFromOrderHeaders() {
        this.currentPage = PAGE_SUMMARY;
    }

    handleOrderHeaderFieldChange(event) {
        const groupKey = event.target.dataset.groupKey;
        const field = event.target.dataset.field;
        const value = event.detail.value;

        this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) => {
            if (group.groupKey !== groupKey) {
                return group;
            }

            if (field === 'estimateRequired' && group.hasModRequest) {
                return {
                    ...group,
                    estimateRequired: ESTIMATE_REQUIRED_QUOTE_VALUE
                };
            }

            const updated = { ...group, [field]: value };
            if (field === 'estimateRequired') {
                if (value === ESTIMATE_REQUIRED_QUOTE_VALUE) {
                    updated.estimateContactId =
                        updated.estimateContactId || updated.contactId || '';
                } else {
                    updated.estimateContactId = '';
                }
            }
            return updated;
        });

        if (field === 'estimateRequired' && value === ESTIMATE_REQUIRED_QUOTE_VALUE) {
            this.promptEstimateContactEmailIfNeeded(groupKey);
        }
    }

    handleOrderHeaderContactChange(event) {
        const groupKey = event.target.dataset.groupKey;
        const contactId = event.detail.recordId || '';

        this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) => {
            if (group.groupKey !== groupKey) {
                return group;
            }

            const defaultEstimateContact =
                group.estimateRequired === ESTIMATE_REQUIRED_QUOTE_VALUE &&
                !group.estimateContactId
                    ? contactId
                    : group.estimateContactId;

            const defaultModRequestContact =
                group.hasModRequest && !group.modRequestContactId
                    ? contactId
                    : group.modRequestContactId;

            return {
                ...group,
                contactId,
                estimateContactId: defaultEstimateContact,
                modRequestContactId: defaultModRequestContact
            };
        });

        this.promptEstimateContactEmailIfNeeded(groupKey);
    }

    handleOrderHeaderEstimateContactChange(event) {
        const groupKey = event.target.dataset.groupKey;
        const estimateContactId = event.detail.recordId || '';

        this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) =>
            group.groupKey === groupKey ? { ...group, estimateContactId } : group
        );

        this.promptEstimateContactEmailIfNeeded(groupKey);
    }

    handleOrderHeaderModRequestContactChange(event) {
        const groupKey = event.target.dataset.groupKey;
        const modRequestContactId = event.detail.recordId || '';

        this.proposedReturnOrderGroups = this.proposedReturnOrderGroups.map((group) =>
            group.groupKey === groupKey ? { ...group, modRequestContactId } : group
        );

        if (
            modRequestContactId &&
            this.isEstimateContactEmailMissing(modRequestContactId)
        ) {
            this.openUpdateContactEmailModal(modRequestContactId, { groupKey });
        }
    }

    async handleApproveAndCreate() {
        if (!this.validateHeader() || !this.validateSummary()) {
            return;
        }
        if (this.hasInstrumentReturnOrderGroups && !this.validateOrderHeaders()) {
            return;
        }

        this.isSaving = true;
        try {
            const groupsPayload = (this.proposedReturnOrderGroups || []).map((group) => ({
                groupKey: group.groupKey,
                repairCenterId: group.requiresRepairCenterSelection
                    ? group.selectedRepairCenterId
                    : group.repairCenterId,
                requiresRepairCenterSelection: group.requiresRepairCenterSelection,
                lineItemsJson: group.lineItemsJson,
                orderHeader:
                    group.returnOrderType === RETURN_ORDER_TYPE_INSTRUMENTS
                        ? {
                              contactId: group.contactId,
                              estimateContactId: group.estimateContactId,
                              estimateRequired: group.estimateRequired,
                              modRequestContactId: group.modRequestContactId,
                              hasModRequest: Boolean(group.hasModRequest),
                              repairWarranty: group.repairWarranty,
                              warrantyNotes: group.warrantyNotes,
                              previousReturnOrder: group.previousReturnOrder,
                              customerPo: group.customerPo,
                              customerReference: group.customerReference,
                              hospitalReferencedTrayName: group.hospitalReferencedTrayName,
                              shipToAccountId: group.shipToAccountId
                          }
                        : null
            }));

            const result = await createReturnOrders({
                headerJson: JSON.stringify(this.buildHeaderPayload()),
                groupsJson: JSON.stringify(groupsPayload)
            });

            const createdOrders = result?.returnOrders || [];
            if (createdOrders.length === 0) {
                throw new Error('No return orders were created.');
            }

            this.createdReturnOrders = createdOrders;
            this.currentPage = PAGE_CREATED;
            await this.generatePaperworkForCreatedOrders(createdOrders);
        } catch (error) {
            this.showError('Failed to create return orders', error);
        } finally {
            this.isSaving = false;
        }
    }

    async generatePaperworkForCreatedOrders(createdOrders) {
        this.isGeneratingPaperwork = true;
        const messages = [];

        try {
            await this.ensurePdfLibLoaded();

            for (const order of createdOrders || []) {
                const returnOrderId = order.returnOrderId;
                const returnOrderNumber = order.returnOrderNumber || returnOrderId;
                if (!returnOrderId) {
                    continue;
                }

                let paperwork;
                try {
                    paperwork = await generatePaperworkForReturnOrder({ returnOrderId });
                } catch (error) {
                    messages.push({
                        key: `${returnOrderId}-paperwork-error`,
                        severity: 'error',
                        text: `${returnOrderNumber}: Paperwork generation failed. ${this.normalizeErrorMessage(error)}`
                    });
                    continue;
                }

                if (paperwork?.shippingLabelError) {
                    messages.push({
                        key: `${returnOrderId}-label-error`,
                        severity: 'error',
                        text: `${returnOrderNumber}: Shipping label could not be created. ${paperwork.shippingLabelError}`
                    });
                }

                if (paperwork?.roFormError) {
                    messages.push({
                        key: `${returnOrderId}-form-error`,
                        severity: 'error',
                        text: `${returnOrderNumber}: RO Form could not be created. ${paperwork.roFormError}`
                    });
                }

                if (
                    paperwork?.roFormBase64 &&
                    paperwork?.shippingLabelBase64
                ) {
                    try {
                        const combinedBase64 = await this.mergePdfBase64(
                            paperwork.roFormBase64,
                            paperwork.shippingLabelBase64
                        );
                        await attachCombinedPdf({
                            returnOrderId,
                            base64Pdf: combinedBase64,
                            returnOrderNumber: paperwork.returnOrderNumber || returnOrderNumber
                        });
                    } catch (error) {
                        messages.push({
                            key: `${returnOrderId}-combined-error`,
                            severity: 'error',
                            text: `${returnOrderNumber}: Combined PDF could not be created. ${this.normalizeErrorMessage(error)}`
                        });
                    }
                }
            }
        } finally {
            // Errors only — sticky toasts stay until the user closes them.
            this.isGeneratingPaperwork = false;
            for (const message of messages) {
                if (message.severity !== 'error') {
                    continue;
                }
                this.showToast('Paperwork', message.text, 'error', 'sticky');
            }
        }
    }

    async ensurePdfLibLoaded() {
        if (this._pdfLibInitialized) {
            return;
        }
        await loadScript(this, pdfLibResource);
        this._pdfLibInitialized = true;
    }

    async mergePdfBase64(roFormBase64, shippingLabelBase64) {
        const PDFLibApi = window.PDFLib;
        if (!PDFLibApi?.PDFDocument) {
            throw new Error('pdf-lib failed to load.');
        }

        const mergedPdf = await PDFLibApi.PDFDocument.create();
        const formPdf = await PDFLibApi.PDFDocument.load(this.base64ToUint8Array(roFormBase64));
        const labelPdf = await PDFLibApi.PDFDocument.load(
            this.base64ToUint8Array(shippingLabelBase64)
        );

        const formPages = await mergedPdf.copyPages(formPdf, formPdf.getPageIndices());
        formPages.forEach((page) => mergedPdf.addPage(page));

        const labelPages = await mergedPdf.copyPages(labelPdf, labelPdf.getPageIndices());
        labelPages.forEach((page) => mergedPdf.addPage(page));

        const mergedBytes = await mergedPdf.save();
        return this.uint8ArrayToBase64(mergedBytes);
    }

    base64ToUint8Array(base64) {
        const binary = window.atob(base64);
        const bytes = new Uint8Array(binary.length);
        for (let i = 0; i < binary.length; i += 1) {
            bytes[i] = binary.charCodeAt(i);
        }
        return bytes;
    }

    uint8ArrayToBase64(bytes) {
        let binary = '';
        const chunkSize = 0x8000;
        for (let i = 0; i < bytes.length; i += chunkSize) {
            const chunk = bytes.subarray(i, i + chunkSize);
            binary += String.fromCharCode.apply(null, chunk);
        }
        return window.btoa(binary);
    }

    normalizeErrorMessage(error) {
        if (!error) {
            return 'Unknown error.';
        }
        if (typeof error === 'string') {
            return error;
        }
        return (
            error.body?.message ||
            error.message ||
            (Array.isArray(error.body) ? error.body.map((item) => item.message).join(' ') : null) ||
            'Unknown error.'
        );
    }

    handleOpenCreatedReturnOrder(event) {
        event.preventDefault();
        const returnOrderId = event.currentTarget.dataset.id;
        if (!returnOrderId) {
            return;
        }
        this.finishCreateFlow(returnOrderId);
    }

    handleCloseCreatedOrdersScreen() {
        this.finishCreateFlow(null);
    }

    finishCreateFlow(returnOrderId) {
        if (returnOrderId) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: returnOrderId,
                    objectApiName: 'ReturnOrder',
                    actionName: 'view'
                }
            });
        } else if (
            !this.isRecordActionLaunch &&
            !this.embeddedMode &&
            this.originRecordId &&
            this.originObjectApiName
        ) {
            this[NavigationMixin.Navigate]({
                type: 'standard__recordPage',
                attributes: {
                    recordId: this.originRecordId,
                    objectApiName: this.originObjectApiName,
                    actionName: 'view'
                }
            });
        }

        if (this.isRecordActionLaunch) {
            this.dispatchEvent(new CloseActionScreenEvent());
            return;
        }

        if (this.embeddedMode) {
            this.dispatchEvent(new CustomEvent('exit', { bubbles: true, composed: true }));
            return;
        }

        if (!returnOrderId) {
            if (this.isHomePageLaunch) {
                this.resetStandaloneWizard();
                return;
            }
            this.closeLaunchSurface();
        }
    }

    showError(title, error) {
        const message = error?.body?.message || error?.message || 'Unknown error';
        this.showToast(title, message, 'error');
    }

    showToast(title, message, variant, mode) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant,
                mode: mode || (variant === 'error' ? 'sticky' : 'dismissible')
            })
        );
    }
}