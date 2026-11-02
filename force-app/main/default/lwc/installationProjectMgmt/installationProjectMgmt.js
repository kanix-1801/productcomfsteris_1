import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { NavigationMixin } from 'lightning/navigation';
import { loadStyle } from 'lightning/platformResourceLoader';
import getCaseDetails from '@salesforce/apex/InstallationProjectMgmtController.getCaseDetails';
import getAccountDetails from '@salesforce/apex/InstallationProjectMgmtController.getAccountDetails';
import getProjectTemplates from '@salesforce/apex/InstallationProjectMgmtController.getProjectTemplates';
import getCasesForAccount from '@salesforce/apex/InstallationProjectMgmtController.getCasesForAccount';
import getTemplateItems from '@salesforce/apex/InstallationProjectMgmtController.getTemplateItems';
import createProject from '@salesforce/apex/InstallationProjectMgmtController.createProject';
import userId from '@salesforce/user/Id';
import { getRecord } from 'lightning/uiRecordApi';
import NAME_FIELD from '@salesforce/schema/User.Name';
import hasRelatedProjects from '@salesforce/apex/InstallationProjectMgmtController.hasRelatedProjects';
import getContactsForAccount from '@salesforce/apex/InstallationProjectMgmtController.getContactsForAccount';

// Page route constants
const PAGE_ROUTES = {
    CASE_REVIEW: 'caseReview',
    TEMPLATE_SELECTION: 'templateSelection',
    PROJECT_HEADER: 'projectHeader',
    PROJECT_LINES: 'projectLines',
    CONFIRMATION: 'confirmation'
};

// Path type constants
const PATH_TYPE = {
    CASE: 'CASE',
    ACCOUNT: 'ACCOUNT'
};

function getApexErrorMessage(error, fallback = 'Unknown error occurred') {
    if (!error) {
        return fallback;
    }
    if (Array.isArray(error.body)) {
        const messages = error.body.map((entry) => entry.message).filter(Boolean);
        if (messages.length) {
            return messages.join(', ');
        }
    }
    if (error.body?.output?.errors?.length) {
        const messages = error.body.output.errors.map((entry) => entry.message).filter(Boolean);
        if (messages.length) {
            return messages.join(', ');
        }
    }
    if (error.body?.pageErrors?.length) {
        const messages = error.body.pageErrors.map((entry) => entry.message).filter(Boolean);
        if (messages.length) {
            return messages.join(', ');
        }
    }
    return error.body?.message || error.message || fallback;
}

/** Numeric item sequence (main lines are whole numbers; sub-lines are fractional e.g. 5.01). */
function itemNumberAsNumber(itemNumber) {
    return Number(itemNumber);
}

function isMainLineItemNumber(itemNumber) {
    const n = itemNumberAsNumber(itemNumber);
    if (Number.isNaN(n)) {
        return false;
    }
    return Math.abs(n - Math.round(n)) < 1e-6;
}

function findParentMainItem(itemsWithDates, subItemNumber) {
    const parentMain = Math.floor(itemNumberAsNumber(subItemNumber));
    return itemsWithDates.find(
        (i) =>
            isMainLineItemNumber(i.ItemNumber__c) &&
            itemNumberAsNumber(i.ItemNumber__c) === parentMain
    );
}

// Page configuration with routing metadata
const PAGE_CONFIG = {
    [PAGE_ROUTES.CASE_REVIEW]: {
        key: PAGE_ROUTES.CASE_REVIEW,
        order: 1,
        title: 'Case Review',
        subtitle: '',
        paths: [PATH_TYPE.CASE]
    },
    [PAGE_ROUTES.TEMPLATE_SELECTION]: {
        key: PAGE_ROUTES.TEMPLATE_SELECTION,
        order: 2,
        title: 'Template Selection',
        subtitle: '',
        paths: [PATH_TYPE.CASE, PATH_TYPE.ACCOUNT]
    },
    [PAGE_ROUTES.PROJECT_HEADER]: {
        key: PAGE_ROUTES.PROJECT_HEADER,
        order: 3,
        title: 'Configure Project',
        subtitle: '',
        paths: [PATH_TYPE.CASE, PATH_TYPE.ACCOUNT]
    },
    [PAGE_ROUTES.PROJECT_LINES]: {
        key: PAGE_ROUTES.PROJECT_LINES,
        order: 4,
        title: 'Configure Items',
        subtitle: '',
        paths: [PATH_TYPE.CASE, PATH_TYPE.ACCOUNT]
    },
    [PAGE_ROUTES.CONFIRMATION]: {
        key: PAGE_ROUTES.CONFIRMATION,
        order: 5,
        title: 'Ready to Create Project',
        subtitle: '',
        paths: [PATH_TYPE.CASE, PATH_TYPE.ACCOUNT]
    }
};

export default class InstallationProjectMgmt extends NavigationMixin(LightningElement) {
    @api recordId;
    
    // Make objectApiName reactive - reinitialize when it's set
    _objectApiName;
    @api
    get objectApiName() {
        return this._objectApiName;
    }
    set objectApiName(value) {
        this._objectApiName = value;
        if (value && !this.initialized) {
            this.setPathFromObjectName(value);
        }
    }
    
    currentPageRoute;
    pathType;
    initialized = false;
    stylesLoaded = false;
    caseData;
    accountData;
    templates;
    selectedTemplateId;
    selectedTemplateRows = []; // Array to track selected rows in datatable
    
    // Computed property to conditionally pass caseId only when on Case path
    get caseIdForWire() {
        // Only return recordId if we're on Case path, otherwise return undefined
        return this.pathType === PATH_TYPE.CASE ? this.recordId : undefined;
    }
    
    // Computed property to conditionally pass accountId only when on Account path
    get accountIdForWire() {
        // Only return recordId if we're on Account path, otherwise return undefined
        return this.pathType === PATH_TYPE.ACCOUNT ? this.recordId : undefined;
    }

    get registrationNumberForCaseFilter() {
        // Empty string (not undefined) so the @wire still runs when the starting
        // case has no registration number. Undefined skips the Apex call.
        return this.startingCaseRegistrationNumber || '';
    }
    
    // Page 3 - Project Header fields
    projectName = '';
    projectDescription = '';
    projectOwnerId;
    currentUserName = '';
    projectAccountId;
    projectContactId = undefined; // Project__c.ProjectContact__c
    primaryContactId = undefined; // Project__c.PrimaryContact__c
    selectedCaseIds = [];
    projectStartDate;
    projectEndDate;
    shippedDate;
    requestedDate;
    primaryEst;
    primaryInstaller;
    districtServiceManager;
    capitalAccountManager;
    primaryCaseId;
    caseOptions = [];
    accountIdForCases;
    accountContacts = [];
    filteredContacts = [];
    projectContactName = '';
    showContactAutocomplete = false;
    // Flag to prevent duplicate related project checks
    relatedProjectsChecked = false;
    startingCaseRegistrationNumber;
    
