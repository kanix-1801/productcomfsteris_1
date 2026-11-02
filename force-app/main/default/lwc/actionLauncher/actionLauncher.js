import { LightningElement, api, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import USER_ID from '@salesforce/user/Id';
import ACCOUNT_OWNER_ID from '@salesforce/schema/Account.OwnerId';

import getActions from '@salesforce/apex/ActionLauncherController.getActions';
import getVisibilityConfig from '@salesforce/apex/AccountPageVisibilityController.getVisibilityConfig';
import hasKeyAccountProcessReviewPermission from '@salesforce/customPermission/KeyAccountProcessReview';

const PAGE_NAME = 'Customer360';
const COMPONENT_API_NAME = 'ActionLauncher';
const DEFAULT_OBJECT_API_NAME = 'Account';
const DEFAULT_VISIBLE_ACTION_COUNT = 3;
const WEB_LINK = 'WebLink';
const PROCESS_REVIEW_ACTION_API_NAME = 'Account.CreateKeyAccountProcessReview';

export default class ActionLauncher extends NavigationMixin(LightningElement) {
    @api recordId;
    @api objectApiName;

    /** Comma separated quick action API names, maintained in Lightning App Builder. */
    @api actionApiNames;

    /** How many actions render as pills before the rest move into the dropdown. */
    @api visibleActionCount = DEFAULT_VISIBLE_ACTION_COUNT;

    searchTerm = '';
    actions = [];
    loadError = false;
    configByComponent = {};
    accountOwnerId;

    get effectiveRecordId() {
        return this.recordId || this.getRecordIdFromUrl();
    }

    get effectiveObjectApiName() {
        return this.objectApiName || DEFAULT_OBJECT_API_NAME;
    }

    @wire(getVisibilityConfig, {
        accountId: '$effectiveRecordId',
        pageName: PAGE_NAME
    })
    wiredVisibilityConfig({ data, error }) {
        if (data) {
            this.configByComponent = {};

            data.configs.forEach((item) => {
                this.configByComponent[item.componentApiName] = item;
            });
        } else if (error) {
            this.configByComponent = {};
            // eslint-disable-next-line no-console
            console.error('Action Launcher visibility error', error);
        }
    }

    @wire(getRecord, {
        recordId: '$effectiveRecordId',
        fields: [ACCOUNT_OWNER_ID]
    })
    wiredAccount({ data, error }) {
        if (data) {
            this.accountOwnerId = data.fields?.OwnerId?.value;
        } else if (error) {
            this.accountOwnerId = undefined;
            // eslint-disable-next-line no-console
            console.error('Action Launcher owner lookup error', error);
        }
    }

    @wire(getActions, {
        recordId: '$effectiveRecordId',
        objectApiName: '$effectiveObjectApiName',
        actionApiNames: '$actionApiNames'
    })
    wiredActions({ data, error }) {
        if (data) {
            this.actions = data
                .filter((action) => this.isActionAvailable(action.apiName))
                .map((action) => ({
                    apiName: action.apiName,
                    label: action.label,
                    actionType: action.actionType,
                    url: action.url,
                    opensInNewWindow: action.opensInNewWindow === true
                }));
            this.loadError = false;
        } else if (error) {
            this.actions = [];
            this.loadError = true;
            // eslint-disable-next-line no-console
            console.error('Action Launcher failed to load actions', error);
        }
    }

    get filteredActions() {
        const term = this.searchTerm.trim().toLowerCase();

        if (!term) {
            return this.actions;
        }

        return this.actions.filter((action) => action.label.toLowerCase().includes(term));
    }

    // App Builder hands the property over as a string, so coerce before slicing.
    get inlineActionLimit() {
        const configuredLimit = Number(this.visibleActionCount);

        return Number.isFinite(configuredLimit) && configuredLimit > 0
            ? Math.floor(configuredLimit)
            : DEFAULT_VISIBLE_ACTION_COUNT;
    }

    get primaryActions() {
        return this.filteredActions.slice(0, this.inlineActionLimit);
    }

    get overflowActions() {
        return this.filteredActions.slice(this.inlineActionLimit);
    }

    get hasOverflowActions() {
        return this.overflowActions.length > 0;
    }

    get overflowLabel() {
        const count = this.overflowActions.length;

        return count === 1 ? '1 more action' : `${count} more actions`;
    }

    get isRecordOwner() {
        return this.idsMatch(this.accountOwnerId, USER_ID);
    }

    get showActionLauncher() {
        return this.isVisible(COMPONENT_API_NAME) || this.isRecordOwner;
    }

    get showNoResults() {
        return !this.loadError && this.filteredActions.length === 0;
    }

    get noResultsMessage() {
        return this.actions.length === 0
            ? 'No actions are available.'
            : 'No actions match your search.';
    }

    isVisible(componentName) {
        return this.configByComponent[componentName]?.isVisible === true;
    }

    // Key Account Process Review PS is the only grant of this custom permission.
    isActionAvailable(apiName) {
        if (apiName !== PROCESS_REVIEW_ACTION_API_NAME) {
            return true;
        }

        return hasKeyAccountProcessReviewPermission === true;
    }

    idsMatch(leftId, rightId) {
        if (!leftId || !rightId) {
            return false;
        }

        return String(leftId).substring(0, 15) === String(rightId).substring(0, 15);
    }

    handleSearchChange(event) {
        this.searchTerm = event.target.value;
    }

    handleActionClick(event) {
        this.launchAction(event.currentTarget.dataset.apiName);
    }

    handleOverflowSelect(event) {
        this.launchAction(event.detail.value);
    }

    launchAction(actionApiName) {
        const action = this.actions.find((item) => item.apiName === actionApiName);

        if (!action) {
            return;
        }

        if (action.actionType === WEB_LINK) {
            this.launchWebLink(action);
            return;
        }

        this[NavigationMixin.Navigate]({
            type: 'standard__quickAction',
            attributes: {
                apiName: action.apiName
            },
            state: {
                recordId: this.effectiveRecordId
            }
        });
    }

    launchWebLink(action) {
        if (!action.url) {
            return;
        }

        const pageReference = {
            type: 'standard__webPage',
            attributes: {
                url: action.url
            }
        };

        if (action.opensInNewWindow) {
            this[NavigationMixin.GenerateUrl](pageReference).then((url) => {
                window.open(url, '_blank', 'noopener');
            });
            return;
        }

        this[NavigationMixin.Navigate](pageReference);
    }

    getRecordIdFromUrl() {
        const match = window.location.pathname.match(/\/Account\/([a-zA-Z0-9]{15,18})/);

        return match ? match[1] : null;
    }
}