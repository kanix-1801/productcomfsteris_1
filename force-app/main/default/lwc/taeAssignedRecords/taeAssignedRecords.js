/**
 * @description GC-3333 - Standard related-list style component for TAE assigned Accounts or Opportunities.
 *              Preview mode shows the first page on the record tab; View All opens a full-page list with
 *              server-side name search and pagination via TAEAssignedRecordService.
 *              GC-3373 - Applies FlexiPage previewPageSize and fullPageSize after recordId is set, and
 *              forwards fullPageSize to the UrlAddressable View All screen via c__pageSize.
 */
import { LightningElement, api, wire } from 'lwc';
import { CurrentPageReference, NavigationMixin } from 'lightning/navigation';
import { getRecord, getFieldValue } from 'lightning/uiRecordApi';
import getAssignedRecordsForUi from '@salesforce/apex/TAEAssignedRecordService.getAssignedRecordsForUi';
import TAE_NAME from '@salesforce/schema/TemporaryAccessException__c.Name';

const RECORD_TYPE_ACCOUNT = 'Account';
const RECORD_TYPE_OPPORTUNITY = 'Opportunity';
const SORT_DIRECTION_ASC = 'ASC';
const SORT_DIRECTION_DESC = 'DESC';
const DEFAULT_PREVIEW_PAGE_SIZE = 10;
const DEFAULT_FULL_PAGE_SIZE = 25;
const SEARCH_DEBOUNCE_MS = 300;
const TAE_OBJECT_API_NAME = 'TemporaryAccessException__c';
const TAE_OBJECT_LABEL = 'Temporary Exception Requests';
const TAE_RECORD_FALLBACK_LABEL = 'Temporary Exception Request';

export default class TaeAssignedRecords extends NavigationMixin(LightningElement) {
    _recordId;

    @api
    get recordId() {
        return this._recordId;
    }

    set recordId(value) {
        this._recordId = value;
        this.buildTaeRecordUrl();
        if (value && !this.isFullPage) {
            this.initializePreviewMode();
            this.scheduleLoad();
        }
    }

    @api recordTypeFilter = RECORD_TYPE_ACCOUNT;

    _previewPageSize = DEFAULT_PREVIEW_PAGE_SIZE;
    _fullPageSize = DEFAULT_FULL_PAGE_SIZE;

    /**
     * @description GC-3373 - FlexiPage can assign this after recordId, so the setter
     *              reapplies the preview page size instead of keeping the default 10.
     */
    @api
    get previewPageSize() {
        return this._previewPageSize;
    }

    set previewPageSize(value) {
        this._previewPageSize = this.normalizeConfiguredPageSize(
            value,
            DEFAULT_PREVIEW_PAGE_SIZE
        );
        if (!this.isFullPage) {
            this.applyConfiguredPageSize(this._previewPageSize);
        }
    }

    /**
     * @description GC-3373 - FlexiPage full-page size. Applied on the record page instance
     *              and forwarded to View All through navigation state.
     */
    @api
    get fullPageSize() {
        return this._fullPageSize;
    }

    set fullPageSize(value) {
        this._fullPageSize = this.normalizeConfiguredPageSize(
            value,
            DEFAULT_FULL_PAGE_SIZE
        );
        if (this.isFullPage) {
            this.applyConfiguredPageSize(this._fullPageSize);
        }
    }

    records = [];
    totalRecords = 0;
    pageNumber = 1;
    pageSize = DEFAULT_PREVIEW_PAGE_SIZE;
    totalPages = 0;

    searchTerm = '';
    appliedSearchTerm = '';
    sortDirection = SORT_DIRECTION_ASC;

    isLoading = true;
    isFullPage = false;
    errorMessage = '';
    taeRecordName = '';
    taeRecordUrl = '';

    searchDebounceTimeout;
    // GC-3373 - True while a coalesced load is queued for the current tick.
    isLoadScheduled = false;

    @wire(getRecord, { recordId: '$recordId', fields: [TAE_NAME] })
    wiredTaeRecord({ data }) {
        if (data) {
            this.taeRecordName = getFieldValue(data, TAE_NAME) || '';
        } else {
            this.taeRecordName = '';
        }
        this.buildTaeRecordUrl();
    }

    disconnectedCallback() {
        if (this.searchDebounceTimeout) {
            clearTimeout(this.searchDebounceTimeout);
        }
    }

