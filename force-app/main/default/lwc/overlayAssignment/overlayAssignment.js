import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import searchTerritories from '@salesforce/apex/OverlayAssignmentController.searchTerritories';
import searchAccounts from '@salesforce/apex/OverlayAssignmentController.searchAccounts';
import retrieveAccounts from '@salesforce/apex/OverlayAssignmentController.retrieveAccounts';
import searchOverlayUsers from '@salesforce/apex/OverlayAssignmentController.searchOverlayUsers';
import submitOverlayAssignments from '@salesforce/apex/OverlayAssignmentController.submitOverlayAssignments';
import getAssignmentSummary from '@salesforce/apex/OverlayAssignmentController.getAssignmentSummary';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

/**
 * @author PWC Developer
 * @date 2026/06/09
 * 
 * @description 
 * Overlay Assignment wizard.
 *
 * Supports the end-to-end Sales Overlay flow:
 * 1. Select one or more territories/Accounts.
 * 2. Review accounts associated to selected search criteria.
 * 3. Select one or more overlay users.
 * 4. Review summary and confirm assignment creation.
 */
export default class OverlayAssignment extends NavigationMixin(LightningElement) {
    // Controls whether the main modal is displayed on the Lightning App Page.
    @track showModal = true;

    // Wizard state and loading indicator.
    @track step = 1;
    @track isLoading = false;

    // Territory search results and selected territory state.
    @track territorySearchKey = '';
    @track territoryData = [];
    @track selectedTerritoryIds = [];

    // Master selected territory list used to preserve selected territories across multiple searches.
    @track selectedTerritoryRecords = [];

    // Controls confirmation prompt shown before retrieving accounts.
    @track showRetrievePrompt = false;

    // Current page of account rows and full client-side account dataset.
    @track accountSearchKey = '';
    @track accountType = '';
    @track accountSearchData = [];
    @track allAccountSearchData = [];
    @track hasAccountSearchResultsBeenDisplayed = false;
    @track selectedSearchAccountIds = [];
    @track selectedSearchAccountRecords = [];

    //Data for client-side pagination for account search screen
    accountSearchPageNumber = 1;
    accountSearchPageSize = 25;
    accountSearchTotalPages = 1;
    accountSearchTotalRecords = 0;

    // Current page of account rows and full client-side account dataset.
    @track accountData = [];
    @track allAccountData = [];

    // Datatable selected account IDs for the current page and global deselected account IDs across all pages.
    @track selectedAccountIds = [];
    @track deselectedAccountIds = [];

    //Data for client-side pagination for Retrieve accounts screen
    accountPageNumber = 1;
    accountPageSize = 25;
    accountTotalPages = 1;
    accountTotalRecords = 0;

    //Page size options dropdown
    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    //User search details and search restuls
    @track userSearchKey = '';
    @track userData = [];
    @track selectedUserIds = [];
    @track selectedUserRecords = [];
    @track hoveredUserId;

    //Summary of overlay assignments
    @track summaryData = [];
    @track selectedSummaryTerritory;
    @track selectedSummaryAccounts = [];
    @track showTerritoryAccountsPopup = false;

    //Collapsible search sections on step 1
    @track isTerritorySearchCollapsed = false;
    @track isSelectedTerritoriesCollapsed = false;
    @track isAccountSearchCollapsed = false;
    @track isSelectedAccountsCollapsed = false;

    // Territory table columns.
    territoryColumns = [
        { label: 'Territory ID', fieldName: 'territoryId' },
        { label: 'Territory Description', fieldName: 'territoryDescription' }
    ];

    // Account search table columns.
    accountSearchColumns = [
        { label: 'Account Name', fieldName: 'accountName' },
        { label: 'Account Number', fieldName: 'accountNumber' },
        { label: 'Account Type', fieldName: 'accountType' }
        // { label: 'Territory ID', fieldName: 'territoryId' },
        // { label: 'Territory Description', fieldName: 'territoryDescription' }
    ];

    // Account data table columns (Step 2) - territory columns shown only for territory-based search.
    accountTerritoryColumns = [
        { label: 'Territory ID', fieldName: 'territoryId', sortable: true },
        { label: 'Territory Description', fieldName: 'territoryDescription', sortable: true }
    ];

