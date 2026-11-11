import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getAssignmentTypeLabel from '@salesforce/apex/LsOverlayAssignmentController.getAssignmentTypeLabel';
import searchTerritories from '@salesforce/apex/LsOverlayAssignmentController.searchTerritories';
import searchAccounts from '@salesforce/apex/LsOverlayAssignmentController.searchAccounts';
import retrieveAccounts from '@salesforce/apex/LsOverlayAssignmentController.retrieveAccounts';
import searchOverlayUsers from '@salesforce/apex/LsOverlayAssignmentController.searchOverlayUsers';
import getAssignmentSummary from '@salesforce/apex/LsOverlayAssignmentController.getAssignmentSummary';
import submitOverlayAssignments from '@salesforce/apex/LsOverlayAssignmentController.submitOverlayAssignments';

/**
 * @author PWC Developer
 * @date 2026/11/04
 *
 * @description
 * GCL-79 - Life Sciences Overlay Assignment wizard.
 *
 * Supports the end-to-end Life Sciences Sales Overlay flow:
 * 1. Select one or more territories/Accounts.
 * 2. Review the Customer accounts for the selected search criteria.
 * GPO, IDN, and Address are not shown. Submit adds the user to the selected Customer and its child accounts.
 * 3. Select one or more overlay users.
 * 4. Review summary and confirm assignment creation.
 * Only Account access is extended on submit.
 */
export default class LsOverlayAssignment extends LightningElement {
    @track showModal = true;
    @track step = 1;
    @track isLoading = false;
    @track territorySearchKey = '';
    @track territoryData = [];
    @track selectedTerritoryIds = [];
    @track selectedTerritoryRecords = [];
    @track showRetrievePrompt = false;
    @track accountSearchKey = '';
    @track accountType = '';
    @track accountSearchData = [];
    @track allAccountSearchData = [];
    @track hasAccountSearchResultsBeenDisplayed = false;
    @track selectedSearchAccountIds = [];
    @track selectedSearchAccountRecords = [];
    @track accountData = [];
    @track allAccountData = [];
    @track selectedAccountIds = [];
    @track deselectedAccountIds = [];
    @track userSearchKey = '';
    @track userData = [];
    @track selectedUserIds = [];
    @track selectedUserRecords = [];
    @track summaryData = [];
    @track selectedSummaryTerritory;
    @track selectedSummaryAccounts = [];
    @track showTerritoryAccountsPopup = false;
    @track isTerritorySearchCollapsed = false;
    @track isSelectedTerritoriesCollapsed = false;
    @track isAccountSearchCollapsed = false;
    @track isSelectedAccountsCollapsed = false;

    accountSearchPageNumber = 1;
    accountSearchPageSize = 25;
    accountSearchTotalPages = 1;
    accountSearchTotalRecords = 0;
    accountPageNumber = 1;
    accountPageSize = 25;
    accountTotalPages = 1;
    accountTotalRecords = 0;

    // Mirrors LsOverlayAssignmentService.ASSIGNMENT_TYPE_SALESFORCE_ASSIGNED. Loaded from Apex
    // in checkAccess() so this label can never drift from the value submit() actually writes.
    assignmentTypeLabel = '';

    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    territoryColumns = [
        { label: 'Territory ID', fieldName: 'territoryId' },
        { label: 'Territory Description', fieldName: 'territoryDescription' }
    ];

    accountSearchColumns = [
        { label: 'Account Name', fieldName: 'accountName' },
        { label: 'Account Number', fieldName: 'accountNumber' },
        { label: 'Account Type', fieldName: 'accountType' }
    ];

    accountColumnsBase = [
        { label: 'Account Name', fieldName: 'accountName' },
        { label: 'Account Number', fieldName: 'accountNumber' },
        { label: 'Account Type', fieldName: 'accountType' }
    ];

