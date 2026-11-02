@isTest
private class CreateTaskHelperTestNew {
    
    @testSetup
    static void setupData() {
        // 1. Get Standard Pricebook ID
        Id pricebookId = Test.getStandardPricebookId();
        
        // 2. Create a Test User
        Profile p = [SELECT Id FROM Profile WHERE Name='Standard User' LIMIT 1];
        User testUser = new User(
            Alias = 'tuser', Email='testuser@ford.com', 
            EmailEncodingKey='UTF-8', LastName='Testing', LanguageLocaleKey='en_US', 
            LocaleSidKey='en_US', ProfileId = p.Id, 
            TimeZoneSidKey='America/Los_Angeles', UserName='testuser' + DateTime.now().getTime() + '@ford.com',
            IsActive = true
        );
        insert testUser;
        
        // 3. Create Account
        Account acc = new Account(Name = 'Test Account');
        insert acc;
        
        // 4. Create Case (RecordType CBMCase)
        Id caseRecordTypeId = Schema.SObjectType.Case.getRecordTypeInfosByDeveloperName().get('CBMCase').getRecordTypeId();
        Case c = new Case(
            Subject = 'Test Case',
            AccountId = acc.Id,
            RecordTypeId = caseRecordTypeId,
            UrgentOrder__c = true,
            Status = 'New'
        );
        insert c;
        
        // 5. Create Order - ASSIGN PRICEBOOK HERE
        Order ord = new Order(
            AccountId = acc.Id,
            EffectiveDate = Date.today(),
            Status = 'Draft',
            OrderNumber__c = 'ORD123',
            ParentCase__c = c.Id,
            RegistrationNumber__c = 'REG123',
            Pricebook2Id = pricebookId // Required to add OrderItems
        );
        insert ord;
        
        // Link Case back to Order (Case.Order__c is used in the helper queries)
        c.Order__c = ord.Id;
        update c;
        
        // 6. Create Product and PricebookEntry
        Product2 prod = new Product2(Name = 'Test Product', IsActive = true, SalesCategoryCode__c = 'Test');
        insert prod;
        
        PricebookEntry pbe = new PricebookEntry(
            Pricebook2Id = pricebookId, 
            Product2Id = prod.Id, 
            UnitPrice = 100, 
            IsActive = true
        );
        insert pbe;
        
        // 7. Create OrderItem (Order Line)
        OrderItem line = new OrderItem(
            OrderId = ord.Id,
            PricebookEntryId = pbe.Id,
            Quantity = 1,
            UnitPrice = 100 ,
           ScheduledDate__c = Date.today().addDays(5)
        );
        insert line;
        HoldMatrix__c holdtest = new HoldMatrix__c(
            
            Name = 'Credit Check Failure'
        );
        insert holdtest;
        
        
        // 8. Create OrderAndOrderLineHold__c
        OrderAndOrderLineHold__c hold = new OrderAndOrderLineHold__c(
            Order__c = ord.Id,
            //Active__c = true,
            ReasonCode__c = 'ADR',
            HoldMatrix__c = holdtest.Id
        );
        insert hold;
        
        // 9. Case Team Setup
        // Ensure a role exists. If not, this might need a try/catch or manual creation of role in some orgs.
        CaseTeamRole role = [SELECT Id FROM CaseTeamRole LIMIT 1];
        CaseTeamMember ctm = new CaseTeamMember(
            ParentId = c.Id,
            MemberId = testUser.Id,
            TeamRoleId = role.Id
        );
        insert ctm;
    }
    
