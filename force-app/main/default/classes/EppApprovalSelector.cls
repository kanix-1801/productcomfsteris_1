/**
 * @description SOQL accessors for sequential EPP regional approval (GC-3432).
 */
public with sharing class EppApprovalSelector {
    @TestVisible
    private static List<EPP_Approval_Hierarchy__mdt> testHierarchy;

    /**
     * @description Loads EPP Opportunity fields used for submit validation and status updates.
     * @param opportunityId Opportunity Id.
     * @return Opportunity row or null when not found.
     */
    public static Opportunity selectOpportunity(Id opportunityId) {
        List<Opportunity> rows = [
            SELECT
                Id,
                Name,
                AccountId,
                StageName,
                Region__c,
                Country__c,
                Financial_Link__c,
                Product_Equipment__c,
                Placement_Start_Date__c,
                Placement_End_Date__c,
                Customer_Commercial_Commitment_Type__c,
                ConsumablesCommitment__c,
                ServiceCommitment__c,
                InstallationCommitment__c,
                ServiceType__c,
                OtherServiceTypeDetails__c,
                AnnualServiceAmount__c,
                PreventativeMaintenanceFrequency__c,
                ServiceStartDate__c,
                ServiceEndDate__c,
                InstallationAmount__c,
                EPP_Approval_Status__c,
                EPP_Sequence_Completed__c,
                EPP_All_Approvals_Complete__c,
                EPP_Submitted_Date__c,
                EPP_Submitted_By__c,
                RecordType.DeveloperName
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    /**
     * @description Capital equipment lines for an EPP, using the same product filter as the EPP Products tab.
     * @param opportunityId Opportunity Id.
     * @return Equipment Opportunity Products.
     */
    public static List<OpportunityLineItem> selectEquipmentLines(Id opportunityId) {
        if (opportunityId == null) {
            return new List<OpportunityLineItem>();
        }
        return EPPPricebookEntrySelector.selectLines(opportunityId, false);
    }

    /**
     * @description Consumable lines for an EPP, using the same product filter as the EPP Products tab.
     * @param opportunityId Opportunity Id.
     * @return Consumable Opportunity Products.
     */
    public static List<OpportunityLineItem> selectConsumableLines(Id opportunityId) {
        if (opportunityId == null) {
            return new List<OpportunityLineItem>();
        }
        return EPPPricebookEntrySelector.selectLines(opportunityId, true);
    }

    /**
     * @description Active hierarchy rows for a canonical region, ordered by sequence.
     * @param region Canonical region value stored on custom metadata.
     * @return Hierarchy rows, or the test override list when set.
     */
    public static List<EPP_Approval_Hierarchy__mdt> selectHierarchy(String region) {
        if (testHierarchy != null) {
            List<EPP_Approval_Hierarchy__mdt> matchingRows = new List<EPP_Approval_Hierarchy__mdt>();
            for (EPP_Approval_Hierarchy__mdt row : testHierarchy) {
                if (row.Active__c && region != null && region.equalsIgnoreCase(row.Region__c)) {
                    matchingRows.add(row);
                }
            }
            return matchingRows;
        }

        return [
            SELECT Region__c, Sequence__c, Approver_Username__c, Approver_Role__c, Active__c
            FROM EPP_Approval_Hierarchy__mdt
            WHERE Active__c = TRUE
            AND Region__c = :region
            ORDER BY Sequence__c
        ];
    }

    /**
     * @description Current-submission approver rows ordered by sequence.
     * @param opportunityId Opportunity Id.
     * @return DealApprovalApprover__c rows.
     */
    public static List<DealApprovalApprover__c> selectCurrentApprovers(Id opportunityId) {
        return [
            SELECT
                Id,
                Opportunity__c,
                Approver__c,
                Approver__r.Name,
                Approver__r.Email,
                Approver__r.IsActive,
                ApproverRole__c,
                Sequence__c,
                IsCurrent__c,
                Decision__c,
                DecisionComments__c,
                DecisionDate__c,
                Submitted_By__c
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityId
            AND IsCurrent__c = TRUE
            ORDER BY Sequence__c NULLS LAST
        ];
    }

    /**
     * @description Resolves Users by Username for hierarchy routing.
     * @param usernames Salesforce Usernames.
     * @return Username to User map.
     */
    public static Map<String, User> selectUsersByUsername(Set<String> usernames) {
        Map<String, User> usersByUsername = new Map<String, User>();
        if (usernames == null || usernames.isEmpty()) {
            return usersByUsername;
        }

        for (User userRow : [
            SELECT Id, Name, Email, Username, IsActive
            FROM User
            WHERE Username IN :usernames
        ]) {
            usersByUsername.put(userRow.Username, userRow);
        }
        return usersByUsername;
    }

    /**
     * @description Custom notification type Id for EPP approval alerts.
     * @param developerName CustomNotificationType DeveloperName.
     * @return Notification type Id or null.
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