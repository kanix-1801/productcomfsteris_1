public class CreateTasks {
    public static void createTasks(String ordnumber){
        Order ord= [select id,RegistrationNumber__c, Active__c,ParentCase__r.IPMDecision__c,ParentCase__r.Sales_Decision__c,ParentCase__c,OrderClassification__c,ParentCase__r.Status from Order where OrderNumber__c = :ordnumber];
        List<TaskSLAConfig__mdt> listTasConfig = [SELECT AssignTo__c, CalculateSLADaily__c, DueDateCriteria__c, Frequency__c, IsActive__c, IsTransferRequired__c, Object__c, SLACriteria__c, TaskCreationCriteria__c, TaskSubject__c, 
                                                  TransferCriteria__c FROM TaskSLAConfig__mdt where IsActive__c=true and Object__c='Order'];
        
        for(TaskSLAConfig__mdt taskconfig: listTasConfig){
               FormulaEval.FormulaInstance instance = Formula.builder()
    			.withType(	Order.SObjectType)
    			.withReturnType(FormulaEval.FormulaReturnType.BOOLEAN)
    			.withFormula(taskconfig.TaskCreationCriteria__c)
    			.build();
			// Evaluate the formula on the sObject
			Boolean iscreateTask = (Boolean)instance.evaluate(ord);
            if(iscreateTask)
               System.debug(taskconfig.TaskSubject__c);
			}
    }

}