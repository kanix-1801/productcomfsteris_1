/**
 * @author PWC Developer
 * @date 2026-11-25
 * @group Life Sciences
 * @description GCL-74 AC1, AC2, AC4, AC5 - Removes Account Team and Opportunity Team rows of deactivated
 *              Life Sciences users and records each removal in Inactive User Assignment History.
 *
 *              Rows are matched on AssignmentType__c only. Record ownership is never changed.
 *              One Queueable run handles one page of rows and chains itself while a page is full.
 *              Kept separate from the Healthcare InactiveUserTeamCleanup so Healthcare behaviour is unchanged.
 *
 *              Runs without sharing on purpose. The job runs as the user who deactivated the account, and the
 *              same rows must be removed whoever that is (Standards 5.10.4, admin-level operations).
 */
public without sharing class LSInactiveUserCleanupQueueable implements Queueable {

    private static final String SCENARIO = 'GCL-74 LS Inactive User Cleanup';
    private static final String LOG_TAG = 'GCL-74';
    private static final String OBJECT_ACCOUNT = 'Account';
    private static final String OBJECT_OPPORTUNITY = 'Opportunity';

    /**
     * @description Maximum team rows read per object in one run. Account plus Opportunity history inserts
     *              and the matching deletes stay well below the 10,000 DML row limit at this size.
     */
    @TestVisible
    private static Integer rowLimit = 2000;

    /**
     * @description Set to true when a full page means another run is needed. Tests read this
     *              because queueable chaining cannot run inside a test.
     */
    @TestVisible
    private static Boolean isChainRequested = false;

    private Map<Id, Date> inactiveDateByUserIdMap;
    private Set<String> assignmentTypeSet;

    /**
     * @description Creates the cleanup job.
     * @param inactiveDateByUserIdMap Deactivated user Id mapped to the date they were deactivated.
     * @param assignmentTypeSet AssignmentType__c values whose team rows are removed.
     */
    public LSInactiveUserCleanupQueueable(Map<Id, Date> inactiveDateByUserIdMap, Set<String> assignmentTypeSet) {
        this.inactiveDateByUserIdMap = new Map<Id, Date>(inactiveDateByUserIdMap);
        this.assignmentTypeSet = new Set<String>(assignmentTypeSet);
    }

    /**
     * @description Writes history rows, then deletes the matching team rows, in one transaction.
     *              A failure rolls back both steps, so no team row is lost without its history row.
     * @param queueableContext Queueable context from the platform.
     * @example
     * System.enqueueJob(new LSInactiveUserCleanupQueueable(inactiveDateByUserIdMap, assignmentTypeSet));
     */
    public void execute(QueueableContext queueableContext) {
        List<AccountTeamMember> accountTeamMemberList = new List<AccountTeamMember>();
        List<OpportunityTeamMember> opportunityTeamMemberList = new List<OpportunityTeamMember>();
        Logger.setScenario(SCENARIO);
        try {
            Set<Id> userIdSet = inactiveDateByUserIdMap.keySet();
            accountTeamMemberList = AccountTeamMemberSelector.selectByUserIdsAndAssignmentTypes(
                userIdSet,
                assignmentTypeSet,
                rowLimit
            );
            opportunityTeamMemberList = OpportunityTeamMemberSelector.selectByUserIdsAndAssignmentTypes(
                userIdSet,
                assignmentTypeSet,
                rowLimit
            );
            if (accountTeamMemberList.isEmpty() && opportunityTeamMemberList.isEmpty()) {
                return;
            }

            insert buildHistoryList(accountTeamMemberList, opportunityTeamMemberList);
            delete accountTeamMemberList;
            delete opportunityTeamMemberList;

            if (accountTeamMemberList.size() >= rowLimit || opportunityTeamMemberList.size() >= rowLimit) {
                enqueueNextPage();
            }
        } catch (DmlException dmlError) {
            List<SObject> affectedRecordList = new List<SObject>();
            affectedRecordList.addAll(accountTeamMemberList);
            affectedRecordList.addAll(opportunityTeamMemberList);
            Logger.error('LS inactive user cleanup failed while writing history or deleting team rows.', dmlError)
                .addTag(LOG_TAG)
                .setRecord(affectedRecordList);
            throw new LSInactiveUserCleanupException(
                'GCL-74: LS inactive user cleanup failed on DML. ' + dmlError.getMessage(),
                dmlError
            );
        } catch (QueryException queryError) {
            Logger.error('LS inactive user cleanup failed while reading team rows.', queryError)
                .addTag(LOG_TAG);
            throw new LSInactiveUserCleanupException(
                'GCL-74: LS inactive user cleanup failed on query. ' + queryError.getMessage(),
                queryError
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Builds one history row for every team row, before the team rows are deleted.
     *              Assignment_Type__c comes from AssignmentType__c, not from TeamMemberRole.
     * @param accountTeamMemberList Account Team rows about to be deleted.
     * @param opportunityTeamMemberList Opportunity Team rows about to be deleted.
     * @return History rows ready to insert.
     */
    private List<InactiveUserAssignmentHistory__c> buildHistoryList(
        List<AccountTeamMember> accountTeamMemberList,
        List<OpportunityTeamMember> opportunityTeamMemberList
    ) {
        List<InactiveUserAssignmentHistory__c> historyList = new List<InactiveUserAssignmentHistory__c>();
        for (AccountTeamMember teamMember : accountTeamMemberList) {
            historyList.add(new InactiveUserAssignmentHistory__c(
                User__c = teamMember.UserId,
                Account__c = teamMember.AccountId,
                Assignment_Type__c = teamMember.AssignmentType__c,
                AssignmentObject__c = OBJECT_ACCOUNT,
                UserInactivationDate__c = getInactivationDate(teamMember.UserId),
                IsLifeSciences__c = true
            ));
        }
        for (OpportunityTeamMember teamMember : opportunityTeamMemberList) {
            historyList.add(new InactiveUserAssignmentHistory__c(
                User__c = teamMember.UserId,
                Opportunity__c = teamMember.OpportunityId,
                Assignment_Type__c = teamMember.AssignmentType__c,
                AssignmentObject__c = OBJECT_OPPORTUNITY,
                UserInactivationDate__c = getInactivationDate(teamMember.UserId),
                IsLifeSciences__c = true
            ));
        }
        return historyList;
    }

    /**
     * @description Looks up the deactivation date for a user, defaulting to today.
     * @param userId Deactivated user Id.
     * @return The date the user was deactivated.
     */
    private Date getInactivationDate(Id userId) {
        Date inactivationDate = inactiveDateByUserIdMap.get(userId);
        return inactivationDate == null ? System.today() : inactivationDate;
    }

    /**
     * @description Starts the next page. Inside a test the job is not enqueued, because tests cannot chain
     *              Queueables; the request is recorded in isChainRequested instead.
     */
    private void enqueueNextPage() {
        isChainRequested = true;
        if (!Test.isRunningTest()) {
            System.enqueueJob(new LSInactiveUserCleanupQueueable(inactiveDateByUserIdMap, assignmentTypeSet));
        }
    }
}