    // Page 5 - Confirmation (Template Items)
    templateItems = [];
    templateItemsWithDates = [];
    showRowNumbers = false;
    draftValues = []; // Track draft values for inline editing
    isCreatingProject = false; // Track loading state for project creation
    // Reused as inline warning flag instead of modal
    /** Apex result: Case already has at least one linked Installation Project (banner on Case Review only). */
    caseHasRelatedProject = false;
    checkingRelatedProjects = false; // Track if we're checking for related projects

    // Template datatable columns
    templateColumns = [
        { label: 'Name', fieldName: 'Name', type: 'text' }
    ];
    
    // Template items datatable columns for Page 4
    templateItemColumns = [
        { 
            label: '#', 
            fieldName: 'displayItemNumber',
            type: 'text',
            cellAttributes: { alignment: 'left' },
            initialWidth: 70,
            editable: false // Item number is not editable
        },
        { 
            label: 'Type', 
            fieldName: 'Type__c', 
            type: 'picklist',
            typeAttributes: {
                placeholder: 'Select Type',
                options: [
                    { label: 'Task', value: 'Task' },
                    { label: 'Event', value: 'Event' }
                ],
                value: { fieldName: 'Type__c' }
            },
            cellAttributes: { alignment: 'left' },
            initialWidth: 120,
            editable: true
        },
        { 
            label: 'Name', 
            fieldName: 'Name', 
            type: 'text',
            cellAttributes: { alignment: 'left' },
            editable: true
            // No initialWidth - will flex to fill remaining space (largest column)
        },
        { 
            label: 'Duration (Days)', 
            fieldName: 'Duration__c', 
            type: 'number',
            typeAttributes: {
                step: '1', // Integer only
                min: 0
            },
            cellAttributes: { alignment: 'left' },
            initialWidth: 120,
            editable: true
        },
        { 
            label: 'Date', 
            fieldName: 'calculatedStartDate', 
            type: 'date-local',
            cellAttributes: { alignment: 'left' },
            initialWidth: 130,
            editable: false // Date is calculated, not editable
        },
        {
            type: 'action',
            typeAttributes: { 
                rowActions: this.getRowActions.bind(this)
            },
            cellAttributes: { alignment: 'left' },
            initialWidth: 75
        }
    ];
    
    // Define row actions for the action menu - different for main items vs sub-items
    getRowActions(row, doneCallback) {
        const isMainItem = isMainLineItemNumber(row.ItemNumber__c);
        
        let actions;
        if (isMainItem) {
            // Main items: Delete, Add Line, Add Sub-line
            actions = [
                { label: 'Delete', name: 'delete' },
                { label: 'Add Line', name: 'add_line' },
                { label: 'Add Sub-line', name: 'add_subline' }
            ];
        } else {
            // Sub-items: Delete only
            actions = [
                { label: 'Delete', name: 'delete' }
            ];
        }
        
        doneCallback(actions);
    }

    connectedCallback() {
        // No modal CSS to load anymore
        this.stylesLoaded = true;
        
        // Set default project start date to today
        const today = new Date();
        this.projectStartDate = today.toISOString().split('T')[0]; // Format as YYYY-MM-DD
        
        console.log('Connected callback - recordId:', this.recordId, 'objectApiName:', this.objectApiName, 'initialized:', this.initialized, 'isCasePath:', this.isCasePath);
        
        // Initialize if we have recordId and objectApiName
        if (this.recordId && this.objectApiName && !this.initialized) {
            this.setPathFromObjectName(this.objectApiName);
        }
        
        // Check for related projects immediately if we're on Case path and haven't initialized yet
        if (this.isCasePath && this.recordId && !this.initialized) {
            console.log('Calling checkForRelatedProjectsOnInit');
            this.checkForRelatedProjectsOnInit();
        } else if (this.initialized) {
            // If already initialized, check if we're on Case path and should show modal
            if (this.isCasePath && this.recordId) {
                console.log('Already initialized, checking for related projects');
                this.checkForRelatedProjectsOnInit();
            }
        }
    }

    // Wire to get case details when on Case path
    @wire(getCaseDetails, { caseId: '$caseIdForWire' })
    wiredCase({ error, data }) {
        if (data) {
            this.caseData = data;
            this.startingCaseRegistrationNumber = data.RegistrationNumber__c?.trim() || null;
            // Set default values for Page 3
            this.projectOwnerId = data.OwnerId;
            this.projectAccountId = data.AccountId;
            this.accountIdForCases = data.AccountId;
            this.selectedCaseIds = [data.Id]; // Pre-select current case
            // Attempt to default Primary Contact from Case Contact against Account
            this.primaryContactId = data.ContactId ? data.ContactId : this.primaryContactId;
            this.applyDefaultProjectNameFromCaseReview();
            this.ensureStartingCaseInCaseOptions();
            console.log('Case data loaded:', this.caseData);
        } else if (error) {
            // Only show error if we're on Case path (not Account path)
            if (this.pathType === PATH_TYPE.CASE) {
                console.error('Error loading case data:', error);
                this.caseData = null;
                this.showToast('Error', 'Failed to load case data: ' + (error.body?.message || error.message), 'error');
            }
        }
    }

    // Wire to get account details when on Account path
    @wire(getAccountDetails, { accountId: '$accountIdForWire' })
    wiredAccount({ error, data }) {
        if (data) {
            this.accountData = data;
            // Set default values for Page 3
            this.projectOwnerId = data.OwnerId;
            // Clear project/primary contact if account context changes
            if (this.projectAccountId !== data.Id) {
                this.projectContactId = undefined;
                this.projectContactName = '';
                this.primaryContactId = undefined;
            }
            this.projectAccountId = data.Id;
            console.log('Account data loaded:', this.accountData);
        } else if (error) {
            // Only show error if we're on Account path (not Case path)
            if (this.pathType === PATH_TYPE.ACCOUNT) {
                console.error('Error loading account data:', error);
                this.accountData = null;
                this.showToast('Error', 'Failed to load account data: ' + (error.body?.message || error.message), 'error');
            }
        }
    }

    // Wire to get current user name (for Page 5 display)
    @wire(getRecord, { recordId: '$_currentUserId', fields: [NAME_FIELD] })
    wiredCurrentUser({ data, error }) {
        if (data) {
            this.currentUserName = data.fields.Name.value;
        } else if (error) {
            // Fallback: empty string if user name cannot be resolved
            this.currentUserName = '';
            // optional console error only (no toast needed)
            // console.error('Error loading current user', error);
        }
    }

