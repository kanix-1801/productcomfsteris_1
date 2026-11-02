import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { CloseActionScreenEvent } from 'lightning/actions';
import { loadStyle } from 'lightning/platformResourceLoader';
import modal from '@salesforce/resourceUrl/custommodalcss_installationProjectEditor';
import getProjectData from '@salesforce/apex/InstallationProjectEditorController.getProjectData';
import getActiveUsers from '@salesforce/apex/InstallationProjectEditorController.getActiveUsers';
import updateProjectItems from '@salesforce/apex/InstallationProjectEditorController.updateProjectItems';

export default class InstallationProjectEditor extends LightningElement {
    @api recordId;
    
    projectData;
    projectItems = [];
    isLoading = true;
    isSaving = false;
    stylesLoaded = false;
    userOptions = []; // Will be populated from wire
    
    // Status options for picklist
    statusOptions = [
        { label: 'Open', value: 'Open' },
        { label: 'Completed', value: 'Completed' },
        { label: 'Canceled', value: 'Canceled' }
    ];

    // Type options for picklist
    typeOptions = [
        { label: 'Task', value: 'Task' },
        { label: 'Event', value: 'Event' }
    ];

    connectedCallback() {
        // Load custom modal CSS from static resource
        if (!this.stylesLoaded) {
            loadStyle(this, modal)
                .then(() => {
                    this.stylesLoaded = true;
                })
                .catch(error => {
                    console.error('Error loading custom modal CSS:', error);
                });
        }
        
        // Add click listener to close autocomplete when clicking outside
        this.clickHandler = (event) => {
            const isInsideAutocomplete = event.target.closest('.autocomplete-container');
            if (!isInsideAutocomplete) {
                this.projectItems.forEach(item => {
                    item.showAutocomplete = false;
                });
                this.projectItems = [...this.projectItems];
            }
        };
        document.addEventListener('click', this.clickHandler);
    }

    disconnectedCallback() {
        // Remove click listener
        if (this.clickHandler) {
            document.removeEventListener('click', this.clickHandler);
        }
    }

    // Wire to get active users
    @wire(getActiveUsers)
    wiredUsers({ error, data }) {
        if (data) {
            // Convert User records to options for combobox
            this.userOptions = data.map(user => ({
                label: user.Name,
                value: user.Id
            }));
            console.log('Active users loaded:', this.userOptions.length);
        } else if (error) {
            console.error('Error loading active users:', error);
        }
    }

    // Wire to get project data - reactive, automatically handles when recordId becomes available
    @wire(getProjectData, { projectId: '$recordId' })
    wiredProjectData({ error, data }) {
        if (data) {
            this.projectData = data;
            // Debug: log raw payload for inspection (helps verify server-returned sequence/itemNumber)
            console.debug('getProjectData payload items:', data.items);
            // Add boolean properties for template conditionals
            this.projectItems = data.items ? data.items.map(item => ({
                ...item,
                isTask: item.recordType === 'Task',
                isEvent: item.recordType === 'Event',
                isMainItem: item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber,
                isNew: item.isNew || (item.id && item.id.startsWith('temp_')) || false,
                ownerSearchText: item.ownerName || '', // Initialize search text with current owner name
                showAutocomplete: false,
                filteredUsers: [],
                noUsersFound: false
            })) : [];
            this.isLoading = false;
            console.log('Project data loaded:', this.projectData);
            console.log('Project items with owners:', this.projectItems.map(item => ({
                id: item.id,
                ownerId: item.ownerId,
                ownerName: item.ownerName,
                recordType: item.recordType,
                sequence: item.sequence,
                itemNumber: item.itemNumber
            })));
        } else if (error) {
            console.error('Error loading project data:', error);
            this.isLoading = false;
            this.showToast('Error', 'Failed to load project data: ' + (error.body?.message || error.message), 'error');
        } else {
            // Still loading (neither data nor error yet)
            this.isLoading = true;
        }
    }

