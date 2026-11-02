/**
 * @author Akash Dahinde
 * @date 09-25-2026
 * @story GCL-11
 * @description Validates Opportunity Contact Role insert/update events through
 *              PrimaryContactHandler. Uses the standard trigger automation
 *              hierarchy setting for global and trigger-specific bypass.
 */
trigger OpportunityContactRoleTrigger on OpportunityContactRole (
    before insert,
    before update
) {
    Automation_Setting_Trigger__c settings = Automation_Setting_Trigger__c.getInstance();

    if (settings != null && (
        settings.BypassOppContactRolesTrigger__c
        || settings.disableAll__c
    )) {
        return;
    }

    new PrimaryContactHandler().run();
}