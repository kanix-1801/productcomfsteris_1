/**
 * @author Sahithi
 * @date 04-11-2026
 * @description 3658 - Warning banner for an Instrument Processing Opportunity.
 *              Shows when Sales Operations / Contracting team members were not added
 *              and Opportunity_Team_Member_Count__c is 0.
 */
import { LightningElement, api, wire } from 'lwc';
import { getFieldValue, getRecord } from 'lightning/uiRecordApi';
import OPPORTUNITY_TEAM_MEMBER_COUNT from '@salesforce/schema/Opportunity.Opportunity_Team_Member_Count__c';

const BANNER_MESSAGE =
    'Sales Operations / Contracting team members were not added. Add them manually from the Opportunity Team related list.';

export default class OpportunityTeamMemberBanner extends LightningElement {
    @api recordId;

    teamMemberCount;

    /**
     * @description 3658 - Reads Opportunity_Team_Member_Count__c for the current record.
     */
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

    /**
     * @description 3658 - Banner is shown only when the team member count is 0.
     */
    get isVisible() {
        return Number(this.teamMemberCount) === 0;
    }

    /**
     * @description 3658 - Message telling the user to add the team members manually.
     */
    get bannerMessage() {
        return BANNER_MESSAGE;
    }
}