    // Provide reactive reference for recordId param above
    get _currentUserId() {
        return userId;
    }

    // Wire to get project templates
    @wire(getProjectTemplates)
    wiredTemplates({ error, data }) {
        if (data) {
            this.templates = data;
            console.log('Templates loaded:', this.templates);
        } else if (error) {
            console.error('Error loading templates:', error);
            this.templates = null;
            this.showToast('Error', 'Failed to load templates: ' + (error.body?.message || error.message), 'error');
        }
    }

    // Wire to get cases for the account
    @wire(getCasesForAccount, { accountId: '$accountIdForCases', registrationNumber: '$registrationNumberForCaseFilter' })
    wiredCases({ error, data }) {
        if (data) {
            this.caseOptions = data.map(c => ({
                label: this.formatCaseOptionLabel(c),
                value: c.Id
            }));
            this.ensureStartingCaseInCaseOptions();
            console.log('Cases loaded:', this.caseOptions);
        } else if (error) {
            console.error('Error loading cases:', error);
            this.caseOptions = [];
        }
    }
    
    // Wire to get contacts for the account
    @wire(getContactsForAccount, { accountId: '$projectAccountId' })
    wiredContacts({ error, data }) {
        if (data) {
            this.accountContacts = data.map(c => ({
                label: c.Name,
                value: c.Id
            }));
        } else if (error) {
            console.error('Error loading contacts:', error);
            this.accountContacts = [];
        }
    }

    // Wire to get template items for Page 5
    @wire(getTemplateItems, { templateId: '$selectedTemplateId' })
    wiredTemplateItems({ error, data }) {
        if (data) {
            // Normalize incoming items with initial displayItemNumber so the first render shows correctly
            this.templateItems = data.map(item => {
                const isMain = isMainLineItemNumber(item.ItemNumber__c);
                if (isMain) {
                    return { ...item, displayItemNumber: String(item.ItemNumber__c) };
                }
                // For subs, show minimal decimals unless 10th (UI-only)
                const frac = Math.round((item.ItemNumber__c - Math.floor(item.ItemNumber__c)) * 100);
                // If incoming data already encodes hundredths, compress to single decimal unless it's an exact tenth (e.g., 1.10 stays 1.10 only after user adds 10th)
                const displayItemNumber = frac % 10 === 0
                    ? `${Math.floor(item.ItemNumber__c)}.${Math.floor(frac / 10)}`
                    : `${Math.floor(item.ItemNumber__c)}.${(frac % 10)}`;
                return { ...item, displayItemNumber };
            });
            this.calculateItemDates();
        } else if (error) {
            console.error('Error loading template items:', error);
            this.templateItems = [];
            this.templateItemsWithDates = [];
        }
    }
    
    // Calculate dates for template items based on dependency type
    calculateItemDates() {
        if (!this.templateItems || this.templateItems.length === 0) {
            this.templateItemsWithDates = [];
            return;
        }
        
        const itemsWithDates = [];
        
        // Calculate start dates
        for (const item of this.templateItems) {
            const isMainItem = isMainLineItemNumber(item.ItemNumber__c);
            let startDate = null;
            const offsetDays = Number(item.AutoFilledStartDays__c) || 0;

            // Sub-lines (e.g. 5.01): same anchor date as parent main line (5)
            if (!isMainItem) {
                const parentItem = findParentMainItem(itemsWithDates, item.ItemNumber__c);
                if (parentItem?.calculatedStartDate) {
                    startDate = new Date(parentItem.calculatedStartDate);
                    if (offsetDays) {
                        startDate.setDate(startDate.getDate() + offsetDays);
                    }
                }
            }

            // Check if item has a dependency type configured
            if (!startDate && item.DependencyType__c) {
                // Calculate start date based on DependencyType__c
                if (item.DependencyType__c === 'Start Date') {
                    // Start date = Project Start Date + AutoFilledStartDays__c
                    if (this.projectStartDate) {
                        startDate = new Date(this.projectStartDate);
                        startDate.setDate(startDate.getDate() + offsetDays);
                    }
                } else if (item.DependencyType__c === 'Shipped Date') {
                    // Start date = Shipped Date + AutoFilledStartDays__c
                    if (this.shippedDate) {
                        startDate = new Date(this.shippedDate);
                        startDate.setDate(startDate.getDate() + offsetDays);
                    }
                } else if (item.DependencyType__c === 'Requested Date') {
                    // Start date = Requested Date + AutoFilledStartDays__c
                    if (this.requestedDate) {
                        startDate = new Date(this.requestedDate);
                        startDate.setDate(startDate.getDate() + offsetDays);
                    }
                } else if (item.DependencyType__c === 'Dependent Item') {
                    // Start date = Referenced Item start date + AutoFilledStartDays__c
                    if (item.ItemDependency__c) {
                        // Find the dependent item by its Id
                        const dependentItem = itemsWithDates.find(i => i.Id === item.ItemDependency__c);
                        if (dependentItem && dependentItem.calculatedStartDate) {
                            startDate = new Date(dependentItem.calculatedStartDate);
                            startDate.setDate(startDate.getDate() + offsetDays);
                        }
                    }
                }
            } else if (!startDate && isMainItem) {
                // No dependency: offset from project start (first main) or previous main start (sequence)
                const previousMainItems = itemsWithDates.filter((i) =>
                    isMainLineItemNumber(i.ItemNumber__c)
                );
                if (previousMainItems.length > 0) {
                    const lastMainItem = previousMainItems[previousMainItems.length - 1];
                    if (lastMainItem.calculatedStartDate) {
                        startDate = new Date(lastMainItem.calculatedStartDate);
                        startDate.setDate(startDate.getDate() + offsetDays);
                    }
                } else if (this.projectStartDate) {
                    startDate = new Date(this.projectStartDate);
                    startDate.setDate(startDate.getDate() + offsetDays);
                }
            }
            
            // Fallback when anchor dates are not yet available
            if (!startDate && this.projectStartDate) {
                startDate = new Date(this.projectStartDate);
                startDate.setDate(startDate.getDate() + offsetDays);
            }
            
            // Calculate end date: start date + duration
            let endDate = null;
            const duration = Number(item.Duration__c) || 0;
            const isZeroDurationEvent =
                item.Type__c && item.Type__c.toLowerCase() === 'event' && duration === 0;
            if (startDate && !isZeroDurationEvent) {
                endDate = new Date(startDate);
                endDate.setDate(endDate.getDate() + duration);
            }
            
            itemsWithDates.push({
                ...item,
                calculatedStartDate: startDate ? startDate.toISOString().split('T')[0] : null, // Format as YYYY-MM-DD
                calculatedEndDate: endDate ? endDate.toISOString().split('T')[0] : null, // Format as YYYY-MM-DD
                isSubItem: !isMainItem // Flag for styling sub-items
            });
        }
        
        // Create new array reference to trigger reactivity
        this.templateItemsWithDates = [...itemsWithDates];
    }

