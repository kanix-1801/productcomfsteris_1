/**
 * Queueable class responsible for creating assignment history records
 * 				  and removing Account Team Member and Opportunity Team Member assignments for inactive Sales Users.
 * @author 		: Vinay
 * @date 		: 2026-06-12
 */

public inherited sharing class InactiveUserTeamCleanup implements Queueable {
    private Set<Id> userIds;
    private Set<String> teamMemberRoles;
    private Map<Id, Date> userIdToInactiveDate;
	/**
     *Initializes cleanup processing with User, role,
     * and inactivation date information.
     */
    public InactiveUserTeamCleanup(
        Set<Id> userIds,
         Set<String> teamMemberRoles,
        Map<Id, Date> userIdToInactiveDate
    ) {
        this.userIds = new Set<Id>(userIds);
        this.teamMemberRoles = new Set<String>(teamMemberRoles);
        this.userIdToInactiveDate = new Map<Id, Date>(userIdToInactiveDate);
    }

    /**
     *Creates assignment history records and deletes
     * matching team member assignments.
     */
    public void execute(QueueableContext queueableContext) {
        List<AccountTeamMember> accountTeamMembers = TeamMemberSelector.getAccountTeamMembersByUserIdsAndRoles(userIds,  teamMemberRoles);

        List<OpportunityTeamMember> opportunityTeamMembers = TeamMemberSelector.getOpportunityTeamMembersByUserIdsAndRoles(userIds,  teamMemberRoles);

        if (accountTeamMembers.isEmpty() && opportunityTeamMembers.isEmpty()) {
            return;
        }

        List<InactiveUserAssignmentHistory__c> historyRecords =
            buildHistoryRecords(accountTeamMembers, opportunityTeamMembers);

        List<SObject> teamMembersToDelete = new List<SObject>();
        teamMembersToDelete.addAll(accountTeamMembers);
        teamMembersToDelete.addAll(opportunityTeamMembers);

        try {
            if (!historyRecords.isEmpty()) {
                insert historyRecords;
            }

            if (!teamMembersToDelete.isEmpty()) {
                delete teamMembersToDelete;
            }
        } catch (DmlException exceptionRecord) {
            Logger.error('Failed to process inactive Sales User team member cleanup.')
                .addTag('UserTrigger')
                .setRecord(teamMembersToDelete);

            throw exceptionRecord;
        } finally {
            Logger.saveLog();
        }
    }

   	/**
     *Builds assignment history records prior to
     * Account Team Member and Opportunity Team Member deletion.
     */
    private List<InactiveUserAssignmentHistory__c> buildHistoryRecords(
        List<AccountTeamMember> accountTeamMembers,
        List<OpportunityTeamMember> opportunityTeamMembers
    ) {
        List<InactiveUserAssignmentHistory__c> historyRecords =
            new List<InactiveUserAssignmentHistory__c>();

        for (AccountTeamMember accountTeamMember : accountTeamMembers) {
            historyRecords.add(
                new InactiveUserAssignmentHistory__c(
                    User__c = accountTeamMember.UserId,
                    Account__c = accountTeamMember.AccountId,
                    Assignment_Type__c = accountTeamMember.TeamMemberRole,
                    AssignmentObject__c = 'Account',
                    UserInactivationDate__c =  System.today()
                       // userIdToInactiveDate.get(accountTeamMember.UserId)
                )
            );
        }

        for (OpportunityTeamMember opportunityTeamMember : opportunityTeamMembers) {
            historyRecords.add(
                new InactiveUserAssignmentHistory__c(
                    User__c = opportunityTeamMember.UserId,
                    Opportunity__c = opportunityTeamMember.OpportunityId,
                    Assignment_Type__c = opportunityTeamMember.TeamMemberRole,
                    AssignmentObject__c = 'Opportunity',
                    UserInactivationDate__c = System.today()
                       // userIdToInactiveDate.get(opportunityTeamMember.UserId)
                )
            );
        }

        return historyRecords;
    }
}