    @wire(CurrentPageReference)
    handlePageReference(pageReference) {
        const state = pageReference?.state || {};
        const isFullPageRequest = state.c__view === 'all' && !!state.c__recordId;

        if (isFullPageRequest) {
            const nextRecordId = state.c__recordId;
            const nextRecordType = state.c__recordType || this.resolvedRecordType;
            // GC-3373 - Design attributes do not reach lightning__UrlAddressable, so the
            // record page forwards FlexiPage fullPageSize through c__pageSize.
            const nextPageSize = this.normalizeConfiguredPageSize(
                state.c__pageSize,
                DEFAULT_FULL_PAGE_SIZE
            );
            const shouldInitialize =
                !this.isFullPage ||
                this._recordId !== nextRecordId ||
                this.recordTypeFilter !== nextRecordType ||
                this._fullPageSize !== nextPageSize;

            this._recordId = nextRecordId;
            this.recordTypeFilter = nextRecordType;
            this._fullPageSize = nextPageSize;
            this.isFullPage = true;
            this.buildTaeRecordUrl();

            if (shouldInitialize) {
                this.initializeFullPageMode();
                this.scheduleLoad();
            }
            return;
        }

        if (pageReference?.type === 'standard__recordPage') {
            this.isFullPage = false;
        }
    }

    initializePreviewMode() {
        this.pageNumber = 1;
        this.pageSize = this._previewPageSize;
        this.appliedSearchTerm = '';
        this.searchTerm = '';
    }

    initializeFullPageMode() {
        this.pageNumber = 1;
        this.pageSize = this._fullPageSize;
    }