    // Handle type change
    handleTypeChange(event) {
        const itemId = event.target.dataset.id;
        const newType = event.detail.value;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.recordType = newType;
            // Update boolean properties based on new type
            item.isTask = newType === 'Task';
            item.isEvent = newType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Handle status change
    handleStatusChange(event) {
        const itemId = event.target.dataset.id;
        const newStatus = event.detail.value;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.status = newStatus;
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Handle subject/details change
    handleSubjectChange(event) {
        const itemId = event.target.dataset.id;
        const newSubject = event.target.value;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.subject = newSubject;
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Handle duration change
    handleDurationChange(event) {
        const itemId = event.target.dataset.id;
        const newDuration = event.target.value ? Number(event.target.value) : 0;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.duration = newDuration;
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Handle owner search input
    handleOwnerSearch(event) {
        event.stopPropagation(); // Prevent click from bubbling
        const itemId = event.target.dataset.id;
        const searchText = event.target.value;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.ownerSearchText = searchText;
            
            // Filter users based on search text
            let filtered = [];
            if (!searchText || searchText.trim() === '') {
                // When empty, show ALL users (for scrolling)
                filtered = this.userOptions;
            } else {
                // When searching, show ALL filtered results (not limited to 5)
                const searchLower = searchText.toLowerCase();
                filtered = this.userOptions.filter(user => 
                    user.label.toLowerCase().includes(searchLower)
                );
            }
            
            item.filteredUsers = filtered;
            item.showAutocomplete = true;
            item.noUsersFound = filtered.length === 0 && searchText && searchText.trim() !== '';
            
            // Close other autocompletes
            this.projectItems.forEach(i => {
                if (i.id !== itemId) {
                    i.showAutocomplete = false;
                }
            });
            
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Handle container click to prevent closing
    handleContainerClick(event) {
        event.stopPropagation();
    }

    // Handle dropdown click to prevent closing
    handleDropdownClick(event) {
        event.stopPropagation();
    }

    // Handle owner selection from dropdown
    handleOwnerSelect(event) {
        event.stopPropagation(); // Prevent click from bubbling to card
        const itemId = event.currentTarget.dataset.itemId;
        const userId = event.currentTarget.dataset.userId;
        const userName = event.currentTarget.dataset.userName;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.ownerId = userId;
            item.ownerName = userName;
            item.ownerSearchText = userName; // Set search text to selected name
            item.showAutocomplete = false; // Close dropdown
            item.filteredUsers = [];
            item.noUsersFound = false;
            
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }


    // Handle due date change
    handleDueDateChange(event) {
        const itemId = event.target.dataset.id;
        const newDate = event.detail.value;
        
        const item = this.projectItems.find(i => i.id === itemId);
        if (item) {
            item.activityDate = newDate;
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            // Cascade date changes to items below
            this.cascadeDateChange(item, newDate);
            // Trigger reactivity
            this.projectItems = [...this.projectItems];
        }
    }

    // Cascade date changes based on template dependencies (same logic as installationProjectMgmt)
    cascadeDateChange(changedItem, newDate) {
        if (!newDate || !this.projectData) {
            return;
        }

        const changedIndex = this.projectItems.findIndex(i => i.id === changedItem.id);
        if (changedIndex === -1) {
            return;
        }

        // Recalculate dates for all items below the changed item sequentially
        // This ensures each item uses the updated dates from previous items
        for (let i = changedIndex + 1; i < this.projectItems.length; i++) {
            const item = this.projectItems[i];
            
            // Skip if item has explicit dependency configuration (not sequential)
            // Only process items with no dependency or 'Dependent Item' dependency
            if (item.dependencyType && item.dependencyType !== 'Dependent Item') {
                continue;
            }

            // Check if this is a main item or sub-item
            const isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;

            if (isMainItem) {
                // Main item: start after previous main item's end date
                // Find all main items that come before this one (including updated ones)
                const previousMainItems = [];
                for (let j = 0; j < i; j++) {
                    const prevItem = this.projectItems[j];
                    if (prevItem.itemNumber != null && Math.floor(prevItem.itemNumber) === prevItem.itemNumber) {
                        previousMainItems.push(prevItem);
                    }
                }
                
                if (previousMainItems.length > 0) {
                    const lastMainItem = previousMainItems[previousMainItems.length - 1];
                    if (lastMainItem.activityDate) {
                        // Calculate end date: start date + duration
                        const lastEndDate = this.addDays(lastMainItem.activityDate, lastMainItem.duration || 0);
                        item.activityDate = this.formatDate(lastEndDate);
                    }
                }
            } else if (item.itemNumber != null) {
                // Sub-item: use parent main item's start date
                const parentMainNumber = Math.floor(item.itemNumber);
                // Find the parent main item (could be before or at current position)
                const parentItem = this.projectItems.find(it => 
                    it.itemNumber != null &&
                    Math.floor(it.itemNumber) === parentMainNumber && 
                    Math.floor(it.itemNumber) === it.itemNumber
                );
                
                if (parentItem && parentItem.activityDate) {
                    // Sub-items use the parent's start date (activityDate)
                    item.activityDate = parentItem.activityDate;
                }
            }
            
            // Preserve boolean properties
            item.isTask = item.recordType === 'Task';
            item.isEvent = item.recordType === 'Event';
            item.isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
        }
    }

    // Helper to add days to a date string and return formatted string
    addDays(dateStr, days) {
        if (!dateStr) return null;
        const date = new Date(dateStr);
        date.setDate(date.getDate() + (days || 0));
        return date.toISOString().split('T')[0];
    }

    // Helper to format date to YYYY-MM-DD
    formatDate(date) {
        if (!date) return null;
        if (typeof date === 'string') {
            return date;
        }
        if (date instanceof Date) {
            return date.toISOString().split('T')[0];
        }
        return date;
    }

    // Handle cancel
    handleCancel() {
        this.dispatchEvent(new CloseActionScreenEvent());
    }

    // Handle save
    handleSave() {
        this.isSaving = true;

        // Prepare items for update/create
        const itemsToUpdate = this.projectItems.map(item => ({
            id: item.id,
            recordType: item.recordType,
            status: item.status,
            ownerId: item.ownerId,
            activityDate: item.activityDate,
            duration: item.duration,
            sequence: item.sequence,
            subject: item.subject,
            isNew: item.isNew || false
        }));

        updateProjectItems({ 
            itemsJson: JSON.stringify(itemsToUpdate),
            projectId: this.recordId
        })
            .then(() => {
                this.showToast('Success', 'Project items updated successfully', 'success');
                // Close the modal
                this.dispatchEvent(new CloseActionScreenEvent());
                // Refresh the page to show updated data
                window.location.reload();
            })
            .catch(error => {
                console.error('Error updating project items:', error);
                const errorMessage = error.body?.message || error.message || 'Unknown error occurred';
                this.showToast('Error', 'Failed to update project items: ' + errorMessage, 'error');
            })
            .finally(() => {
                this.isSaving = false;
            });
    }

    showToast(title, message, variant) {
        const event = new ShowToastEvent({
            title: title,
            message: message,
            variant: variant
        });
        this.dispatchEvent(event);
    }

    // Handle row actions from the action menu
    handleRowAction(event) {
        const actionName = event.detail.value;
        const itemId = event.currentTarget.dataset.id;
        const row = this.projectItems.find(item => item.id === itemId);
        
        if (!row) return;
        
        switch (actionName) {
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

    // Handle delete line
    handleDeleteLine(row) {
        const itemNumber = row.itemNumber;
        const isMainItem = row.isMainItem;
        
        let filteredItems;
        if (isMainItem) {
            // Delete main line and all its sub-lines
            const mainNumber = Math.floor(itemNumber);
            filteredItems = this.projectItems.filter(item => {
                if (item.itemNumber == null) return true; // Keep items without itemNumber
                const currentMain = Math.floor(item.itemNumber);
                // Keep items that don't belong to this main line
                return currentMain !== mainNumber;
            });
        } else {
            // Delete just this sub-line
            filteredItems = this.projectItems.filter(item => {
                return item.id !== row.id;
            });
        }
        
        // Update the array reference
        this.projectItems = filteredItems.map(item => ({
            ...item,
            isTask: item.recordType === 'Task',
            isEvent: item.recordType === 'Event',
            isMainItem: item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber
        }));
        
        // Re-order item numbers
        this.reorderItemNumbers();
        
        // Show success message
        this.showToast('Success', 'Line removed.', 'success');
    }

    // Reorder item numbers
    reorderItemNumbers() {
        if (!this.projectItems || this.projectItems.length === 0) {
            return;
        }
        
        let mainCounter = 1;
        let currentMainNumber = null;
        let subCounter = 1;
        
        // Reorder item numbers
        let reorderedItems = this.projectItems.map(item => {
            const isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;
            
            if (isMainItem) {
                // This is a main item - assign new main number
                currentMainNumber = mainCounter;
                const newItemNumber = mainCounter;
                mainCounter++;
                subCounter = 1; // Reset sub counter for this main item
                
                return {
                    ...item,
                    itemNumber: newItemNumber,
                    sequence: newItemNumber,
                    isMainItem: true
                };
            } else if (item.itemNumber != null) {
                // This is a sub-item - assign new sub number under current main
                const newItemNumber = currentMainNumber + (subCounter / 10);
                subCounter++;
                
                return {
                    ...item,
                    itemNumber: newItemNumber,
                    sequence: newItemNumber,
                    isMainItem: false
                };
            } else {
                // Item without itemNumber - keep as is
                return {
                    ...item,
                    isMainItem: false
                };
            }
        });
        
        // Update with new array reference to trigger reactivity
        this.projectItems = reorderedItems.map(item => ({
            ...item,
            isTask: item.recordType === 'Task',
            isEvent: item.recordType === 'Event',
            isMainItem: item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber
        }));
        
        // Recalculate dates after reordering
        this.cascadeDateChangeAfterReorder();
    }

    // Cascade date changes after reordering
    cascadeDateChangeAfterReorder() {
        if (!this.projectData || !this.projectData.projectStartDate) {
            return;
        }

        // Recalculate dates for all items sequentially
        for (let i = 0; i < this.projectItems.length; i++) {
            const item = this.projectItems[i];
            
            // Skip if item has explicit dependency configuration (not sequential)
            if (item.dependencyType && item.dependencyType !== 'Dependent Item') {
                continue;
            }

            // Check if this is a main item or sub-item
            const isMainItem = item.itemNumber != null && Math.floor(item.itemNumber) === item.itemNumber;

            if (isMainItem) {
                // Main item: start after previous main item's end date
                const previousMainItems = [];
                for (let j = 0; j < i; j++) {
                    const prevItem = this.projectItems[j];
                    if (prevItem.itemNumber != null && Math.floor(prevItem.itemNumber) === prevItem.itemNumber) {
                        previousMainItems.push(prevItem);
                    }
                }
                
                if (previousMainItems.length > 0) {
                    const lastMainItem = previousMainItems[previousMainItems.length - 1];
                    if (lastMainItem.activityDate) {
                        // Calculate end date: start date + duration
                        const lastEndDate = this.addDays(lastMainItem.activityDate, lastMainItem.duration || 0);
                        item.activityDate = this.formatDate(lastEndDate);
                    }
                } else if (this.projectData.projectStartDate) {
                    // First main item uses project start date
                    item.activityDate = this.formatDate(this.projectData.projectStartDate);
                }
            } else if (item.itemNumber != null) {
                // Sub-item: use parent main item's start date
                const parentMainNumber = Math.floor(item.itemNumber);
                // Find the parent main item
                const parentItem = this.projectItems.find(it => 
                    it.itemNumber != null &&
                    Math.floor(it.itemNumber) === parentMainNumber && 
                    Math.floor(it.itemNumber) === it.itemNumber
                );
                
                if (parentItem && parentItem.activityDate) {
                    // Sub-items use the parent's start date (activityDate)
                    item.activityDate = parentItem.activityDate;
                }
            }
        }
        
        // Trigger reactivity
        this.projectItems = [...this.projectItems];
    }

    // Handle add line
    handleAddLine(row) {
        const selectedItemNumber = row.itemNumber;
        const selectedIndex = this.projectItems.findIndex(
            item => item.id === row.id
        );
        
        if (selectedIndex === -1) return;
        
        // Find the position after the selected line AND all its sub-lines
        const selectedMainNumber = selectedItemNumber != null ? Math.floor(selectedItemNumber) : null;
        let insertIndex = selectedIndex;
        
        // Find all sub-items of the selected line
        if (selectedMainNumber != null) {
            for (let i = selectedIndex + 1; i < this.projectItems.length; i++) {
                const currentItem = this.projectItems[i];
                if (currentItem.itemNumber == null) continue;
                const currentMain = Math.floor(currentItem.itemNumber);
                // If this item belongs to the same main number, update insert index
                if (currentMain === selectedMainNumber) {
                    insertIndex = i;
                } else {
                    // We've moved to a different main line, stop searching
                    break;
                }
            }
        }
        
        // Calculate the new main item number (next whole number after the selected item)
        const nextMainNumber = selectedItemNumber != null ? Math.floor(selectedItemNumber) + 1 : 1;
        
        // Calculate start date: clicked item's start date + duration
        let newStartDate = this.projectData?.projectStartDate || new Date().toISOString().split('T')[0];
        if (row.activityDate && row.duration !== null && row.duration !== undefined) {
            const clickedStartDate = new Date(row.activityDate);
            const duration = Number(row.duration) || 0;
            clickedStartDate.setDate(clickedStartDate.getDate() + duration);
            newStartDate = clickedStartDate.toISOString().split('T')[0];
        }
        
        // Create new main line
        const newLine = {
            id: 'temp_' + Date.now(), // Temporary ID for new items
            recordType: 'Event',
            sequence: nextMainNumber,
            subject: 'New Line',
            activityDate: newStartDate,
            duration: 1,
            ownerId: null,
            ownerName: null,
            status: 'Open',
            itemNumber: nextMainNumber,
            type: 'Event',
            templateDuration: 1,
            dependencyType: null,
            autoFilledStartDays: 0,
            itemDependency: null,
            isTask: false,
            isEvent: true,
            isMainItem: true,
            isNew: true, // Flag to identify new items
            ownerSearchText: '',
            showAutocomplete: false,
            filteredUsers: [],
            noUsersFound: false
        };
        
        // Insert the new line after the selected row AND all its sub-lines
        const updatedItems = [...this.projectItems];
        updatedItems.splice(insertIndex + 1, 0, newLine);
        
        // Update the array
        this.projectItems = updatedItems;
        
        // Reorder all item numbers
        this.reorderItemNumbers();
        
        this.showToast('Success', 'Line added.', 'success');
    }

    // Handle add sub-line
    handleAddSubline(row) {
        const parentItemNumber = row.itemNumber;
        const parentIndex = this.projectItems.findIndex(
            item => item.id === row.id
        );
        
        if (parentIndex === -1) return;
        
        // Find the last sub-item of this parent, or the parent itself if no sub-items exist
        const parentMain = parentItemNumber != null ? Math.floor(parentItemNumber) : null;
        
        if (parentMain == null) {
            return; // Can't add sub-line to item without itemNumber
        }
        
        let insertIndex = parentIndex;
        // Determine the next sub-index by scanning existing itemNumber values for the parent.
        // This is more robust than relying on array order or a simple count.
        let maxSubIndex = 0; // 0 means no sub-items yet
        for (let i = 0; i < this.projectItems.length; i++) {
            const currentItem = this.projectItems[i];
            if (currentItem.itemNumber == null) continue;
            const currentMain = Math.floor(currentItem.itemNumber);
            if (currentMain === parentMain) {
                // If this is a sub-item (not the parent main itself)
                if (currentItem.itemNumber !== parentMain) {
                    // Calculate sub index as integer (e.g., .3 -> 3)
                    const fraction = Math.abs(currentItem.itemNumber - parentMain);
                    // Use rounding to avoid floating precision issues
                    const subIndex = Math.round(fraction * 10);
                    if (!isNaN(subIndex) && subIndex > maxSubIndex) {
                        maxSubIndex = subIndex;
                    }
                    // Track insert position so we add after the last existing sub-item
                    insertIndex = i;
                } else {
                    // If it's the parent main, ensure insertIndex is at least the parentIndex
                    if (i === parentIndex) {
                        insertIndex = Math.max(insertIndex, i);
                    }
                }
            }
        }
        
        // Next sub index is maxSubIndex + 1
        const nextSubIndex = maxSubIndex + 1;
        
        // Check if we already have 9 sub-items (maximum allowed)
        if (nextSubIndex > 9) {
            this.showToast('Warning', 'Cannot add more than 9 sub-tasks per Event', 'warning');
            return;
        }
        
        // Calculate start date: parent item's start date
        let newStartDate = this.projectData?.projectStartDate || new Date().toISOString().split('T')[0];
        if (row.activityDate) {
            newStartDate = this.formatDate(row.activityDate);
        }
        
        // Create new sub-line (item number will be recalculated)
        const newSubLine = {
            id: 'temp_' + Date.now(), // Temporary ID for new items
            recordType: 'Task',
            sequence: parentMain + (nextSubIndex / 10), // Temporary number, will be reordered
            subject: 'New Sub-line',
            activityDate: newStartDate,
            duration: 1,
            ownerId: null,
            ownerName: null,
            status: 'Open',
            itemNumber: parentMain + (nextSubIndex / 10), // Temporary number, will be reordered
            type: 'Task',
            templateDuration: 1,
            dependencyType: null,
            autoFilledStartDays: 0,
            itemDependency: null,
            isTask: true,
            isEvent: false,
            isMainItem: false,
            isNew: true, // Flag to identify new items
            ownerSearchText: '',
            showAutocomplete: false,
            filteredUsers: [],
            noUsersFound: false
        };
        
        // Insert the new sub-line after the last sub-item (or after parent)
        const updatedItems = [...this.projectItems];
        updatedItems.splice(insertIndex + 1, 0, newSubLine);
        
        // Update the array
        this.projectItems = updatedItems;
        
        // Reorder all item numbers
        this.reorderItemNumbers();
        
        this.showToast('Success', 'Sub-line added.', 'success');
    }
}