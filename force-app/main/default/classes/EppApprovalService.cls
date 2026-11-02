/**
 * @description Sequential regional EPP approval using DealApprovalApprover__c and EPP_Approval_Hierarchy__mdt (GC-3432).
 *              Path is region-based only; placement value does not change the hierarchy.
 */
public with sharing class EppApprovalService {
    public static final String RECORD_TYPE_EPP = 'HCSalesEquipmentPlacementProgram';
    public static final String STATUS_DRAFT = 'Draft';
    public static final String STATUS_SUBMITTED = 'Submitted for Approval';
    public static final String STATUS_APPROVED = 'Approved';
    public static final String STATUS_NOT_APPROVED = 'Not Approved';
    public static final String DECISION_PENDING = 'Pending';
    public static final String DECISION_APPROVED = 'Approved';
    public static final String DECISION_REJECTED = 'Rejected';
    public static final String ACTION_PREVIEW = 'Preview';
    public static final String ACTION_SUBMIT = 'Submit';
    public static final String ACTION_APPROVE = 'Approve';
    public static final String ACTION_REJECT = 'Reject';
    public static final String STAGE_DRAFT = 'Draft';
    public static final String STAGE_APPROVAL = 'Approval';
    public static final String STAGE_CONTRACTING = 'Contracting';
    public static final String REGION_APAC = 'APAC';
    public static final String REGION_LATAM = 'LATAM';
    public static final String REGION_US_CANADA = 'US & Canada';
    private static final String NOTIFICATION_TYPE = 'EPP_Approval_Required';
    private static final String CLASS_NAME = 'EppApprovalService';

    public class EppApprovalException extends Exception {
    }

    public class FlowRequest {
        @InvocableVariable(required=true label='Action Type')
        public String actionType;
        @InvocableVariable(required=true label='Opportunity Id')
        public Id opportunityId;
        @InvocableVariable(label='Decision Comments')
        public String comments;
    }

    public class FlowResult {
        @InvocableVariable(label='Can Continue')
        public Boolean canContinue;
        @InvocableVariable(label='Missing Requirements')
        public String missingRequirements;
        @InvocableVariable(label='Approval Path Summary')
        public String approvalPathSummary;
        @InvocableVariable(label='Message')
        public String message;
    }

    /**
     * @description Screen flow entry for preview, submit, approve, and reject.
     * @param requests Flow invocations.
     * @return One result per request.
     */
    @InvocableMethod(label='EPP Sequential Approval' description='Preview, submit, approve, or reject EPP regional approval.')
    public static List<FlowResult> processFlowRequest(List<FlowRequest> requests) {
        List<FlowResult> results = new List<FlowResult>();
        if (requests == null || requests.isEmpty()) {
            return results;
        }

        for (FlowRequest request : requests) {
            FlowResult result = new FlowResult();
            try {
                if (ACTION_SUBMIT.equalsIgnoreCase(request.actionType)) {
                    submitForApproval(request.opportunityId);
                    result.canContinue = true;
                    result.message = 'The EPP was submitted for regional approval.';
                } else if (ACTION_APPROVE.equalsIgnoreCase(request.actionType)) {
                    decide(request.opportunityId, DECISION_APPROVED, request.comments);
                    result.canContinue = true;
                    result.message = 'Approval recorded.';
                } else if (ACTION_REJECT.equalsIgnoreCase(request.actionType)) {
                    decide(request.opportunityId, DECISION_REJECTED, request.comments);
                    result.canContinue = true;
                    result.message = 'The EPP was not approved and returned to Draft.';
                } else {
                    Preview preview = buildPreview(request.opportunityId);
                    result.canContinue = preview.missingRequirements.isEmpty();
                    result.missingRequirements = formatMissingRequirements(preview.missingRequirements);
                    result.approvalPathSummary = preview.pathSummary;
                    result.message = result.canContinue
                        ? 'Review the regional approval path, then submit.'
                        : result.missingRequirements;
                }
            } catch (EppApprovalException approvalException) {
                result.canContinue = false;
                result.message = approvalException.getMessage();
                result.missingRequirements = approvalException.getMessage();
            } catch (Exception unexpectedException) {
                ErrorLogger.logException(unexpectedException, CLASS_NAME, 'processFlowRequest');
                result.canContinue = false;
                result.message = unexpectedException.getMessage();
                result.missingRequirements = unexpectedException.getMessage();
            }
            results.add(result);
        }
        return results;
    }

    /**
     * @description Validates Financial Link and Region without persisting.
     * @param opportunityId Opportunity Id.
     * @return Missing requirement messages and path summary.
     */
    public static Preview buildPreview(Id opportunityId) {
        Opportunity opportunityRecord = requireEppOpportunity(opportunityId);
        Preview preview = new Preview();
        preview.missingRequirements = collectMissingRequirements(opportunityRecord);

        String canonicalRegion = normalizeRegion(opportunityRecord.Region__c);
        List<EPP_Approval_Hierarchy__mdt> hierarchy = canonicalRegion == null
            ? new List<EPP_Approval_Hierarchy__mdt>()
            : EppApprovalSelector.selectHierarchy(canonicalRegion);
        preview.pathSummary = buildPathSummary(canonicalRegion, hierarchy);
        return preview;
    }

    /**
     * @description Creates sequential Deal Approver rows, stamps Submitted By/Date, and notifies the first approver.
     * @param opportunityId Opportunity Id.
     */
    public static void submitForApproval(Id opportunityId) {
        Opportunity opportunityRecord = requireEppOpportunity(opportunityId);
        String statusValue = currentStatus(opportunityRecord);
        if (STATUS_SUBMITTED.equals(statusValue)) {
            throw new EppApprovalException('This EPP is already submitted for approval.');
        }
        if (STATUS_APPROVED.equals(statusValue) && opportunityRecord.StageName != STAGE_DRAFT) {
            throw new EppApprovalException('This EPP is already approved.');
        }

        Preview preview = buildPreview(opportunityId);
        if (!preview.missingRequirements.isEmpty()) {
            throw new EppApprovalException(String.join(preview.missingRequirements, ' '));
        }

        String canonicalRegion = normalizeRegion(opportunityRecord.Region__c);
        List<EPP_Approval_Hierarchy__mdt> hierarchy = EppApprovalSelector.selectHierarchy(canonicalRegion);
        if (hierarchy.isEmpty()) {
            throw new EppApprovalException(
                'No active EPP approval hierarchy is configured for region ' + canonicalRegion + '.'
            );
        }
        Map<String, User> usersByUsername = EppApprovalSelector.selectUsersByUsername(collectUsernames(hierarchy));

        deactivateCurrentApprovers(opportunityId);

        Datetime submittedOn = System.now();
        Id submittedById = UserInfo.getUserId();
        List<DealApprovalApprover__c> approversToInsert = new List<DealApprovalApprover__c>();
        for (EPP_Approval_Hierarchy__mdt step : hierarchy) {
            User approverUser = usersByUsername.get(step.Approver_Username__c);
            if (approverUser == null || !approverUser.IsActive) {
                throw new EppApprovalException(
                    'No active approver user is configured for ' +
                    step.Region__c +
                    ' sequence ' +
                    String.valueOf(step.Sequence__c) +
                    '.'
                );
            }
            Decimal sequenceValue = step.Sequence__c;
            approversToInsert.add(
                new DealApprovalApprover__c(
                    Opportunity__c = opportunityId,
                    Approver__c = approverUser.Id,
                    ApproverRole__c = step.Approver_Role__c,
                    Sequence__c = sequenceValue,
                    IsRequired__c = true,
                    IsCurrent__c = true,
                    Decision__c = DECISION_PENDING,
                    Submitted_By__c = submittedById
                )
            );
        }
        insert approversToInsert;

        DealApprovalApprover__c firstApprover = firstPendingApprover(approversToInsert);
        opportunityRecord.EPP_Approval_Status__c = STATUS_SUBMITTED;
        opportunityRecord.StageName = STAGE_APPROVAL;
        opportunityRecord.EPP_Submitted_By__c = submittedById;
        opportunityRecord.EPP_Submitted_Date__c = submittedOn;
        opportunityRecord.EPP_Sequence_Completed__c = '0';
        opportunityRecord.EPP_All_Approvals_Complete__c = false;
        opportunityRecord.EPP_Current_Approver__c = firstApprover == null ? null : firstApprover.Approver__c;
        update opportunityRecord;

        notifyApprover(firstApprover, opportunityRecord, true);
    }

    /**
     * @description Records the running user's sequential decision and either advances or completes the path.
     * @param opportunityId Opportunity Id.
     * @param decision Approved or Rejected.
     * @param comments Required when rejecting.
     */
    public static void decide(Id opportunityId, String decision, String comments) {
        Opportunity opportunityRecord = requireEppOpportunity(opportunityId);
        if (!STATUS_SUBMITTED.equals(currentStatus(opportunityRecord))) {
            throw new EppApprovalException('This EPP is not waiting for approval.');
        }

        Boolean isApprove = DECISION_APPROVED.equals(decision);
        Boolean isReject = DECISION_REJECTED.equals(decision);
        if (!isApprove && !isReject) {
            throw new EppApprovalException('Decision must be Approved or Rejected.');
        }
        if (isReject && String.isBlank(comments)) {
            throw new EppApprovalException('Enter a rejection reason.');
        }

        List<DealApprovalApprover__c> currentApprovers =
            EppApprovalSelector.selectCurrentApprovers(opportunityId);
        DealApprovalApprover__c pendingRow = findPendingForRunningUser(currentApprovers);
        if (pendingRow == null) {
            throw new EppApprovalException('You are not the current sequential approver for this EPP.');
        }

        pendingRow.Decision__c = decision;
        pendingRow.DecisionComments__c = comments;
        pendingRow.DecisionDate__c = System.now();
        update pendingRow;

        if (isReject) {
            opportunityRecord.EPP_Approval_Status__c = STATUS_NOT_APPROVED;
            opportunityRecord.EPP_All_Approvals_Complete__c = false;
            opportunityRecord.EPP_Current_Approver__c = null;
            opportunityRecord.StageName = STAGE_DRAFT;
            update opportunityRecord;
            return;
        }

        Integer completedSequence = pendingRow.Sequence__c == null ? 0 : pendingRow.Sequence__c.intValue();
        opportunityRecord.EPP_Sequence_Completed__c = String.valueOf(completedSequence);

        DealApprovalApprover__c nextPending = findNextPending(currentApprovers, pendingRow);
        if (nextPending == null) {
            opportunityRecord.EPP_Approval_Status__c = STATUS_APPROVED;
            opportunityRecord.EPP_All_Approvals_Complete__c = true;
            opportunityRecord.EPP_Current_Approver__c = null;
            opportunityRecord.StageName = STAGE_CONTRACTING;
            update opportunityRecord;
            return;
        }

        opportunityRecord.EPP_Current_Approver__c = nextPending.Approver__c;
        update opportunityRecord;
        notifyApprover(nextPending, opportunityRecord, false);
    }

    /**
     * @description Preview payload for the submit screen flow.
     */
    public class Preview {
        public List<String> missingRequirements = new List<String>();
        public String pathSummary;
    }

    @TestVisible
    static String normalizeRegion(String regionValue) {
        if (String.isBlank(regionValue)) {
            return null;
        }
        String folded = regionValue.trim().toUpperCase();
        if (folded.contains('APAC') || folded.contains('ASIA') || folded.contains('PACIFIC')) {
            return REGION_APAC;
        }
        if (folded.contains('LATAM') || folded.contains('LATIN')) {
            return REGION_LATAM;
        }
        if (
            folded.contains('CANADA') ||
            folded.contains('UNITED STATES') ||
            folded == 'US' ||
            folded.contains('US &') ||
            folded.contains('US AND') ||
            folded.contains('NORTH AMERICA')
        ) {
            return REGION_US_CANADA;
        }
        return regionValue.trim();
    }

    @TestVisible
    static List<String> collectMissingRequirements(Opportunity opportunityRecord) {
        List<String> missingRequirements = new List<String>();
        if (
            String.isBlank(opportunityRecord.Financial_Link__c) &&
            !hasFinancialAnalysisFile(opportunityRecord.Id)
        ) {
            missingRequirements.add('Financial Link');
        }
        if (String.isBlank(opportunityRecord.Region__c)) {
            missingRequirements.add('Region');
        }
        if (String.isBlank(opportunityRecord.Product_Equipment__c)) {
            missingRequirements.add('Product/Equipment');
        }
        if (opportunityRecord.Placement_Start_Date__c == null) {
            missingRequirements.add('Placement Start Date');
        }
        if (opportunityRecord.Placement_End_Date__c == null) {
            missingRequirements.add('Placement End Date');
        }
        if (
            opportunityRecord.Placement_Start_Date__c != null &&
            opportunityRecord.Placement_End_Date__c != null &&
            opportunityRecord.Placement_End_Date__c < opportunityRecord.Placement_Start_Date__c
        ) {
            missingRequirements.add(
                'Please enter a Placement End Date on or after the Placement Start Date.'
            );
        }
        if (opportunityRecord.ConsumablesCommitment__c != true && opportunityRecord.ServiceCommitment__c != true  &&  opportunityRecord.InstallationCommitment__c != true) {
            missingRequirements.add('Customer Commercial Commitment Type');
        }
        return missingRequirements;
    }

    private static String formatMissingRequirements(List<String> missingRequirements) {
        List<String> fieldNames = new List<String>();
        List<String> notes = new List<String>();
        for (String item : missingRequirements) {
            if (String.isBlank(item)) {
                continue;
            }
            if (item.startsWith('Please ')) {
                notes.add(item);
            } else {
                fieldNames.add(item);
            }
        }
        String text = '';
        if (!fieldNames.isEmpty()) {
            text = 'Please fill ' + String.join(fieldNames, ', ') + '.';
        }
        if (!notes.isEmpty()) {
            text = (text + ' ' + String.join(notes, ' ')).trim();
        }
        return text;
    }

    private static Boolean hasFinancialAnalysisFile(Id opportunityId) {
        if (opportunityId == null) {
            return false;
        }
        return [
            SELECT COUNT()
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :opportunityId
            WITH SYSTEM_MODE
        ] > 0;
    }

    private static Opportunity requireEppOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new EppApprovalException('Opportunity Id is required.');
        }
        Opportunity opportunityRecord = EppApprovalSelector.selectOpportunity(opportunityId);
        if (opportunityRecord == null) {
            throw new EppApprovalException('Opportunity was not found.');
        }
        if (!RECORD_TYPE_EPP.equals(opportunityRecord.RecordType.DeveloperName)) {
            throw new EppApprovalException('This action is only available on Equipment Placement Program Opportunities.');
        }
        return opportunityRecord;
    }

    private static String currentStatus(Opportunity opportunityRecord) {
        return String.isBlank(opportunityRecord.EPP_Approval_Status__c)
            ? STATUS_DRAFT
            : opportunityRecord.EPP_Approval_Status__c;
    }

    private static String buildPathSummary(String canonicalRegion, List<EPP_Approval_Hierarchy__mdt> hierarchy) {
        if (String.isBlank(canonicalRegion)) {
            return 'Region is required to determine the approval path.';
        }
        if (hierarchy.isEmpty()) {
            return 'No active sequential steps are configured for ' + canonicalRegion + '.';
        }
        List<String> steps = new List<String>();
        for (EPP_Approval_Hierarchy__mdt step : hierarchy) {
            steps.add(String.valueOf(step.Sequence__c.intValue()) + '. ' + step.Approver_Role__c);
        }
        return canonicalRegion + ': ' + String.join(steps, ' → ');
    }

    private static Set<String> collectUsernames(List<EPP_Approval_Hierarchy__mdt> hierarchy) {
        Set<String> usernames = new Set<String>();
        for (EPP_Approval_Hierarchy__mdt step : hierarchy) {
            if (String.isNotBlank(step.Approver_Username__c)) {
                usernames.add(step.Approver_Username__c);
            }
        }
        return usernames;
    }

    private static void deactivateCurrentApprovers(Id opportunityId) {
        List<DealApprovalApprover__c> currentApprovers =
            EppApprovalSelector.selectCurrentApprovers(opportunityId);
        for (DealApprovalApprover__c currentApprover : currentApprovers) {
            currentApprover.IsCurrent__c = false;
        }
        if (!currentApprovers.isEmpty()) {
            update currentApprovers;
        }
    }

    private static DealApprovalApprover__c firstPendingApprover(List<DealApprovalApprover__c> insertedRows) {
        DealApprovalApprover__c firstRow = null;
        for (DealApprovalApprover__c row : insertedRows) {
            if (firstRow == null || (row.Sequence__c != null && row.Sequence__c < firstRow.Sequence__c)) {
                firstRow = row;
            }
        }
        return firstRow;
    }

    private static DealApprovalApprover__c findPendingForRunningUser(List<DealApprovalApprover__c> currentApprovers) {
        DealApprovalApprover__c lowestPending = null;
        for (DealApprovalApprover__c row : currentApprovers) {
            if (!DECISION_PENDING.equals(row.Decision__c)) {
                continue;
            }
            if (lowestPending == null || row.Sequence__c < lowestPending.Sequence__c) {
                lowestPending = row;
            }
        }
        if (lowestPending == null || lowestPending.Approver__c != UserInfo.getUserId()) {
            return null;
        }
        return lowestPending;
    }

    private static DealApprovalApprover__c findNextPending(
        List<DealApprovalApprover__c> currentApprovers,
        DealApprovalApprover__c decidedRow
    ) {
        DealApprovalApprover__c nextRow = null;
        for (DealApprovalApprover__c row : currentApprovers) {
            if (row.Id == decidedRow.Id || !DECISION_PENDING.equals(row.Decision__c)) {
                continue;
            }
            if (nextRow == null || row.Sequence__c < nextRow.Sequence__c) {
                nextRow = row;
            }
        }
        return nextRow;
    }

    private static void notifyApprover(
        DealApprovalApprover__c approverRow,
        Opportunity opportunityRecord,
        Boolean isSubmit
    ) {
        if (approverRow == null || approverRow.Approver__c == null) {
            return;
        }

        String title = 'EPP approval needed: ' + opportunityRecord.Name;
        String body = isSubmit
            ? 'An EPP was submitted for regional approval and is waiting for your review.'
            : 'The previous EPP approver completed their step. This EPP is waiting for your review.';

        try {
            Id notificationTypeId = EppApprovalSelector.selectNotificationTypeId(NOTIFICATION_TYPE);
            if (notificationTypeId != null) {
                Messaging.CustomNotification notification = new Messaging.CustomNotification();
                notification.setTitle(title);
                notification.setBody(body);
                notification.setNotificationTypeId(notificationTypeId);
                notification.setTargetId(opportunityRecord.Id);
                notification.send(new Set<String>{ String.valueOf(approverRow.Approver__c) });
            }
        } catch (Exception notificationException) {
            ErrorLogger.logException(notificationException, CLASS_NAME, 'notifyApprover');
        }

        try {
            Messaging.SingleEmailMessage emailMessage = new Messaging.SingleEmailMessage();
            emailMessage.setTargetObjectId(approverRow.Approver__c);
            emailMessage.setSaveAsActivity(false);
            emailMessage.setSubject(title);
            emailMessage.setPlainTextBody(body + '\nOpportunity Id: ' + opportunityRecord.Id);
            Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ emailMessage }, false);
        } catch (Exception emailException) {
            ErrorLogger.logException(emailException, CLASS_NAME, 'notifyApproverEmail');
        }
    }
}