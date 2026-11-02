import { LightningElement, api } from 'lwc';
import { FlowAttributeChangeEvent } from 'lightning/flowSupport';
import getAttendees from '@salesforce/apex/EventAttendeeService.getAttendees';
import search from '@salesforce/apex/EventAttendeeService.search';

/**
 * GC-3489 - People and Resources picker used on the Healthcare Sales Event screen flow.
 * Adds and removes are staged here. The flow writes them when Save is clicked.
 */
export default class HsEventAttendees extends LightningElement {
    /** Event Id passed in by the screen flow. */
    @api recordId;
    /** True on the read-only screen. Hides search and remove. */
    @api readOnly = false;
    /** JSON of staged adds and removes. Empty when nothing has changed. */
    @api changePayload = '';

    /** Invitees loaded from the Event, including the owner. */
    attendees = [];
    /** Search hits that are not already selected. */
    results = [];
    /** Current text in the search box. */
    searchTerm = '';
    /** People or Resources. */
    activeTab = 'People';
    /** Message shown above the tabs when load or search fails. */
    errorMessage = '';
    /** True while the initial attendee list is loading. */
    isLoading = true;
    /** True while a search request is in flight. */
    isSearching = false;

    /** People and resources selected in this session and not yet saved. */
    _added = [];
    /** EventRelation Ids staged for delete. */
    _removedRelationIds = [];
    /** Debounce timer for the search box. */
    _searchTimer;

    /**
     * Loads the current invitees as soon as the flow screen opens.
     */
    connectedCallback() {
        this.loadAttendees();
    }

    /**
     * @returns {boolean} True when the user can search and remove attendees.
     */
    get isEditable() {
        return this.readOnly !== true && this.readOnly !== 'true';
    }

    /**
     * Saved invitees minus staged removals, plus people selected in this session.
     * @returns {object[]} Rows that should appear selected.
     */
    get displayedAttendees() {
        const removed = new Set(this._removedRelationIds);
        const existing = this.attendees.filter((row) => !removed.has(row.relationId));
        return existing.concat(this._added);
    }

    /**
     * Selected rows for the active tab, with an icon and a remove flag.
     * The Event owner stays visible and cannot be removed.
     * @returns {object[]} Rows rendered as pills.
     */
    get visibleAttendees() {
        const showResources = this.activeTab === 'Resources';
        return this.displayedAttendees
            .filter((row) => (row.kind === 'Resource') === showResources)
            .map((row) => ({
                ...row,
                iconName: this.iconFor(row.kind),
                canRemove: this.isEditable && row.isOwner !== true
            }));
    }

    /**
     * @returns {boolean} True when the active tab has at least one selected row.
     */
    get hasVisibleAttendees() {
        return this.visibleAttendees.length > 0;
    }

    /**
     * @returns {string} Placeholder for the search box on the active tab.
     */
    get searchPlaceholder() {
        return this.activeTab === 'Resources' ? 'Search Resources...' : 'Search People...';
    }

    /**
     * @returns {boolean} True when the search dropdown should be open.
     */
    get isDropdownOpen() {
        return this.isEditable && (this.isSearching || this.results.length > 0 || this.showEmptyResults);
    }

    /**
     * @returns {string} SLDS combobox classes, including the open state.
     */
    get comboboxClass() {
        return `slds-combobox slds-dropdown-trigger slds-dropdown-trigger_click${this.isDropdownOpen ? ' slds-is-open' : ''}`;
    }

    /**
     * @returns {string} Message shown when a search of at least two characters returns nothing.
     */
    get emptyResultsLabel() {
        return this.activeTab === 'Resources'
            ? 'No resources found. An admin creates these under Public Calendars and Resources.'
            : 'No people found.';
    }

    /**
     * @returns {boolean} True when the search finished with no hits.
     */
    get showEmptyResults() {
        return !this.isSearching && this.searchTerm.trim().length >= 2 && this.results.length === 0;
    }

    /**
     * Loads invitees from EventAttendeeService and publishes an empty change payload.
     */
    async loadAttendees() {
        this.isLoading = true;
        this.errorMessage = '';
        try {
            this.attendees = await getAttendees({ eventId: this.recordId });
        } catch (error) {
            this.errorMessage = this.messageFrom(error);
            this.attendees = [];
        } finally {
            this.isLoading = false;
            this.publishChanges();
        }
    }