    accountColumnsBase = [
        { label: 'Account Name', fieldName: 'accountName' },
        { label: 'Account Number', fieldName: 'accountNumber' },
        { label: 'Account Type', fieldName: 'accountType' }
        // { label: 'TAS Address ID', fieldName: 'tasAddressId' }
    ];

    //Account type options.
    accountTypeOptions = [
        { label: '--None--', value: '' },
        { label: 'Customer', value: 'Customer' },
        { label: 'IDN', value: 'IDN' },
        { label: 'GPO', value: 'GPO' }
    ];

    // Step visibility helpers used by the template.
    get isStepOne() { return this.step === 1; }
    get isStepTwo() { return this.step === 2; }
    get isStepThree() { return this.step === 3; }
    get isStepFour() { return this.step === 4; }

    // Disable account retrieval until any search criteria is entered and either account or territory is selected
    get isRetrieveDisabled() { return !this.hasSearchCriteria; }

    // Disable search territory button when no search key is entered.
    get isSearchTerritoriesDisabled() { return !this.territorySearchKey || this.territorySearchKey.trim().length === 0; }

    // Disable search accounts button when no search key is entered or no account type is selected.
    get isSearchAccountsDisabled() {
        return (!this.accountSearchKey || this.accountSearchKey.trim().length === 0) && !this.accountType;
    }

    // confirm is search criteria exists based on the combination of search keys
    get hasSearchCriteria() {
        return this.selectedTerritoryIds.length > 0
            || this.selectedSearchAccountIds.length > 0
    }

    // Disable step navigation when no accounts remain selected.
    get isNextDisabled() { return this.selectedAccountCount === 0; }

    // Because all accounts are selected by default, selected count is total minus explicit deselections.
    get selectedAccountCount() { return this.getSelectedAccountIdsForSubmit().length; }

    // Disable final review/submit until at least one overlay user is selected.
    get isSubmitDisabled() { return this.selectedUserIds.length === 0; }

    // Dynamic card title based on the current wizard step.
    get cardTitle() {
        if (this.isStepOne) { return 'Select Territories / Accounts'; }
        if (this.isStepTwo) { return 'Accounts For Selected Search Criteria'; }
        if (this.isStepThree) { return 'Select Overlay Users'; }
        if (this.isStepFour) { return 'Review Overlay Assignment Summary'; }
        return 'Overlay Assignment';
    }