    accountTerritoryColumns = [
        { label: 'Territory ID', fieldName: 'territoryId', sortable: true },
        { label: 'Territory Description', fieldName: 'territoryDescription', sortable: true }
    ];

    accountTypeOptions = [
        { label: '--None--', value: '' },
        { label: 'Customer', value: 'Customer' }
    ];

    /**
     * GCL-79 - Loads the assignment-type label used on the confirmation step from Apex,
     * so it always matches what submit() will write.
     */
    connectedCallback() {
        this.loadAssignmentTypeLabel();
    }

    async loadAssignmentTypeLabel() {
        try {
            this.assignmentTypeLabel = await getAssignmentTypeLabel();
        } catch (error) {
            this.showError(error);
        }
    }

    get isStepOne() { return this.step === 1; }
    get isStepTwo() { return this.step === 2; }
    get isStepThree() { return this.step === 3; }
    get isStepFour() { return this.step === 4; }
    get isRetrieveDisabled() { return !this.hasSearchCriteria; }
    get isSearchTerritoriesDisabled() { return !this.territorySearchKey || this.territorySearchKey.trim().length === 0; }
    get isSearchAccountsDisabled() {
        return (!this.accountSearchKey || this.accountSearchKey.trim().length === 0) && !this.accountType;
    }
    get hasSearchCriteria() {
        return this.selectedTerritoryIds.length > 0 || this.selectedSearchAccountIds.length > 0;
    }
    get isNextDisabled() { return this.selectedAccountCount === 0; }
    get selectedAccountCount() { return this.getSelectedAccountIdsForSubmit().length; }
    get isSubmitDisabled() { return this.selectedUserIds.length === 0; }
    get cardTitle() {
        if (this.isStepOne) { return 'Select Territories / Accounts'; }
        if (this.isStepTwo) { return 'Accounts For Selected Search Criteria'; }
        if (this.isStepThree) { return 'Select Overlay Users'; }
        if (this.isStepFour) { return 'Review Overlay Assignment Summary'; }
        return 'Life Sciences Sales Overlay';
    }
    get territorySearchIconName() { return this.isTerritorySearchCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get selectedTerritoriesIconName() { return this.isSelectedTerritoriesCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get accountSearchIconName() { return this.isAccountSearchCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get selectedAccountsIconName() { return this.isSelectedAccountsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get hasTerritoryResults() { return this.territoryData.length > 0; }
    get hasSelectedTerritories() { return this.selectedTerritoryRecords.length > 0; }
    get hasAccountSearchResults() { return this.accountSearchData.length > 0; }
    get hasSelectedSearchAccounts() { return this.selectedSearchAccountRecords.length > 0; }
    get isTerritoryBasedSearch() {
        return this.selectedTerritoryIds.length > 0;
    }
    get accountColumns() {
        return this.isTerritoryBasedSearch
            ? [...this.accountColumnsBase, ...this.accountTerritoryColumns]
            : [...this.accountColumnsBase];
    }
    get accountTableKey() {
        return this.isTerritoryBasedSearch ? 'territory-search-table' : 'account-search-table';
    }
    get accountSearchPageSizeValue() { return String(this.accountSearchPageSize); }
    get accountPageSizeValue() { return String(this.accountPageSize); }
    get disablePreviousAccountSearchPage() { return this.accountSearchPageNumber <= 1; }
    get disableNextAccountSearchPage() { return this.accountSearchPageNumber >= this.accountSearchTotalPages; }
    get disablePreviousAccountPage() { return this.accountPageNumber <= 1; }
    get disableNextAccountPage() { return this.accountPageNumber >= this.accountTotalPages; }

    // Closes the wizard without saving anything.
    closeModal() {
        this.showModal = false;
    }

    // Step navigation helpers.
    goToStepOne() { this.step = 1; }
    goToStepTwo() { this.step = 2; }
    goToStepThree() { this.step = 3; }
    goBackToUsersFromSummary() { this.step = 3; }

    // Input change handlers for Step 1 search fields.
    handleTerritorySearchChange(event) { this.territorySearchKey = event.target.value; }
    handleAccountSearchChange(event) { this.accountSearchKey = event.target.value; }
    handleAccountTypeChange(event) { this.accountType = event.detail.value; }
    handleUserSearchChange(event) { this.userSearchKey = event.target.value; }

    handleTerritoryEnterKey(event) {
        if (event.key === 'Enter') {
            this.handleSearchTerritories();
        }
    }

    handleSearchAccountsEnter(event) {
        if (event.key === 'Enter') {
            this.handleSearchAccounts();
        }
    }

    handleSearchUsersEnter(event) {
        if (event.key === 'Enter') {
            this.handleSearchUsers();
        }
    }

    /**
     * GCL-79 - Searches Life Sciences territories by Territory ID, Name, or Description.
     */
    async handleSearchTerritories() {
        if (this.isSearchTerritoriesDisabled) {
            return;
        }
        try {
            this.isLoading = true;
            this.territoryData = await searchTerritories({ searchKey: this.territorySearchKey }) || [];
            this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);
            if (this.territoryData.length === 0) {
                this.showToast('', 'No matching Life Sciences territories found.', 'error');
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Tracks which territory rows are selected across repeated searches, and clears any
     * already-retrieved Step 1 account results when the selected territories change.
     */
    handleTerritorySelection(event) {
        const previousIds = [...this.selectedTerritoryIds];
        const selectedRows = event.detail.selectedRows;
        const visibleIds = this.territoryData.map(row => row.territoryId);
        const selectedVisibleIds = selectedRows.map(row => row.territoryId);
        this.selectedTerritoryRecords = this.selectedTerritoryRecords.filter(record => {
            const isVisible = visibleIds.includes(record.territoryId);
            return !isVisible || selectedVisibleIds.includes(record.territoryId);
        });
        selectedRows.forEach(row => {
            if (!this.selectedTerritoryRecords.some(record => record.territoryId === row.territoryId)) {
                this.selectedTerritoryRecords = [...this.selectedTerritoryRecords, row];
            }
        });
        this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);
        if (previousIds.length !== this.selectedTerritoryIds.length || previousIds.some(id => !this.selectedTerritoryIds.includes(id))) {
            this.clearAccountSearchResults(false);
        }
    }

    // Removes a territory pill from the selected-territories list.
    handleRemoveSelectedTerritory(event) {
        const territoryId = event.detail.name;
        this.selectedTerritoryRecords = this.selectedTerritoryRecords.filter(record => record.territoryId !== territoryId);
        this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);
        this.clearAccountSearchResults(false);
    }

    /**
     * GCL-79 - Searches Life Sciences accounts by Name/Number and/or Type, optionally
     * scoped to the already-selected territories.
     */
    async handleSearchAccounts() {
        if (this.isSearchAccountsDisabled) {
            return;
        }
        try {
            this.isLoading = true;
            const result = await searchAccounts({
                accountSearchKey: this.accountSearchKey,
                accountType: this.accountType,
                territoryIds: this.selectedTerritoryIds
            });
            this.allAccountSearchData = result || [];
            this.accountSearchTotalRecords = this.allAccountSearchData.length;
            this.accountSearchTotalPages = Math.max(Math.ceil(this.accountSearchTotalRecords / this.accountSearchPageSize), 1);
            this.accountSearchPageNumber = 1;
            this.hasAccountSearchResultsBeenDisplayed = this.accountSearchTotalRecords > 0;
            if (this.accountSearchTotalRecords === 0) {
                this.showToast('', 'No matching Life Sciences accounts found.', 'error');
            }
            this.refreshAccountSearchPage();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Clears the Step 1 account search results and, optionally, the search inputs.
    clearAccountSearchResults(clearInputs) {
        if (clearInputs) {
            this.accountSearchKey = '';
            this.accountType = '';
        }
        this.accountSearchData = [];
        this.allAccountSearchData = [];
        this.hasAccountSearchResultsBeenDisplayed = false;
        this.selectedSearchAccountIds = [];
        this.selectedSearchAccountRecords = [];
        this.accountSearchPageNumber = 1;
        this.accountSearchTotalPages = 1;
        this.accountSearchTotalRecords = 0;
    }

    // Slices allAccountSearchData into the current client-side page for Step 1's results table.
    refreshAccountSearchPage() {
        const startIndex = (this.accountSearchPageNumber - 1) * this.accountSearchPageSize;
        this.accountSearchData = this.allAccountSearchData.slice(startIndex, startIndex + this.accountSearchPageSize);
        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    // Tracks which Step 1 account search rows are selected across repeated searches/pages.
    handleAccountSearchSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleIds = this.accountSearchData.map(row => row.accountId);
        const selectedVisibleIds = selectedRows.map(row => row.accountId);
        this.selectedSearchAccountRecords = this.selectedSearchAccountRecords.filter(record => {
            return !visibleIds.includes(record.accountId) || selectedVisibleIds.includes(record.accountId);
        });
        selectedRows.forEach(row => {
            if (!this.selectedSearchAccountRecords.some(record => record.accountId === row.accountId)) {
                this.selectedSearchAccountRecords = [...this.selectedSearchAccountRecords, row];
            }
        });
        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    // Removes an account pill from the selected-accounts list on Step 1.
    handleRemoveSelectedSearchAccount(event) {
        const accountId = event.detail.name;
        this.selectedSearchAccountRecords = this.selectedSearchAccountRecords.filter(record => record.accountId !== accountId);
        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    // Client-side pagination controls for Step 1's account search results.
    handlePreviousAccountSearchPage() {
        if (this.accountSearchPageNumber > 1) {
            this.accountSearchPageNumber -= 1;
            this.refreshAccountSearchPage();
        }
    }

    handleNextAccountSearchPage() {
        if (this.accountSearchPageNumber < this.accountSearchTotalPages) {
            this.accountSearchPageNumber += 1;
            this.refreshAccountSearchPage();
        }
    }

    handleAccountSearchPageSizeChange(event) {
        this.accountSearchPageSize = Number(event.detail.value);
        this.accountSearchTotalPages = Math.max(Math.ceil(this.accountSearchTotalRecords / this.accountSearchPageSize), 1);
        this.accountSearchPageNumber = 1;
        this.refreshAccountSearchPage();
    }

    // Expand/collapse toggles for the Step 1 collapsible sections.
    toggleTerritorySearchSection() { this.isTerritorySearchCollapsed = !this.isTerritorySearchCollapsed; }
    toggleSelectedTerritoriesSection() { this.isSelectedTerritoriesCollapsed = !this.isSelectedTerritoriesCollapsed; }
    toggleAccountSearchSection() { this.isAccountSearchCollapsed = !this.isAccountSearchCollapsed; }
    toggleSelectedAccountsSection() { this.isSelectedAccountsCollapsed = !this.isSelectedAccountsCollapsed; }

    // Clears every Step 1 search/selection so the user can start over.
    handleResetStepOne() {
        this.territorySearchKey = '';
        this.territoryData = [];
        this.selectedTerritoryIds = [];
        this.selectedTerritoryRecords = [];
        this.showRetrievePrompt = false;
        this.clearAccountSearchResults(true);
    }

    /**
     * Step 1 "Next" - Loads Step 2 accounts, then asks the user to confirm before moving on.
     */
    async handleRetrieveAccountsClick() {
        await this.loadAccountData();
        if (this.accountTotalRecords === 0) {
            this.showToast('', 'No matching accounts found for the selected search criteria.', 'error');
        } else {
            this.showRetrievePrompt = true;
        }
    }

    // "No" on the confirm-selection prompt: go back to Step 1 to change the search.
    handleSelectMoreTerritories() {
        this.showRetrievePrompt = false;
        this.step = 1;
    }

    // "Yes" on the confirm-selection prompt: proceed to Step 2 with the loaded accounts.
    handleConfirmRetrieveAccounts() {
        this.showRetrievePrompt = false;
        this.step = 2;
    }

    /**
     * GCL-79 - Loads address-level accounts for the selected search criteria and
     * resets per-page selection so every row starts selected by default.
     */
    async loadAccountData() {
        try {
            this.isLoading = true;
            const result = await retrieveAccounts({
                territoryIds: this.selectedTerritoryIds,
                accountSearchKey: this.accountSearchKey,
                accountType: this.accountType,
                selectedSearchAccountIds: this.selectedSearchAccountIds
            });
            this.allAccountData = result || [];
            this.accountTotalRecords = this.allAccountData.length;
            this.accountTotalPages = Math.max(Math.ceil(this.accountTotalRecords / this.accountPageSize), 1);
            this.accountPageNumber = 1;
            this.deselectedAccountIds = [];
            this.refreshAccountPage();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // GCL-79 - Slices allAccountData into the current client-side page for Step 2, applying the
    // "selected by default unless explicitly deselected" rule to each page as it is shown.
    refreshAccountPage() {
        const startIndex = (this.accountPageNumber - 1) * this.accountPageSize;
        this.accountData = this.allAccountData.slice(startIndex, startIndex + this.accountPageSize);
        this.selectedAccountIds = this.accountData
            .filter(row => !this.deselectedAccountIds.includes(row.accountId))
            .map(row => row.accountId);
    }

    /**
     * GCL-79 - Tracks explicit deselection of Step 2 accounts across pages. Accounts start
     * selected; only rows the user unchecks are added to deselectedAccountIds.
     */
    handleAccountSelection(event) {
        const visibleIds = this.accountData.map(row => row.accountId);
        const selectedVisibleIds = event.detail.selectedRows.map(row => row.accountId);
        visibleIds.forEach(accountId => {
            const isSelected = selectedVisibleIds.includes(accountId);
            const isTracked = this.deselectedAccountIds.includes(accountId);
            if (!isSelected && !isTracked) {
                this.deselectedAccountIds = [...this.deselectedAccountIds, accountId];
            }
            if (isSelected && isTracked) {
                this.deselectedAccountIds = this.deselectedAccountIds.filter(id => id !== accountId);
            }
        });
        this.selectedAccountIds = selectedVisibleIds;
    }

    // Client-side pagination controls for Step 2's account table.
    handlePreviousAccountPage() {
        if (this.accountPageNumber > 1) {
            this.accountPageNumber -= 1;
            this.refreshAccountPage();
        }
    }

    handleNextAccountPage() {
        if (this.accountPageNumber < this.accountTotalPages) {
            this.accountPageNumber += 1;
            this.refreshAccountPage();
        }
    }

    handleAccountPageSizeChange(event) {
        this.accountPageSize = Number(event.detail.value);
        this.accountTotalPages = Math.max(Math.ceil(this.accountTotalRecords / this.accountPageSize), 1);
        this.accountPageNumber = 1;
        this.refreshAccountPage();
    }

    /**
     * GCL-79 - Searches active Life Sciences Sales users by name or email.
     */
    async handleSearchUsers() {
        try {
            this.isLoading = true;
            const result = await searchOverlayUsers({ searchKey: this.userSearchKey });
            this.userData = (result || []).map(user => ({
                ...user,
                isSelected: this.selectedUserIds.includes(user.userId),
                showTooltip: false
            }));
            if (this.userData.length === 0) {
                this.showToast('', 'No matching Life Sciences users found.', 'error');
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // GCL-79 - Adds or removes a user from the overlay-user selection.
    handleUserCheckboxChange(event) {
        const userId = event.target.dataset.userid;
        if (event.target.checked) {
            const selectedUser = this.userData.find(user => user.userId === userId);
            if (selectedUser && !this.selectedUserRecords.some(user => user.userId === userId)) {
                this.selectedUserRecords = [...this.selectedUserRecords, selectedUser];
            }
        } else {
            this.selectedUserRecords = this.selectedUserRecords.filter(user => user.userId !== userId);
        }
        this.selectedUserIds = this.selectedUserRecords.map(user => user.userId);
        this.userData = this.userData.map(user => ({
            ...user,
            isSelected: this.selectedUserIds.includes(user.userId)
        }));
    }

    // Removes a user pill from the selected-overlay-users list.
    handleRemoveSelectedUser(event) {
        const userId = event.detail.name;
        this.selectedUserRecords = this.selectedUserRecords.filter(user => user.userId !== userId);
        this.selectedUserIds = this.selectedUserRecords.map(user => user.userId);
        this.userData = this.userData.map(user => ({
            ...user,
            isSelected: this.selectedUserIds.includes(user.userId)
        }));
    }

    // GCL-79 - Shows the Country/Manager detail tooltip for the hovered user row.
    handleUserMouseOver(event) {
        const userId = event.currentTarget.dataset.userid;
        this.userData = this.userData.map(user => ({ ...user, showTooltip: user.userId === userId }));
    }

    handleUserMouseOut() {
        this.userData = this.userData.map(user => ({ ...user, showTooltip: false }));
    }

    /**
     * GCL-79 - Loads the confirmation summary for the selected territories/accounts/users.
     */
    async goToSummary() {
        try {
            this.isLoading = true;
            const result = await getAssignmentSummary({
                territoryIds: this.selectedTerritoryIds,
                selectedAccountIds: this.getSelectedAccountIdsForSubmit()
            });
            const selectedUsersText = this.selectedUserRecords.map(user => user.userName).join(', ');
            this.summaryData = (result || []).map(row => ({
                ...row,
                accountCount: row.selectedAccounts ? row.selectedAccounts.length : 0,
                selectedUsersText
            }));
            this.step = 4;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // GCL-79 - Final selected-account list for summary/submit: every loaded account except
    // the ones explicitly deselected on Step 2.
    getSelectedAccountIdsForSubmit() {
        return this.allAccountData
            .filter(row => !this.deselectedAccountIds.includes(row.accountId))
            .map(row => row.accountId);
    }

    // Opens the popup listing every account under a summary row's territory.
    handleTerritorySummaryClick(event) {
        const territoryId = event.currentTarget.dataset.territoryid;
        const selectedTerritory = this.summaryData.find(row => row.territoryId === territoryId);
        if (selectedTerritory) {
            this.selectedSummaryTerritory = selectedTerritory;
            this.selectedSummaryAccounts = selectedTerritory.selectedAccounts;
            this.showTerritoryAccountsPopup = true;
        }
    }

    closeTerritoryAccountsPopup() {
        this.showTerritoryAccountsPopup = false;
        this.selectedSummaryTerritory = null;
        this.selectedSummaryAccounts = [];
    }

    /**
     * GCL-79 - Confirm and Submit: creates the Account Team overlay assignments and closes
     * the wizard on success. Cancel (goBackToUsersFromSummary) leaves Step 4 without saving.
     */
    async handleConfirmSubmit() {
        try {
            this.isLoading = true;
            await submitOverlayAssignments({
                territoryIds: this.selectedTerritoryIds,
                selectedAccountIds: this.getSelectedAccountIdsForSubmit(),
                userIds: this.selectedUserIds
            });
            this.showToast('Success', 'Life Sciences overlay assignments created.', 'success');
            this.closeModal();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    // Shows a toast message.
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Shows a server/Apex error message, falling back to a generic message when none is provided.
    showError(error) {
        const message = error && error.body && error.body.message
            ? error.body.message
            : 'Unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}