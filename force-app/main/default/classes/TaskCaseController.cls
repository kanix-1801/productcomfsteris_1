public class TaskCaseController {
    public Task task { get; set; }
    public Case relatedCase { get; set; }

    public TaskCaseController(ApexPages.StandardController controller) {
        // Get the current Task record ID
        Id taskId = controller.getId();
        
        // Query the Task including the WhatId
        task = [SELECT Id, Subject, WhatId FROM Task WHERE Id = :taskId LIMIT 1];
        
        // Check if WhatId points to a Case (prefix '500')
        if (task.WhatId != null && String.valueOf(task.WhatId).startsWith('500')) {
            relatedCase = [SELECT Id, CaseNumber, Subject, Status FROM Case WHERE Id = :task.WhatId LIMIT 1];
        }
    }
}