    // Computed properties for case fields
    get orderNumber() {
        // Updated to use Oracle Order Number directly from Case per request
        return this.caseData?.OracleOrderNumber__c || '--';
    }

    get accountName() {
        return this.caseData?.Account?.Name || '--';
    }

    formatCaseOptionLabel(caseRecord) {
        const caseNumber = caseRecord.CaseNumber || '';
        const subject = caseRecord.Subject || '';
        const registrationNumber = caseRecord.RegistrationNumber__c || '';
        const baseLabel = `${caseNumber} - ${subject}`;
        return registrationNumber ? `${baseLabel} - ${registrationNumber}` : baseLabel;
    }

    ensureStartingCaseInCaseOptions() {
        if (this.pathType !== PATH_TYPE.CASE || !this.caseData?.Id) {
            return;
        }

        const startingCaseOption = {
            label: this.formatCaseOptionLabel(this.caseData),
            value: this.caseData.Id
        };
        const existingIndex = this.caseOptions.findIndex(opt => opt.value === this.caseData.Id);

        if (existingIndex >= 0) {
            this.caseOptions = this.caseOptions.map((opt, index) =>
                index === existingIndex ? startingCaseOption : opt
            );
        } else {
            this.caseOptions = [...this.caseOptions, startingCaseOption];
        }
    }

    getSelectedCaseLabels() {
        if (!this.selectedCaseIds || this.selectedCaseIds.length === 0) {
            return [];
        }

        return this.selectedCaseIds
            .map(caseId => {
                const option = this.caseOptions.find(opt => opt.value === caseId);
                if (option) {
                    return option.label;
                }
                if (this.caseData?.Id === caseId) {
                    return this.formatCaseOptionLabel(this.caseData);
                }
                return null;
            })
            .filter(label => label);
    }

    /**
     * Page 3 Project Name default: same Account and Order # as Case Review (page 1, row 3).
     * Only fills when the field is still empty so the user can change or clear it without us overwriting non-empty edits.
     */
    applyDefaultProjectNameFromCaseReview() {
        if (this.pathType !== PATH_TYPE.CASE || !this.caseData) {
            return;
        }
        if (this.projectName && this.projectName.trim().length > 0) {
            return;
        }
        const account = this.caseData.Account?.Name?.trim();
        const order = this.caseData.OracleOrderNumber__c?.trim();
        if (account && order) {
            this.projectName = `${account} ${order}`;
        } else if (account) {
            this.projectName = account;
        } else if (order) {
            this.projectName = order;
        }
    }

    get ownerName() {
        return this.caseData?.Owner?.Name || '--';
    }

    get recordTypeName() {
        return this.caseData?.RecordType?.Name || '--';
    }

    get selectedTemplateName() {
        const selectedTemplate = this.templates?.find(t => t.Id === this.selectedTemplateId);
        return selectedTemplate?.Name || '--';
    }

    get projectOwnerName() {
        // Always display the current user as Project Owner on Confirmation (Page 5)
        // since server enforces OwnerId = current user on create
        return this.currentUserName || '';
    }

    get projectAccountName() {
        // On Case path, get account name from case data; on Account path, get from account data
        if (this.pathType === PATH_TYPE.CASE) {
            return this.caseData?.Account?.Name || '';
        } else if (this.pathType === PATH_TYPE.ACCOUNT) {
            return this.accountData?.Name || '';
        }
        return '';
    }
    
    // Page 5 - Confirmation summary getters
    get caseLabel() {
        if (!this.selectedCaseIds || this.selectedCaseIds.length === 0) {
            return 'From Case';
        }
        return this.selectedCaseIds.length === 1 ? 'From Case' : 'From Cases';
    }
    
    get selectedCasesDisplay() {
        if (!this.selectedCaseIds || this.selectedCaseIds.length === 0) {
            return '--';
        }

        const labels = this.getSelectedCaseLabels();
        if (labels.length === 0) {
            return this.selectedCaseIds.length + ' case(s) selected';
        }

        return labels.join(', ');
    }
    
    get selectedCasesArray() {
        if (!this.selectedCaseIds || this.selectedCaseIds.length === 0) {
            return ['--'];
        }

        const labels = this.getSelectedCaseLabels();
        if (labels.length === 0) {
            return [this.selectedCaseIds.length + ' case(s) selected'];
        }

        return labels;
    }
    
    get taskCount() {
        if (!this.templateItemsWithDates || this.templateItemsWithDates.length === 0) {
            return 0;
        }
        return this.templateItemsWithDates.filter(item => 
            item.Type__c && item.Type__c.toLowerCase() === 'task'
        ).length;
    }
    
    get eventCount() {
        if (!this.templateItemsWithDates || this.templateItemsWithDates.length === 0) {
            return 0;
        }
        return this.templateItemsWithDates.filter(item => 
            item.Type__c && item.Type__c.toLowerCase() === 'event'
        ).length;
    }

    setPathFromObjectName(objectApiName) {
        if (this.initialized) return;
        
        console.log('Setting path from object name:', objectApiName);
        
        // Determine path type and initial page route based on object
        if (objectApiName === 'Account') {
            this.pathType = PATH_TYPE.ACCOUNT;
            this.currentPageRoute = PAGE_ROUTES.TEMPLATE_SELECTION;
            this.projectAccountId = this.recordId;
            this.accountIdForCases = this.recordId;
        } else {
            this.pathType = PATH_TYPE.CASE;
            this.currentPageRoute = PAGE_ROUTES.CASE_REVIEW;
        }
        
        console.log('Path type set to:', this.pathType);
        
        // Check for related projects immediately if we're on Case path
        if (this.pathType === PATH_TYPE.CASE && this.recordId) {
            console.log('Path set to CASE, checking for related projects immediately');
            this.checkForRelatedProjectsOnInit();
        }
        
        this.initialized = true;
    }

    // Get valid pages for current path in order
    get validPages() {
        // If not initialized yet, return empty array to prevent errors
        if (!this.initialized || !this.pathType) {
            return [];
        }
        return Object.values(PAGE_CONFIG)
            .filter(page => page.paths.includes(this.pathType))
            .sort((a, b) => a.order - b.order);
    }

    // Get current page config
    get currentPageConfig() {
        if (!this.initialized || !this.currentPageRoute) {
            return null;
        }
        return PAGE_CONFIG[this.currentPageRoute];
    }

