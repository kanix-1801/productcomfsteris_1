/**
 * @author Abhishek Mishra
 * @date 15-10-2026
 * @description #GC-3435 Trigger handler for Team Member.
 *              Delegates duplicate checks and record sharing to TeamMemberService.
 */
public with sharing class TeamMemberTriggerHandler extends TriggerHandler {

    /**
     * @description Blocks a Team Member row that has no parent or repeats a user on the same record.
     */
    @TestVisible
    protected override void beforeInsert() {
        TeamMemberService.validateDuplicates((List<TeamMember__c>) Trigger.new);
    }

    /**
     * @description Re-checks the parent and user when a Team Member row changes.
     */
    @TestVisible
    protected override void beforeUpdate() {
        TeamMemberService.validateDuplicates((List<TeamMember__c>) Trigger.new);
    }

    /**
     * @description Shares each parent record after a Team Member is added.
     */
    @TestVisible
    protected override void afterInsert() {
        TeamMemberService.syncShares((List<TeamMember__c>) Trigger.new, null);
    }

    /**
     * @description Rebuilds shares when the user, parent, or access changes.
     */
    @TestVisible
    protected override void afterUpdate() {
        TeamMemberService.syncShares(
            (List<TeamMember__c>) Trigger.new,
            (Map<Id, TeamMember__c>) Trigger.oldMap
        );
    }

    /**
     * @description Removes the share when the last Team Member row for that user is deleted.
     */
    @TestVisible
    protected override void afterDelete() {
        TeamMemberService.syncShares(null, (Map<Id, TeamMember__c>) Trigger.oldMap);
    }

    /**
     * @description Restores the share when a Team Member row is undeleted.
     */
    @TestVisible
    protected override void afterUndelete() {
        TeamMemberService.syncShares((List<TeamMember__c>) Trigger.new, null);
    }
}