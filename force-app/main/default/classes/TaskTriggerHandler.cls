/**
 * @author PSL
 * @date 01-20-2026
 * @description handler class for handling Task logics on database events.
 */
public class TaskTriggerHandler extends TriggerHandler {
    
    /**
     * @description Constructor - optionally configure recursion control
     */
    public TaskTriggerHandler() {
        super();
        
    }
    
    /**
     * @description Invokes helper to prevent deletion of CBM Task record type tasks for non-admin users.
     * @param oldTasks List of Task records from trigger.old slated for deletion
     * @return void
     */
    protected override void beforeDelete(){
        if (!AutomationControl.isTriggerEnabled('TaskTrigger')) return;
        TaskTriggerHelper.preventTaskDeletion((List<Task>) Trigger.old);
    }
    // CBM-526
   
    protected override void beforeInsert(){
        if (!AutomationControl.isTriggerEnabled('TaskTrigger')) return;
        TaskTriggerHelper.restrictPriorityForNonAdmin((List<Task>) Trigger.new, null, true, false);
    }
    
    protected override void beforeUpdate(){
        if (!AutomationControl.isTriggerEnabled('TaskTrigger')) return;
        TaskTriggerHelper.restrictPriorityForNonAdmin((List<Task>) Trigger.new, (Map<Id,Task>) Trigger.oldMap, false, true);
    }

}