    // Get current page index in the valid pages array
    get currentPageIndex() {
        if (!this.initialized) {
            return -1;
        }
        return this.validPages.findIndex(page => page.key === this.currentPageRoute);
    }

    // Path type check
    get isCasePath() {
        return this.pathType === PATH_TYPE.CASE;
    }


    // Add this getter to your JS (it was missing or implied in your previous version)
    get isPage1() {
        if (!this.initialized) {
            return false;
        }
        return this.currentPageRoute === PAGE_ROUTES.CASE_REVIEW;
    }

    get isPage2() {
        if (!this.initialized) {
            return false;
        }
        return this.currentPageRoute === PAGE_ROUTES.TEMPLATE_SELECTION;
    }

    get isPage3() {
        if (!this.initialized) {
            return false;
        }
        return this.currentPageRoute === PAGE_ROUTES.PROJECT_HEADER;
    }

    get isPage4() {
        if (!this.initialized) {
            return false;
        }
        return this.currentPageRoute === PAGE_ROUTES.PROJECT_LINES;
    }

    get isPage5() {
        if (!this.initialized) {
            return false;
        }
        return this.currentPageRoute === PAGE_ROUTES.CONFIRMATION;
    }

    // Progress indicator configuration
    get progressSteps() {
        return this.validPages.map((page) => {
            // Special handling for step 5 - different label for progress bar
            const progressLabel = page.key === PAGE_ROUTES.CONFIRMATION ? 'Confirmation' : page.title;
            
            // Combine title and subtitle for tooltip if subtitle exists
            const tooltipText = page.subtitle 
                ? `${page.title} - ${page.subtitle}` 
                : page.title;
            
            return {
                label: progressLabel,
                value: page.key,
                // assistiveText is used for the tooltip
                assistiveText: tooltipText
            };
        });
    }

    get currentStepValue() {
        return this.currentPageRoute;
    }

    // Page title and subtitle
    get pageTitle() {
        return this.currentPageConfig?.title || 'Installation Project Management';
    }

    get pageSubtitle() {
        return this.currentPageConfig?.subtitle || '';
    }

    // Navigation state
    get isFirstPage() {
        return this.currentPageIndex === 0;
    }

    get isLastPage() {
        return this.currentPageIndex === this.validPages.length - 1;
    }

    // Button visibility
    get showBackButton() {
        return true;
    }

    get showNextButton() {
        return !this.isLastPage;
    }

    get showCreateButton() {
        return this.isLastPage;
    }

    get isBackDisabled() {
        return false;
    }

    get isNextDisabled() {
        // Disable Next on page 2 if no template is selected
        if (this.isPage2) {
            return !this.selectedTemplateId;
        }
        
        // Page 3 - Enable Next only when form is valid
        if (this.isPage3) {
            return !this.isPage3FormValid;
        }
        
        return false;
    }
    
    // Validation for Page 3 form fields
    get isPage3FormValid() {
        // Check all required fields
        const hasProjectName = this.projectName && this.projectName.trim().length > 0;
        const hasProjectOwner = this.projectOwnerId && this.projectOwnerId.length > 0;
        const hasStartDate = this.projectStartDate && this.projectStartDate.length > 0;
        // const hasEndDate = this.projectEndDate && this.projectEndDate.length > 0; // Commented out
        const hasShippedDate = this.shippedDate && this.shippedDate.length > 0;
        const hasRequestedDate = this.requestedDate && this.requestedDate.length > 0;
        const hasCases = this.selectedCaseIds && this.selectedCaseIds.length > 0;
        
        // Check if all dates are valid (if they exist)
        const datesValid = this.areDatesValid;
        
        return hasProjectName && hasProjectOwner && hasStartDate && 
               hasShippedDate && hasRequestedDate && hasCases && datesValid;
    }

    // Navigation methods
    navigateToPage(pageRoute) {
        const pageConfig = PAGE_CONFIG[pageRoute];
        if (pageConfig && pageConfig.paths.includes(this.pathType)) {
            this.currentPageRoute = pageRoute;
        }
    }

    navigateNext() {
        const nextIndex = this.currentPageIndex + 1;
        if (nextIndex < this.validPages.length) {
            this.currentPageRoute = this.validPages[nextIndex].key;
        }
    }

    navigateBack() {
        const prevIndex = this.currentPageIndex - 1;
        if (prevIndex >= 0) {
            this.currentPageRoute = this.validPages[prevIndex].key;
        }
    }

    // Event handlers
    handleBack() {
        if (this.isFirstPage) {
            this.handleClose();
        } else {
            this.navigateBack();
        }
    }

    handleNext() {
        // If we're on the Case Review page (page 1) and on Case path, check for related projects
        if (this.isPage1 && this.isCasePath && !this.relatedProjectsChecked) {
            this.checkForRelatedProjects();
        } else {
            this.navigateNext();
        }
    }
    
    /**
     * Check if the case has any related projects
     */
    checkForRelatedProjects() {
        if (!this.recordId || !this.isCasePath) {
            this.navigateNext();
            return;
        }
        
        this.checkingRelatedProjects = true;
        this.caseHasRelatedProject = false;

        // Call the Apex method to check for related projects
        hasRelatedProjects({ caseId: this.recordId })
            .then(result => {
                this.checkingRelatedProjects = false;
                if (result) {
                    this.caseHasRelatedProject = true;
                    // Allow user to continue to next page per UX goal
                    this.navigateNext();
                } else {
                    this.navigateNext();
                }
            })
            .catch(error => {
                this.checkingRelatedProjects = false;
                console.error('Error checking related projects:', error);
                // In case of error, still proceed to next page
                this.navigateNext();
            });
    }
    
    /**
     * Check for related projects when component initializes
     */
    checkForRelatedProjectsOnInit() {
        if (!this.recordId || !this.isCasePath || this.initialized) {
            return;
        }
        
        console.log('Checking for related projects on init - recordId:', this.recordId, 'isCasePath:', this.isCasePath);
        
        // Call the Apex method to check for related projects
        hasRelatedProjects({ caseId: this.recordId })
            .then(result => {
                console.log('Related projects check result:', result);
                if (result) {
                    console.log('Showing inline related project warning');
                    this.caseHasRelatedProject = true;
                } else {
                    // No related projects, continue normally
                    console.log('No related projects found');
                }
            })
            .catch(error => {
                console.error('Error checking related projects on init:', error);
                // In case of error, continue normally
            });
    }

