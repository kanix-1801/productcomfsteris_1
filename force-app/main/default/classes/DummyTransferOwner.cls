public with sharing class DummyTransferOwner
    implements Database.Batchable<SObject>, Database.Stateful
    {
        
        
        
        public Database.QueryLocator start(Database.BatchableContext bc) {
            
            
             List<TaskSLAConfig__mdt> cfgs=[
            SELECT Id, DeveloperName, MasterLabel,
          TaskSubject__c, IsActive__c, IsTransferRequired__c,   
                TransferCriteria__c, TransferTo__c, Object__c FROM TaskSLAConfig__mdt 
                WHERE IsActive__c = TRUE AND IsTransferRequired__c = TRUE];
            
            set<string> subjString = new set<string>();
            
            for(TaskSLAConfig__mdt cfg: cfgs){
                if(cfg.taskSubject__C!=null){
                    subjString.add(cfg.taskSubject__C);
                }
            }
            
            String taskQuery =
            'SELECT Id, Subject, Status, OwnerId, WhatId, ' +
            '       Priority, ActivityDate, CreatedDate, LastModifiedDate ' +
            'FROM Task ' +
            'WHERE Subject IN :subjString ' +
            '  AND Status = Open ' +
            '  AND WhatId != null';
            
            
             return Database.getQueryLocator(taskQuery);
            
            
        }
    public void execute(Database.BatchableContext bc, List<SObject> scope) {
        
        List<Task> tasksInScope = new List<Task>();
        for (SObject sob : scope) tasksInScope.add((Task)sob);
        
        set<id> caseIDs = new set<id>();
         
        for(task ts : tasksInScope){
            if(ts.WhatId != null && String.valueOf(ts.WhatId).startsWith('500')){
                caseIds.add(ts.whatID);
            }
        }
        if(!caseIDs.isEmpty()){
            
        }
        
    }
    public void finish(Database.BatchableContext bc) {
        
    }

}