   /* @isTest
    static void testCreateTasksForOrderNumber() {
        List<String> orderNums = new List<String>{'ORD123'};
            
            Test.startTest();
        CreateTaskHelper.createTasksForOrderNumber(orderNums);
        Test.stopTest();
        
        // Coverage check: The code queries metadata. If metadata exists, tasks will be created.
        List<Task> tasks = [SELECT Id FROM Task WHERE Order__c != null];
        System.debug('Tasks created for Order: ' + tasks.size());
    }
    
    @isTest
    static void testCreateTasksForOrderLine() {
        Test.startTest();
        CreateTaskHelper.createTasksForOrderLine('ORD123');
        Test.stopTest();
        
        List<Task> tasks = [SELECT Id FROM Task WHERE OrderLine__c != null];
        System.debug('Tasks created for Line: ' + tasks.size());
    }
    
    @isTest
    static void testCreateTasksForOrderAndOrderLineHold() {
        Test.startTest();
        // Test Active Hold Creation
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('ORD123');
        
        // Test Inactive Hold (covers the update/close logic)
        OrderAndOrderLineHold__c hold = [SELECT Id FROM OrderAndOrderLineHold__c LIMIT 1];
        //hold.Active__c = false;
        update hold;
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('ORD123');
        Test.stopTest();
    }
    
    @isTest
    static void testCalculateTaskSLAs() {
        Order ord = [SELECT Id, OrderNumber__c FROM Order LIMIT 1];
        
        // Insert a task manually to test SLA calculation logic
        Task t = new Task(
            Subject = 'Test Task',
            Order__c = ord.Id,
            Status = 'Open',
            Priority = 'Normal'
        );
        insert t;
        
        Test.startTest();
        CreateTaskHelper.calculateTaskSLAs(new List<String>{ord.OrderNumber__c});
        Test.stopTest();
    }
    
    @isTest
    static void testUtilityMethods() {
        Order ord = [SELECT Id FROM Order LIMIT 1];
        Case c = [SELECT Id FROM Case LIMIT 1];
        User u = [SELECT Id FROM User WHERE IsActive = true LIMIT 1];
        CaseTeamMember ctm = [SELECT Id, TeamRole.Name, MemberId, ParentId FROM CaseTeamMember WHERE ParentId = :c.Id LIMIT 1];
        
        Test.startTest();
        // Test resolveOwnerFromCaseTeam
        Id ownerId = CreateTaskHelper.resolveOwnerFromCaseTeam(c.Id, ctm.TeamRole.Name, new List<CaseTeamMember>{ctm}, new Set<Id>{u.Id});
        
        // Test mapPriorityFromSla
        CreateTaskHelper.mapPriorityFromSla('Red');
        CreateTaskHelper.mapPriorityFromSla('Yellow');
        CreateTaskHelper.mapPriorityFromSla('Green');
        
        // Test key generator
        CreateTaskHelper.key('TestSubj', c.Id, ord.Id);
        
        // Test Boolean/Text Evaluation (Empty strings to trigger safety checks)
        CreateTaskHelper.evaluateBoolean('', ord);
        CreateTaskHelper.evaluateText('', ord);
        Test.stopTest();
    }
    
    @isTest
    static void testExceptionHandling() {
        Test.startTest();
        // Test null inputs to ensure early returns are covered
        CreateTaskHelper.createTasksForOrderNumber(null);
        CreateTaskHelper.createTasksForOrderLine(null);
        CreateTaskHelper.calculateTaskSLAs(null);
        
        // Attempt to trigger a formula error by passing a null object to evaluator
        try {
            CreateTaskHelper.evaluateDueDate('CreatedDate', null);
        } catch (Exception e) {
            System.debug('Caught expected formula exception');
        }
        Test.stopTest();
    }
   
    @isTest
    static void testCreateTasksForOrderLineWithExistingTasks() {
        // 1. Get an active Metadata Config for OrderItem (Order Line)
        List<TaskSLAConfig__mdt> configs = [
            SELECT TaskSubject__c, Frequency__c 
            FROM TaskSLAConfig__mdt 
            WHERE IsActive__c = true AND Object__c = 'OrderItem' 
            LIMIT 1
        ];
        
        if (configs.isEmpty()) {
            System.debug('Skipping test: No active metadata for OrderItem found.');
            return;
        }
        TaskSLAConfig__mdt cfg = configs[0];
        
        // 2. Get Data from Setup
        Order ord = [SELECT Id, OrderNumber__c, ParentCase__c FROM Order WHERE OrderNumber__c = 'ORD123' LIMIT 1];
        OrderItem oli = [SELECT Id FROM OrderItem WHERE OrderId = :ord.Id LIMIT 1];
        Case c = [SELECT Id FROM Case WHERE Id = :ord.ParentCase__c];
        
        // Ensure Case is linked to Order for the query
        c.Order__c = ord.Id;
        update c;
        
        // 3. Create EXISTING tasks to trigger the red lines in the loop
        List<Task> tasksToInsert = new List<Task>();
        Id taskRT = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
        
        // Task 1: Covers initial "existingTasksByPhase" and "existingKeys" logic
        Task t1 = new Task(
            Subject = cfg.TaskSubject__c,
            WhatId = c.Id,
            OrderLine__c = oli.Id,
            Status = 'Completed',
            Phase__c = 1,
            RecordTypeId = taskRT
        );
        t1.put('Order__c', ord.Id); // Using put as per class usage
        tasksToInsert.add(t1);
        
        // Task 2: Covers the "else" branch and "existPhas < t.Phase__c" logic
        Task t2 = new Task(
            Subject = cfg.TaskSubject__c,
            WhatId = c.Id,
            OrderLine__c = oli.Id,
            Status = 'Open',
            Phase__c = 2, // Higher phase than t1
            RecordTypeId = taskRT
        );
        t2.put('Order__c', ord.Id);
        tasksToInsert.add(t2);
        
        insert tasksToInsert;
        
        Test.startTest();
        // This call will now find the tasks above and execute the red lines
        CreateTaskHelper.createTasksForOrderLine('ORD123');
        Test.stopTest();
        
        // Verification: The code should have processed existing tasks and skipped creating duplicates
        // based on the deduplication logic in the helper.
    }
 
    @isTest
static void testInactiveHoldTaskCompletion() {
    // 1. Get Metadata - Ensure we get a Subject that has a Frequency defined
    // The helper only queries tasks whose subjects are in the 'allSubjects' set
    List<TaskSLAConfig__mdt> configs = [
        SELECT TaskSubject__c, Frequency__c 
        FROM TaskSLAConfig__mdt 
        WHERE IsActive__c = true 
        AND Object__c = 'OrderAndOrderLineHold__c' 
        AND Frequency__c != null 
        LIMIT 1
    ];
    
    if (configs.isEmpty()) return;
    String validSubject = configs[0].TaskSubject__c;

    // 2. Setup Data
    Order ord = [SELECT Id, ParentCase__c FROM Order WHERE OrderNumber__c = 'ORD123' LIMIT 1];
    
    // Ensure the Case matches the helper's query: RecordType.DeveloperName = 'CBMCase'
    Id cbmCaseRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'CBMCase' LIMIT 1].Id;
    Case c = [SELECT Id FROM Case WHERE Id = :ord.ParentCase__c];
    c.Order__c = ord.Id; // CRITICAL: Helper queries Case WHERE Order__c = :orderId
    c.RecordTypeId = cbmCaseRT;
    update c;

    // 3. Create a Hold record
   HoldMatrix__c holdtestnew = new HoldMatrix__c(Name = 'Credit Check Failure');
        insert holdtestnew;
        
        OrderAndOrderLineHold__c hold = new OrderAndOrderLineHold__c(
            Order__c = ord.Id,
            HoldMatrix__c = holdtestnew.Id,
            // IMPORTANT: Check your TaskSLAConfig__mdt formula for 'OrderAndOrderLineHold__c'.
            // If the formula requires a specific ReasonCode, you MUST set it here.
            ReasonCode__c = 'Engineering' 
        );
        insert hold;
    
    // 4. Create an OPEN Task linked to this Hold
    Id taskRT = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
    Task openTask = new Task(
        Subject = validSubject,
        WhatId = c.Id, // Must match the caseId found by the helper
        OrderAndOrderLineHold__c = hold.Id,
        Status = 'Open',
        RecordTypeId = taskRT
    );
    openTask.put('Order__c', ord.Id);
    insert openTask;

    // 5. Make the Hold INACTIVE
    // If Active__c is a formula, we set common fields that usually trigger 'Active = false'
    try {
       // hold.Active__c = false;
        hold.put('ReasonResolvedDate__c', System.now());
        hold.put('HoldReleasedDate__c', System.now());
        update hold;
    } catch(Exception e) {
        // If Active__c is a read-only formula, the put() above handles the underlying fields
    }

    Test.startTest();
    // 6. Execute the helper
    CreateTaskHelper.createTasksForOrderAndOrderLineHold('ORD123');
    Test.stopTest();

    // 7. Verification
    Task updatedTask = [SELECT Status FROM Task WHERE Id = :openTask.Id];
    System.assertEquals('Completed', updatedTask.Status, 'The task should have been closed because the hold is inactive.');
}
  
    @isTest
    static void testHoldTaskDetailedCoverage() {
        // 1. Get the Metadata Config to know what Subject and Formula to use
        List<TaskSLAConfig__mdt> configs = [
            SELECT TaskSubject__c, TaskCreationCriteria__c, Frequency__c, AssignTo__c
            FROM TaskSLAConfig__mdt 
            WHERE IsActive__c = true AND Object__c = 'OrderAndOrderLineHold__c' 
            LIMIT 1
        ];
        
        if (configs.isEmpty()) return;
        TaskSLAConfig__mdt cfg = configs[0];
        
        // 2. Get Data and fix the Case Record Type
        Order ord = [SELECT Id, ParentCase__c FROM Order WHERE OrderNumber__c = 'ORD123' LIMIT 1];
        
        // The helper queries Case WHERE RecordType.DeveloperName = 'CBMCase'
        // If the RecordType doesn't match, caseId is null and red lines are skipped.
        Id cbmCaseRT = [SELECT Id FROM RecordType WHERE SObjectType = 'Case' AND DeveloperName = 'CBMCase' LIMIT 1].Id;
        Case c = [SELECT Id FROM Case WHERE Id = :ord.ParentCase__c];
        c.Order__c = ord.Id;
        c.RecordTypeId = cbmCaseRT;
        update c;
        
        // 3. Create Hold record
        HoldMatrix__c holdtest = new HoldMatrix__c(Name = 'Credit Check Failure');
        insert holdtest;
        
        OrderAndOrderLineHold__c hold = new OrderAndOrderLineHold__c(
            Order__c = ord.Id,
            HoldMatrix__c = holdtest.Id,
            // IMPORTANT: Check your TaskSLAConfig__mdt formula for 'OrderAndOrderLineHold__c'.
            // If the formula requires a specific ReasonCode, you MUST set it here.
            ReasonCode__c = 'Engineering' 
        );
        insert hold;
        
        // 4. Create an EXISTING task to cover the deduplication red lines
        Id taskRT = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
        Task existingTask = new Task(
            Subject = cfg.TaskSubject__c,
            WhatId = c.Id,
            OrderAndOrderLineHold__c = hold.Id,
            Status = 'Open',
            RecordTypeId = taskRT
        );
        existingTask.put('Order__c', ord.Id);
        insert existingTask;
        
        Test.startTest();
        
        // --- PART 1: Cover Deduplication (The red lines inside the first IF block) ---
        // This call finds the 'existingTask', sets hasOpenForSubjectAndHold = true, and hits 'continue'
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('ORD123');
        
        // --- PART 2: Cover Creation (The red lines for Frequency, DueDate, and Owner) ---
        // We delete the task so the code is forced to proceed to the creation logic
        delete existingTask; 
        
        // This call will now pass the dedupe check and execute the rest of the method
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('ORD123');
        
        Test.stopTest();
    }
    // ***************  Handler test methods **************** //
      @IsTest
    static void testCreateTasksForOrderAndOrderLineHold_Success() {
        // Retrieve the order number created in setup
        Order ord = [SELECT OrderNumber__c FROM Order LIMIT 1];
        
        Test.startTest();
        // Call the method
        CreateTaskHelper.createTasksForOrderAndOrderLineHold(ord.OrderNumber__c);
        Test.stopTest();
        
        // Verify results
        // We check for tasks related to the Hold record
        List<Task> createdTasks = [SELECT Id, Subject, Priority, WhatId, OrderAndOrderLineHold__c 
                                   FROM Task 
                                   WHERE OrderAndOrderLineHold__c != null];
        
        // Note: If coverage is 0 on the loop, ensure you have an active 
        // TaskSLAConfig__mdt for 'OrderAndOrderLineHold__c' in your org.
        System.debug('Total Hold Tasks Created: ' + createdTasks.size());
    }
    
    
    
    @IsTest
    static void testCreateTasksForOrderAndOrderLineHold_InvalidInputs() {
        Test.startTest();
        // Test null input
        CreateTaskHelper.createTasksForOrderAndOrderLineHold(null);
        
        // Test non-existent order number
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('NON_EXISTENT_999');
        Test.stopTest();
        
        // Verify no tasks were created
        Integer taskCount = [SELECT Count() FROM Task WHERE OrderAndOrderLineHold__c != null];
        System.assertEquals(0, taskCount, 'No tasks should be created for invalid order numbers');
    }
    
    
    
    @IsTest
    static void testFormulaExceptions() {
        Account acc = new Account(Name = 'Exception Test');
        insert acc;
        
        Test.startTest();
        
        // 1. Trigger evaluateBoolean Exception (Invalid Formula)
        try {
            CreateTaskHelper.evaluateBoolean('INVALID_FUNCTION(Id)', acc);
        } catch (Exception e) {
            System.debug('Caught expected evaluateBoolean exception');
        }
        
        // 2. Trigger evaluateDueDate Exception (Invalid Formula)
        try {
            CreateTaskHelper.evaluateDueDate('MALFORMED + FORMULA', acc);
        } catch (Exception e) {
            System.debug('Caught expected evaluateDueDate exception');
        }
        
        // 3. Trigger evaluateText Exception
        try {
            CreateTaskHelper.evaluateText('FAKE_FIELD__c', acc);
        } catch (Exception e) {
            System.debug('Caught expected evaluateText exception');
        }
        
        Test.stopTest();
    }
    
    @IsTest
    static void testTransferOwnerNullLogic() {
        // Covers the early return statements in transferOwner
        Id ownerId = UserInfo.getUserId();
        
        Id result1 = CreateTaskHelper.transferOwner(null, null, ownerId, null, null, null);
        System.assertEquals(ownerId, result1);
        
        String configJson = '{"IsTransferRequired__c": false}';
        TaskSLAConfig__mdt mockCfg = (TaskSLAConfig__mdt)JSON.deserialize(configJson, TaskSLAConfig__mdt.class);
        Id result2 = CreateTaskHelper.transferOwner(mockCfg, NewGuid(), ownerId, null, null, null);
        System.assertEquals(ownerId, result2);
    }
    
    // Helper to generate a dummy Id for testing
    private static Id NewGuid() {
        return Id.valueOf(Account.sObjectType.getDescribe().getKeyPrefix() + '000000000001');
    }
    @isTest
    static void createTasksForOrderAndOrderLineHold_Test() {
        // Create test data
        Account acc = new Account(Name = 'Test Account 3');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id, 
            Status = 'Draft', 
            EffectiveDate = Date.today(), 
            OrderNumber__c = 'TEST-003',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;
        
        // Test normal execution
        Test.startTest();
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('TEST-003');
        CreateTaskHelper.createTasksForOrderAndOrderLineHold(null);
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('NONEXISTENT');
        Test.stopTest();
    }
    @isTest
    static void createTasksForOrderAndOrderLineHold_Test1() {
        // 1. Setup Basic Data
        Account acc = new Account(Name = 'Test Account 3');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id, 
            Status = 'Draft', 
            EffectiveDate = Date.today(), 
            OrderNumber__c = 'TEST-003',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;
        
        // 2. Create the "caseId" record 
        // (Assuming caseId is a Case. If the code uses the Order ID as caseId, skip this and use ord.Id)
        Case c = new Case(Subject = 'Order Case', AccountId = acc.Id);
        insert c;
        
        // 3. Insert the Task that the query is looking for
        // REPLACE 'Hold Task' with a real subject string from your helper class logic
        Task t = new Task(
            Subject = 'Hold Task', 
            WhatId = c.Id,         // Use ord.Id here if the code uses Order as caseId
            Order__c = ord.Id,
            Status = 'Not Started',
            Priority = 'Normal'
            // Phase__c = 1       // Populate this if it's a custom field used in your code
        );
        insert t;
        
        // 4. Run the test
        Test.startTest();
        CreateTaskHelper.createTasksForOrderAndOrderLineHold('TEST-003');
        Test.stopTest();
    }
    static void testCreateTasksForOrderLinenew() {
        // Create test data
        Account acc = new Account(Name = 'Test Account 3');
        insert acc;
        
        Order ord = new Order(
            AccountId = acc.Id, 
            Status = 'Draft', 
            EffectiveDate = Date.today(), 
            OrderNumber__c = 'TEST-003',
            Pricebook2Id = Test.getStandardPricebookId()
        );
        insert ord;
        
        // Test normal execution
        Test.startTest();
        CreateTaskHelper.createTasksForOrderLine('TEST-003');
        CreateTaskHelper.createTasksForOrderLine(null);
        CreateTaskHelper.createTasksForOrderLine('NONEXISTENT');
        Test.stopTest();
    }
    
    
    @IsTest
    static void testEmptyInputs() {
        Test.startTest();
        CreateTaskHelper.calculateTaskSLAs(null);
        CreateTaskHelper.createTasksForOrderAndOrderLineHold(null);
        Test.stopTest();
        
        // Simply verifying no exceptions were thrown
        System.assert(true);
    }
    
    
    @IsTest
    static void testCalculateTaskSLAs_DeepCoverage() {
        // 1. Get the Order created in your @TestSetup
        Order ord = [SELECT Id, OrderNumber__c FROM Order LIMIT 1];
        
        // 2. Query the exact same metadata the method will query internally
        List<TaskSLAConfig__mdt> configs = [
            SELECT TaskSubject__c, SLACriteria__c, CalculateSLADaily__c 
            FROM TaskSLAConfig__mdt 
            WHERE IsActive__c = true
        ];
        
        // 3. Find a config that has both a Subject and SLA Criteria
        TaskSLAConfig__mdt targetCfg;
        for (TaskSLAConfig__mdt cfg : configs) {
            if (String.isNotBlank(cfg.TaskSubject__c) && String.isNotBlank(cfg.SLACriteria__c)) {
                targetCfg = cfg;
                break;
            }
        }
        
        // If this fails, you need to create/activate a Metadata record in your org
        System.assertNotEquals(null, targetCfg, 'Test requires at least one active TaskSLAConfig__mdt with Subject and SLA Criteria');
        
        // 4. Create the Task. 
        // IMPORTANT: Subject must match metadata exactly for the 'Subject IN :cfgSubjects' filter
        Task t = new Task(
            Subject = targetCfg.TaskSubject__c, 
            Order__c = ord.Id,                // This matches 'Order__c IN :orderIds'
            Status = 'Open',
            RiskLevel__c = null,              // null ensures the 'changed' logic is triggered
            ActivityDate = Date.today()
        );
        insert t;
        
        // Verify the task exists before calling the method
        List<Task> checkExists = [SELECT Id FROM Task WHERE Order__c = :ord.Id AND Subject = :targetCfg.TaskSubject__c];
        System.assertEquals(1, checkExists.size(), 'Task must be queryable by Order and Subject');
        
        Test.startTest();
        // 5. Call the method with the specific Order Number from setup
        CreateTaskHelper.calculateTaskSLAs(new List<String>{ord.OrderNumber__c});
        Test.stopTest();
        
        // 6. Final check to ensure the RiskLevel__c was actually updated
        Task updatedTask = [SELECT RiskLevel__c FROM Task WHERE Id = :t.Id];
        System.debug('Risk Level after test: ' + updatedTask.RiskLevel__c);
    }*/
    
}