    // Show chevron icons for collapsible sections
    get territorySearchIconName() { return this.isTerritorySearchCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get selectedTerritoriesIconName() { return this.isSelectedTerritoriesCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get accountSearchIconName() { return this.isAccountSearchCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }
    get selectedAccountsIconName() { return this.isSelectedAccountsCollapsed ? 'utility:chevronright' : 'utility:chevrondown'; }

    //Territory results are present and territory is selected
    get hasTerritoryResults() { return this.territoryData.length > 0; }
    get hasSelectedTerritories() { return this.selectedTerritoryRecords.length > 0; }

    //Account results are present and accounts are selected
    get hasAccountSearchResults() { return this.accountSearchData.length > 0; }
    get hasSelectedSearchAccounts() { return this.selectedSearchAccountRecords.length > 0; }

    //Set the pagination values for accoutn search screen
    get accountSearchPageSizeValue() { return String(this.accountSearchPageSize); }
    get accountPageSizeValue() { return String(this.accountPageSize); }

    get isTerritoryBasedSearch() {
        return this.selectedTerritoryIds.length > 0;
    }

    get accountColumns() {
        return this.isTerritoryBasedSearch
            ? [...this.accountColumnsBase,...this.accountTerritoryColumns,]
            : [...this.accountColumnsBase];
    }

    get accountTableKey() {
        return this.isTerritoryBasedSearch ? 'territory-search-table' : 'account-search-table';
    }

    /**
     * Closes the modal and returns the user to the previous browser history entry.
     */
    closeModal() {
        this.showModal = false;
        window.history.back();
    }

    //Navigation between each screens/steps
    goToStepOne() { this.step = 1; }
    goToStepTwo() { this.step = 2; }
    goToStepThree() { this.step = 3; }
    goBackToUsersFromSummary() { this.step = 3; }

    //Handle terriory search
    handleTerritorySearchChange(event) { this.territorySearchKey = event.target.value; }

    handleTerritoryEnterKey(event) {
            if(event.key === 'Enter'){
                this.handleSearchTerritories();
            }
    }
    async handleSearchTerritories() {
        if (this.isSearchTerritoriesDisabled) {
            return;
        }

        try {
            this.isLoading = true;
            this.territoryData = await searchTerritories({ searchKey: this.territorySearchKey });
            this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);
            if (this.territoryData.length == 0) {
                this.showToast('', 'No matching territories found. Please try a different search!', 'error');
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    //Set the selected the territory rows and reset account search results if the results were already shown
    handleTerritorySelection(event) {
        const previouslySelectedTerritoryIds = [...this.selectedTerritoryIds];
        const selectedRows = event.detail.selectedRows;
        const visibleTerritoryIds = this.territoryData.map(row => row.territoryId);
        const selectedVisibleTerritoryIds = selectedRows.map(row => row.territoryId);

        this.selectedTerritoryRecords = this.selectedTerritoryRecords.filter(record => {
            const isVisible = visibleTerritoryIds.includes(record.territoryId);
            const isStillSelected = selectedVisibleTerritoryIds.includes(record.territoryId);
            return !isVisible || isStillSelected;
        });

        selectedRows.forEach(row => {
            const alreadyExists = this.selectedTerritoryRecords.some(record => record.territoryId === row.territoryId);
            if (!alreadyExists) {
                this.selectedTerritoryRecords = [...this.selectedTerritoryRecords, row];
            }
        });

        this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);

        if (this.haveSelectedTerritoriesChanged(previouslySelectedTerritoryIds, this.selectedTerritoryIds)) {
            this.resetAccountSearchAfterTerritoryChange();
        }
    }


    haveSelectedTerritoriesChanged(previousIds, currentIds) {
        if (previousIds.length !== currentIds.length) {
            return true;
        }

        return previousIds.some(id => !currentIds.includes(id));
    }

    //Remove the selected the territory rows and reset account search results if the results were already shown
    handleRemoveSelectedTerritory(event) {
        const territoryIdToRemove = event.detail.name;
        this.selectedTerritoryRecords = this.selectedTerritoryRecords.filter(record => record.territoryId !== territoryIdToRemove);
        this.selectedTerritoryIds = this.selectedTerritoryRecords.map(record => record.territoryId);
        this.resetAccountSearchAfterTerritoryChange();
    }

    //Handle account name/number or Type search
    handleAccountSearchChange(event) { this.accountSearchKey = event.target.value; }
    handleAccountTypeChange(event) { this.accountType = event.detail.value; }

    handleSearchAccountsEnter(event) {
            if(event.key === 'Enter'){
                this.handleSearchAccounts();
            }
    }

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
            if (this.accountSearchTotalRecords == 0) {
                this.showToast('', 'No matching accounts found for the selected search criteria. Try different Territory or Account', 'error');
            }
            this.refreshAccountSearchPage();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    //Clear account search results
    clearAccountSearchSelection() {
        this.clearAccountSearchResults(false);
    }

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
        this.selectedSearchAccountPageIds = [];
        this.accountSearchPageNumber = 1;
        this.accountSearchTotalPages = 1;
        this.accountSearchTotalRecords = 0;
    }

    resetAccountSearchAfterTerritoryChange() {
        if (this.hasAccountSearchResultsBeenDisplayed) {
            this.clearAccountSearchResults(false);
        }
    }

    //Refresh account search pagination
    refreshAccountSearchPage() {
        const startIndex = (this.accountSearchPageNumber - 1) * this.accountSearchPageSize;
        const endIndex = Math.min(startIndex + this.accountSearchPageSize, this.accountSearchTotalRecords);
        this.accountSearchData = this.allAccountSearchData.slice(startIndex, endIndex);
        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    //Set the selected the account rows
    handleAccountSearchSelection(event) {
        const selectedRows = event.detail.selectedRows;
        const visibleAccountIds = this.accountSearchData.map(row => row.accountId);
        const selectedVisibleAccountIds = selectedRows.map(row => row.accountId);

        this.selectedSearchAccountRecords = this.selectedSearchAccountRecords.filter(record => {
            const isVisible = visibleAccountIds.includes(record.accountId);
            const isStillSelected = selectedVisibleAccountIds.includes(record.accountId);
            return !isVisible || isStillSelected;
        });

        selectedRows.forEach(row => {
            const alreadyExists = this.selectedSearchAccountRecords.some(record => record.accountId === row.accountId);
            if (!alreadyExists) {
                this.selectedSearchAccountRecords = [...this.selectedSearchAccountRecords, row];
            }
        });

        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    //Remove the selected the account rows
    handleRemoveSelectedSearchAccount(event) {
        const accountIdToRemove = event.detail.name;
        this.selectedSearchAccountRecords = this.selectedSearchAccountRecords.filter(record => record.accountId !== accountIdToRemove);
        this.selectedSearchAccountIds = this.selectedSearchAccountRecords.map(record => record.accountId);
    }

    //Handle pagination data
    handlePreviousAccountSearchPage() {
        if (this.accountSearchPageNumber > 1) {
            this.accountSearchPageNumber--;
            this.refreshAccountSearchPage();
        }
    }

    handleNextAccountSearchPage() {
        if (this.accountSearchPageNumber < this.accountSearchTotalPages) {
            this.accountSearchPageNumber++;
            this.refreshAccountSearchPage();
        }
    }

    handleAccountSearchPageSizeChange(event) {
        this.accountSearchPageSize = Number(event.detail.value);
        this.accountSearchTotalPages = Math.max(Math.ceil(this.accountSearchTotalRecords / this.accountSearchPageSize), 1);
        this.accountSearchPageNumber = 1;
        this.refreshAccountSearchPage();
    }

    get disablePreviousAccountSearchPage() { return this.accountSearchPageNumber <= 1; }
    get disableNextAccountSearchPage() { return this.accountSearchPageNumber >= this.accountSearchTotalPages; }


    refreshAccountPage() {
        const startIndex = (this.accountPageNumber - 1) * this.accountPageSize;
        const endIndex = Math.min(startIndex + this.accountPageSize, this.accountTotalRecords);
        this.accountData = this.allAccountData.slice(startIndex, endIndex);
        this.selectedAccountIds = this.accountData
            .filter(row => !this.deselectedAccountIds.includes(row.accountId))
            .map(row => row.accountId);
    }

    //Expand or collapse the search sections on Step 1 based on the user click of chevron icon
    toggleTerritorySearchSection() { this.isTerritorySearchCollapsed = !this.isTerritorySearchCollapsed; }
    toggleSelectedTerritoriesSection() { this.isSelectedTerritoriesCollapsed = !this.isSelectedTerritoriesCollapsed; }
    toggleAccountSearchSection() { this.isAccountSearchCollapsed = !this.isAccountSearchCollapsed; }
    toggleSelectedAccountsSection() { this.isSelectedAccountsCollapsed = !this.isSelectedAccountsCollapsed; }

    //Reset all the input data in search screen in step 1
    handleResetStepOne() {
        this.territorySearchKey = '';
        this.territoryData = [];
        this.selectedTerritoryIds = [];
        this.selectedTerritoryRecords = [];
        this.accountSearchKey = '';
        this.accountType = '';
        this.accountSearchData = [];
        this.allAccountSearchData = [];
        this.hasAccountSearchResultsBeenDisplayed = false;
        this.selectedSearchAccountIds = [];
        this.selectedSearchAccountRecords = [];
        this.accountSearchPageNumber = 1;
        this.accountSearchPageSize = 25;
        this.accountSearchTotalPages = 1;
        this.accountSearchTotalRecords = 0;
        this.showRetrievePrompt = false;
        this.isTerritorySearchCollapsed = false;
        this.isAccountSearchCollapsed = false;
    }

    //Confirm the territory/account selection
    async handleRetrieveAccountsClick() {
        await this.loadAccountData();
        if (this.accountTotalRecords == 0) {
            this.showToast('', 'No matching accounts found for the selected search criteria', 'error');
        }
        else {
            this.showRetrievePrompt = true;
        }
    }

    //If the yes is selected on confirmation popup - go back to step 1
    handleSelectMoreTerritories() {
        this.showRetrievePrompt = false;
        this.step = 1;
    }

    //If the no is selected on confirmation popup - go to step 2. Handle Retrieve account information for step 2
    handleConfirmRetrieveAccounts() {
        this.showRetrievePrompt = false;
        this.step = 2;
    }

    //Handle Retrieve account information for step 2 - apex call
    async loadAccountData() {
        try {
            this.isLoading = true;
            const result = await retrieveAccounts({
                territoryIds: this.selectedTerritoryIds,
                accountSearchKey: this.accountSearchKey,
                accountType: this.accountType,
                selectedSearchAccountIds: this.selectedSearchAccountIds
            });

            this.allAccountData = result.accounts || [];
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

    //Handle account selection/deselection on Retrieve accounts page
    handleAccountSelection(event) {
        const visibleAccountIds = this.accountData.map(row => row.accountId);
        const selectedVisibleIds = event.detail.selectedRows.map(row => row.accountId);

        visibleAccountIds.forEach(accountId => {
            const isSelected = selectedVisibleIds.includes(accountId);
            const isDeselectedTracked = this.deselectedAccountIds.includes(accountId);

            if (!isSelected && !isDeselectedTracked) {
                this.deselectedAccountIds = [...this.deselectedAccountIds, accountId];
            }

            if (isSelected && isDeselectedTracked) {
                this.deselectedAccountIds = this.deselectedAccountIds.filter(id => id !== accountId);
            }
        });

        this.selectedAccountIds = selectedVisibleIds;
    }

    //Handle pagination data
    handlePreviousAccountPage() {
        if (this.accountPageNumber > 1) {
            this.accountPageNumber--;
            this.refreshAccountPage();
        }
    }

    handleNextAccountPage() {
        if (this.accountPageNumber < this.accountTotalPages) {
            this.accountPageNumber++;
            this.refreshAccountPage();
        }
    }

    handleAccountPageSizeChange(event) {
        this.accountPageSize = Number(event.detail.value);
        this.accountTotalPages = Math.max(Math.ceil(this.accountTotalRecords / this.accountPageSize), 1);
        this.accountPageNumber = 1;
        this.refreshAccountPage();
    }

    get disablePreviousAccountPage() { return this.accountPageNumber <= 1; }
    get disableNextAccountPage() { return this.accountPageNumber >= this.accountTotalPages; }

    //Handle user search input and selection 
    handleUserSearchChange(event) { this.userSearchKey = event.target.value; }

    handleSearchUsersEnter(event){
        if(event.key === 'Enter'){
            this.handleSearchUsers();
        }
    }
    //apex call for fetching users based on search
    async handleSearchUsers() {
        try {
            this.isLoading = true;
            const result = await searchOverlayUsers({ searchKey: this.userSearchKey });
            this.userData = (result || []).map(user => ({
                ...user,
                isSelected: this.selectedUserIds.includes(user.userId),
                showTooltip: false
            }));
            if(this.userData.length === 0){
                this.showToast('', 'No matching users found. Please try a different search!', 'error');
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    //Remove selected user if unchecked
    handleRemoveSelectedUser(event) {
        const userIdToRemove = event.detail.name;
        this.selectedUserRecords = this.selectedUserRecords.filter(user => user.userId !== userIdToRemove);
        this.selectedUserIds = this.selectedUserRecords.map(user => user.userId);
        this.userData = this.userData.map(user => ({
            ...user,
            isSelected: this.selectedUserIds.includes(user.userId)
        }));
    }

    //Show user information on mouse hover 
    handleUserMouseOver(event) {
        const userId = event.currentTarget.dataset.userid;
        this.userData = this.userData.map(user => ({
            ...user,
            showTooltip: user.userId === userId
        }));
    }

    //Close tooltip when mouse hover is out
    handleUserMouseOut() {
        this.userData = this.userData.map(user => ({
            ...user,
            showTooltip: false
        }));
    }

    //Handle user selection
    handleUserCheckboxChange(event) {
        const userId = event.target.dataset.userid;
        const checked = event.target.checked;

        if (checked) {
            const selectedUser = this.userData.find(user => user.userId === userId);
            const alreadyExists = this.selectedUserRecords.some(user => user.userId === userId);

            if (selectedUser && !alreadyExists) {
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

    //Show final overlay assignment summary information based on all the selections
    async goToSummary() {
        try {
            this.isLoading = true;
            const result = await getAssignmentSummary({
                territoryIds: this.selectedTerritoryIds,
                selectedAccountIds: this.getSelectedAccountIdsForSubmit()
            });

            this.summaryData = result.map(row => ({
                ...row,
                accountCount: row.selectedAccounts ? row.selectedAccounts.length : 0,
                selectedUsersText: this.getSelectedUsersText()
            }));
            this.step = 4;
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    //helper for displaying selected users in summary
    getSelectedUsersText() {
        if (!this.selectedUserRecords || this.selectedUserRecords.length === 0) {
            return '';
        }
        return this.selectedUserRecords.map(user => user.userName).join(', ');
    }

    //helper to get final selected account ids after removing deselected accounts
    getSelectedAccountIdsForSubmit() {
        return this.allAccountData
            .filter(row => !this.deselectedAccountIds.includes(row.accountId))
            .map(row => row.accountId);
    }

    //Open account popup if the territory or account search link is clicked on summary
    handleTerritorySummaryClick(event) {
        const territoryId = event.currentTarget.dataset.territoryid;
        const selectedTerritory = this.summaryData.find(row => row.territoryId === territoryId);

        if (selectedTerritory) {
            this.selectedSummaryTerritory = selectedTerritory;
            this.selectedSummaryAccounts = selectedTerritory.selectedAccounts;
            this.showTerritoryAccountsPopup = true;
        }
    }

    //Close account summary popup
    closeTerritoryAccountsPopup() {
        this.showTerritoryAccountsPopup = false;
        this.selectedSummaryTerritory = null;
        this.selectedSummaryAccounts = [];
    }

    //Handle final confirm and submit
    async handleConfirmSubmit() { await this.handleSubmit(); }

    async handleSubmit() {
        try {
            this.isLoading = true;
            await submitOverlayAssignments({
                territoryIds: this.selectedTerritoryIds,
                selectedAccountIds: this.getSelectedAccountIdsForSubmit(),
                userIds: this.selectedUserIds
            });

            this.showToast('Success', 'Overlay assignments created successfully.', 'success');
            this.resetWizard();
            this.closeModal();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isLoading = false;
        }
    }

    //reset all the selections
    resetWizard() {
        this.step = 1;
        this.territorySearchKey = '';
        this.territoryData = [];
        this.selectedTerritoryIds = [];
        this.selectedTerritoryRecords = [];
        this.accountSearchKey = '';
        this.accountType = '';
        this.accountSearchData = [];
        this.allAccountSearchData = [];
        this.hasAccountSearchResultsBeenDisplayed = false;
        this.selectedSearchAccountIds = [];
        this.selectedSearchAccountRecords = [];
        this.accountSearchPageNumber = 1;
        this.accountSearchPageSize = 25;
        this.accountSearchTotalPages = 1;
        this.accountSearchTotalRecords = 0;
        this.accountData = [];
        this.allAccountData = [];
        this.selectedAccountIds = [];
        this.deselectedAccountIds = [];
        this.accountPageNumber = 1;
        this.accountPageSize = 25;
        this.accountTotalPages = 1;
        this.accountTotalRecords = 0;
        this.userSearchKey = '';
        this.userData = [];
        this.selectedUserIds = [];
        this.selectedUserRecords = [];
        this.summaryData = [];
        this.selectedSummaryTerritory = null;
        this.selectedSummaryAccounts = [];
        this.showTerritoryAccountsPopup = false;
        this.showRetrievePrompt = false;
        this.isTerritorySearchCollapsed = false;
        this.isSelectedTerritoriesCollapsed = false;
        this.isAccountSearchCollapsed = false;
        this.isSelectedAccountsCollapsed = false;
    }

    // Show any toast message
    showToast(title, message, variant) {
        this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
    }

    // Show any error message
    showError(error) {
        let message = 'Unexpected error occurred.';
        if (error && error.body && error.body.message) {
            message = error.body.message;
        }
        this.showToast('Error', message, 'error');
    }
}