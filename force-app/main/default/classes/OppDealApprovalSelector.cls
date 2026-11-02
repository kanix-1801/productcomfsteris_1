/**
 * @author Himanshu Chaurasia
 * @date 2026/09/15
 *
 * @group GC-3235
 *
 * @description SOQL accessors for Strategic Contract deal approval (Opportunity, team, approvers, notifications).
 */
public with sharing class OppDealApprovalSelector {
    /**
     * @description Loads Opportunity header fields used by submit, decide, and panel rendering.
     * @param opportunityId Opportunity Id.
     * @return Opportunity row with deal approval and strategic contract fields, or null when not found.
     */
    public static Opportunity selectOpportunity(Id opportunityId) {
        return [
            SELECT
                Id,
                Name,
                StageName,
                OwnerId,
                Owner.Name,
                Owner.Email,
                RecordType.DeveloperName,
                DealApprovalStatus__c,
                DealApprovalRejectionReason__c,
                DealApprovalSubmissionComments__c,
                Dealstrategy__c,
                FinancialAssessment__c,
                BusinessUnit__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
    }

    /**
     * @description Returns Deal Desk Lead and Business Unit Leader team members for approver resolution.
     * @param opportunityId Opportunity Id.
     * @return Matching Opportunity Team Member rows.
     */
    public static List<OpportunityTeamMember> selectApproverTeamMembers(Id opportunityId) {
        return [
            SELECT Id, OpportunityId, UserId, User.Name, User.Email, User.IsActive, TeamMemberRole
            FROM OpportunityTeamMember
            WHERE OpportunityId = :opportunityId
            AND TeamMemberRole IN (
                :OppDealApprovalService.ROLE_DEAL_DESK,
                :OppDealApprovalService.ROLE_BU_LEADER
            )
        ];
    }

    /**
     * @description Loads active approver rows for an in-flight or completed approval cycle.
     * @param opportunityId Opportunity Id.
     * @return Current DealApprovalApprover__c rows ordered by role and approver name.
     */
    public static List<DealApprovalApprover__c> selectCurrentApprovers(Id opportunityId) {
        if (opportunityId == null) {
            return new List<DealApprovalApprover__c>();
        }

        return [
            SELECT
                Id,
                Opportunity__c,
                Approver__c,
                Approver__r.Name,
                Approver__r.Email,
                Approver__r.IsActive,
                ApproverRole__c,
                IsRequired__c,
                IsCurrent__c,
                Decision__c,
                DecisionComments__c,
                DecisionDate__c
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityId
            AND IsCurrent__c = true
            ORDER BY ApproverRole__c, Approver__r.Name
        ];
    }

    /**
     * @description Loads a single approver row for decision validation and update.
     * @param approverRecordId DealApprovalApprover__c Id.
     * @return Approver row with decision fields, or null when not found.
     */
    public static DealApprovalApprover__c selectApprover(Id approverRecordId) {
        return [
            SELECT
                Id,
                Opportunity__c,
                Approver__c,
                ApproverRole__c,
                IsRequired__c,
                IsCurrent__c,
                Decision__c
            FROM DealApprovalApprover__c
            WHERE Id = :approverRecordId
            LIMIT 1
        ];
    }

    /**
     * @description GC-3517 Next approval cycle for a submit. The first submit is cycle 1.
     * @param opportunityId Opportunity Id.
     * @return Highest Approval Cycle Number plus 1, or 1 when no approver rows exist.
     */
    public static Integer selectNextApprovalCycleNumber(Id opportunityId) {
        if (opportunityId == null) {
            return 1;
        }

        AggregateResult[] cycleResults = [
            SELECT MAX(ApprovalCycleNumber__c) maxCycle
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityId
        ];
        Decimal maxCycle = (Decimal) cycleResults[0].get('maxCycle');
        if (maxCycle == null) {
            Integer existingRows = [
                SELECT COUNT()
                FROM DealApprovalApprover__c
                WHERE Opportunity__c = :opportunityId
            ];
            return existingRows > 0 ? 2 : 1;
        }
        return Integer.valueOf(maxCycle) + 1;
    }

    /**
     * @description Resolves Custom Notification Type Id for deal approval alerts.
     * @param developerName CustomNotificationType DeveloperName.
     * @return Notification type Id, or null when metadata is not deployed.
     */
    public static Id selectNotificationTypeId(String developerName) {
        List<CustomNotificationType> notificationTypes = [
            SELECT Id
            FROM CustomNotificationType
            WHERE DeveloperName = :developerName
            LIMIT 1
        ];
        return notificationTypes.isEmpty() ? null : notificationTypes[0].Id;
    }
}