    /**
     * Switches between People and Resources and clears the previous search.
     * @param {CustomEvent} event Active tab event. event.target.value is People or Resources.
     */
    handleTab(event) {
        this.activeTab = event.target.value;
        this.results = [];
        this.searchTerm = '';
    }

    /**
     * Stores the search text and runs the search 300ms after the user stops typing.
     * @param {InputEvent} event Input event from the search box.
     */
    handleSearchInput(event) {
        this.searchTerm = event.target.value;
        window.clearTimeout(this._searchTimer);
        this._searchTimer = window.setTimeout(() => {
            this.runSearch();
        }, 300);
    }

    /**
     * Searches the active tab and hides people who are already selected, including the owner.
     */
    async runSearch() {
        const term = (this.searchTerm || '').trim();
        if (term.length < 2) {
            this.results = [];
            return;
        }
        this.isSearching = true;
        this.errorMessage = '';
        try {
            const found = await search({ eventId: this.recordId, term, tab: this.activeTab });
            const selected = new Set(this.displayedAttendees.map((row) => row.recordId));
            this.results = found
                .filter((row) => !selected.has(row.recordId))
                .map((row) => ({ ...row, iconName: this.iconFor(row.kind) }));
        } catch (error) {
            this.errorMessage = this.messageFrom(error);
            this.results = [];
        } finally {
            this.isSearching = false;
        }
    }

    /**
     * Stages the clicked search hit. Re-selecting a removed invitee cancels that removal.
     * @param {MouseEvent} event Click on a search result. data-id is the record Id.
     */
    handleAdd(event) {
        const recordId = event.currentTarget.dataset.id;
        const match = this.results.find((row) => row.recordId === recordId);
        if (!match) {
            return;
        }
        const removedExisting = this.attendees.find(
            (row) => row.recordId === recordId && this._removedRelationIds.includes(row.relationId)
        );
        if (removedExisting) {
            this._removedRelationIds = this._removedRelationIds.filter((id) => id !== removedExisting.relationId);
        } else if (!this._added.some((row) => row.recordId === recordId)) {
            this._added = this._added.concat({
                relationId: null,
                recordId: match.recordId,
                name: match.name,
                kind: match.kind,
                pending: true
            });
        }
        this.results = [];
        this.searchTerm = '';
        this.publishChanges();
    }

    /**
     * Stages a removal. A pending add is dropped. The Event owner is left in place.
     * @param {MouseEvent} event Click on a pill remove button. data-id is the record Id.
     */
    handleRemove(event) {
        const recordId = event.currentTarget.dataset.id;
        const pending = this._added.find((row) => row.recordId === recordId);
        if (pending) {
            this._added = this._added.filter((row) => row.recordId !== recordId);
        } else {
            const existing = this.attendees.find((row) => row.recordId === recordId);
            if (existing?.isOwner === true) {
                return;
            }
            if (existing && !this._removedRelationIds.includes(existing.relationId)) {
                this._removedRelationIds = this._removedRelationIds.concat(existing.relationId);
            }
        }
        this.publishChanges();
    }

    /**
     * Sends the staged adds and removes to the flow. An empty string means nothing should be saved.
     */
    publishChanges() {
        const payload = JSON.stringify({
            addIds: this._added.map((row) => row.recordId),
            removeRelationIds: this._removedRelationIds
        });
        const hasChanges = this._added.length > 0 || this._removedRelationIds.length > 0;
        const value = hasChanges ? payload : '';
        this.changePayload = value;
        this.dispatchEvent(new FlowAttributeChangeEvent('changePayload', value));
    }

    /**
     * @param {string} kind User, Contact, Lead, or Resource.
     * @returns {string} SLDS icon name for that kind.
     */
    iconFor(kind) {
        if (kind === 'Contact') {
            return 'standard:contact';
        }
        if (kind === 'Lead') {
            return 'standard:lead';
        }
        if (kind === 'Resource') {
            return 'standard:service_resource';
        }
        return 'standard:user';
    }

    /**
     * @param {object} error Apex or client error.
     * @returns {string} Message safe to show above the tabs.
     */
    messageFrom(error) {
        return error?.body?.message || 'Attendees could not be loaded.';
    }
}