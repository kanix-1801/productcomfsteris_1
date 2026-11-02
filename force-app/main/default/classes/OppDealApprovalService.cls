/**
 * @author Himanshu Chaurasia
 * @date 2026/09/15
 *
 * @group GC-3235
 *
 * @description Parallel deal approval for Strategic Contract Opportunities in Deal Development & Approval.
 *              Submit creates DealApprovalApprover__c rows for Deal Desk, BU Leaders, and optional additional approvers.
 *              Opportunity.DealApprovalStatus__c rolls up to Not Submitted, Pending Approval, Approved, or Rejected.
 *              GC-3517 stamps ApprovalCycleNumber__c on each new submission.
 *              GC-3546 accepts any number of additional approvers from the submit screen.
 */
public with sharing class OppDealApprovalService {
    /** Strategic Contract Opportunity record type DeveloperName. */
    public static final String RECORD_TYPE_DEVELOPER_NAME = 'HCSalesStrategicContract';
    /** Stage where the deal approval panel and submit flow are available. */
    public static final String STAGE_DEAL_DEVELOPMENT = 'Deal Development & Approval';
    /** Opportunity Team role resolved as a required approver. */
    public static final String ROLE_DEAL_DESK = 'Deal Desk Lead';
    /** Opportunity Team role resolved as a required approver when Business Unit is populated. */
    public static final String ROLE_BU_LEADER = 'Business Unit Leader';
    /** Role assigned to users added on the submit screen flow. */
    public static final String ROLE_ADDITIONAL = 'Additional Approver';

    /** Opportunity has not been submitted for parallel approval. */
    public static final String OPP_STATUS_NOT_SUBMITTED = 'Not Submitted';
    /** At least one approver has not completed a decision. */
    public static final String OPP_STATUS_PENDING = 'Pending Approval';
    /** All required approvers approved the deal. */
    public static final String OPP_STATUS_APPROVED = 'Approved';
    /** A required approver rejected the deal. */
    public static final String OPP_STATUS_REJECTED = 'Rejected';

    /** DealApprovalApprover__c decision before action. */
    public static final String DECISION_PENDING = 'Pending';
    /** Approver approved the deal. */
    public static final String DECISION_APPROVED = 'Approved';
    /** Approver rejected the deal. */
    public static final String DECISION_REJECTED = 'Rejected';

    /** LWC panel hidden (wrong record type or stage). */
    public static final String MODE_HIDDEN = 'Hidden';
    /** Owner may submit; required approvers shown from team. */
    public static final String MODE_SUBMIT = 'Submit';
    /** Running user has a pending approver row and may decide. */
    public static final String MODE_PENDING_APPROVER = 'PendingApprover';
    /** Approval in progress; running user is not the active approver. */
    public static final String MODE_PENDING_VIEWER = 'PendingViewer';
    /** Deal approval completed successfully. */
    public static final String MODE_APPROVED = 'Approved';
    /** Deal was rejected; owner may rework and resubmit. */
    public static final String MODE_REJECTED = 'Rejected';

    /** Screen flow action: validate submit prerequisites only. */
    public static final String ACTION_PREVIEW = 'Preview';
    /** Screen flow action: persist approvers and set Pending Approval. */
    public static final String ACTION_SUBMIT = 'Submit';

    private static final String NOTIFICATION_TYPE = 'Deal_Submitted_For_Approval';
    private static final String CLASS_NAME = 'OppDealApprovalService';

    /** Aura DTO for the deal approval panel on Opportunity. */
    public class ApprovalContext {
        @AuraEnabled
        public Boolean showPanel;
        @AuraEnabled
        public String mode;
        @AuraEnabled
        public Id opportunityId;
        @AuraEnabled
        public String opportunityName;
        @AuraEnabled
        public String dealApprovalStatus;
        @AuraEnabled
        public String rejectionReason;
        @AuraEnabled
        public String submissionComments;
        @AuraEnabled
        public Boolean canDecide;
        @AuraEnabled
        public Id currentApproverRecordId;
        @AuraEnabled
        public List<ApproverRow> approvers;
    }

    /** Single approver row for panel display and submit planning. */
    public class ApproverRow {
        @AuraEnabled
        public Id id;
        @AuraEnabled
        public Id userId;
        @AuraEnabled
        public String userName;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public Boolean required;
        @AuraEnabled
        public String decision;
        @AuraEnabled
        public String comments;
        @AuraEnabled
        public Boolean isCurrentUser;
    }

    /** Invocable input for the Strategic Deal Approval screen flow. */
    public class FlowRequest {
        @InvocableVariable(required=true label='Action Type' description='Preview or Submit')
        public String actionType;
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;
        @InvocableVariable(
            label='Additional Approvers'
            description='Users added on the submit screen. There is no fixed maximum.'
        )
        public List<Id> additionalApproverIds;
        @InvocableVariable(label='Submission Comments')
        public String comments;
    }

    /** Invocable output for preview validation and submit confirmation. */
    public class FlowResult {
        @InvocableVariable(label='Can Submit')
        public Boolean canSubmit;
        @InvocableVariable(label='Required Approver Summary')
        public String requiredApproverSummary;
        @InvocableVariable(label='Missing Requirements')
        public String missingRequirements;
        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * @description Screen flow entry: preview submit requirements or submit the deal for parallel approval.
     * @param requests One or more flow invocations (bulk-safe).
     * @return Preview or submit result per request.
     */
    @InvocableMethod(label='Strategic Deal Approval' description='Preview or submit Strategic Contract deal approval.')
    public static List<FlowResult> processFlowRequest(List<FlowRequest> requests) {
        List<FlowResult> results = new List<FlowResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (FlowRequest request : requests) {
            FlowResult result = new FlowResult();
            try {
                if (ACTION_SUBMIT.equalsIgnoreCase(request.actionType)) {
                    submitForApproval(
                        request.opportunityId,
                        collectAdditionalApproverIds(request),
                        request.comments
                    );
                    result.canSubmit = true;
                    result.message = 'The deal was submitted for approval.';
                } else {
                    ApprovalPreview preview = buildSubmitPreview(request.opportunityId);
                    result.canSubmit = preview.missingRequirements.isEmpty();
                    result.requiredApproverSummary = preview.requiredApproverSummary;
                    result.missingRequirements = String.join(preview.missingRequirements, ' ');
                    result.message = result.canSubmit
                        ? 'Review the approval group, add any additional approvers, then submit.'
                        : result.missingRequirements;
                }
            } catch (AuraHandledException exceptionValue) {
                result.canSubmit = false;
                result.message = exceptionValue.getMessage();
                result.missingRequirements = exceptionValue.getMessage();
            }
            results.add(result);
        }
        return results;
    }

    /**
     * @description Builds LWC panel state from Opportunity status and current approver rows.
     * @param opportunityId Opportunity Id.
     * @return Approval context including mode, approvers, and whether the user may decide.
     */
    public static ApprovalContext getApprovalContext(Id opportunityId) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opportunityRecord = OppDealApprovalSelector.selectOpportunity(opportunityId);
        ApprovalContext context = new ApprovalContext();
        context.opportunityId = opportunityRecord.Id;
        context.opportunityName = opportunityRecord.Name;
        context.dealApprovalStatus = opportunityRecord.DealApprovalStatus__c;
        context.rejectionReason = opportunityRecord.DealApprovalRejectionReason__c;
        context.submissionComments = opportunityRecord.DealApprovalSubmissionComments__c;
        context.approvers = new List<ApproverRow>();
        context.showPanel = isStrategicDealDevelopment(opportunityRecord);
        context.mode = MODE_HIDDEN;
        context.canDecide = false;

        if (!context.showPanel) {
            return context;
        }

        List<DealApprovalApprover__c> currentApprovers =
            OppDealApprovalSelector.selectCurrentApprovers(opportunityId);
        context.approvers = toApproverRows(currentApprovers);

        String opportunityStatus = String.isBlank(opportunityRecord.DealApprovalStatus__c)
            ? OPP_STATUS_NOT_SUBMITTED
            : opportunityRecord.DealApprovalStatus__c;

        if (OPP_STATUS_PENDING.equals(opportunityStatus)) {
            context.mode = MODE_PENDING_VIEWER;
            DealApprovalApprover__c currentApprover = findCurrentPendingApprover(currentApprovers);
            if (currentApprover != null) {
                context.mode = MODE_PENDING_APPROVER;
                context.canDecide = true;
                context.currentApproverRecordId = currentApprover.Id;
            }
            return context;
        }

        if (OPP_STATUS_APPROVED.equals(opportunityStatus)) {
            context.mode = MODE_APPROVED;
            return context;
        }

        context.mode = OPP_STATUS_REJECTED.equals(opportunityStatus) ? MODE_REJECTED : MODE_SUBMIT;
        if (context.approvers.isEmpty()) {
            context.approvers = buildRequiredApproverRows(opportunityRecord);
        }
        return context;
    }

    /**
     * @description Validates prerequisites, creates approver rows, updates Opportunity status, and notifies approvers.
     * @param opportunityId Opportunity Id.
     * @param additionalApproverIds Optional users from the submit screen. There is no fixed maximum.
     * @param comments Submission comments stored on the Opportunity.
     * @return Refreshed approval context after submit.
     */
    public static ApprovalContext submitForApproval(
        Id opportunityId,
        List<Id> additionalApproverIds,
        String comments
    ) {
        if (opportunityId == null) {
            throw new AuraHandledException('Opportunity Id is required.');
        }

        Opportunity opportunityRecord = OppDealApprovalSelector.selectOpportunity(opportunityId);
        validateStrategicDealDevelopment(opportunityRecord);

        String opportunityStatus = String.isBlank(opportunityRecord.DealApprovalStatus__c)
            ? OPP_STATUS_NOT_SUBMITTED
            : opportunityRecord.DealApprovalStatus__c;
        if (OPP_STATUS_PENDING.equals(opportunityStatus)) {
            throw new AuraHandledException('This deal is already pending approval.');
        }
        if (OPP_STATUS_APPROVED.equals(opportunityStatus)) {
            throw new AuraHandledException('This deal is already approved.');
        }

        Map<Id, ApproverRow> plannedApprovers = buildRequiredApproverMap(opportunityRecord);
        addAdditionalApproversToMap(plannedApprovers, additionalApproverIds);

        List<String> missingRequirements = collectSubmitRequirements(
            opportunityRecord,
            plannedApprovers.values()
        );
        if (!missingRequirements.isEmpty()) {
            throw new AuraHandledException(String.join(missingRequirements, ' '));
        }

        deactivateCurrentApprovers(opportunityId);
        Integer approvalCycleNumber = OppDealApprovalSelector.selectNextApprovalCycleNumber(opportunityId);

        List<DealApprovalApprover__c> approversToInsert = new List<DealApprovalApprover__c>();
        Set<Id> approverUserIds = new Set<Id>();
        for (ApproverRow plannedApprover : plannedApprovers.values()) {
            approverUserIds.add(plannedApprover.userId);
            approversToInsert.add(
                new DealApprovalApprover__c(
                    Opportunity__c = opportunityId,
                    Approver__c = plannedApprover.userId,
                    ApproverRole__c = plannedApprover.role,
                    IsRequired__c = plannedApprover.required,
                    IsCurrent__c = true,
                    Decision__c = DECISION_PENDING,
                    ApprovalCycleNumber__c = approvalCycleNumber
                )
            );
        }
        insert approversToInsert;

        opportunityRecord.DealApprovalStatus__c = OPP_STATUS_PENDING;
        opportunityRecord.DealApprovalRejectionReason__c = null;
        opportunityRecord.DealApprovalSubmissionComments__c = String.isBlank(comments) ? null : comments;
        update opportunityRecord;

        ShareHelper shareHelper = new ShareHelper();
        shareHelper.grantOpportunityAccess(opportunityId, approverUserIds);
        shareHelper.notifyUsers(
            approverUserIds,
            opportunityRecord.Id,
            'Approval needed: ' + opportunityRecord.Name,
            buildSubmitNotificationBody(opportunityRecord.DealApprovalSubmissionComments__c)
        );

        return getApprovalContext(opportunityId);
    }

    /**
     * @description Records approve or reject on the approver row and rolls up Opportunity status when complete.
     * @param approverRecordId DealApprovalApprover__c Id for the running user.
     * @param decision Approved or Rejected.
     * @param comments Rejection reason (required on reject) or optional approval notes.
     * @return Refreshed approval context after the decision.
     */
    public static ApprovalContext decide(Id approverRecordId, String decision, String comments) {
        if (approverRecordId == null || String.isBlank(decision)) {
            throw new AuraHandledException('Approver record and decision are required.');
        }

        Boolean isApprove = DECISION_APPROVED.equals(decision);
        Boolean isReject = DECISION_REJECTED.equals(decision);
        if (!isApprove && !isReject) {
            throw new AuraHandledException('Decision must be Approved or Rejected.');
        }
        if (isReject && String.isBlank(comments)) {
            throw new AuraHandledException('A rejection reason is required when rejecting the deal.');
        }

        DealApprovalApprover__c approverRecord = OppDealApprovalSelector.selectApprover(approverRecordId);
        if (approverRecord.Approver__c != UserInfo.getUserId()) {
            throw new AuraHandledException('Only the assigned approver can record this decision.');
        }
        if (!DECISION_PENDING.equals(approverRecord.Decision__c) || !approverRecord.IsCurrent__c) {
            throw new AuraHandledException('This approval request has already been decided.');
        }

        Id opportunityId = approverRecord.Opportunity__c;
        Opportunity opportunityRecord = OppDealApprovalSelector.selectOpportunity(opportunityId);
        if (!OPP_STATUS_PENDING.equals(opportunityRecord.DealApprovalStatus__c)) {
            throw new AuraHandledException('This deal is no longer pending approval.');
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
                'Deal rejected: ' + opportunityRecord.Name,
                'A designated approver rejected the deal. Review the rejection reason and resubmit after rework.'
            );
            return getApprovalContext(opportunityId);
        }

        Boolean allRequiredApproved = true;
        for (DealApprovalApprover__c remainingApprover : OppDealApprovalSelector.selectCurrentApprovers(opportunityId)) {
            if (remainingApprover.IsRequired__c && !DECISION_APPROVED.equals(remainingApprover.Decision__c)) {
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
                'Deal approved: ' + opportunityRecord.Name,
                'All required approvers have approved the deal. The Opportunity may now progress to Customer Negotiation.'
            );
        }

        return getApprovalContext(opportunityId);
    }

    /** Internal DTO for submit preview validation in the screen flow. */
    private class ApprovalPreview {
        public String requiredApproverSummary;
        public List<String> missingRequirements;
    }

    /**
     * @description Validates strategic contract context and builds preview text for the submit flow.
     * @param opportunityId Opportunity Id.
     * @return Missing requirements and approver summary for Preview action.
     */
    private static ApprovalPreview buildSubmitPreview(Id opportunityId) {
        Opportunity opportunityRecord = OppDealApprovalSelector.selectOpportunity(opportunityId);
        validateStrategicDealDevelopment(opportunityRecord);

        List<ApproverRow> requiredApprovers = buildRequiredApproverRows(opportunityRecord);
        ApprovalPreview preview = new ApprovalPreview();
        preview.missingRequirements = collectSubmitRequirements(opportunityRecord, requiredApprovers);
        preview.requiredApproverSummary = toApproverSummary(requiredApprovers);
        return preview;
    }

    /**
     * @description Collects non-null additional approver Ids from the flow request.
     * @param request Screen flow invocable input.
     * @return User Ids to merge into the planned approver set.
     */
    private static List<Id> collectAdditionalApproverIds(FlowRequest request) {
        List<Id> additionalApproverIds = new List<Id>();
        if (request == null || request.additionalApproverIds == null) {
            return additionalApproverIds;
        }
        for (Id additionalApproverId : request.additionalApproverIds) {
            if (additionalApproverId != null) {
                additionalApproverIds.add(additionalApproverId);
            }
        }
        return additionalApproverIds;
    }

    /**
     * @description True when the Opportunity is Strategic Contract in Deal Development & Approval.
     * @param opportunityRecord Opportunity row with RecordType and StageName.
     * @return Whether deal approval UI and submit are applicable.
     */
    private static Boolean isStrategicDealDevelopment(Opportunity opportunityRecord) {
        return RECORD_TYPE_DEVELOPER_NAME.equals(opportunityRecord.RecordType.DeveloperName) &&
            STAGE_DEAL_DEVELOPMENT.equals(opportunityRecord.StageName);
    }

    /**
     * @description Ensures submit and preview run only for eligible Strategic Contract Opportunities.
     * @param opportunityRecord Opportunity row to validate.
     */
    private static void validateStrategicDealDevelopment(Opportunity opportunityRecord) {
        if (!isStrategicDealDevelopment(opportunityRecord)) {
            throw new AuraHandledException(
                'Deal approval is only available for Strategic Contract Opportunities in Deal Development & Approval.'
            );
        }
    }

    /**
     * @description Required approvers derived from Opportunity Team roles (preview/submit planning).
     * @param opportunityRecord Opportunity Id context.
     * @return Approver rows keyed by user (via map values).
     */
    private static List<ApproverRow> buildRequiredApproverRows(Opportunity opportunityRecord) {
        return buildRequiredApproverMap(opportunityRecord).values();
    }

    /**
     * @description Builds required approver map from Deal Desk and BU Leader team members.
     * @param opportunityRecord Opportunity Id context.
     * @return Map of user Id to planned approver row.
     */
    private static Map<Id, ApproverRow> buildRequiredApproverMap(Opportunity opportunityRecord) {
        Map<Id, ApproverRow> rowsByUserId = new Map<Id, ApproverRow>();
        for (OpportunityTeamMember teamMember : OppDealApprovalSelector.selectApproverTeamMembers(
            opportunityRecord.Id
        )) {
            if (teamMember.UserId == null || teamMember.User == null || !teamMember.User.IsActive) {
                continue;
            }
            mergeApproverRow(
                rowsByUserId,
                teamMember.UserId,
                teamMember.User.Name,
                teamMember.TeamMemberRole,
                true
            );
        }
        return rowsByUserId;
    }

    /**
     * @description Adds optional approvers from the submit flow without duplicating required roles.
     * @param rowsByUserId Planned approvers keyed by user Id (mutated).
     * @param additionalApproverIds Additional user Ids from the flow.
     */
    private static void addAdditionalApproversToMap(
        Map<Id, ApproverRow> rowsByUserId,
        List<Id> additionalApproverIds
    ) {
        if (additionalApproverIds == null || additionalApproverIds.isEmpty()) {
            return;
        }

        Set<Id> uniqueUserIds = new Set<Id>(additionalApproverIds);
        uniqueUserIds.remove(null);
        if (uniqueUserIds.isEmpty()) {
            return;
        }

        for (User additionalUser : [
            SELECT Id, Name, IsActive
            FROM User
            WHERE Id IN :uniqueUserIds
        ]) {
            if (!additionalUser.IsActive) {
                continue;
            }
            if (rowsByUserId.containsKey(additionalUser.Id)) {
                continue;
            }
            mergeApproverRow(
                rowsByUserId,
                additionalUser.Id,
                additionalUser.Name,
                ROLE_ADDITIONAL,
                true
            );
        }
    }

    /**
     * @description Inserts or merges an approver row; Deal Desk role wins over BU Leader when both apply.
     * @param rowsByUserId Approver map keyed by user Id.
     * @param userId Approver user Id.
     * @param userName Display name.
     * @param role Team or additional role label.
     * @param required Whether the approver counts toward required approval rollup.
     */
    private static void mergeApproverRow(
        Map<Id, ApproverRow> rowsByUserId,
        Id userId,
        String userName,
        String role,
        Boolean required
    ) {
        if (!rowsByUserId.containsKey(userId)) {
            ApproverRow row = new ApproverRow();
            row.userId = userId;
            row.userName = userName;
            row.role = role;
            row.required = required == true;
            row.decision = DECISION_PENDING;
            row.isCurrentUser = userId == UserInfo.getUserId();
            rowsByUserId.put(userId, row);
            return;
        }

        ApproverRow existingRow = rowsByUserId.get(userId);
        if (ROLE_DEAL_DESK.equals(role)) {
            existingRow.role = ROLE_DEAL_DESK;
        } else if (ROLE_BU_LEADER.equals(role) && !ROLE_DEAL_DESK.equals(existingRow.role)) {
            existingRow.role = ROLE_BU_LEADER;
        }
        existingRow.required = existingRow.required || required == true;
    }

    /**
     * @description Maps persisted DealApprovalApprover__c rows to LWC approver DTOs.
     * @param persistedApprovers Current approver records from the selector.
     * @return Rows for panel display.
     */
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
            row.isCurrentUser = persistedApprover.Approver__c == UserInfo.getUserId();
            rows.add(row);
        }
        return rows;
    }

    /**
     * @description Human-readable list of planned required approvers for the submit preview.
     * @param approverRows Planned approver rows.
     * @return Multi-line summary or message when no approvers were found.
     */
    private static String toApproverSummary(List<ApproverRow> approverRows) {
        if (approverRows == null || approverRows.isEmpty()) {
            return 'No Deal Desk Lead or Business Unit Leaders were found on the Opportunity Team.';
        }

        List<String> summaryLines = new List<String>();
        for (ApproverRow approverRow : approverRows) {
            summaryLines.add(approverRow.role + ': ' + approverRow.userName);
        }
        return String.join(summaryLines, '\n');
    }

    /**
     * @description Validates deal strategy, financial assessment, and required team roles before submit.
     * @param opportunityRecord Opportunity header fields.
     * @param plannedApprovers Approver rows planned for insert.
     * @return User-facing requirement messages; empty when submit may proceed.
     */
    private static List<String> collectSubmitRequirements(
        Opportunity opportunityRecord,
        List<ApproverRow> plannedApprovers
    ) {
        List<String> missingRequirements = new List<String>();
        if (String.isBlank(opportunityRecord.Dealstrategy__c)) {
            missingRequirements.add('Deal strategy is required before submit.');
        }
        if (String.isBlank(opportunityRecord.FinancialAssessment__c)) {
            missingRequirements.add('Financial assessment is required before submit.');
        }

        Boolean hasDealDesk = false;
        Boolean hasBuLeader = false;
        for (ApproverRow plannedApprover : plannedApprovers) {
            if (ROLE_DEAL_DESK.equals(plannedApprover.role)) {
                hasDealDesk = true;
            }
            if (ROLE_BU_LEADER.equals(plannedApprover.role)) {
                hasBuLeader = true;
            }
        }

        if (!hasDealDesk) {
            missingRequirements.add('A Deal Desk Lead is required on the Opportunity Team.');
        }
        if (String.isNotBlank(opportunityRecord.BusinessUnit__c) && !hasBuLeader) {
            missingRequirements.add(
                'Applicable Business Unit Leader(s) must be associated with the Opportunity before submit.'
            );
        }
        return missingRequirements;
    }

    /**
     * @description Finds the running user's pending approver row during Pending Approval.
     * @param persistedApprovers Current approver records.
     * @return Approver row the user may act on, or null.
     */
    private static DealApprovalApprover__c findCurrentPendingApprover(
        List<DealApprovalApprover__c> persistedApprovers
    ) {
        for (DealApprovalApprover__c persistedApprover : persistedApprovers) {
            if (
                persistedApprover.Approver__c == UserInfo.getUserId() &&
                DECISION_PENDING.equals(persistedApprover.Decision__c)
            ) {
                return persistedApprover;
            }
        }
        return null;
    }

    /**
     * @description Builds custom notification body for submit alerts (truncated for platform limits).
     * @param comments Submission comments from the Opportunity.
     * @return Notification body text.
     */
    private static String buildSubmitNotificationBody(String comments) {
        String body = 'A Strategic Contract deal was submitted for your approval. Open the Opportunity to approve or reject.';
        if (String.isNotBlank(comments)) {
            body += '\n\nSubmission comments: ' + comments;
        }
        if (body.length() > 750) {
            body = body.substring(0, 747) + '...';
        }
        return body;
    }

    /**
     * @description Marks prior-cycle approver rows inactive before a resubmit inserts new current rows.
     * @param opportunityId Opportunity Id.
     */
    private static void deactivateCurrentApprovers(Id opportunityId) {
        List<DealApprovalApprover__c> currentApprovers =
            OppDealApprovalSelector.selectCurrentApprovers(opportunityId);
        if (currentApprovers.isEmpty()) {
            return;
        }

        for (DealApprovalApprover__c currentApprover : currentApprovers) {
            currentApprover.IsCurrent__c = false;
        }
        update currentApprovers;
    }

    /**
     * @description Grants manual Opportunity share and sends custom notifications (without sharing for DML).
     */
    @TestVisible
    private without sharing class ShareHelper {
        /**
         * @description Inserts manual OpportunityShare rows so approvers can edit the Opportunity.
         * @param opportunityId Opportunity Id.
         * @param userIds Approver user Ids.
         */
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

        /**
         * @description Sends Deal_Submitted_For_Approval custom notifications; failures are logged only.
         * @param userIds Recipient user Ids.
         * @param opportunityId Target Opportunity for the notification link.
         * @param title Notification title.
         * @param body Notification body.
         */
        public void notifyUsers(Set<Id> userIds, Id opportunityId, String title, String body) {
            if (userIds == null || userIds.isEmpty() || opportunityId == null) {
                return;
            }

            Set<Id> recipientIds = new Set<Id>();
            for (Id userId : userIds) {
                if (userId != null && userId != UserInfo.getUserId()) {
                    recipientIds.add(userId);
                }
            }
            if (recipientIds.isEmpty()) {
                return;
            }

            try {
                Id notificationTypeId = OppDealApprovalSelector.selectNotificationTypeId(NOTIFICATION_TYPE);
                if (notificationTypeId != null) {
                    Messaging.CustomNotification notification = new Messaging.CustomNotification();
                    notification.setTitle(title);
                    notification.setBody(body);
                    notification.setNotificationTypeId(notificationTypeId);
                    notification.setTargetId(opportunityId);
                    Set<String> recipientIdStrings = new Set<String>();
                    for (Id recipientId : recipientIds) {
                        recipientIdStrings.add(String.valueOf(recipientId));
                    }
                    notification.send(recipientIdStrings);
                }
            } catch (Exception notificationException) {
                ErrorLogger.logException(notificationException, CLASS_NAME, 'notifyUsers');
            }
        }
    }
}