    handleTemplateRowSelection(event) {
        const selectedRows = event.detail.selectedRows;
        
        if (selectedRows.length > 0) {
            // Only one row can be selected due to max-row-selection="1"
            const selectedTemplate = selectedRows[0];
            this.selectedTemplateId = selectedTemplate.Id;
            this.selectedTemplateRows = [selectedTemplate.Id];
            
            console.log('Selected template:', this.selectedTemplateId);
        } else {
            // No rows selected
            this.selectedTemplateId = null;
            this.selectedTemplateRows = [];
        }
    }

    // Page 3 field change handlers
    handleProjectNameChange(event) {
        this.projectName = event.target.value;
    }

    handleProjectDescriptionChange(event) {
        this.projectDescription = event.target.value;
    }

    handleProjectOwnerChange(event) {
        this.projectOwnerId = event.detail.value;
    }

    // Capture values from lightning-input-field lookup selections (Primary/Project Contact)
    handlePrimaryContactChange(event) {
        this.primaryContactId = event.detail.value;
    }
    handleProjectContactSearch(event) {
        const searchTerm = event.target.value;
        this.projectContactName = searchTerm;
        if (!searchTerm || searchTerm.length === 0) {
            this.projectContactId = undefined;
            this.filteredContacts = this.accountContacts;
        } else {
            this.filteredContacts = this.accountContacts.filter(c =>
                c.label.toLowerCase().includes(searchTerm.toLowerCase())
            );
        }
        this.showContactAutocomplete = true;
    }

    handleProjectContactFocus() {
        this.filteredContacts = this.projectContactName
            ? this.accountContacts.filter(c =>
                  c.label.toLowerCase().includes(this.projectContactName.toLowerCase())
              )
            : this.accountContacts;
        this.showContactAutocomplete = true;
    }

    handleProjectContactSelect(event) {
        this.projectContactId = event.currentTarget.dataset.contactId;
        this.projectContactName = event.currentTarget.dataset.contactName;
        this.showContactAutocomplete = false;
    }

    handleProjectContactBlur() {
        // Delay to allow click on dropdown to register
        // eslint-disable-next-line @lwc/lwc/no-async-operation
        setTimeout(() => {
            this.showContactAutocomplete = false;
        }, 250);
    }

    handleCaseSelection(event) {
        this.selectedCaseIds = event.detail.value;
        console.log('Selected cases:', this.selectedCaseIds);
    }

    handleProjectStartDateChange(event) {
        this.projectStartDate = event.target.value;
        // Recalculate template item dates when start date changes
        this.calculateItemDates();
        // Validate other dates against the new start date
        this.validateDatesAgainstStartDate();
    }

    handleProjectEndDateChange(event) {
        this.projectEndDate = event.target.value;
        this.validateEndDate();
    }

    handleShippedDateChange(event) {
        this.shippedDate = event.target.value;
        this.validateShippedDate();
        // Recalculate template item dates when shipped date changes
        this.calculateItemDates();
    }

    handleRequestedDateChange(event) {
        this.requestedDate = event.target.value;
        this.validateRequestedDate();
        // Recalculate template item dates when requested date changes
        this.calculateItemDates();
    }

    // New field change handlers
    handlePrimaryEstChange(event) {
        this.primaryEst = event.target.value;
    }

    handlePrimaryInstallerChange(event) {
        this.primaryInstaller = event.target.value;
    }

    handleDistrictServiceManagerChange(event) {
        this.districtServiceManager = event.target.value;
    }

    handleCapitalAccountManagerChange(event) {
        this.capitalAccountManager = event.target.value;
    }
    
    // Validation methods for dates
    /* Commented out - Project End Date is not used
    validateEndDate() {
        if (this.projectStartDate && this.projectEndDate) {
            const startDate = new Date(this.projectStartDate);
            const endDate = new Date(this.projectEndDate);
            
            if (endDate <= startDate) {
                const inputField = this.template.querySelector('[data-id="projectEndDate"]');
                if (inputField) {
                    inputField.setCustomValidity('End Date must be after Start Date');
                    inputField.reportValidity();
                }
                return false;
            } else {
                const inputField = this.template.querySelector('[data-id="projectEndDate"]');
                if (inputField) {
                    inputField.setCustomValidity('');
                    inputField.reportValidity();
                }
                return true;
            }
        }
        return true;
    }
    */
    
    validateShippedDate() {
        if (this.projectStartDate && this.shippedDate) {
            const startDate = new Date(this.projectStartDate);
            const shippedDate = new Date(this.shippedDate);
            
            if (shippedDate <= startDate) {
                const inputField = this.template.querySelector('[data-id="shippedDate"]');
                if (inputField) {
                    inputField.setCustomValidity('Shipped Date must be after Start Date');
                    inputField.reportValidity();
                }
                return false;
            } else {
                const inputField = this.template.querySelector('[data-id="shippedDate"]');
                if (inputField) {
                    inputField.setCustomValidity('');
                    inputField.reportValidity();
                }
                return true;
            }
        }
        return true;
    }
    
    validateRequestedDate() {
        if (this.projectStartDate && this.requestedDate) {
            const startDate = new Date(this.projectStartDate);
            const requestedDate = new Date(this.requestedDate);
            
            if (requestedDate <= startDate) {
                const inputField = this.template.querySelector('[data-id="requestedDate"]');
                if (inputField) {
                    inputField.setCustomValidity('Requested Date must be after Start Date');
                    inputField.reportValidity();
                }
                return false;
            } else {
                const inputField = this.template.querySelector('[data-id="requestedDate"]');
                if (inputField) {
                    inputField.setCustomValidity('');
                    inputField.reportValidity();
                }
                return true;
            }
        }
        return true;
    }
    
    validateDatesAgainstStartDate() {
        // this.validateEndDate(); // Commented out - Project End Date is not used
        this.validateShippedDate();
        this.validateRequestedDate();
    }
    
    get areDatesValid() {
        if (!this.projectStartDate) return true;
        
        let isValid = true;
        
        /* Commented out - Project End Date is not used
        if (this.projectEndDate) {
            const startDate = new Date(this.projectStartDate);
            const endDate = new Date(this.projectEndDate);
            if (endDate <= startDate) isValid = false;
        }
        */
        
        if (this.shippedDate) {
            const startDate = new Date(this.projectStartDate);
            const shippedDate = new Date(this.shippedDate);
            if (shippedDate <= startDate) isValid = false;
        }
        
        if (this.requestedDate) {
            const startDate = new Date(this.projectStartDate);
            const requestedDate = new Date(this.requestedDate);
            if (requestedDate <= startDate) isValid = false;
        }
        
        return isValid;
    }
    
