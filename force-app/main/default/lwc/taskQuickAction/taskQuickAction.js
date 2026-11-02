// LWC JS
import { LightningElement, api } from 'lwc';
import getTaskById from '@salesforce/apex/TaskQuickActionController.getTaskById';
import updateCaseEmailLanguage from '@salesforce/apex/TaskQuickActionController.updateCaseEmailLanguage';
import updateCaseEmailType from '@salesforce/apex/TaskQuickActionController.updateCaseEmailType';

export default class TaskQuickAction extends LightningElement {
    @api recordId;
    @api hardcodedValue;
    isLoading = true;
    taskData;
     
    connectedCallback() {
        this.fetchTaskData();
        console.log('hardcoded Value', this.hardcodedValue);
    }
   
    async fetchTaskData() {
        try {
            this.taskData = await getTaskById({ taskId: this.recordId });

            if (this.taskData) {
                console.log('DEBUG: Task Id:', this.taskData.Id);
                console.log('DEBUG: WhatId:', this.taskData.WhatId);
                console.log('DEBUG: EmailType__c:', this.taskData.EmailType__c);

                if (this.taskData.EmailType__c && this.taskData.WhatId) {
                    await updateCaseEmailType({
                        caseId: this.taskData.WhatId,
                        emailType: this.taskData.EmailType__c
                    });
                }
                if (this.taskData.WhatId && this.hardcodedValue) {
                    await updateCaseEmailLanguage({
                        caseId: this.taskData.WhatId,
                        language: this.hardcodedValue
                    });
                }
                // Notify Aura wrapper with Case Id
                this.dispatchEvent(new CustomEvent('complete', {
                    detail: { caseId: this.taskData.WhatId }
                }));

            }
        } catch (error) {
            console.error('DEBUG: Error fetching Task:', JSON.stringify(error));
        } finally {
            this.isLoading = false;
        }
    }
}