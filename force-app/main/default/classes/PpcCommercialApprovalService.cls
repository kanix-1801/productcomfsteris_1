/**
 * @description Pay Per Click commercial approval. The submit screen flow selects the approver
 *              users, and this class stores the decision on the existing Deal Approval Approver
 *              object. Strategic Contract approval is unchanged.
 */
public with sharing class PpcCommercialApprovalService {
    public static final String RECORD_TYPE_DEVELOPER_NAME = 'HCSalesPayPerClick';
    public static final String STAGE_PROPOSAL = 'Proposal';

    public static final String OPP_STATUS_NOT_SUBMITTED = 'Not Submitted';
    public static final String OPP_STATUS_PENDING = 'Pending Approval';
    public static final String OPP_STATUS_APPROVED = 'Approved';
    public static final String OPP_STATUS_REJECTED = 'Rejected';

    public static final String DECISION_PENDING = 'Pending';
    public static final String DECISION_APPROVED = 'Approved';
    public static final String DECISION_REJECTED = 'Rejected';

    public static final String MODE_HIDDEN = 'Hidden';
    public static final String MODE_SUBMIT = 'Submit';
    public static final String MODE_PENDING_APPROVER = 'PendingApprover';
    public static final String MODE_PENDING_VIEWER = 'PendingViewer';
    public static final String MODE_APPROVED = 'Approved';
    public static final String MODE_REJECTED = 'Rejected';

    private static final String NOTIFICATION_TYPE = 'Deal_Submitted_For_Approval';
    private static final String CLASS_NAME = 'PpcCommercialApprovalService';

    public class ApprovalContext {
        @AuraEnabled public Boolean showPanel;
        @AuraEnabled public String mode;
        @AuraEnabled public Boolean canSubmit;
        @AuraEnabled public Boolean canDecide;
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String opportunityName;
        @AuraEnabled public String dealApprovalStatus;
        @AuraEnabled public String rejectionReason;
        @AuraEnabled public String submissionComments;
        @AuraEnabled public String financialAssessment;
        @AuraEnabled public String financialAssessmentLink;
        @AuraEnabled public String missingRequirements;
        @AuraEnabled public Id currentApproverRecordId;
        @AuraEnabled public List<ApproverRow> approvers;
        @AuraEnabled public List<ApproverRow> history;
    }

    public class ApproverRow {
        @AuraEnabled public Id id;
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String role;
        @AuraEnabled public Boolean required;
        @AuraEnabled public String decision;
        @AuraEnabled public String comments;
        @AuraEnabled public String decisionDate;
        @AuraEnabled public Boolean isCurrentUser;
    }

    @AuraEnabled
    public static ApprovalContext getApprovalContext(Id opportunityId) {
        if (opportunityId == null) {
            throw auraError('Opportunity Id is required.');
        }

        Opportunity opportunityRecord = selectOpportunity(opportunityId);
        ApprovalContext context = baseContext(opportunityRecord);
        if (!context.showPanel) {
            return context;
        }

        List<DealApprovalApprover__c> allApprovers = selectApprovers(opportunityId);
        List<DealApprovalApprover__c> currentApprovers = new List<DealApprovalApprover__c>();
        List<DealApprovalApprover__c> priorApprovers = new List<DealApprovalApprover__c>();
        for (DealApprovalApprover__c approverRecord : allApprovers) {
            if (approverRecord.IsCurrent__c) {
                currentApprovers.add(approverRecord);
            } else {
                priorApprovers.add(approverRecord);
            }
        }

        context.history = toApproverRows(priorApprovers);
        String opportunityStatus = currentStatus(opportunityRecord);

        if (OPP_STATUS_PENDING.equals(opportunityStatus)) {
            context.approvers = toApproverRows(currentApprovers);
            context.mode = MODE_PENDING_VIEWER;
            DealApprovalApprover__c currentApprover = findPendingApprover(currentApprovers);
            if (currentApprover != null) {
                context.mode = MODE_PENDING_APPROVER;
                context.canDecide = true;
                context.currentApproverRecordId = currentApprover.Id;
            }
            return context;
        }

        if (OPP_STATUS_APPROVED.equals(opportunityStatus)) {
            context.approvers = toApproverRows(currentApprovers);
            context.mode = MODE_APPROVED;
            return context;
        }

        if (OPP_STATUS_REJECTED.equals(opportunityStatus)) {
            context.approvers = toApproverRows(currentApprovers);
            context.mode = MODE_REJECTED;
            return context;
        }

        context.mode = MODE_SUBMIT;
        return context;
    }

    public class FlowSubmitRequest {
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;
        @InvocableVariable(label='Submission Comments')
        public String comments;
        @InvocableVariable(label='Approver User 1')
        public Id approverUser1;
        @InvocableVariable(label='Approver User 2')
        public Id approverUser2;
        @InvocableVariable(label='Approver User 3')
        public Id approverUser3;
    }

    public class FlowSubmitResult {
        @InvocableVariable(label='Success')
        public Boolean success;
        @InvocableVariable(label='Message')
        public String message;
    }

    @InvocableMethod(
        label='Submit Pay Per Click for Approval'
        description='Routes a Pay Per Click Opportunity to the approver users selected on the screen.'
    )
    public static List<FlowSubmitResult> submitFromFlow(List<FlowSubmitRequest> requests) {
        List<FlowSubmitResult> results = new List<FlowSubmitResult>();
        for (FlowSubmitRequest request : requests) {
            FlowSubmitResult result = new FlowSubmitResult();
            try {
                submitForSelectedApprovers(
                    request == null ? null : request.opportunityId,
                    request == null ? null : request.comments,
                    request == null
                        ? new Set<Id>()
                        : new Set<Id>{
                            request.approverUser1,
                            request.approverUser2,
                            request.approverUser3
                        }
                );
                result.success = true;
                result.message = 'Submitted for approval.';
            } catch (Exception ex) {
                result.success = false;
                result.message = ex.getMessage();
            }
            results.add(result);
        }
        return results;
    }

    private static ApprovalContext submitForSelectedApprovers(
        Id opportunityId,
        String comments,
        Set<Id> selectedUserIds
    ) {
        if (opportunityId == null) {
            throw auraError('Opportunity Id is required.');
        }
        selectedUserIds.remove(null);
        if (selectedUserIds.isEmpty()) {
            throw auraError('Select at least one Approver User.');
        }

        Opportunity opportunityRecord = selectOpportunity(opportunityId);
        validateOpportunityCanSubmit(opportunityRecord);

        List<ApproverRow> plannedApprovers = new List<ApproverRow>();
        for (User selectedUser : [
            SELECT Id, Name
            FROM User
            WHERE Id IN :selectedUserIds
            AND IsActive = true
        ]) {
            ApproverRow row = new ApproverRow();
            row.userId = selectedUser.Id;
            row.userName = selectedUser.Name;
            row.role = 'Additional Approver';
            row.required = true;
            row.decision = DECISION_PENDING;
            plannedApprovers.add(row);
        }
        if (plannedApprovers.size() != selectedUserIds.size()) {
            throw auraError('All selected Approver Users must be active.');
        }

        List<String> missingRequirements = collectCommercialRequirements(opportunityRecord);
        if (!missingRequirements.isEmpty()) {
            throw auraError(String.join(missingRequirements, ' '));
        }
        return persistSubmission(opportunityRecord, comments, plannedApprovers);
    }

    private static void validateOpportunityCanSubmit(Opportunity opportunityRecord) {
        if (!isPayPerClickProposal(opportunityRecord)) {
            throw auraError(
                'Commercial approval is only available for Pay Per Click Opportunities in Proposal.'
            );
        }
        String opportunityStatus = currentStatus(opportunityRecord);
        if (OPP_STATUS_PENDING.equals(opportunityStatus)) {
            throw auraError('This Opportunity is already pending approval.');
        }
        if (OPP_STATUS_APPROVED.equals(opportunityStatus)) {
            throw auraError('This Opportunity is already approved.');
        }
    }

    private static ApprovalContext persistSubmission(
        Opportunity opportunityRecord,
        String comments,
        List<ApproverRow> plannedApprovers
    ) {
        deactivateCurrentApprovers(opportunityRecord.Id);

        List<DealApprovalApprover__c> approversToInsert = new List<DealApprovalApprover__c>();
        Set<Id> approverUserIds = new Set<Id>();
        for (ApproverRow plannedApprover : plannedApprovers) {
            approverUserIds.add(plannedApprover.userId);
            approversToInsert.add(
                new DealApprovalApprover__c(
                    Opportunity__c = opportunityRecord.Id,
                    Approver__c = plannedApprover.userId,
                    ApproverRole__c = plannedApprover.role,
                    IsRequired__c = true,
                    IsCurrent__c = true,
                    Decision__c = DECISION_PENDING
                )
            );
        }
        insert approversToInsert;

        opportunityRecord.DealApprovalStatus__c = OPP_STATUS_PENDING;
        opportunityRecord.DealApprovalRejectionReason__c = null;
        opportunityRecord.DealApprovalSubmissionComments__c = String.isBlank(comments) ? null : comments;
        update opportunityRecord;

        ShareHelper shareHelper = new ShareHelper();
        shareHelper.grantOpportunityAccess(opportunityRecord.Id, approverUserIds);
        shareHelper.notifyUsers(
            approverUserIds,
            opportunityRecord.Id,
            'Approval needed: ' + opportunityRecord.Name,
            buildSubmitNotificationBody(opportunityRecord.DealApprovalSubmissionComments__c)
        );
        return getApprovalContext(opportunityRecord.Id);
    }

    @AuraEnabled
    public static ApprovalContext decide(Id approverRecordId, String decision, String comments) {
        if (approverRecordId == null || String.isBlank(decision)) {
            throw auraError('Approver record and decision are required.');
        }

        Boolean isApprove = DECISION_APPROVED.equals(decision);
        Boolean isReject = DECISION_REJECTED.equals(decision);
        if (!isApprove && !isReject) {
            throw auraError('Decision must be Approved or Rejected.');
        }
        if (isReject && String.isBlank(comments)) {
            throw auraError('A rejection reason is required when rejecting the Opportunity.');
        }

        DealApprovalApprover__c approverRecord = selectApprover(approverRecordId);
        if (approverRecord.Approver__c != UserInfo.getUserId()) {
            throw auraError('Only the assigned approver can record this decision.');
        }
        if (!DECISION_PENDING.equals(approverRecord.Decision__c) || !approverRecord.IsCurrent__c) {
            throw auraError('This approval request has already been decided.');
        }

        Opportunity opportunityRecord = selectOpportunity(approverRecord.Opportunity__c);
        if (!RECORD_TYPE_DEVELOPER_NAME.equals(opportunityRecord.RecordType.DeveloperName)) {
            throw auraError('This approval request is not for a Pay Per Click Opportunity.');
        }
        if (!OPP_STATUS_PENDING.equals(opportunityRecord.DealApprovalStatus__c)) {
            throw auraError('This Opportunity is no longer pending approval.');
        }

        approverRecord.Decision__c = decision;
        approverRecord.DecisionComments__c = comments;
        approverRecord.DecisionDate__c = System.now();
        update approverRecord;

        if (isReject) {
            opportunityRecord.DealApprovalStatus__c = OPP_STATUS_REJECTED;
            opportunityRecord.DealApprovalRejectionReason__c = comments;
            update opportunityRecord;
            new ShareHelper().notifyUsers(
                new Set<Id>{ opportunityRecord.OwnerId },
                opportunityRecord.Id,
                'Pay Per Click rejected: ' + opportunityRecord.Name,
                'A commercial approver rejected the Opportunity. Review the rejection reason and resubmit after rework.'
            );
            return getApprovalContext(opportunityRecord.Id);
        }

        Boolean allRequiredApproved = true;
        for (DealApprovalApprover__c remainingApprover : selectApprovers(opportunityRecord.Id)) {
            if (
                remainingApprover.IsCurrent__c &&
                remainingApprover.IsRequired__c &&
                !DECISION_APPROVED.equals(remainingApprover.Decision__c)
            ) {
                allRequiredApproved = false;
                break;
            }
        }

        if (allRequiredApproved) {
            opportunityRecord.DealApprovalStatus__c = OPP_STATUS_APPROVED;
            opportunityRecord.DealApprovalRejectionReason__c = null;
            update opportunityRecord;
            new ShareHelper().notifyUsers(
                new Set<Id>{ opportunityRecord.OwnerId },
                opportunityRecord.Id,
                'Pay Per Click approved: ' + opportunityRecord.Name,
                'The required commercial approvers have approved this Pay Per Click Opportunity.'
            );
        }
        return getApprovalContext(opportunityRecord.Id);
    }

    private static ApprovalContext baseContext(Opportunity opportunityRecord) {
        ApprovalContext context = new ApprovalContext();
        context.opportunityId = opportunityRecord.Id;
        context.opportunityName = opportunityRecord.Name;
        context.dealApprovalStatus = opportunityRecord.DealApprovalStatus__c;
        context.rejectionReason = opportunityRecord.DealApprovalRejectionReason__c;
        context.submissionComments = opportunityRecord.DealApprovalSubmissionComments__c;
        context.financialAssessment = opportunityRecord.FinancialAssessment__c;
        context.financialAssessmentLink = opportunityRecord.Financial_Assessment_Link__c;
        context.approvers = new List<ApproverRow>();
        context.history = new List<ApproverRow>();
        context.canSubmit = false;
        context.canDecide = false;
        context.mode = MODE_HIDDEN;

        String status = currentStatus(opportunityRecord);
        Boolean hasDecision =
            OPP_STATUS_PENDING.equals(status) ||
            OPP_STATUS_APPROVED.equals(status) ||
            OPP_STATUS_REJECTED.equals(status);
        context.showPanel =
            RECORD_TYPE_DEVELOPER_NAME.equals(opportunityRecord.RecordType.DeveloperName) &&
            (STAGE_PROPOSAL.equals(opportunityRecord.StageName) || hasDecision);
        return context;
    }

    private static Boolean isPayPerClickProposal(Opportunity opportunityRecord) {
        return RECORD_TYPE_DEVELOPER_NAME.equals(opportunityRecord.RecordType.DeveloperName) &&
            STAGE_PROPOSAL.equals(opportunityRecord.StageName);
    }

    private static String currentStatus(Opportunity opportunityRecord) {
        return String.isBlank(opportunityRecord.DealApprovalStatus__c)
            ? OPP_STATUS_NOT_SUBMITTED
            : opportunityRecord.DealApprovalStatus__c;
    }

    private static List<String> collectCommercialRequirements(Opportunity opportunityRecord) {
        List<String> missingRequirements = new List<String>();
        if (String.isBlank(opportunityRecord.Commercial_Commitment__c)) {
            missingRequirements.add('Commercial Commitment is required before submit.');
        }
        if (
            String.isBlank(opportunityRecord.FinancialAssessment__c) &&
            String.isBlank(opportunityRecord.Financial_Assessment_Link__c)
        ) {
            missingRequirements.add('Financial Assessment Link is required before submit.');
        }
        return missingRequirements;
    }

    private static void deactivateCurrentApprovers(Id opportunityId) {
        List<DealApprovalApprover__c> currentApprovers = new List<DealApprovalApprover__c>();
        for (DealApprovalApprover__c approverRecord : selectApprovers(opportunityId)) {
            if (approverRecord.IsCurrent__c) {
                approverRecord.IsCurrent__c = false;
                currentApprovers.add(approverRecord);
            }
        }
        if (!currentApprovers.isEmpty()) {
            update currentApprovers;
        }
    }

    private static DealApprovalApprover__c findPendingApprover(List<DealApprovalApprover__c> approvers) {
        for (DealApprovalApprover__c approverRecord : approvers) {
            if (
                approverRecord.Approver__c == UserInfo.getUserId() &&
                DECISION_PENDING.equals(approverRecord.Decision__c)
            ) {
                return approverRecord;
            }
        }
        return null;
    }

    private static List<ApproverRow> toApproverRows(List<DealApprovalApprover__c> persistedApprovers) {
        List<ApproverRow> rows = new List<ApproverRow>();
        for (DealApprovalApprover__c persistedApprover : persistedApprovers) {
            ApproverRow row = new ApproverRow();
            row.id = persistedApprover.Id;
            row.userId = persistedApprover.Approver__c;
            row.userName = persistedApprover.Approver__r.Name;
            row.role = persistedApprover.ApproverRole__c;
            row.required = persistedApprover.IsRequired__c;
            row.decision = persistedApprover.Decision__c;
            row.comments = persistedApprover.DecisionComments__c;
            row.decisionDate = persistedApprover.DecisionDate__c == null
                ? null
                : persistedApprover.DecisionDate__c.format();
            row.isCurrentUser = persistedApprover.Approver__c == UserInfo.getUserId();
            rows.add(row);
        }
        return rows;
    }

    private static String buildSubmitNotificationBody(String comments) {
        String body = 'A Pay Per Click Opportunity was submitted for commercial approval. Open the Opportunity to review the financial assessment and approve or reject.';
        if (String.isNotBlank(comments)) {
            body += '\n\nSubmission comments: ' + comments;
        }
        if (body.length() > 750) {
            body = body.substring(0, 747) + '...';
        }
        return body;
    }

    private static Opportunity selectOpportunity(Id opportunityId) {
        List<Opportunity> opportunities = [
            SELECT
                Id,
                Name,
                StageName,
                OwnerId,
                RecordType.DeveloperName,
                DealApprovalStatus__c,
                DealApprovalRejectionReason__c,
                DealApprovalSubmissionComments__c,
                FinancialAssessment__c,
                Financial_Assessment_Link__c,
                Commercial_Commitment__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (opportunities.isEmpty()) {
            throw auraError('Opportunity was not found.');
        }
        return opportunities[0];
    }

    private static List<DealApprovalApprover__c> selectApprovers(Id opportunityId) {
        return [
            SELECT
                Id,
                Opportunity__c,
                Approver__c,
                Approver__r.Name,
                ApproverRole__c,
                IsRequired__c,
                IsCurrent__c,
                Decision__c,
                DecisionComments__c,
                DecisionDate__c,
                CreatedDate
            FROM DealApprovalApprover__c
            WHERE Opportunity__c = :opportunityId
            ORDER BY CreatedDate DESC, ApproverRole__c
        ];
    }

    private static DealApprovalApprover__c selectApprover(Id approverRecordId) {
        List<DealApprovalApprover__c> approvers = [
            SELECT Id, Opportunity__c, Approver__c, IsRequired__c, IsCurrent__c, Decision__c
            FROM DealApprovalApprover__c
            WHERE Id = :approverRecordId
            LIMIT 1
        ];
        if (approvers.isEmpty()) {
            throw auraError('Approval request was not found.');
        }
        return approvers[0];
    }

    private static AuraHandledException auraError(String message) {
        AuraHandledException exceptionValue = new AuraHandledException(message);
        exceptionValue.setMessage(message);
        return exceptionValue;
    }

    @TestVisible
    private without sharing class ShareHelper {
        public void grantOpportunityAccess(Id opportunityId, Set<Id> userIds) {
            if (opportunityId == null || userIds == null || userIds.isEmpty()) {
                return;
            }

            Set<Id> existingUserIds = new Set<Id>();
            for (OpportunityShare existingShare : [
                SELECT UserOrGroupId
                FROM OpportunityShare
                WHERE OpportunityId = :opportunityId
                AND UserOrGroupId IN :userIds
            ]) {
                existingUserIds.add(existingShare.UserOrGroupId);
            }

            List<OpportunityShare> sharesToInsert = new List<OpportunityShare>();
            for (Id userId : userIds) {
                if (userId == null || existingUserIds.contains(userId) || userId == UserInfo.getUserId()) {
                    continue;
                }
                sharesToInsert.add(
                    new OpportunityShare(
                        OpportunityId = opportunityId,
                        UserOrGroupId = userId,
                        OpportunityAccessLevel = 'Edit',
                        RowCause = Schema.OpportunityShare.RowCause.Manual
                    )
                );
            }
            if (!sharesToInsert.isEmpty()) {
                Database.insert(sharesToInsert, false);
            }
        }

        public void notifyUsers(Set<Id> userIds, Id opportunityId, String title, String body) {
            if (userIds == null || userIds.isEmpty() || opportunityId == null) {
                return;
            }

            Set<String> recipientIds = new Set<String>();
            for (Id userId : userIds) {
                if (userId != null && userId != UserInfo.getUserId()) {
                    recipientIds.add(String.valueOf(userId));
                }
            }
            if (recipientIds.isEmpty()) {
                return;
            }

            try {
                List<CustomNotificationType> notificationTypes = [
                    SELECT Id
                    FROM CustomNotificationType
                    WHERE DeveloperName = :NOTIFICATION_TYPE
                    LIMIT 1
                ];
                if (notificationTypes.isEmpty()) {
                    return;
                }
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle(title);
                notification.setBody(body);
                notification.setNotificationTypeId(notificationTypes[0].Id);
                notification.setTargetId(opportunityId);
                notification.send(recipientIds);
            } catch (Exception notificationException) {
                ErrorLogger.logException(notificationException, CLASS_NAME, 'notifyUsers');
            }
        }
    }
}