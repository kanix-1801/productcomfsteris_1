/**
 * @description       : This faceless LWC is used to redirect the user
 *                      from standard 'Select Opportunity Record Type' page to
 *                      the standard New Opportunity Screen,
 *                      with the Opportunity Name field pre-populated by default,
 *                      for Life Sciences Sales App users.
 * @author            : Sarthak Pani
 * @last modified on  : 01-10-2026
 * @last modified by  : Sarthak Pani
 * @Change log        : Initial Version
**/

import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { encodeDefaultFieldValues } from 'lightning/pageReferenceUtils';
import { CurrentPageReference } from 'lightning/navigation';
import LSOpportunityNameValue from '@salesforce/label/c.LSOpportunityNameValue';

import formFactor from '@salesforce/client/formFactor';
import getCurrentAppDeveloperName from '@salesforce/apex/CurrentAppService.getCurrentAppDeveloperName';

const LIFE_SCIENCE_SALES_APP = 'LifeSciencesSales';

export default class LSNewOppScreen extends NavigationMixin(LightningElement) {
    
    recordTypeId;
    actionType;
    count;
    useRecordTypeCheck;
    navigationLocation;
    uid;
    backgroundContext;

    hasNavigated = false;
    isLifeScienceSalesApp = false;

    oppNameValue = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        if (!currentPageReference || this.hasNavigated) {
            return;
        }
        const state = currentPageReference.state || {};
        this.recordTypeId = state.recordTypeId;
        this.actionType = state.c__actionType;
        this.count = state.count;
        this.useRecordTypeCheck = state.useRecordTypeCheck;
        this.navigationLocation = state.navigationLocation;
        this.uid = state.uid;
        this.backgroundContext = state.backgroundContext;
        
        // This navigation already asked for the standard New page.
        if (state.nooverride === '1' || !this.recordTypeId) {
            return;
        }
        this.hasNavigated = true;
        this.getCurrentAppDeveloperName();
    }

    // Call Apex to check if user is in LS Sales App or not.
    // If yes, set the Opportunity Name field pre-populated by default.
    // Then navigate to the New Opportunity Screen.
    getCurrentAppDeveloperName() {
        this.oppNameValue = '';
        this.isLifeScienceSalesApp = false;
        
        getCurrentAppDeveloperName({ formFactor }).then(result => {
            if(result === LIFE_SCIENCE_SALES_APP) {
                this.isLifeScienceSalesApp = true;
                this.oppNameValue = LSOpportunityNameValue;
            }
            this.navigateToNewOpptyScreen();
        }).catch(error => {
            console.error('Error getting current app developer name:', error);
        });
    }

    // Navigate to the New Opportunity Screen.
    navigateToNewOpptyScreen() {
        // 1. Encode your default values (using exact API names)
        const defaultValues = encodeDefaultFieldValues({
            Name: this.oppNameValue
        });

        // 2. Invoke NavigationMixin.Navigate
        this[NavigationMixin.Navigate]({
            type: 'standard__objectPage',
            attributes: {
                objectApiName: 'Opportunity',
                actionName: 'new'
            },
            state: {
                count: this.count,
                nooverride: '1',
                recordTypeId: this.recordTypeId,
                useRecordTypeCheck: this.useRecordTypeCheck ? this.useRecordTypeCheck : 1,
                navigationLocation: this.navigationLocation ? this.navigationLocation : 'LIST_VIEW',
                uid: this.uid,
                backgroundContext: this.backgroundContext ? this.backgroundContext : '/lightning/o/Opportunity/list?filterName=__Recent',
                defaultFieldValues: defaultValues
            }
        });
    }




    

    // handleClose() {
    //     this.showModal = false;
    //     this[NavigationMixin.Navigate]({
    //         type: 'standard__objectPage',
    //         attributes: {
    //             objectApiName: 'Opportunity',
    //             actionName: 'home'
    //         }
    //     });
    // }

    /**
     * @description Loads Opportunity record types the current user can create.
     *              Master is omitted. The user's default record type is preselected.
     */
    // @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    // wiredOpportunityInfo({ data, error }) {
    //     if (data) {
    //         const availableRecordTypes = Object.values(data.recordTypeInfos || {}).filter(
    //             (info) => info && info.available && !info.master
    //         );

    //         this.recordTypeOptions = availableRecordTypes
    //             .map((info) => ({
    //                 label: info.name,
    //                 value: info.recordTypeId
    //             }))
    //             .sort((left, right) => left.label.localeCompare(right.label));

    //         const defaultRecordType = availableRecordTypes.find((info) => info.defaultRecordTypeMapping);
    //         this.selectedRecordTypeId = defaultRecordType
    //             ? defaultRecordType.recordTypeId
    //             : this.recordTypeOptions[0]?.value;

    //         this.errorMessage = undefined;
    //         this.isLoading = false;
    //     } else if (error) {
    //         this.recordTypeOptions = [];
    //         this.selectedRecordTypeId = undefined;
    //         this.errorMessage = this.reduceError(error);
    //         this.isLoading = false;
    //     }
    // }

    // connectedCallback() {
    //     console.log('recordTypeId', this.recordTypeId);
    //     //this.navigateToNewOpportunity();  //this will call recursion
    // }

    // get hasRecordTypes() {
    //     return this.recordTypeOptions.length > 0;
    // }

    // get showEmptyState() {
    //     return !this.isLoading && !this.errorMessage && !this.hasRecordTypes;
    // }

    // get isNextDisabled() {
    //     return !this.selectedRecordTypeId;
    // }

    // handleRecordTypeChange(event) {
    //     this.selectedRecordTypeId = event.detail.value;
    // }

    

    // reduceError(error) {
    //     if (Array.isArray(error?.body)) {
    //         return error.body.map((entry) => entry.message).join(', ');
    //     }
    //     return error?.body?.message || error?.message || 'Unable to load Opportunity record types.';
    // }


    

    // navigateToRecord() {
    //     const defaultValues = encodeDefaultFieldValues({
    //         Name: 'This is a placeholder name. Do not remove.'
    //     });

    //     this[NavigationMixin.Navigate]({
    //         type: 'standard__component',
    //         attributes: {
    //             componentName: 'c__targetComponent'
    //         },
    //         state: {
    //             defaultFieldValues: defaultValues // Appends as ?c__appendedValue=12345
    //         }
    //     });
    // }

    

    // navigateToRecord() {
    //     const defaultValues = encodeDefaultFieldValues({
    //         Name: 'This is a placeholder name. Do not remove.'
    //     });

    //     this[NavigationMixin.Navigate]({
    //         type: 'standard__component',
    //         attributes: {
    //             componentName: 'c__targetComponent'
    //         },
    //         state: {
    //             defaultFieldValues: defaultValues // Appends as ?c__appendedValue=12345
    //         }
    //     });
    // }
    
}