    // Handle row actions from the datatable
    handleRowAction(event) {
        const actionName = event.detail.action.name;
        const row = event.detail.row;
        
        switch (actionName) {
            case 'delete':
                this.handleDeleteLine(row);
                break;
            case 'add_line':
                this.handleAddLine(row);
                break;
            case 'add_subline':
                this.handleAddSubline(row);
                break;
            default:
                break;
        }
    }
    
    handleDeleteLine(row) {
        const itemNumber = row.ItemNumber__c;
        const isMainItem = Math.floor(itemNumber) === itemNumber;
        
        let filteredItems;
        if (isMainItem) {
            // Delete main line and all its sub-lines
            const mainNumber = Math.floor(itemNumber);
            filteredItems = this.templateItemsWithDates.filter(item => {
                const currentMain = Math.floor(item.ItemNumber__c);
                // Keep items that don't belong to this main line
                return currentMain !== mainNumber;
            });
        } else {
            // Delete just this sub-line
            filteredItems = this.templateItemsWithDates.filter(item => {
                return item.ItemNumber__c !== itemNumber;
            });
        }
        
        // Update the array reference
        this.templateItemsWithDates = [...filteredItems];
        
        // Update the source array as well
        this.templateItems = [...filteredItems];
        
        // Re-order item numbers
        this.reorderItemNumbers();
        
        // Show success message
        this.showToast('Success', 'Line removed.', 'success');
    }
    
    reorderItemNumbers() {
        if (!this.templateItemsWithDates || this.templateItemsWithDates.length === 0) {
            return;
        }
        
        let mainCounter = 1;
        let currentMainNumber = null;
        let subCounter = 1;
        
        // Reorder item numbers
        let reorderedItems = this.templateItemsWithDates
            // Always sort by numeric ItemNumber__c before re-enumeration to normalize any drift
            .slice()
            .sort((a, b) => Number(a.ItemNumber__c) - Number(b.ItemNumber__c))
            .map(item => {
            const isMainItem = isMainLineItemNumber(item.ItemNumber__c);
            
            if (isMainItem) {
                // This is a main item - assign new main number
                currentMainNumber = mainCounter;
                const newItemNumber = mainCounter;
                mainCounter++;
                subCounter = 1; // Reset sub counter for this main item
                
                const displayItemNumber = String(newItemNumber);
                return {
                    ...item,
                    ItemNumber__c: newItemNumber,
                    displayItemNumber
                };
            } else {
                // This is a sub-item - assign new sub number under current main
                // Use hundredths to avoid 1.10 vs 1.9 ordering issues
                const newItemNumber = currentMainNumber + (subCounter / 100);
                subCounter++;
                
                // UI-only formatting: only pad to two decimals once we reach 10th sub-line
                // If fractional part has two digits, show both (e.g., 1.10); else show minimal (e.g., 1.1)
                const frac = Math.round((newItemNumber - Math.floor(newItemNumber)) * 100);
                const displayItemNumber = frac >= 10
                    ? `${Math.floor(newItemNumber)}.${frac.toString().padStart(2,'0')}`
                    : `${Math.floor(newItemNumber)}.${(frac % 10)}`;
                
                return {
                    ...item,
                    ItemNumber__c: newItemNumber,
                    displayItemNumber
                };
            }
        });
        
        // Remove any indentation from display names
        reorderedItems = reorderedItems.map(item => {
            // Remove existing indentation if present
            const cleanName = item.Name.replace(/^\u00A0+/, '');
            
            return {
                ...item,
                Name: cleanName
            };
        });
        
        // Final numeric sort to guarantee correct visual order (handles 10th+ sub-lines)
        reorderedItems.sort((a, b) => Number(a.ItemNumber__c) - Number(b.ItemNumber__c));
        
        // Update with new array reference to trigger reactivity
        this.templateItemsWithDates = [...reorderedItems];
        this.templateItems = [...reorderedItems];
        
        // Recalculate dates after reordering
        this.calculateItemDates();
    }
    
    handleAddLine(row) {
        const selectedItemNumber = row.ItemNumber__c;
        const selectedIndex = this.templateItemsWithDates.findIndex(
            item => item.ItemNumber__c === selectedItemNumber
        );
        
        if (selectedIndex === -1) return;
        
        // Find the position after the selected line AND all its sub-lines
        const selectedMainNumber = Math.floor(selectedItemNumber);
        let insertIndex = selectedIndex;
        
        // Find all sub-items of the selected line
        for (let i = selectedIndex + 1; i < this.templateItemsWithDates.length; i++) {
            const currentMain = Math.floor(this.templateItemsWithDates[i].ItemNumber__c);
            // If this item belongs to the same main number, update insert index
            if (currentMain === selectedMainNumber) {
                insertIndex = i;
            } else {
                // We've moved to a different main line, stop searching
                break;
            }
        }
        
        // Calculate the new main item number (next whole number after the selected item)
        const nextMainNumber = Math.floor(selectedItemNumber) + 1;
        
        // Calculate start date: clicked task's start date + duration
        let newStartDate = this.projectStartDate;
        if (row.calculatedStartDate && row.Duration__c !== null && row.Duration__c !== undefined) {
            const clickedStartDate = new Date(row.calculatedStartDate);
            const duration = Number(row.Duration__c) || 0;
            clickedStartDate.setDate(clickedStartDate.getDate() + duration);
            newStartDate = clickedStartDate.toISOString().split('T')[0];
        }
        
        // Create new main line
        const newLine = {
            Id: 'temp_' + Date.now(), // Temporary ID for new items
            ItemNumber__c: nextMainNumber,
            Type__c: 'Event',
            Name: 'New Line',
            Duration__c: 1,
            DependencyType__c: null,
            AutoFilledStartDays__c: 0,
            ItemDependency__c: null,
            calculatedStartDate: newStartDate,
            calculatedEndDate: null,
            isSubItem: false,
            isNew: true // Flag to identify new items
        };
        
        // Insert the new line after the selected row AND all its sub-lines
        const updatedItems = [...this.templateItemsWithDates];
        updatedItems.splice(insertIndex + 1, 0, newLine);
        
        // Update both arrays
        this.templateItemsWithDates = updatedItems;
        this.templateItems = [...updatedItems];
        
        // Reorder all item numbers
        this.reorderItemNumbers();
        
        this.showToast('Success', 'Line added.', 'success');
    }
    