    /**
     * @description GC-3373 - Returns a positive integer page size, or the fallback when
     *              FlexiPage / URL state is blank, zero, or not numeric.
     */
    normalizeConfiguredPageSize(value, fallback) {
        const parsed = parseInt(value, 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
    }

    /**
     * @description GC-3373 - Reloads the current mode when the configured page size changes.
     */
    applyConfiguredPageSize(configuredPageSize) {
        if (this.pageSize === configuredPageSize) {
            return;
        }

        this.pageSize = configuredPageSize;
        this.pageNumber = 1;

        if (this.recordId) {
            this.scheduleLoad();
        }
    }

    /**
     * @description GC-3373 - Coalesces recordId and FlexiPage size assignment in the same
     *              tick into a single Apex load.
     */
    scheduleLoad() {
        if (this.isLoadScheduled) {
            return;
        }

        this.isLoadScheduled = true;
        Promise.resolve().then(() => {
            this.isLoadScheduled = false;
            this.loadPage();
        });
    }

    async loadPage() {
        if (!this.recordId) {
            this.records = [];
            this.totalRecords = 0;
            this.totalPages = 0;
            this.isLoading = false;
            return;
        }

        this.isLoading = true;
        this.errorMessage = '';

        try {
            const result = await getAssignedRecordsForUi({
                temporaryAccessExceptionId: this.recordId,
                recordType: this.resolvedRecordType,
                searchTerm: this.appliedSearchTerm,
                pageNumber: this.pageNumber,
                pageSize: this.pageSize,
                sortDirection: this.sortDirection
            });

            this.records = (result?.records || []).map((record) => ({
                ...record,
                rowKey: record.assignedRecordId || record.id
            }));
            this.totalRecords = result?.totalRecords || 0;
            this.pageNumber = result?.pageNumber || 1;
            this.pageSize = result?.pageSize || this.pageSize;
            this.totalPages = result?.totalPages || 0;
        } catch (error) {
            this.records = [];
            this.totalRecords = 0;
            this.totalPages = 0;
            this.errorMessage = this.reduceError(error);
        } finally {
            this.isLoading = false;
        }
    }

    get resolvedRecordType() {
        const value = (this.recordTypeFilter || '').trim();
        return value.toLowerCase() === 'opportunity'
            ? RECORD_TYPE_OPPORTUNITY
            : RECORD_TYPE_ACCOUNT;
    }

    get isAccountList() {
        return this.resolvedRecordType === RECORD_TYPE_ACCOUNT;
    }

    get listIconName() {
        return this.isAccountList ? 'standard:account' : 'standard:opportunity';
    }

    get listLabel() {
        return this.isAccountList ? 'Assigned Accounts' : 'Assigned Opportunities';
    }

    get columnLabel() {
        return this.isAccountList ? 'Account' : 'Opportunity';
    }

    get listTitle() {
        if (this.totalRecords <= 0) {
            return this.listLabel;
        }

        if (!this.isFullPage && this.totalRecords > this.pageSize) {
            return `${this.listLabel} (${this.pageSize}+)`;
        }

        return `${this.listLabel} (${this.totalRecords})`;
    }

    get sortIconName() {
        return this.sortDirection === SORT_DIRECTION_DESC
            ? 'utility:arrowdown'
            : 'utility:arrowup';
    }

    get hasRecords() {
        return this.records.length > 0;
    }

    get hasError() {
        return Boolean(this.errorMessage);
    }

    get showViewAll() {
        return !this.isFullPage && this.totalRecords > 0 && !this.isLoading && !this.hasError;
    }

    get showPagination() {
        return this.isFullPage && this.totalRecords > 0 && !this.isLoading && !this.hasError;
    }

    get disablePreviousPage() {
        return this.pageNumber <= 1 || this.isLoading;
    }

    get disableNextPage() {
        return this.pageNumber >= this.totalPages || this.isLoading;
    }

    get paginationSummary() {
        if (this.totalRecords === 0) {
            return '';
        }

        const startRecord = ((this.pageNumber - 1) * this.pageSize) + 1;
        const endRecord = Math.min(this.pageNumber * this.pageSize, this.totalRecords);
        return `Showing ${startRecord}-${endRecord} of ${this.totalRecords}`;
    }

    get searchPlaceholder() {
        return this.isAccountList ? 'Search accounts...' : 'Search opportunities...';
    }

    get showSearchBar() {
        return this.isFullPage;
    }

    get pageWrapperClass() {
        return this.isFullPage ? 'full-page' : '';
    }

    get bodyWrapperClass() {
        return this.isFullPage ? 'full-page__body' : '';
    }

    get taeObjectLabel() {
        return TAE_OBJECT_LABEL;
    }

    get taeBreadcrumbLabel() {
        return this.taeRecordName || TAE_RECORD_FALLBACK_LABEL;
    }

    buildTaeRecordUrl() {
        this.taeRecordUrl = this.recordId
            ? `/lightning/r/${TAE_OBJECT_API_NAME}/${this.recordId}/view`
            : '';
    }

    handleBackToTae(event) {
        if (event) {
            event.preventDefault();
        }
        if (!this.recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId: this.recordId,
                objectApiName: TAE_OBJECT_API_NAME,
                actionName: 'view'
            }
        });
    }

    async handleRefresh() {
        await this.loadPage();
    }

    /**
     * @description GC-3373 - Opens View All and passes FlexiPage fullPageSize as c__pageSize
     *              because the UrlAddressable instance cannot read record-page design attributes.
     */
    handleViewAll(event) {
        event.preventDefault();
        this[NavigationMixin.Navigate]({
            type: 'standard__component',
            attributes: {
                componentName: 'c__taeAssignedRecords'
            },
            state: {
                c__recordId: this.recordId,
                c__recordType: this.resolvedRecordType,
                c__pageSize: String(this._fullPageSize),
                c__view: 'all'
            }
        });
    }

    handleSearchInput(event) {
        this.queueSearch(event.detail.value ?? '');
    }

    handleSearchChange(event) {
        this.queueSearch(event.detail.value ?? '');
    }

    queueSearch(value) {
        this.searchTerm = value;

        if (this.searchDebounceTimeout) {
            clearTimeout(this.searchDebounceTimeout);
        }

        this.searchDebounceTimeout = setTimeout(() => {
            this.appliedSearchTerm = value.trim();
            this.pageNumber = 1;
            this.loadPage();
        }, SEARCH_DEBOUNCE_MS);
    }

    handlePreviousPage() {
        if (this.disablePreviousPage) {
            return;
        }
        this.pageNumber -= 1;
        this.loadPage();
    }

    handleNextPage() {
        if (this.disableNextPage) {
            return;
        }
        this.pageNumber += 1;
        this.loadPage();
    }

    handleToggleSort() {
        if (!this.isFullPage || this.isLoading) {
            return;
        }

        this.sortDirection = this.sortDirection === SORT_DIRECTION_ASC
            ? SORT_DIRECTION_DESC
            : SORT_DIRECTION_ASC;
        this.pageNumber = 1;
        this.loadPage();
    }

    handleRecordClick(event) {
        event.preventDefault();
        const recordId = event.currentTarget.dataset.id;
        if (!recordId) {
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__recordPage',
            attributes: {
                recordId,
                actionName: 'view'
            }
        });
    }

    reduceError(error) {
        if (Array.isArray(error?.body)) {
            return error.body.map((item) => item.message).join(', ');
        }
        if (typeof error?.body?.message === 'string') {
            return error.body.message;
        }
        if (typeof error?.message === 'string') {
            return error.message;
        }
        return 'Unable to load assigned records.';
    }
}