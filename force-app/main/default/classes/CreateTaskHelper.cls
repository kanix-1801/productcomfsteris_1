/**
 * @author PSL
 * @date 12-12-2025
 * @description Helper class for creating Tasks related to Orders, Order Lines, and Holds based on TaskSLAConfig metadata.
 *              Provides methods for task creation, owner resolution, SLA calculation, and formula evaluation.
 */
public with sharing class CreateTaskHelper {
    
    // Build ReasonCode -> Task Subject map for holds
    public static Map<String, String> holdReasonToTaskSubject = new Map<String, String>{
                'ENG' => 'Resolve Engineering Hold',
                'IOA' => 'Resolve IOA Form Hold',
                'LC'  => 'Resolve Logistics Coordination Hold'
            };
    
    /**
     * @description Creates tasks for the given order numbers by querying related Orders and delegating to createTasksForOrders.
     * @param orderNumbers List of order numbers to process
     * @return void
     */
    public static void createTasksForOrderNumber(List<string> orderNumbers){
        try {
            if (orderNumbers == null || orderNumbers.isEmpty()) return;

            
            Set<String> ordNums = new Set<String>();
            for (String n : orderNumbers) {
                if (String.isNotBlank(n)) ordNums.add(n.trim());
            }
            if (ordNums.isEmpty()) return;

           
            List<Order> orders = [
                SELECT id, Status, isMigrated__c, RegistrationNumber__c, Active__c, CreatedDate,NoOfENGHolds__c, AllCapitalLinesClosedDate__c, 
                ParentCase__r.IPMDecision__c,ParentCase__r.Sales_Decision__c, CurrencyIsoCode, 
                ParentCase__c,OrderClassification__c,ParentCase__r.Status,ParentCase__r.UrgentOrder__c, AreAllNonFeeAndDiscountClosed__c, FirstScheduledDateNonPreinstall__c, AllCapitalLinesClosed__c, 
                IsTradInLineOpen__c, IsProceduralMixedExists__c, IsProceduralMixedScheduleDateMissing__c, ProceduralMixedScheduleDate__c, AllReprocessingScheduledDate__c, IsReprocessingExists__c, IsReprocessingScheduleDateMissing__c, Country__c, Type   
                from Order 
                WHERE OrderNumber__c IN :ordNums
            ];
            if (orders.isEmpty()) return;

            // Delegate to the bulk method that works with Orders
            createTasksForOrders(orders);
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'createTasksForOrderNumber', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }
    
    
    
    
    /**
     * @description Main method to create tasks for a list of Orders based on active TaskSLAConfig records.
     * @param orders List of Orders to process
     * @return void
     */
    public static void createTasksForOrders(List<Order> orders) {
        try {
            if (orders == null || orders.isEmpty()) return;

            // --- Collect Order Ids
            Set<Id> orderIds = new Set<Id>();
            for (Order o : orders) if (o.Id != null) orderIds.add(o.Id);
            if (orderIds.isEmpty()) return;

            // --- Find Cases via Case.Order__c
            Map<Id, Id> orderIdToCaseId = new Map<Id, Id>(); // OrderId -> CaseId
            List<Case> cases = [
                SELECT Id, Order__c
                FROM Case
                WHERE Order__c IN :orderIds AND RecordType.DeveloperName = 'CBMCase'
            ];
            Set<Id> caseIds = new Set<Id>();
            for (Case c : cases) {
                orderIdToCaseId.put(c.Order__c, c.Id);
                caseIds.add(c.Id);
            }

            // --- Load active task configs once
            List<TaskSLAConfig__mdt> configs = [
                SELECT AssignTo__c, DueDateCriteria__c, Frequency__c, IsActive__c,
                       Object__c, TaskCreationCriteria__c, TaskSubject__c, DeveloperName,
                       SLACriteria__c, CalculateSLADaily__c, TaskPriorityOrder__c 
                FROM TaskSLAConfig__mdt
                WHERE IsActive__c = true AND Object__c = 'Order'
                ORDER BY TaskPriorityOrder__c NULLS LAST
            ];
            if (configs.isEmpty()) return;

            // --- Case Team Members (owner resolution)
            Map<Id, List<CaseTeamMember>> caseIdToCTMs = new Map<Id, List<CaseTeamMember>>();
            Set<Id> allMemberIds = new Set<Id>();
            if (!caseIds.isEmpty()) {
                List<CaseTeamMember> ctmList = [
                    SELECT Id, TeamRole.Name, MemberId, ParentId
                    FROM CaseTeamMember
                    WHERE ParentId IN :caseIds
                ];
                for (CaseTeamMember ctm : ctmList) {
                    if (!caseIdToCTMs.containsKey(ctm.ParentId)) {
                        caseIdToCTMs.put(ctm.ParentId, new List<CaseTeamMember>());
                    }
                    caseIdToCTMs.get(ctm.ParentId).add(ctm);
                    if (ctm.MemberId != null) allMemberIds.add(ctm.MemberId);
                }
            }

            // --- Prefer active users
            Set<Id> activeUserIds = new Set<Id>();
            if (!allMemberIds.isEmpty()) {
                for (User u : [SELECT Id, IsActive FROM User WHERE Id IN :allMemberIds]) {
                    if (u.IsActive) activeUserIds.add(u.Id);
                }
            }

            // --- Prepare Onetime de-duplication
            Set<String> onetimeSubjects = new Set<String>();
            for (TaskSLAConfig__mdt cfg : configs) {
                if ('Onetime'.equalsIgnoreCase(cfg.Frequency__c) && String.isNotBlank(cfg.TaskSubject__c)) {
                    onetimeSubjects.add(cfg.TaskSubject__c.trim());
                }
            }

            // Prefetch existing tasks (one query)
            Set<String> existingKeys = new Set<String>(); // composite key: subject|caseId|orderId
            if (!onetimeSubjects.isEmpty() && (!caseIds.isEmpty() || !orderIds.isEmpty())) {
                List<Task> existing = [
                    SELECT Id, Subject, WhatId, Order__c
                    FROM Task
                    WHERE IsDeleted = false
                      AND Subject IN :onetimeSubjects
                      AND ((WhatId IN :caseIds) OR (Order__c IN :orderIds))
                ];
                for (Task t : existing) {
                    String subj = t.Subject;
                    Id cId = t.WhatId;
                    Id oId = (Id)t.get('Order__c');
                    if (!String.isBlank(subj) && cId != null && oId != null) {
                        existingKeys.add(key(subj, cId, oId));
                    }
                }
            }

            // --- Build tasks
            List<Task> toInsert = new List<Task>();

            for (Order ord : orders) {
                // Prefer Case.Order__c; fallback to ParentCase__c
                Id caseId = orderIdToCaseId.get(ord.Id);
                if (caseId == null && ord.ParentCase__c != null) caseId = ord.ParentCase__c;

                List<CaseTeamMember> ctmForCase = (caseId != null) ? caseIdToCTMs.get(caseId) : null;

                for (TaskSLAConfig__mdt cfg : configs) {
                    // 1) Creation criteria (Boolean) on Order
                    if (!evaluateBoolean(cfg.TaskCreationCriteria__c, ord)) continue;

                    // 2) Dedupe for Onetime
                    Boolean isOnetime = 'Onetime'.equalsIgnoreCase(cfg.Frequency__c);
                    if (isOnetime && caseId != null) {
                        String k = key(cfg.TaskSubject__c, caseId, ord.Id);
                        if (existingKeys.contains(k)) continue;
                    }

                    // 3) Due date (Date or Datetime → Date)
                    //Date dueDate = evaluateDueDate(cfg.DueDateCriteria__c, ord);

                    // 4) Owner from Case Team (TeamRole.Name equals/contains AssignTo__c)
                    Id ownerId = resolveOwnerFromCaseTeam(caseId, cfg.AssignTo__c, ctmForCase, activeUserIds);
                    if (ownerId == null) ownerId = UserInfo.getUserId(); // fallback

                    // 5) SLA text (TEXT) and Priority mapping
                   

                    // 6) Build Task
                    String priorityText = 'No';
                    if(ord.ParentCase__r.UrgentOrder__c) {
                        priorityText = 'Yes';
                    }
                    Task t = new Task();
                    t.Subject      = cfg.TaskSubject__c;
                    t.OwnerId      = ownerId;
                    t.Status       = 'Open';        // adjust to your org
                    //t.ActivityDate = dueDate;              // null allowed
                    t.Priority     = priorityText;
                    t.RecordTypeId = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
                    t.TaskTeam__c  = cfg.AssignTo__c;
                    if (caseId != null) t.WhatId = caseId; // relate to Case
                    t.put('Order__c', ord.Id);             // custom lookup to Order

                    // Optional: persist SLA text if you have Task.SLA__c (Text)
                    // t.put('SLA__c', slaText);

                    t.CurrencyIsoCode = ord.CurrencyIsoCode;
                    toInsert.add(t);

                    // Update dedupe set to avoid multiple inserts in this run
                    if (isOnetime && caseId != null) {
                        existingKeys.add(key(cfg.TaskSubject__c, caseId, ord.Id));
                    }
                }
            }

            // --- Single DML
            if (!toInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(toInsert, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Task insert error: ' + e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'createTasksForOrders', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }

    // ===================== Helpers =====================

    /**
     * @description Generates a composite key for de-duplication of tasks based on Subject, Case ID, and Order ID.
     * @param subject Task subject line
     * @param caseId ID of the related Case
     * @param orderId ID of the related Order
     * @return String composite key
     */
    @TestVisible
    private static String key(String subject, Id caseId, Id orderId) {
        return (subject == null ? '' : subject.trim()) + '|' + (String)caseId + '|' + (String)orderId;
    }

    /**
     * @description Resolves the Task owner from Case Team members based on Team Role matching.
     * @param caseId ID of the related Case
     * @param assignCode Team role name to match against
     * @param ctmForCase List of CaseTeamMember records for the Case
     * @param activeUserIds Set of active user IDs for preference
     * @return Id of the resolved owner or null if none found
     */
    @TestVisible
    private static Id resolveOwnerFromCaseTeam(
        Id caseId,
        String assignCode,
        List<CaseTeamMember> ctmForCase,
        Set<Id> activeUserIds
    ) {
        if (caseId == null || String.isBlank(assignCode) || ctmForCase == null || ctmForCase.isEmpty()) return null;

        String needle = assignCode.trim().toLowerCase();

        Set<Id> matches = new Set<Id>();
        for (CaseTeamMember ctm : ctmForCase) {
            String roleNameLower = (ctm.TeamRole != null && ctm.TeamRole.Name != null)
                ? ctm.TeamRole.Name.trim().toLowerCase()
                : '';
            if (String.isBlank(roleNameLower) || ctm.MemberId == null) continue;

            if (roleNameLower.equals(needle) || roleNameLower.contains(needle)) {
                matches.add(ctm.MemberId);
            }
        }
        if (matches.isEmpty()) return null;

        List<Id> sorted = new List<Id>();
        sorted.addAll(matches);
        sorted.sort();

        for (Id mId : sorted) {
            if (activeUserIds.contains(mId)) return mId; // prefer active
        }
        return sorted[0];
    }

    // ---------- SLA → Priority ----------
    /**
     * @description Maps SLA text values to Task.Priority values for standard prioritization.
     * @param sla Text representation of SLA level ("Red", "Yellow", "Green", "No SLA")
     * @return Mapped priority value or empty string if unrecognized
     */
    @TestVisible
    private static String mapPriorityFromSla(String sla) {
        if (String.isBlank(sla)) return '';
        String s = sla.trim();
        if (s.equalsIgnoreCase('Red'))    return 'Red';
        if (s.equalsIgnoreCase('Yellow')) return 'Yellow';
        if (s.equalsIgnoreCase('Green'))  return 'Green';
        if (s.equalsIgnoreCase('No SLA')) return '';
        return '';
    }

    // ---------- Transfer Logic (post owner identification) ----------
    /**
     * @description Optionally transfers the intended Task owner to another Case Team role based on configuration.
     * @param cfg TaskSLAConfig__mdt record defining transfer behavior
     * @param caseId ID of the related Case
     * @param currentOwnerId Current owner ID of the Task
     * @param sObjContext SObject context for evaluating transfer criteria
     * @param ctmForCase List of CaseTeamMember records for the Case
     * @param activeUserIds Set of active user IDs for preference
     * @return Updated owner ID or original if no transfer occurs
     */
    public static Id transferOwner(
        TaskSLAConfig__mdt cfg,
        Id caseId,
        Id currentOwnerId,
        SObject sObjContext,
        List<CaseTeamMember> ctmForCase,
        Set<Id> activeUserIds
    ) {
        if (cfg == null || caseId == null) return currentOwnerId;
        if (cfg.IsTransferRequired__c != true) return currentOwnerId;

        // Evaluate TransferCriteria__c as BOOLEAN on the provided context
        Boolean transferOk = false;
        if (!String.isBlank(cfg.TransferCriteria__c)) {
            transferOk = evaluateBoolean(cfg.TransferCriteria__c, sObjContext);
        }

        if (transferOk && !String.isBlank(cfg.TransferTo__c)) {
            // Use existing matching logic (equals or contains, prefer active)
            Id transferedOwner = resolveOwnerFromCaseTeam(caseId, cfg.TransferTo__c, ctmForCase, activeUserIds);
            if (transferedOwner != null) return transferedOwner;
        }
        return currentOwnerId;
    }

    // ---------- Dynamic Formula Evaluation (SObject context) ----------
    /**
     * @description Evaluates a BOOLEAN formula against the given SObject context.
     * @param formulaText Formula text to evaluate
     * @param sObj SObject context for evaluation
     * @return Boolean result of formula evaluation
     */
    @TestVisible
    private static Boolean evaluateBoolean(String formulaText, SObject sObj) {
        if (String.isBlank(formulaText)) return false;
        try {
            FormulaEval.FormulaInstance inst = System.Formula.builder()
                .withType(sObj.getSObjectType())
                .withReturnType(FormulaEval.FormulaReturnType.BOOLEAN)
                .withFormula(formulaText)
                .build();
            Object result = inst.evaluate(sObj);
            return (result instanceof Boolean) ? (Boolean)result : false;
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'evaluateBoolean'+'***'+formulaText, ErrorLogger.Level.ERROR, sObj.Id, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }

    /**
     * @description Evaluates a DATE/DATETIME formula and normalizes the result to Date.
     * @param formulaText Formula text to evaluate
     * @param sObj SObject context for evaluation
     * @return Date result of formula evaluation or null if invalid
     */
    @TestVisible
    private static Date evaluateDueDate(String formulaText, SObject sObj) {
        if (String.isBlank(formulaText)) return null;

        // First: build as DATE and handle Datetime at runtime
        try {
            FormulaEval.FormulaInstance iDate = System.Formula.builder()
                .withType(sObj.getSObjectType())
                .withReturnType(FormulaEval.FormulaReturnType.DATE)
                .withFormula(formulaText)
                .build();
            
             

            Object r = iDate.evaluate(sObj);
            if (r instanceof Date)     return (Date)r;
            if (r instanceof Datetime) return ((Datetime)r).date();
            if (r == null)             return null;

            // Log the exception with recordId if available
            ErrorLogger.logMessage('DueDateCriteria unexpected type with DATE builder: ' + String.valueOf(r) + ' -------> ' + formulaText, 'CreateTaskHelper', 'evaluateDueDate', ErrorLogger.Level.ERROR, sObj.Id+'', null);
            return null;

        } catch (Exception e1) {
            // Fallback: build as DATETIME
            try {
                // Log the exception with recordId if available
                ErrorLogger.logException(e1, 'CreateTaskHelper', 'evaluateDueDate:'+'***'+formulaText, ErrorLogger.Level.ERROR, sObj.Id, null);
                
                FormulaEval.FormulaInstance iDt = System.Formula.builder()
                    .withType(sObj.getSObjectType())
                    .withReturnType(FormulaEval.FormulaReturnType.DATETIME)
                    .withFormula(formulaText)
                    .build();

                Object r2 = iDt.evaluate(sObj);
                if (r2 instanceof Datetime) return ((Datetime)r2).date();
                if (r2 instanceof Date)     return (Date)r2;
                if (r2 == null)             return null;

                return null;

            } catch (Exception e2) {
                // Log the exception with recordId if available
                ErrorLogger.logException(e2, 'CreateTaskHelper', 'evaluateDueDate'+'***'+formulaText, ErrorLogger.Level.ERROR, sObj.Id, null);
                // Re-throw the exception to maintain original behavior
                throw e2;
            }
        }
    }

    /**
     * @description Evaluates a TEXT formula (typically SLA criteria) against the given SObject context.
     * @param formulaText Formula text to evaluate
     * @param sObj SObject context for evaluation
     * @return String result of formula evaluation or null if invalid
     */
    @TestVisible
    private static String evaluateText(String formulaText, SObject sObj) {
        if (String.isBlank(formulaText)) return null;
        try {
            FormulaEval.FormulaInstance inst = System.Formula.builder()
                .withType(sObj.getSObjectType())
                .withReturnType(FormulaEval.FormulaReturnType.String)
                .withFormula(formulaText)
                .build();
            Object result = inst.evaluate(sObj);
            return (result instanceof String) ? (String)result : null;
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'evaluateText'+'***'+formulaText, ErrorLogger.Level.ERROR, sObj.Id, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }

    /**
     * @description Creates tasks for Order Lines based on TaskSLAConfig records where Object__c = 'OrderItem'.
     * @param orderNumber The Order Number of the order received from Oracle to create tasks
     * @return void
     */
    public static void createTasksForOrderLine(String orderNumber) {
        try {
            if (orderNumber == null) return;

            // Load the Order (for relationship fallbacks like ParentCase__c)
            List<Order> ordList = [
                SELECT Id, isMigrated__c, ParentCase__c, ParentCase__r.UrgentOrder__c, CurrencyIsoCode 
                FROM Order
                WHERE OrderNumber__c = :orderNumber
                LIMIT 1
            ];
            if (ordList.isEmpty()) return;

            Order ord = ordList[0];
            String orderId = ord.Id;

            // Load active task configs for OrderItem (Order Line) objects
            List<TaskSLAConfig__mdt> configs = [
                SELECT AssignTo__c, DueDateCriteria__c, Frequency__c, IsActive__c,
                       Object__c, TaskCreationCriteria__c, TaskSubject__c, DeveloperName
                FROM TaskSLAConfig__mdt
                WHERE IsActive__c = true AND Object__c = 'OrderItem'
            ];
            if (configs.isEmpty()) return;

            // Find Case for the Order via Case.Order__c (fallback to Order.ParentCase__c)
            Id caseId;
            List<Case> caseList = [
                SELECT Id
                FROM Case
                WHERE Order__c = :orderId AND RecordType.DeveloperName = 'CBMCase'
                LIMIT 1
            ];
            if (!caseList.isEmpty()) {
                caseId = caseList[0].Id;
            } else if (ord != null && ord.ParentCase__c != null) {
                caseId = ord.ParentCase__c;
            }

            // Prefetch Case Team members for owner resolution
            List<CaseTeamMember> ctmForCase = new List<CaseTeamMember>();
            Set<Id> activeUserIds = new Set<Id>();
            if (caseId != null) {
                ctmForCase = [
                    SELECT Id, TeamRole.Name, MemberId, ParentId
                    FROM CaseTeamMember
                    WHERE ParentId = :caseId
                ];
                Set<Id> memberIds = new Set<Id>();
                for (CaseTeamMember ctm : ctmForCase) if (ctm.MemberId != null) memberIds.add(ctm.MemberId);
                if (!memberIds.isEmpty()) {
                    for (User u : [SELECT Id, IsActive FROM User WHERE Id IN :memberIds]) {
                        if (u.IsActive) activeUserIds.add(u.Id);
                    }
                }
            }

            // Prepare frequency-based de-duplication
            Set<String> onetimeSubjects = new Set<String>();
            Set<String> phasewiseSubjects = new Set<String>();
            Set<String> phasewiseIfCompletedSubjects = new Set<String>();
            for (TaskSLAConfig__mdt cfg : configs) {
                if (String.isNotBlank(cfg.TaskSubject__c)) {
                    if ('Onetime'.equalsIgnoreCase(cfg.Frequency__c)) {
                        onetimeSubjects.add(cfg.TaskSubject__c.trim());
                    }
                    // Frequency__c contains 'Phasewise'
                    if (!String.isBlank(cfg.Frequency__c) && cfg.Frequency__c.toLowerCase().contains('phasewise')) {
                        phasewiseSubjects.add(cfg.TaskSubject__c.trim());
                    }
                    // Frequency__c contains 'Phasewise If Completed'
                    if (!String.isBlank(cfg.Frequency__c) && cfg.Frequency__c.toLowerCase().contains('phasewise if completed')) {
                        phasewiseIfCompletedSubjects.add(cfg.TaskSubject__c.trim());
                    }
                }
            }

            // Query all non-Active holds for the order for the required reason codes
            List<OrderAndOrderLineHold__c> inactiveHolds = [
                SELECT Id, ReasonCode__c, IsProcessed__c
                FROM OrderAndOrderLineHold__c
                WHERE Order__c = :orderId
                  AND Active__c = false
                  AND IsProcessed__c = false
                  AND ReasonCode__c IN :holdReasonToTaskSubject.keySet()
            ];

            // List of processed Holds
            List<OrderAndOrderLineHold__c> holdsToUpdate = new List<OrderAndOrderLineHold__c>();
            // Create a set of inactive hold task subjects based on the map and query
            Set<String> inactiveHoldSubjects = new Set<String>();
            for (OrderAndOrderLineHold__c h : inactiveHolds) {
                h.IsProcessed__c = true;
                holdsToUpdate.add(h);
                String rc = h.ReasonCode__c;
                if (rc != null && holdReasonToTaskSubject.containsKey(rc)) {
                    inactiveHoldSubjects.add(holdReasonToTaskSubject.get(rc));
                }
            }

            // If any inactive hold subjects exist, collect matching open tasks for this order to complete
            List<Task> tasksToUpdate = new List<Task>();

            // Helper set for quick "already created in this run" de-dup (for Onetime)
            Set<String> existingKeys = new Set<String>();
            // Prefetch existing tasks for Onetime and Phasewise If Completed subjects (Subject + Case + Order)
            Map<String, List<Task>> existingTasksByKey = new Map<String, List<Task>>();
            Map<String, Integer> existingTasksByPhase = new Map<String, Integer>();
            if ((!onetimeSubjects.isEmpty() || !phasewiseSubjects.isEmpty() || !phasewiseIfCompletedSubjects.isEmpty()) && (caseId != null || orderId != null)) {
                Set<String> allSubjects = new Set<String>();
                allSubjects.addAll(onetimeSubjects);
                allSubjects.addAll(phasewiseSubjects);
                allSubjects.addAll(phasewiseIfCompletedSubjects);

                Map<String, List<Task>> tasksBySubjPhase = new Map<String, List<Task>>();

                List<Task> existing = [
                    SELECT Id, Subject, WhatId, Order__c, Status, IsClosed, Phase__c, OrderLine__c, OrderLine__r.Active__c 
                    FROM Task
                    WHERE IsDeleted = false
                      AND Subject IN :allSubjects
                      AND Order__c = :orderId ORDER BY Phase__c DESC
                ];
                for (Task t : existing) {
                    String subj = t.Subject;
                    Id cId = t.WhatId;
                    Id oId = (Id)t.get('Order__c');
                    Id olId = (Id)t.get('OrderLine__c');
                    
                    if (!existingTasksByPhase.containsKey(subj)) {
                        existingTasksByPhase.put(subj, (Integer)t.Phase__c);                        
                    } else {
                        Integer existPhas = existingTasksByPhase.get(subj);     
                        if (existPhas < t.Phase__c) {
                            existingTasksByPhase.put(subj, (Integer)t.Phase__c);
                        }                   
                    }

                    if (!String.isBlank(subj) && cId != null && oId != null) {
                        existingKeys.add(key(subj, cId, oId));
                    }
                    if (!String.isBlank(subj) && oId != null && olId != null) {
                        String k = key(subj, oId, olId);
                        if (!existingTasksByKey.containsKey(k)) {
                            existingTasksByKey.put(k, new List<Task>());
                        }
                        existingTasksByKey.get(k).add(t);
                    }

                    if(inactiveHoldSubjects.contains(subj)){
                        t.Status = 'Completed';
                        tasksToUpdate.add(t);
                    }
                    
                    if(phasewiseSubjects.contains(subj)){
                        String key = subj + t.Phase__c;
                        if (!tasksBySubjPhase.containsKey(key)) {
                            tasksBySubjPhase.put(key, new List<Task>());
                        }
                        tasksBySubjPhase.get(key).add(t);
                    }
                    
                }

                for(List<Task> phaseTaskList : tasksBySubjPhase.values()){
                    Boolean allLinesInactive = true;
                    for(Task phaseTask : phaseTaskList){
                        if(phaseTask.OrderLine__r.Active__c){
                            allLinesInactive = false;
                            break;
                        }
                    }
                    if(allLinesInactive){
                        for(Task phaseTask : phaseTaskList){
                            if(phaseTask.Status != 'Completed'){
                                phaseTask.Status = 'Completed';
                                if(!tasksToUpdate.contains(phaseTask)){
                                    tasksToUpdate.add(phaseTask);
                                }                                
                            }
                        }                        
                    }
                }
            }

            
            // Query OrderItem rows for this Order. Include fields referenced by your formulas as needed.
            List<OrderItem> lines = [
                SELECT Id, OrderId, OrderLineStatus__c, Active__c, ScheduledDate__c, CreateSubcase__c, IsScheduleDateCaplinesChanged__c, RequestDate__c, OrderLineType__c, ActualShipmentDate__c, Warehouse__c, Order.isActiveLCHold__c, Order.OrderClassification__c, Order.FinalShipmentDateNonPreinstall__c, 
                Product2Id, Quantity, Product2.SalesCategory__c, Product2.ItemType__c, Product2.PSAM__r.ProductFAMCode__c, TASSalesCategory__c, OrderLineTypeRollup__c, OrderLineHold__c, Hold__c, Order.isMigrated__c, Order.AllNonPreinstaLinsHavBlnkActualShipDate__c, Order.NoOfCapitalLines__c, 
                Order.Account.CustomerClassCode__c, Order.Status, Order.isActiveC1Hold__c, Order.isActiveC2Hold__c, Order.TurnsProject__c, Order.CreatedDate, Order.Guaranteed_Delivery__c, Order.Country__c, Order.NoOfIOAHolds__c, Order.NoOfENGHolds__c, Order.isActiveDFHold__c, Order.FirstScheduledDateNonPreinstall__c, Order.AllCapitalLinesClosed__c, Order.Type, Order.RegistrationNumber__c, Order.AllCapitalLinesClosedDate__c, 
                SubCase__r.Customer_Want_Date__c, SubCase__r.PreInstallItem__c, SubCase__r.Status, Order.OrderLevelHold__c, ShippableFlag__c, 
                Case__r.UrgentOrder__c, Case__r.GoNoGoSentDate__c, Case__r.OverAll_GO_NOGODecision__c, Case__r.IPMDecision__c, Case__r.Sales_Decision__c, Case__r.Status 
                FROM OrderItem
                WHERE OrderId = :orderId
            ];
            if (lines.isEmpty()) return;

            List<Task> toInsert = new List<Task>();

            // For each OrderItem, evaluate criteria/date formulas against the OrderItem record
            for (TaskSLAConfig__mdt cfg : configs) {
                Boolean isCaseIdAssigned = false; // will be marked true when first caseId is assigned
                //Integer existingPhase = 0;
                for (OrderItem oli : lines) {
                    if (!evaluateBoolean(cfg.TaskCreationCriteria__c, oli)) continue;

                    String freq = cfg.Frequency__c;
                    Boolean isOnetime = 'Onetime'.equalsIgnoreCase(freq);
                    Boolean isPhasewise = 'Phasewise'.equalsIgnoreCase(freq);
                    Boolean isPhasewiseIfCompleted = 'Phasewise If Completed'.equalsIgnoreCase(freq);

                    // De-duplication rules:
                    // - Onetime: if already created (existing or in this run) for (Subject+Case+Order), skip
                    // - Phasewise If Completed: only allow creation if there is NO existing open task with same (Subject+Case+Order);
                    //   if an existing task exists and is closed, allow a new one; if open, skip.
                    if (caseId != null && String.isNotBlank(cfg.TaskSubject__c)) {
                        String k = key(cfg.TaskSubject__c, orderId, oli.Id);

                        if (isOnetime) {
                            // Skip if created previously or in this run
                            if (existingKeys.contains(key(cfg.TaskSubject__c, caseId, orderId))) continue;
                        }

                        if (isPhasewise) {
                            // Check existing tasks: 
                            //Boolean hasExistingTask = false;
                            if (existingTasksByKey.containsKey(k)) {
                                continue;
                                /*for (Task et : existingTasksByKey.get(k)) {
                                    if (existingPhase < et.Phase__c) {
                                        existingPhase = (Integer)et.Phase__c;
                                        hasExistingTask = true;
                                        break;
                                    }
                                }*/
                            }
                            //if (hasExistingTask) continue;
                            // else proceed; allow new creation
                        }

                        if (isPhasewiseIfCompleted) {
                            // Check existing tasks: if any open task exists, skip; if only closed, allow new
                            Boolean hasOpen = false;
                            if (existingTasksByKey.containsKey(k)) {
                                for (Task et : existingTasksByKey.get(k)) {
                                    if (et.IsClosed == false) { hasOpen = true; break; }
                                }
                            }
                            if (hasOpen) continue;
                            // else proceed (no open task, or none exist); allow new creation
                        }
                    }

                    //Date dueDate = evaluateDueDate(cfg.DueDateCriteria__c, oli);

                    Id ownerId = resolveOwnerFromCaseTeam(caseId, cfg.AssignTo__c, ctmForCase, activeUserIds);
                    if (ownerId == null) ownerId = UserInfo.getUserId();

                    /* Post-identification transfer check based on config (IsTransferRequired__c, TransferCriteria__c, SLACriteria__c)
                    Id transferOwnerId = transferOwner(cfg, caseId, ownerId, oli, ctmForCase, activeUserIds);
                    if(transferOwnerId != null) {
                        ownerId = transferOwnerId;
                    }*/
                    
                    String priorityText = 'No';
                    if(ord.ParentCase__r.UrgentOrder__c) {
                        priorityText = 'Yes';
                    }
                    Task t = new Task();
                    t.Subject      = cfg.TaskSubject__c;
                    t.OwnerId      = ownerId;
                    t.Status       = 'Open';
                    t.Priority     = priorityText;
                    t.TaskTeam__c  = cfg.AssignTo__c;
                    t.OrderLine__c = oli.Id;
                    t.RecordTypeId = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
                    if(!isCaseIdAssigned && caseId != null) {
                        t.WhatId = caseId;
                        //t.ActivityDate = dueDate;
                        isCaseIdAssigned = true;
                    }
                    if (isPhasewise) {
                        Integer phase = existingTasksByPhase.get(cfg.TaskSubject__c);
                        if (phase != null) {
                            t.put('Phase__c', phase+1);
                        }else {
                            t.put('Phase__c', 1);
                        }
                    }
                    t.put('Order__c', orderId);




                    /*Phase wise task creation
                    if((cfg.Frequency__c != null && cfg.Frequency__c.contains('Phase')) {
                        if(phase != null) {
                            map.put(phase,tasks);//all tasks for similar name
                            phase = 1;
                        }
                    }*/





                    t.CurrencyIsoCode = ord.CurrencyIsoCode;
                    toInsert.add(t);

                    if (caseId != null && String.isNotBlank(cfg.TaskSubject__c)) {
                        String k = key(cfg.TaskSubject__c, orderId, oli.Id);
                        if (isOnetime) {
                            // mark as created in this run
                            existingKeys.add(key(cfg.TaskSubject__c, caseId, orderId));
                        }
                        if (isPhasewise) {
                            // reflect new creation so subsequent configs in same run see it as "open" until inserted
                            if (!existingTasksByKey.containsKey(k)) existingTasksByKey.put(k, new List<Task>());
                            // We won't know IsClosed until insert; treat as open by default for intra-run checks
                            // (no need to add the in-memory Task instance)
                        }
                        if (isPhasewiseIfCompleted) {
                            // reflect new creation so subsequent configs in same run see it as "open" until inserted
                            if (!existingTasksByKey.containsKey(k)) existingTasksByKey.put(k, new List<Task>());
                            // We won't know IsClosed until insert; treat as open by default for intra-run checks
                            // (no need to add the in-memory Task instance)
                        }
                    }
                }
            }

            if (!toInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(toInsert, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Task insert error: ' + e.getMessage());
                        }
                    }
                }
            }

            // Persist completion of matched tasks in a single DML
            if (!tasksToUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(tasksToUpdate, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Task update error: ' + e.getMessage());
                        }
                    }
                }
            }

            // Persist completion of processed holds in a single DML
            if (!holdsToUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(holdsToUpdate, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Hold update error: ' + e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'createTasksForOrderLine', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }
    

    

    /**
     * @description Creates Hold Tasks based on TaskSLAConfig records where Object__c = 'OrderAndOrderLineHold__c'.
     * @param orderNumber The Order Number of the order to create Hold tasks for
     * @return void
     */
    public static void createTasksForOrderAndOrderLineHold(String orderNumber) {
        try {
            if (orderNumber == null) return;

            // Load Order for case fallback and urgency
            List<Order> ordList = [
                SELECT Id, ParentCase__c, ParentCase__r.UrgentOrder__c, CurrencyIsoCode 
                FROM Order
                WHERE OrderNumber__c = :orderNumber
                LIMIT 1
            ];
            if (ordList.isEmpty()) return;

            Order ord = ordList[0];
            Id orderId = ord.Id;

            // Load active task configs for Hold
            List<TaskSLAConfig__mdt> configs = [
                SELECT AssignTo__c, DueDateCriteria__c, Frequency__c, IsActive__c,
                       Object__c, TaskCreationCriteria__c, TaskSubject__c, DeveloperName
                FROM TaskSLAConfig__mdt
                WHERE IsActive__c = true AND Object__c = 'OrderAndOrderLineHold__c'
            ];
            if (configs.isEmpty()) return;

            // Resolve Case: prefer Case.Order__c; fallback to Order.ParentCase__c
            Id caseId;
            List<Case> caseList = [
                SELECT Id
                FROM Case
                WHERE Order__c = :orderId AND RecordType.DeveloperName = 'CBMCase'
                LIMIT 1
            ];
            if (!caseList.isEmpty()) {
                caseId = caseList[0].Id;
            } else if (ord.ParentCase__c != null) {
                caseId = ord.ParentCase__c;
            }

            // Prefetch Case Team + Active Users
            List<CaseTeamMember> ctmForCase = new List<CaseTeamMember>();
            Set<Id> activeUserIds = new Set<Id>();
            if (caseId != null) {
                ctmForCase = [
                    SELECT Id, TeamRole.Name, MemberId, ParentId
                    FROM CaseTeamMember
                    WHERE ParentId = :caseId
                ];
                Set<Id> memberIds = new Set<Id>();
                for (CaseTeamMember ctm : ctmForCase) if (ctm.MemberId != null) memberIds.add(ctm.MemberId);
                if (!memberIds.isEmpty()) {
                    for (User u : [SELECT Id, IsActive FROM User WHERE Id IN :memberIds]) {
                        if (u.IsActive) activeUserIds.add(u.Id);
                    }
                }
            }

            // Frequency buckets for dedupe
            Set<String> onetimeSubjects = new Set<String>();
            for (TaskSLAConfig__mdt cfg : configs) {
                if (String.isNotBlank(cfg.TaskSubject__c)) {
                    String subj = cfg.TaskSubject__c.trim();
                    if ('Onetime'.equalsIgnoreCase(cfg.Frequency__c)) {
                        onetimeSubjects.add(subj);
                    }
                }
            }

            // Prefetch existing tasks for dedupe
            Set<String> existingKeys = new Set<String>(); // subject|case|order (Onetime)
            Map<String, List<Task>> existingTasksByKey = new Map<String, List<Task>>(); // subject|case|hold (phasewise)

            if (!onetimeSubjects.isEmpty() && caseId != null) {
                Set<String> allSubjects = new Set<String>();
                allSubjects.addAll(onetimeSubjects);

                List<Task> existing = [
                    SELECT Id, Subject, WhatId, Order__c, Status, IsClosed, Phase__c, OrderAndOrderLineHold__c
                    FROM Task
                    WHERE WhatId = :caseId
                      AND Subject IN :allSubjects
                      AND IsClosed = false
                      AND IsDeleted = false
                    ORDER BY Phase__c DESC
                ];
                for (Task t : existing) {
                    String subj = t.Subject;
                    Id cId = t.WhatId;
                    Id oId = (Id)t.get('Order__c');
                    Id holdId = (Id)t.get('OrderAndOrderLineHold__c');

                    if (!String.isBlank(subj) && cId != null && oId != null) {
                        existingKeys.add(key(subj, cId, oId));
                    }
                    if (!String.isBlank(subj) && cId != null && holdId != null) {
                        String k = key(subj, cId, holdId);
                        if (!existingTasksByKey.containsKey(k)) {
                            existingTasksByKey.put(k, new List<Task>());
                        }
                        existingTasksByKey.get(k).add(t);
                    }
                }
            }

            // Query Holds; include specified fields and needed referenced Order fields
            List<OrderAndOrderLineHold__c> holds = [
                SELECT Id,
                       Order__c,
                       ReasonCode__c,
                       Active__c,
                       CreatedDate, ReasonResolvedDate__c, HoldReleasedDate__c, 
                       Order__r.FirstScheduledDateNonPreinstall__c, Order__r.Type, 
                       Order__r.Country__c, Order__r.isActiveC1Hold__c, 
                       Order__r.CreatedDate, Order__r.RegistrationNumber__c 
                FROM OrderAndOrderLineHold__c
                WHERE Order__c = :orderId
            ];
            if (holds.isEmpty()) return;

            // Behavior: complete tasks for inactive holds; dedupe active hold tasks by Case+Subject+Hold (open prevents new)
            List<Task> toInsert = new List<Task>();
            List<Task> toUpdate = new List<Task>();

            // Build maps for quick lookup by Hold Id
            Map<Id, List<Task>> openTasksByHoldId = new Map<Id, List<Task>>();
            for (List<Task> bucket : existingTasksByKey.values()) {
                for (Task tExisting : bucket) {
                    Id hId = (Id)tExisting.get('OrderAndOrderLineHold__c');
                    if (hId == null) continue;
                    if (!openTasksByHoldId.containsKey(hId)) openTasksByHoldId.put(hId, new List<Task>());
                    openTasksByHoldId.get(hId).add(tExisting);
                }
            }

            for (TaskSLAConfig__mdt cfg : configs) {

                // For each hold, either close existing (if inactive) or create new (if active)
                for (OrderAndOrderLineHold__c hold : holds) {
                    // Close tasks for this hold when inactive (set to Completed if not already)
                    if (hold.Active__c == false) {
                        List<Task> tasksForHold = openTasksByHoldId.get(hold.Id);
                        if (tasksForHold != null && !tasksForHold.isEmpty()) {
                            for (Task tUpd : tasksForHold) {
                                if (tUpd.Status != 'Completed') {
                                    tUpd.Status = 'Completed';
                                    toUpdate.add(tUpd);
                                }
                            }
                        }
                        // No creation when inactive; continue to next hold
                        continue;
                    }

                    // Active hold: create a Task only if there is no existing OPEN Task for same Case+Subject+Hold
                    if (!evaluateBoolean(cfg.TaskCreationCriteria__c, hold)) continue;

                    String freq = cfg.Frequency__c;
                    Boolean isOnetime = 'Onetime'.equalsIgnoreCase(freq);

                    if (caseId != null && String.isNotBlank(cfg.TaskSubject__c)) {
                        if (isOnetime) {
                            // Skip if created previously or in this run
                            if (existingKeys.contains(key(cfg.TaskSubject__c, caseId, orderId))) break;
                        }
                    }

                    // Due date from Hold formula
                    //Date dueDate = evaluateDueDate(cfg.DueDateCriteria__c, hold);

                    // Owner via Case Team
                    Id ownerId = resolveOwnerFromCaseTeam(caseId, cfg.AssignTo__c, ctmForCase, activeUserIds);
                    if (ownerId == null) ownerId = UserInfo.getUserId();

                    // Priority from Urgent flag
                    String priorityText = 'No';
                    if (ord.ParentCase__r.UrgentOrder__c) {
                        priorityText = 'Yes';
                    }

                    Task t = new Task();
                    t.Subject      = cfg.TaskSubject__c;
                    t.OwnerId      = ownerId;
                    t.Status       = 'Open';
                    t.Priority     = priorityText;
                    t.TaskTeam__c  = cfg.AssignTo__c;
                    t.RecordTypeId = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
                    t.WhatId = caseId;
                    //t.ActivityDate = dueDate;
                    t.put('Order__c', orderId);
                    t.put('OrderAndOrderLineHold__c', hold.Id);

                    t.CurrencyIsoCode = ord.CurrencyIsoCode;
                    toInsert.add(t);
                    existingKeys.add(key(cfg.TaskSubject__c, caseId, orderId));
                }
            }

            // Perform DML
            if (!toUpdate.isEmpty()) {
                Database.update(toUpdate, false);
            }
            if (!toInsert.isEmpty()) {
                Database.SaveResult[] results = Database.insert(toInsert, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Hold Task insert error: ' + e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            ErrorLogger.logException(e, 'CreateTaskHelper', 'createTasksForOrderAndOrderLineHold', ErrorLogger.Level.ERROR, null, null);
            throw e;
        }
    }

    
    /**
     * @description Calculates SLA for Tasks related to the given Order Numbers using TaskSLAConfig metadata.
     * @param orderNumbers List of order numbers to process
     * @return void
     */
    public static void calculateTaskSLAs(
        List<String> orderNumbers
    ) {
        try {            
            List<TaskSLAConfig__mdt> configs = [
                SELECT Id, AssignTo__c, DueDateCriteria__c, Frequency__c, IsActive__c,
                       Object__c, TaskCreationCriteria__c, TaskSubject__c, DeveloperName,
                       SLACriteria__c, CalculateSLADaily__c
                FROM TaskSLAConfig__mdt
                WHERE IsActive__c = true
            ];
            if (orderNumbers == null || orderNumbers.isEmpty()) return;
            if (configs == null || configs.isEmpty()) return;
        
            // Normalize & de-duplicate incoming order numbers
            Set<String> ordNums = new Set<String>();
            for (String n : orderNumbers) {
                if (String.isNotBlank(n)) ordNums.add(n.trim());
            }
            if (ordNums.isEmpty()) return;
        
            // Query Orders by OrderNumber__c → collect Order Ids
            List<Order> orders = [
                SELECT Id, OrderNumber__c
                FROM Order
                WHERE OrderNumber__c IN :ordNums
            ];
            if (orders.isEmpty()) return;
        
            Set<Id> orderIds = new Set<Id>();
            for (Order o : orders) orderIds.add(o.Id);
        
            // Build a subject → config map (trim+lower for robust matching)
            Map<String, TaskSLAConfig__mdt> subjToCfg = new Map<String, TaskSLAConfig__mdt>();
            Set<String> cfgSubjects = new Set<String>(); // optional filter to reduce Task rows
            for (TaskSLAConfig__mdt cfg : configs) {
                if (String.isNotBlank(cfg.TaskSubject__c)) {
                    String key = cfg.TaskSubject__c.trim().toLowerCase();
                    subjToCfg.put(key, cfg);
                    cfgSubjects.add(cfg.TaskSubject__c.trim());
                }
            }
        
            // Query Tasks for these Orders (Task context for SLA evaluation).
            // Optional WHERE Subject IN :cfgSubjects to reduce rows if subjects are stable.
            List<Task> tasks = [
                SELECT Id, Subject, Priority, Status, CreatedDate, FirstScheduledDate__c, FirstNonPreinstallScheduledDate__c, ReminderDateTime, 
                       ActivityDate, OwnerId, WhatId, Order__c, RiskLevel__c, Phase__c, 
                       Order__r.NoOfCapitalLines__c, OrderLine__r.ScheduledDate__c, OrderLine__r.PreviousScheduleDate__c, OrderLine__r.Subcase__r.Customer_Want_Date__c, OrderLine__r.Subcase__r.PreInstallItem__c, OrderLine__r.ActualShipmentDate__c, OrderLine__r.Quantity, 
                       Order__r.FinalShipmentDateNonPreinstall__c, Order__r.CreatedDate, Order__r.ParentCase__r.GoNoGoSentDate__c, Order__r.FirstScheduledDateNonPreinstall__c, Order__r.AllCapitalLinesClosedDate__c, Order__r.AllReprocessingScheduledDate__c
                FROM Task
                WHERE IsDeleted = false
                  AND Order__c IN :orderIds
                  AND Status = 'Open'
                  AND Subject IN :cfgSubjects
            ];
            if (tasks.isEmpty()) return;

            Map<String,Date> keyOrdSubPhsByMinSchdDate = new Map<String,Date>();
            Map<String,Date> keyOrdSubPhsByMinSchdDateNonPre = new Map<String,Date>();
            for (Task t : tasks) {
                String key = t.Order__c+t.Subject+t.Phase__c;
                Date scheDate = keyOrdSubPhsByMinSchdDate.get(key);
                Date scheDateNonpre = keyOrdSubPhsByMinSchdDateNonPre.get(key);
                if(scheDate == null || t.OrderLine__r.ScheduledDate__c < scheDate){
                    keyOrdSubPhsByMinSchdDate.put(key, t.OrderLine__r.ScheduledDate__c);
                }
                if(t.OrderLine__r.Subcase__r.PreInstallItem__c == false && (scheDateNonpre == null || t.OrderLine__r.ScheduledDate__c < scheDateNonpre)){
                    keyOrdSubPhsByMinSchdDateNonPre.put(key, t.OrderLine__r.ScheduledDate__c);
                }
            }
            List<Task> toUpdate = new List<Task>();
        
            for (Task t : tasks) {
                if(t.WhatId == null) continue;
                String keyOrdSubPhs = t.Order__c+t.Subject+t.Phase__c;
                Date scheDate = keyOrdSubPhsByMinSchdDate.get(keyOrdSubPhs);
                Date scheDateNonPre = keyOrdSubPhsByMinSchdDateNonPre.get(keyOrdSubPhs);
                String subjKey = (t.Subject == null) ? '' : t.Subject.trim().toLowerCase();
                TaskSLAConfig__mdt cfg = subjToCfg.get(subjKey);
                if (cfg == null || String.isBlank(cfg.SLACriteria__c)) continue;
        
                // If you want to recompute only for configs marked daily:
                if (!cfg.CalculateSLADaily__c && t.RiskLevel__c!=null) continue;

                if (scheDate != null && scheDate != (Date)t.get('FirstScheduledDate__c')) {
                    t.put('FirstScheduledDate__c', scheDate);
                }
                if (scheDateNonPre != null && scheDateNonPre != (Date)t.get('FirstNonPreinstallScheduledDate__c')) {
                    t.put('FirstNonPreinstallScheduledDate__c', scheDateNonPre);
                }
        
                // Evaluate SLA on Task (STRING return type)
                String slaText = evaluateText(cfg.SLACriteria__c, t); // "Red"/"Yellow"/"Green"/"No SLA"
                String newRisk = mapPriorityFromSla(slaText);               // Using your mapping (High/Normal/Low)
        
                Boolean changed = false;
        
                if (newRisk != null && newRisk != (String)t.get('RiskLevel__c') && (t.ReminderDateTime == null || t.ReminderDateTime < System.now())) {
                    t.put('RiskLevel__c', newRisk);
                    changed = true;
                }

                //CBM-656 Re-Evaluate Due Date with task data
                Date newDueDate = evaluateDueDate(cfg.DueDateCriteria__c, t);
                Date activityDate = (Date) t.ActivityDate;
                if(newDueDate == null && activityDate == null) {
                    t.put('ActivityDate', t.Order__r.CreatedDate.Date().addDays(5));
                    changed = true;
                } else if ((changed || activityDate == null) && newDueDate != null && newDueDate < System.Now().Date()) {
                    t.put('ActivityDate', System.Now().Date());
                    changed = true;
                } else if (newDueDate != null && newDueDate != activityDate && newDueDate >= System.Now().Date()) {
                    t.put('ActivityDate', newDueDate);
                    changed = true;
                }
        
                if (changed) toUpdate.add(t);
            }
        
            if (!toUpdate.isEmpty()) {
                Database.SaveResult[] results = Database.update(toUpdate, false);
                for (Database.SaveResult r : results) {
                    if (!r.isSuccess()) {
                        for (Database.Error e : r.getErrors()) {
                            System.debug(LoggingLevel.ERROR, 'Task SLA update error: ' + e.getMessage());
                        }
                    }
                }
            }
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateTaskHelper', 'calculateTaskSLAForOrderNumbers', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }
    
    /**
     * @description Creates and manages tasks for Order holds with advanced parent/child task logic.
     *              Handles header-level and line-level holds, parent task promotion, and task completion rules.
     * @param orderNumber The Order Number to process holds for
     * @return void
     */
    public static void createTasksForPhasewiseHolds(String orderNumber) {
        try {
            if (String.isBlank(orderNumber)) return;

            // 1) Fetch TaskSLAConfig for PhasewiseHolds
            List<TaskSLAConfig__mdt> configs = [
                SELECT AssignTo__c, DueDateCriteria__c, Frequency__c, IsActive__c,
                       Object__c, TaskCreationCriteria__c, TaskSubject__c, DeveloperName,
                       SLACriteria__c, TaskPriorityOrder__c
                FROM TaskSLAConfig__mdt
                WHERE IsActive__c = true 
                  AND Object__c = 'PhasewiseHolds'
                ORDER BY TaskPriorityOrder__c NULLS LAST
            ];
            if (configs.isEmpty()) return;

            // 2) Fetch Order
            List<Order> ordList = [
                SELECT Id, ParentCase__c, ParentCase__r.UrgentOrder__c, OrderNumber__c
                FROM Order
                WHERE OrderNumber__c = :orderNumber
                LIMIT 1
            ];
            if (ordList.isEmpty()) return;
            Order ord = ordList[0];
            Id orderId = ord.Id;

            // 3) Fetch CBM Case
            Id caseId;
            List<Case> caseList = [
                SELECT Id
                FROM Case
                WHERE Order__c = :orderId AND RecordType.DeveloperName = 'CBMCase'
                LIMIT 1
            ];
            if (!caseList.isEmpty()) {
                caseId = caseList[0].Id;
            } else if (ord.ParentCase__c != null) {
                caseId = ord.ParentCase__c;
            }
            if (caseId == null) return;

            // 4) Fetch Case Team Members
            List<CaseTeamMember> ctmForCase = [
                SELECT Id, TeamRole.Name, MemberId, ParentId
                FROM CaseTeamMember
                WHERE ParentId = :caseId
            ];
            Set<Id> memberIds = new Set<Id>();
            for (CaseTeamMember ctm : ctmForCase) {
                if (ctm.MemberId != null) memberIds.add(ctm.MemberId);
            }
            Set<Id> activeUserIds = new Set<Id>();
            if (!memberIds.isEmpty()) {
                for (User u : [SELECT Id, IsActive FROM User WHERE Id IN :memberIds]) {
                    if (u.IsActive) activeUserIds.add(u.Id);
                }
            }

            // 5) Get existing open tasks
            List<Task> existingTasks = [
                SELECT Id, Subject, Order__c, OrderLine__c, WhatId, Phase__c, Status, IsClosed,
                       OrderAndOrderLineHold__c
                FROM Task
                WHERE Order__c = :orderId
                  AND IsClosed = false
                  AND IsDeleted = false
            ];

            // Build maps: composite key = subject + order + orderLineId
            Map<String, Task> existingTaskMap = new Map<String, Task>();
            Map<String, List<Task>> parentTasksBySubject = new Map<String, List<Task>>();
            Map<String, List<Task>> childTasksBySubject = new Map<String, List<Task>>();

            for (Task t : existingTasks) {
                String subj = (t.Subject != null) ? t.Subject.trim() : '';
                String compositeKey = subj + '|' + orderId + '|' + t.OrderLine__c;
                existingTaskMap.put(compositeKey, t);

                // Parent tasks: have WhatId = Case
                if (t.WhatId == caseId) {
                    if (!parentTasksBySubject.containsKey(subj)) {
                        parentTasksBySubject.put(subj, new List<Task>());
                    }
                    parentTasksBySubject.get(subj).add(t);
                } else {
                    // Child tasks: no Case association
                    if (!childTasksBySubject.containsKey(subj)) {
                        childTasksBySubject.put(subj, new List<Task>());
                    }
                    childTasksBySubject.get(subj).add(t);
                }
            }

            // 6) Fetch holds
            List<OrderAndOrderLineHold__c> allHolds = [
                SELECT Id, Order__c, OrderLine__c, ReasonCode__c, Active__c,
                       CreatedDate, ReasonResolvedDate__c, HoldReleasedDate__c
                FROM OrderAndOrderLineHold__c
                WHERE Order__c = :orderId
            ];

            // Separate ACTIVE header and line holds
            Map<String, OrderAndOrderLineHold__c> activeHeaderHolds = new Map<String, OrderAndOrderLineHold__c>();
            Map<String, List<OrderAndOrderLineHold__c>> lineHolds = new Map<String, List<OrderAndOrderLineHold__c>>();

            for (OrderAndOrderLineHold__c hold : allHolds) {
                String holdCode = hold.ReasonCode__c;
                if (hold.OrderLine__c == null) {
                    // Header hold - only track if ACTIVE
                    if (hold.Active__c) {
                        activeHeaderHolds.put(holdCode, hold);
                    }
                } else {
                    // Line hold (all line holds, both active and inactive)
                    if (!lineHolds.containsKey(holdCode)) {
                        lineHolds.put(holdCode, new List<OrderAndOrderLineHold__c>());
                    }
                    lineHolds.get(holdCode).add(hold);
                }
            }

            // 7) Fetch Order Lines
            List<OrderItem> orderLines = [
                SELECT Id, OrderId, OrderLineStatus__c, Active__c, ScheduledDate__c, CreateSubcase__c, IsScheduleDateCaplinesChanged__c, RequestDate__c, OrderLineType__c, ActualShipmentDate__c, Warehouse__c, Order.isActiveLCHold__c, 
                Product2Id, Quantity, Product2.SalesCategory__c, Product2.ItemType__c, TASSalesCategory__c, OrderLineTypeRollup__c, OrderLineHold__c, Hold__c, Order.isMigrated__c,
                Order.Account.CustomerClassCode__c, Order.Status, Order.isActiveC1Hold__c, Order.isActiveC2Hold__c, Order.TurnsProject__c, Order.CreatedDate, Order.Guaranteed_Delivery__c, Order.Country__c, Order.NoOfIOAHolds__c, Order.NoOfENGHolds__c, Order.isActiveDFHold__c, Order.FirstScheduledDateNonPreinstall__c, Order.AllCapitalLinesClosed__c, Order.Type, Order.RegistrationNumber__c, Order.AllCapitalLinesClosedDate__c, 
                SubCase__r.Customer_Want_Date__c, SubCase__r.PreInstallItem__c, SubCase__r.Status, Order.OrderLevelHold__c, 
                Case__r.UrgentOrder__c, Case__r.GoNoGoSentDate__c, Case__r.OverAll_GO_NOGODecision__c, Case__r.IPMDecision__c, Case__r.Sales_Decision__c, Case__r.Status 
                FROM OrderItem
                WHERE OrderId = :orderId
            ];

            Map<Id, OrderItem> orderLineMap = new Map<Id, OrderItem>(orderLines);

            // 8) Core generation loop
            List<Task> toInsert = new List<Task>();
            List<Task> toUpdate = new List<Task>();
            List<Task> toDelete = new List<Task>();

            for (TaskSLAConfig__mdt cfg : configs) {
                String subject = cfg.TaskSubject__c;
                if (String.isBlank(subject)) continue;

                // Determine applicable ACTIVE holds for this config
                Set<Id> applicableHoldIds = new Set<Id>();
                Map<Id, Set<Id>> holdToOrderLines = new Map<Id, Set<Id>>();
                Map<String, Id> headerHoldByCode = new Map<String, Id>(); // Track header hold IDs by code

                for (OrderAndOrderLineHold__c hold : allHolds) {
                    // CRITICAL FIX: Only process ACTIVE holds
                    if (!hold.Active__c) continue;
                    
                    String holdCode = hold.ReasonCode__c;
                    Boolean isHeaderHold = (hold.OrderLine__c == null);

                    // If ACTIVE header hold exists for this code, it overrides line holds
                    if (isHeaderHold) {
                        // Header overrides line holds for this holdCode
                        // Header hold applies to all order lines that pass criteria
                        applicableHoldIds.add(hold.Id);
                        Set<Id> allLineIds = new Set<Id>();
                        for (OrderItem oli : orderLines) allLineIds.add(oli.Id);
                        holdToOrderLines.put(hold.Id, allLineIds);
                        headerHoldByCode.put(holdCode, hold.Id); // Track for parent task assignment
                    } else if (!activeHeaderHolds.containsKey(holdCode)) {
                        // Line hold ONLY if NO ACTIVE header hold exists for same holdCode
                        // CRITICAL: Task created ONLY for the specific order line that has the hold
                        applicableHoldIds.add(hold.Id);
                        Set<Id> lineSet = new Set<Id>{hold.OrderLine__c};
                        holdToOrderLines.put(hold.Id, lineSet);
                    }
                }

                // Create tasks for each applicable hold + order line combination
                for (Id holdId : applicableHoldIds) {
                    Set<Id> lineIds = holdToOrderLines.get(holdId);
                    if (lineIds == null) continue;

                    for (Id lineId : lineIds) {
                        OrderItem oli = orderLineMap.get(lineId);
                        if (oli == null) continue;

                        // Check task creation criteria on order line
                        if (!evaluateBoolean(cfg.TaskCreationCriteria__c, oli)) continue;

                        String compositeKey = subject + '|' + orderId + '|' + lineId;
                        Task existingTask = existingTaskMap.get(compositeKey);

                        if (existingTask == null) {
                            // No existing task - create new
                            List<Task> parentTasks = parentTasksBySubject.get(subject);
                            Boolean parentExists = (parentTasks != null && !parentTasks.isEmpty());

                            Id ownerId = resolveOwnerFromCaseTeam(caseId, cfg.AssignTo__c, ctmForCase, activeUserIds);
                            if (ownerId == null) ownerId = UserInfo.getUserId();

                            String priorityText = 'No';
                            if (ord.ParentCase__r.UrgentOrder__c) priorityText = 'Yes';

                            // Determine the correct hold ID to use
                            Id taskHoldId = holdId;
                            
                            // CRITICAL: If this will be a parent task and a header hold exists, use header hold ID
                            if (!parentExists) {
                                // This will become the parent task
                                // Check if there's a header hold for this hold's reason code
                                OrderAndOrderLineHold__c currentHold = null;
                                for (OrderAndOrderLineHold__c h : allHolds) {
                                    if (h.Id == holdId) {
                                        currentHold = h;
                                        break;
                                    }
                                }
                                
                                if (currentHold != null && currentHold.OrderLine__c != null) {
                                    // This is a line hold - check if header hold exists
                                    if (headerHoldByCode.containsKey(currentHold.ReasonCode__c)) {
                                        // Use header hold ID for parent task
                                        taskHoldId = headerHoldByCode.get(currentHold.ReasonCode__c);
                                    }
                                }
                            }

                            Task newTask = new Task();
                            newTask.Subject = subject;
                            newTask.OwnerId = ownerId;
                            newTask.Status = 'Open';
                            newTask.Priority = priorityText;
                            newTask.TaskTeam__c = cfg.AssignTo__c;
                            newTask.RecordTypeId = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('CBM_Task').getRecordTypeId();
                            newTask.put('Order__c', orderId);
                            newTask.put('OrderLine__c', lineId);
                            newTask.put('OrderAndOrderLineHold__c', taskHoldId);

                            if (parentExists) {
                                // Create as child task (no Case association)
                                // Match parent's phase
                                Integer parentPhase = (Integer)parentTasks[0].Phase__c;
                                newTask.put('Phase__c', parentPhase);
                            } else {
                                // Create as parent task
                                newTask.WhatId = caseId;
                                newTask.put('Phase__c', 1);
                                
                                // Track as new parent
                                if (!parentTasksBySubject.containsKey(subject)) {
                                    parentTasksBySubject.put(subject, new List<Task>());
                                }
                                parentTasksBySubject.get(subject).add(newTask);
                            }

                            toInsert.add(newTask);
                            existingTaskMap.put(compositeKey, newTask);
                        }
                    }
                }

                // 9) Task removal/completion rules
                // Check existing tasks for this subject
                List<Task> allTasksForSubject = new List<Task>();
                if (parentTasksBySubject.containsKey(subject)) {
                    allTasksForSubject.addAll(parentTasksBySubject.get(subject));
                }
                if (childTasksBySubject.containsKey(subject)) {
                    allTasksForSubject.addAll(childTasksBySubject.get(subject));
                }

                // Check if all order lines are inactive
                Boolean allLinesInactive = true;
                for (Task task : allTasksForSubject) {
                    if (task.OrderLine__c == null) continue;
                    
                    OrderItem oli = orderLineMap.get((Id)task.OrderLine__c);
                    if (oli == null) continue;

                    if (oli.Active__c == true) {
                        allLinesInactive = false;
                        break;
                    }
                }

                if (allLinesInactive) {
                    for (Task task : allTasksForSubject) {
                        if (task.Status != 'Completed' && !toDelete.contains(task)) {
                            task.Status = 'Completed';
                            if (!toUpdate.contains(task)) toUpdate.add(task);
                        }
                    }
                }

                if (!allLinesInactive) {
                    for (Task task : allTasksForSubject) {
                        if (task.OrderLine__c == null) continue;
                        
                        OrderItem oli = orderLineMap.get((Id)task.OrderLine__c);
                        if (oli == null) continue;

                        Boolean isApplicable = evaluateBoolean(cfg.TaskCreationCriteria__c, oli);
                        Boolean isChildTask = (task.WhatId != caseId);
                        Boolean isParentTask = (task.WhatId == caseId);

                        if (!isApplicable) {
                            if (isChildTask) {
                                // Delete child task
                                toDelete.add(task);
                            } else if (isParentTask) {
                                // Find next eligible child to promote
                                List<Task> children = childTasksBySubject.get(subject);
                                Task eligibleChild = null;
                                
                                if (children != null) {
                                    for (Task child : children) {
                                        if (toDelete.contains(child)) continue;
                                        OrderItem childOli = orderLineMap.get((Id)child.OrderLine__c);
                                        if (childOli != null && evaluateBoolean(cfg.TaskCreationCriteria__c, childOli)) {
                                            eligibleChild = child;
                                            break;
                                        }
                                    }
                                }

                                if (eligibleChild != null) {
                                    // Replace parent's order line with child's
                                    task.put('OrderLine__c', eligibleChild.OrderLine__c);
                                    task.put('OrderAndOrderLineHold__c', eligibleChild.OrderAndOrderLineHold__c);
                                    toUpdate.add(task);
                                    toDelete.add(eligibleChild);
                                } else {
                                    // No eligible children - mark parent completed
                                    task.Status = 'Completed';
                                    toUpdate.add(task);
                                }
                            }
                        }
                    }

                    // Check hold status for task completion
                    for (Task task : allTasksForSubject) {
                        if (task.Status == 'Completed') continue;
                        if (toDelete.contains(task)) continue;

                        Id holdId = (Id)task.get('OrderAndOrderLineHold__c');
                        if (holdId == null) continue;

                        OrderAndOrderLineHold__c hold = null;
                        for (OrderAndOrderLineHold__c h : allHolds) {
                            if (h.Id == holdId) {
                                hold = h;
                                break;
                            }
                        }

                        if (hold != null && !hold.Active__c) {
                            Boolean isParentTask = (task.WhatId == caseId);
                            Boolean isHeaderHold = (hold.OrderLine__c == null);
                            
                            // NEW LOGIC: Header hold became inactive - check for active line-level holds
                            if (isHeaderHold) {
                                // Header hold is now inactive - need to check each task
                                Id taskOrderLineId = (Id)task.get('OrderLine__c');
                                
                                // Check if this order line has an active line-level hold
                                Boolean hasActiveLineHold = false;
                                if (taskOrderLineId != null) {
                                    String holdCode = hold.ReasonCode__c;
                                    if (lineHolds.containsKey(holdCode)) {
                                        for (OrderAndOrderLineHold__c lineHold : lineHolds.get(holdCode)) {
                                            if (lineHold.OrderLine__c == taskOrderLineId && lineHold.Active__c) {
                                                hasActiveLineHold = true;
                                                break;
                                            }
                                        }
                                    }
                                }
                                
                                if (!hasActiveLineHold) {
                                    // No active line-level hold for this order line - complete the task
                                    task.Status = 'Completed';
                                    if (!toUpdate.contains(task)) toUpdate.add(task);
                                }
                                // If hasActiveLineHold = true, keep task open (do nothing)
                            } else if (isParentTask && !isHeaderHold) {
                                // Line hold became inactive on parent task
                                List<Task> children = childTasksBySubject.get(subject);
                                Task eligibleChild = null;
                                
                                if (children != null) {
                                    for (Task child : children) {
                                        if (toDelete.contains(child)) continue;
                                        if (child.Status == 'Completed') continue;
                                        OrderItem childOli = orderLineMap.get((Id)child.OrderLine__c);
                                        if (childOli != null && evaluateBoolean(cfg.TaskCreationCriteria__c, childOli)) {
                                            eligibleChild = child;
                                            break;
                                        }
                                    }
                                }

                                if (eligibleChild != null) {
                                    // Replace parent's order line with child's
                                    task.put('WhatId', null);
                                    eligibleChild.put('WhatId', caseId);
                                    toUpdate.add(eligibleChild);
                                }
                                // Hold is inactive - complete task
                                task.Status = 'Completed';
                                if (!toUpdate.contains(task)) toUpdate.add(task);
                            } else {
                                // Regular case: hold is inactive - complete task
                                task.Status = 'Completed';
                                if (!toUpdate.contains(task)) toUpdate.add(task);
                            }
                        }
                    }
                }
            }

            // 10) Perform DML
            if (!toDelete.isEmpty()) {
                Database.delete(toDelete, false);
            }
            if (!toUpdate.isEmpty()) {
                Map<Id, Task> filterMap = new Map<Id, Task>();
                for (Task mapTask : toUpdate) {
                    if (mapTask.Id != null) {
                        filterMap.put(mapTask.Id, mapTask);
                    }
                }
                Database.update(filterMap.values(), false);
            }
            if (!toInsert.isEmpty()) {
                Database.insert(toInsert, false);
            }

        } catch (Exception e) {
            ErrorLogger.logException(e, 'CreateTaskHelper', 'createTasksForPhasewiseHolds', ErrorLogger.Level.ERROR, null, null);
            throw e;
        }
    }
}