    handleAddSubline(row) {
        const parentItemNumber = row.ItemNumber__c;
        const parentIndex = this.templateItemsWithDates.findIndex(
            item => item.ItemNumber__c === parentItemNumber
        );
        
        if (parentIndex === -1) return;
        
        // Find the last sub-item of this parent, or the parent itself if no sub-items exist
        const parentMain = Math.floor(parentItemNumber);
        let insertIndex = parentIndex;
        let subItemCount = 0;
        
        // Find all sub-items of this parent and count them
        for (let i = parentIndex + 1; i < this.templateItemsWithDates.length; i++) {
            const currentMain = Math.floor(this.templateItemsWithDates[i].ItemNumber__c);
            if (currentMain === parentMain && this.templateItemsWithDates[i].ItemNumber__c !== parentMain) {
                insertIndex = i;
                subItemCount++;
            } else if (currentMain !== parentMain) {
                break;
            }
        }
        
        // Check if we already have 9 sub-items (maximum allowed)
        if (subItemCount >= 9) {
            this.showToast('Warning', 'Cannot add more than 9 sub-tasks per Event', 'warning');
            return;
        }
        
        // Calculate start date: parent task's start date + duration
        let newStartDate = this.projectStartDate;
        if (row.calculatedStartDate && row.Duration__c !== null && row.Duration__c !== undefined) {
            const parentStartDate = new Date(row.calculatedStartDate);
            const duration = Number(row.Duration__c) || 0;
            parentStartDate.setDate(parentStartDate.getDate() + duration);
            newStartDate = parentStartDate.toISOString().split('T')[0];
        }
        
        // Create new sub-line (item number will be recalculated)
        const newSubLine = {
            Id: 'temp_' + Date.now(), // Temporary ID for new items
            ItemNumber__c: parentMain + 0.1, // Temporary number, will be reordered
            Type__c: 'Task',
            Name: 'New Sub-line',
            Duration__c: 1,
            DependencyType__c: null,
            AutoFilledStartDays__c: 0,
            ItemDependency__c: null,
            calculatedStartDate: newStartDate,
            calculatedEndDate: null,
            isSubItem: true,
            isNew: true // Flag to identify new items
        };
        
        // Insert the new sub-line after the last sub-item (or after parent)
        const updatedItems = [...this.templateItemsWithDates];
        updatedItems.splice(insertIndex + 1, 0, newSubLine);
        
        // Update both arrays (ensure numeric sort before displaying)
        const normalized = updatedItems.slice().sort((a, b) => Number(a.ItemNumber__c) - Number(b.ItemNumber__c));
        this.templateItemsWithDates = normalized;
        this.templateItems = [...normalized];
        
        // Reorder all item numbers
        this.reorderItemNumbers();
        
        this.showToast('Success', 'Sub-line added.', 'success');
    }
    
    // Handle inline editing save
    handleSave(event) {
        const draftValues = event.detail.draftValues;
        
        // Validate draft values
        const validationErrors = [];
        
        draftValues.forEach(draft => {
            // Find the actual item to get the row number
            const item = this.templateItemsWithDates.find(i => i.Id === draft.Id);
            const rowNumber = item ? item.ItemNumber__c : draft.Id;
            
            // Validate Type field
            if (draft.Type__c && draft.Type__c !== 'Task' && draft.Type__c !== 'Event') {
                validationErrors.push(`Row ${rowNumber}: Type must be either "Task" or "Event"`);
            }
            
            // Validate Duration field (must be integer if provided)
            if (draft.Duration__c !== undefined && draft.Duration__c !== null) {
                const duration = Number(draft.Duration__c);
                if (isNaN(duration) || !Number.isInteger(duration) || duration < 0) {
                    validationErrors.push(`Row ${rowNumber}: Duration must be a positive integer or zero`);
                }
            }
        });
        
        // If validation errors exist, show error toast and don't save
        if (validationErrors.length > 0) {
            this.showToast('Validation Error', validationErrors.join('. '), 'error');
            // Clear draft values to remove highlighting
            this.draftValues = [];
            return;
        }
        
        // Update templateItems (source of truth) with edited values
        const updatedItems = this.templateItems.map(item => {
            const draftValue = draftValues.find(draft => draft.Id === item.Id);
            if (draftValue) {
                const updatedItem = { ...item };
                
                // Update fields from draft
                Object.keys(draftValue).forEach(key => {
                    if (key === 'Name') {
                        // Store CLEAN name (without indentation) in templateItems
                        updatedItem.Name = draftValue.Name.replace(/^\u00A0+/, '');
                    } else if (key !== 'Id') {
                        updatedItem[key] = draftValue[key];
                    }
                });
                
                return updatedItem;
            }
            return item;
        });
        
        // Update templateItems with new references
        this.templateItems = [...updatedItems];
        
        // Recalculate dates - this will also update templateItemsWithDates
        this.calculateItemDates();
        
        // Clear draft values to remove highlighting
        this.draftValues = [];
    }
    
    handleCreateProject() {
        // Set loading state
        this.isCreatingProject = true;
        
        // Extract the first case from selected cases
        let firstCaseId = null;
        if (this.selectedCaseIds && this.selectedCaseIds.length > 0) {
            firstCaseId = this.selectedCaseIds[0];
        }
        
        // Debug logging
        console.log('Selected case IDs:', this.selectedCaseIds);
        console.log('First case ID:', firstCaseId);
        
        // Prepare project data
        const projectData = {
            projectName: this.projectName,
            projectDescription: this.projectDescription,
            accountId: this.projectAccountId,
            ownerId: this.projectOwnerId,
            projectStartDate: this.projectStartDate,
            projectEndDate: this.projectEndDate,
            projectShippedDate: this.shippedDate,
            projectRequestedDate: this.requestedDate,
            primaryEst: this.primaryEst,
            primaryInstaller: this.primaryInstaller,
            districtServiceManager: this.districtServiceManager,
            capitalAccountManager: this.capitalAccountManager,
            primaryCaseId: firstCaseId,
            projectTemplateId: this.selectedTemplateId,
            primaryContactId: this.primaryContactId,
            projectContactId: this.projectContactId,
            caseIds: this.selectedCaseIds,
            items: this.templateItemsWithDates
        };
        
        console.log('Project data being sent to Apex:', projectData);
        
        // Call Apex method to create project
        createProject({ projectData: JSON.stringify(projectData) })
            .then(projectId => {
                this.showToast('Success', 'Project created successfully!', 'success');
                console.log('Project created with ID:', projectId);
                
                // Close the modal first
                this.handleClose();
                
                // Navigate to the created project record
                this[NavigationMixin.Navigate]({
                    type: 'standard__recordPage',
                    attributes: {
                        recordId: projectId,
                        actionName: 'view'
                    }
                });
            })
            .catch(error => {
                console.error('Error creating project:', error);
                this.showToast('Error', getApexErrorMessage(error, 'Failed to create project.'), 'error');
            })
            .finally(() => {
                // Reset loading state
                this.isCreatingProject = false;
            });
    }

    handleClose() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }
    
    // Modal actions removed; inline warning does not require user action
}