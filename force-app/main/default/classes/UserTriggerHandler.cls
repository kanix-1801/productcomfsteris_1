/**
 * @description	: Trigger handler for User object events.
 *    			  Responsible for delegating User trigger processing to the service layer.
 * @author 		: Vinay
 * @date 		:2026-06-12
 */
public inherited sharing class UserTriggerHandler extends TriggerHandler {

    /**
     * @description Processes User after update events.
     */
    public override void afterUpdate() {
        UserService.processInactiveSalesUsers(
            (List<User>) Trigger.new,
            (Map<Id, User>) Trigger.oldMap
        );
    }
}