/**
 * @description       : This faceless LWC is used to redirect the user
 *                      from standard 'Select Opportunity Record Type' page to
 *                      the standard New Opportunity Screen,
 *                      with the Opportunity Name field pre-populated by default,
 *                      for LS Equipment & Service and LS Consumables opportunity record types.
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
import OPPORTUNITY_OBJECT from '@salesforce/schema/Opportunity';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';

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
    objectInfo ;

    oppNameValue = '';

    @wire(CurrentPageReference)
    getStateParameters(currentPageReference) {
        debugger;
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
        
        // This navigation is already done by the standard New page.
        if (state.nooverride === '1' || !this.recordTypeId) {
            return;
        }
        this.hasNavigated = true;
    }

    @wire(getObjectInfo, { objectApiName: OPPORTUNITY_OBJECT })
    wiredObjectInfo({ error, data }) {
        debugger;
        if (data) {
            this.objectInfo = data;
            if (this.objectInfo && this.objectInfo.recordTypeInfos && this.recordTypeId) {
                const rtInfo = this.objectInfo.recordTypeInfos[this.recordTypeId];
                if(rtInfo.name === 'LS - Equipment & Service' || rtInfo.name === 'LS - Consumables') {
                    this.oppNameValue = LSOpportunityNameValue;
                }  else {
                    this.oppNameValue = '';
                }
            }
            this.navigateToNewOpptyScreen();


        } else if (error) {
            console.error('Error fetching object info:', error);
        }
    }

    // Navigate to the New Opportunity Screen.
    navigateToNewOpptyScreen() {
        debugger;
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
    
}