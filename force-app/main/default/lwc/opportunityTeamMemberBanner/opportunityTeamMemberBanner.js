import { LightningElement, api, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import OPPORTUNITY_TEAM_MEMBER_COUNT from '@salesforce/schema/Opportunity.Opportunity_Team_Member_Count__c';

const BANNER_MESSAGE =
    'Sales Operations / Contracting team members were not added. Add them manually from the Opportunity Team related list.';

export default class OpportunityTeamMemberBanner extends LightningElement {
    @api recordId;

    teamMemberCount;

    @wire(getRecord, {
        recordId: '$recordId',
        fields: [OPPORTUNITY_TEAM_MEMBER_COUNT]
    })
    wiredOpportunity({ data }) {
        if (data) {
            this.teamMemberCount = getFieldValue(
                data,
                OPPORTUNITY_TEAM_MEMBER_COUNT
            );
        }
    }

    get isVisible() {
        return Number(this.teamMemberCount) === 0;
    }

    get bannerMessage() {
        return BANNER_MESSAGE;
    }
}