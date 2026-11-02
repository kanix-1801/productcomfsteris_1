import { LightningElement, track, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getObjectOptions from '@salesforce/apex/RecordTypePsAssignmentController.getObjectOptions';
import searchUsers from '@salesforce/apex/RecordTypePsAssignmentController.searchUsers';
import getPermissionSetAssignments from '@salesforce/apex/RecordTypePsAssignmentController.getPermissionSetAssignments';
import savePermissionSetAssignments from '@salesforce/apex/RecordTypePsAssignmentController.savePermissionSetAssignments';

/**
 * @author PWC Developer
 * @date 2026/07/15
 *
 * @description
 * GC-3148 - Sales Ops UI for assigning record type permission sets to users.
 */
export default class RecordTypePermissionSetAssignment extends NavigationMixin(LightningElement) {
    @track showModal = true;
    @track isSaving = false;
    @track isSearchingUsers = false;

    @track objectOptions = [];
    @track selectedObjectApiName;

    @track userSearchKey = '';
    @track userData = [];
    @track selectedUserId;
    @track selectedUserLabel = '';

    userPageNumber = 1;
    userPageSize = 25;
    userNameSortDirection = 'asc';

    pageSizeOptions = [
        { label: '25', value: '25' },
        { label: '50', value: '50' },
        { label: '100', value: '100' },
        { label: '150', value: '150' }
    ];

    @track permissionSetOptions = [];
    @track assignedPermissionSetIds = [];
    initialAssignedPermissionSetIds = [];

    minDualListSelection = 0;
    dualListboxSize = 5;

    /**
     * Loads supported object options from CMDT-backed Apex on component init.
     */
    @wire(getObjectOptions)
    wiredObjectOptions({ data, error }) {
        if (data) {
            this.objectOptions = data.map((objectOption) => ({
                label: objectOption.label,
                value: objectOption.value
            }));

            if (this.objectOptions.length > 0 && !this.selectedObjectApiName) {
                this.selectedObjectApiName = this.objectOptions[0].value;
            }
        } else if (error) {
            this.showError(error);
        }
    }

    get isSearchUsersDisabled() {
        return !this.userSearchKey || this.userSearchKey.trim().length === 0;
    }

    get isSearchUsersButtonDisabled() {
        return this.isSearchUsersDisabled || this.isSearchingUsers || this.showLoadingOverlay;
    }

    get searchUsersButtonLabel() {
        return this.isSearchingUsers ? 'Searching...' : 'Search';
    }

    get hasUserResults() {
        return this.userData.length > 0;
    }

    get userResultCount() {
        return this.userData.length;
    }

    get paginatedUserData() {
        const startIndex = (this.userPageNumber - 1) * this.userPageSize;
        return this.userData.slice(startIndex, startIndex + this.userPageSize);
    }

    get userPageSizeValue() {
        return String(this.userPageSize);
    }

    get userTotalPages() {
        return Math.max(Math.ceil(this.userData.length / this.userPageSize), 1);
    }

    get disablePreviousUserPage() {
        return this.userPageNumber <= 1;
    }

    get disableNextUserPage() {
        return this.userPageNumber >= this.userTotalPages;
    }

    get userNameColumnClass() {
        const sortableClass = 'slds-is-sortable';
        if (this.userNameSortDirection === 'asc') {
            return `${sortableClass} slds-is-sorted slds-is-sorted_asc`;
        }
        return `${sortableClass} slds-is-sorted slds-is-sorted_desc`;
    }

    get userNameSortIcon() {
        return this.userNameSortDirection === 'asc' ? 'utility:arrowup' : 'utility:arrowdown';
    }

    get userNameAriaSort() {
        return this.userNameSortDirection === 'asc' ? 'ascending' : 'descending';
    }

    get hasSelectedUser() {
        return !!this.selectedUserId;
    }

    get showPermissionSetAssignment() {
        return this.hasSelectedUser;
    }

    get recordTypeAssignmentSectionTitle() {
        return `Record Type Assignment For "${this.selectedUserLabel}"`;
    }

    get showLoadingOverlay() {
        return this.isSaving;
    }

    get loadingMessage() {
        return 'Saving...';
    }

    get isSaveDisabled() {
        return !this.hasSelectedUser || !this.selectedObjectApiName || this.isSaving;
    }

    get isResetDisabled() {
        return this.showLoadingOverlay || this.isSearchingUsers;
    }

    handleObjectChange(event) {
        this.selectedObjectApiName = event.detail.value;
        this.clearUserSelection();
    }

    handleUserSearchChange(event) {
        this.userSearchKey = event.detail.value;
    }

    handleUserEnterKey(event) {
        if (event.key === 'Enter') {
            event.preventDefault();
            event.stopPropagation();

            if (!this.isSearchUsersButtonDisabled) {
                this.handleSearchUsers();
            }
        }
    }

    /**
     * Searches Healthcare Sales users, clears prior user selection, and resets pagination to page 1.
     */
    async handleSearchUsers() {
        if (this.isSearchingUsers) {
            return;
        }

        this.isSearchingUsers = true;
        this.clearUserSelection();

        try {
            const userResults = await searchUsers({ searchKey: this.userSearchKey });
            this.userNameSortDirection = 'asc';
            this.userData = this.sortUserDataByName(
                (userResults || []).map((userRecord) => this.mapUserRecord(userRecord, false))
            );
            this.userPageNumber = 1;

            if (this.userResultCount === 0) {
                this.showToast('', 'No matching Healthcare Sales users are found!', 'error');
            }
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSearchingUsers = false;
        }
    }

    /**
     * Sets the selected user when a search result row is clicked and loads permission set assignments.
     */
    handleUserRowClick(event) {
        const userId = event.currentTarget.dataset.userId;
        if (!userId) {
            return;
        }

        const selectedUser = this.userData.find((userRecord) => userRecord.userId === userId);

        this.selectedUserId = userId;
        this.selectedUserLabel = selectedUser ? selectedUser.userName : '';
        this.userData = this.userData.map((userRecord) =>
            this.mapUserRecord(userRecord, userRecord.userId === userId)
        );
        this.assignedPermissionSetIds = [];
        this.initialAssignedPermissionSetIds = [];

        this.loadPermissionSetAssignments();
    }

    // Client-side pagination for user search results
    handlePreviousUserPage() {
        if (this.userPageNumber > 1) {
            this.userPageNumber--;
        }
    }

    handleNextUserPage() {
        if (this.userPageNumber < this.userTotalPages) {
            this.userPageNumber++;
        }
    }

    handleUserPageSizeChange(event) {
        this.userPageSize = Number(event.detail.value);
        this.userPageNumber = 1;
    }

    /**
     * Toggles Name column sort direction and re-sorts user search results.
     */
    handleUserNameSort(event) {
        event.preventDefault();
        event.stopPropagation();
        this.userNameSortDirection = this.userNameSortDirection === 'asc' ? 'desc' : 'asc';
        this.userData = this.sortUserDataByName(this.userData);
        this.userPageNumber = 1;
    }

    handleUserNameSortKeydown(event) {
        if (event.key === 'Enter' || event.key === ' ') {
            event.preventDefault();
            this.handleUserNameSort(event);
        }
    }

    sortUserDataByName(userRecords) {
        const directionMultiplier = this.userNameSortDirection === 'asc' ? 1 : -1;
        return [...userRecords].sort(
            (firstUser, secondUser) =>
                directionMultiplier *
                (firstUser.userName || '').localeCompare(secondUser.userName || '')
        );
    }

    handlePermissionSetChange(event) {
        this.assignedPermissionSetIds = event.detail.value;
    }

    /**
     * Loads available and assigned permission sets for the selected user and object.
     */
    async loadPermissionSetAssignments() {
        if (!this.selectedUserId || !this.selectedObjectApiName) {
            return;
        }

        const userIdForRequest = this.selectedUserId;
        const objectApiNameForRequest = this.selectedObjectApiName;

        try {
            const assignmentView = await getPermissionSetAssignments({
                objectApiName: objectApiNameForRequest,
                userId: userIdForRequest
            });

            if (
                userIdForRequest !== this.selectedUserId ||
                objectApiNameForRequest !== this.selectedObjectApiName
            ) {
                return;
            }

            this.permissionSetOptions = (assignmentView.permissionSetOptions || []).map((permissionSetOption) => ({
                label: permissionSetOption.label,
                value: permissionSetOption.permissionSetId
            }));
            this.assignedPermissionSetIds = assignmentView.assignedPermissionSetIds || [];
            this.initialAssignedPermissionSetIds = [...this.assignedPermissionSetIds];
        } catch (error) {
            this.showError(error);
        }
    }

    /**
     * Persists permission set assignments and closes the modal on success.
     */
    async handleSave() {
        if (!this.hasAssignmentChanges()) {
            this.showToast(
                'No Changes',
                'No changes were made to permission set assignments.',
                'info'
            );
            return;
        }

        this.isSaving = true;

        try {
            await savePermissionSetAssignments({
                objectApiName: this.selectedObjectApiName,
                userId: this.selectedUserId,
                selectedPermissionSetIds: this.assignedPermissionSetIds
            });

            this.showToast('Success', 'Permission set assignments were saved successfully.', 'success');
            this.handleCancel();
        } catch (error) {
            this.showError(error);
        } finally {
            this.isSaving = false;
        }
    }

    /**
     * Clears all screen selections and restores default object and pagination values.
     */
    handleReset() {
        this.userSearchKey = '';
        this.userData = [];
        this.selectedUserId = null;
        this.selectedUserLabel = '';
        this.permissionSetOptions = [];
        this.assignedPermissionSetIds = [];
        this.initialAssignedPermissionSetIds = [];
        this.userPageNumber = 1;
        this.userPageSize = 25;
        this.userNameSortDirection = 'asc';
        this.isSearchingUsers = false;
        this.isSaving = false;
        this.selectedObjectApiName =
            this.objectOptions.length > 0 ? this.objectOptions[0].value : null;
    }

    /**
     * Closes the modal and returns the user to the previous browser history entry.
     */
    handleCancel() {
        this.showModal = false;
        window.history.back();
    }

    /**
     * Clears selected user and permission set state when the object selection changes.
     */
    clearUserSelection() {
        this.selectedUserId = null;
        this.selectedUserLabel = '';
        this.permissionSetOptions = [];
        this.assignedPermissionSetIds = [];
        this.initialAssignedPermissionSetIds = [];
        this.userData = this.userData.map((userRecord) => this.mapUserRecord(userRecord, false));
    }

    hasAssignmentChanges() {
        return !this.arePermissionSetIdsEqual(
            this.initialAssignedPermissionSetIds,
            this.assignedPermissionSetIds
        );
    }

    arePermissionSetIdsEqual(firstPermissionSetIds, secondPermissionSetIds) {
        const firstPermissionSetIdSet = new Set(firstPermissionSetIds || []);
        const secondPermissionSetIdSet = new Set(secondPermissionSetIds || []);

        if (firstPermissionSetIdSet.size !== secondPermissionSetIdSet.size) {
            return false;
        }

        return [...firstPermissionSetIdSet].every((permissionSetId) =>
            secondPermissionSetIdSet.has(permissionSetId)
        );
    }

    mapUserRecord(userRecord, isSelected) {
        return {
            ...userRecord,
            isSelected,
            rowClass: isSelected ? 'user-selectable-row user-row-selected' : 'user-selectable-row'
        };
    }

    showToast(title, message, variant) {
        this.dispatchEvent(
            new ShowToastEvent({
                title,
                message,
                variant
            })
        );
    }

    showError(error) {
        const message = error?.body?.message || error?.message || 'An unexpected error occurred.';
        this.showToast('Error', message, 'error');
    }
}