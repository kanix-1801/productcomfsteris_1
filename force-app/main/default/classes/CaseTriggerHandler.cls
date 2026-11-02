/**
 * @description Trigger Handler for Case object following KevinOHara80 framework.
 *              Orchestrates Domain/Service layer calls with no SOQL or DML.
 *              Follows STERIS enterprise architecture standards.
 * @author STERIS
 * @date 2026-04-22
 */
public class CaseTriggerHandler extends TriggerHandler {
    
    /**
     * @description Constructor - optionally configure recursion control
     */
    public CaseTriggerHandler() {
        super();
        
    }
    
    /**
     * @description GW-1279 - Before Insert handler - calls CasesService.applyCaseRoutingRules with Trigger.new;
     *              applies defaults and validates
     */
    protected override void beforeInsert() {
        if (!AutomationControl.isTriggerEnabled('CaseTrigger')) return;
        CasesService.applyCaseRoutingRules((List<Case>) Trigger.new);
        
    }
    
    /**
     * @description After Update handler - orchestrates post-update business logic
     */
    protected override void afterUpdate() {
        /**
         * The following lines were copied from the previous CBM CaseTriggerHandler that this class replaces.
         */
        if (!AutomationControl.isTriggerEnabled('CaseTrigger')) return;
        CaseTriggerHelper.updateChildCasesWithParentWantDate((List<Case>) Trigger.New, ((Map<Id,Case>) Trigger.oldMap), (Map<Id,Case>) Trigger.newMap);
        CaseTriggerHelper.createScheduleCheckInTask((List<Case>) Trigger.New, (Map<Id,Case>) Trigger.oldMap);  //CBM-859

    }
}