/**
 * @author PSL
 * @date 11-10-2025
 * @description Handler class to create parent Cases for Orders and Subcases for Order Lines based on business rules
 * PSL :3rd-June-2026 :SII-5 : Logic added to create a single capital case for life science for all capital lines
 */
public class CreateCaseHandler {
	
    
    /**
     * @description Creates parent Cases for Orders when none exists, using OrderNumber__c list.
     *              - Capital Line: marks urgency and CWD for RMA orders.
     *              - Service Installation: links or creates as per existing Case state.
     *              - Mark OP stage for No Charge orders.
     * @param orderNumbers List of OrderNumber__c values for which Cases need to be created.
     * @return void
     */
 
    
    public static void createCase(List<String> orderNumbers) {
        try {
            if (orderNumbers == null || orderNumbers.isEmpty()) {
                return;
            }

            // Query Orders by OrderNumber__c
            List<Order> orderList = [
                SELECT Id,RegistrationNumber__c, AccountId, OrderNumber__c, Account.Name,ParentCase__c, OrderClassification__c,
                BLOwner__c,LogisticsOwner__c,OMOwner__c, CurrencyIsoCode
                FROM Order 
                WHERE OrderNumber__c IN :orderNumbers and ParentCase__C=null
            ];

            // Collect Order Ids
            Set<Id> orderIds = new Set<Id>();
           // Set<String> registrationNumbers = new Set<String>(); //Need to remove
            for (Order ord : orderList) {
                orderIds.add(ord.Id);
               // if(ord.RegistrationNumber__c!=null)
               // registrationNumbers.add(ord.RegistrationNumber__c);
            }
            
Id parentCaseRTId = getRecordTypeId('Case', 'CBM Case');
//code to check if for same registration number case already exists to link to current case starts
// Map<String, Id> regToCaseMap = new Map<String, Id>();

/*
for (Case c : [
    SELECT Order__r.RegistrationNumber__c FROM Case  WHERE RecordTypeid = :parentCaseRTId
    AND Order__r.RegistrationNumber__c IN :registrationNumbers and parentid=null]) {
    if (String.isNotBlank(c.Order__r.RegistrationNumber__c)) {
        regToCaseMap.put(c.Order__r.RegistrationNumber__c, c.Id);
  
    } 
}*/  //code to check if for same registration number case already exists to link to current case ends

     // Query existing Parent Cases using the Order lookup field
  
   Map<Id, Case> existingCaseMap = new Map<Id, Case>();
   for (Case c : [ SELECT Id, Order__c  FROM Case WHERE RecordTypeid=:parentCaseRTId 
                AND Order__c IN :orderIds]) 
            {
                existingCaseMap.put(c.Order__c, c);
            }
      // Prepare new Cases
    List<Case> csList = new List<Case>();
    Map<Id, Id> orderToCaseMap = new Map<Id, Id>();

            for (Order ord : orderList) {
                if (!existingCaseMap.containsKey(ord.Id)) {
                    Case cs = new Case();
                   
                    //cs.ParentId = regToCaseMap.containsKey(ord.RegistrationNumber__c) ? regToCaseMap.get(ord.RegistrationNumber__c): null;
                    cs.Subject = ord.OrderNumber__c + ' - ' + ord.Account.Name;
                    cs.AccountId = ord.AccountId;
                    cs.RecordTypeId = parentCaseRTId;
                    cs.Status = 'Order Entry';
                    // CBM-401 Handling       
                    if(ord.OrderClassification__c == 'RMA' || ord.OrderClassification__c == 'No Charge'){
                        cs.Customer_Want_Date__c = SYSTEM.TODAY();
                        cs.UrgentOrder__c = TRUE;
                        cs.Status = 'Order Preparation';    
                    }
                    cs.Order__c = ord.Id;
                    cs.CurrencyIsoCode = ord.CurrencyIsoCode;
                    csList.add(cs);
                }
            }

            if (!csList.isEmpty()) {
                insert csList;
                

                // Call CaseAssignmentHandler to assign team members
                CaseAssignmentHandler.assignTeamMembers(csList);

                for (Case cs : csList) {
                    orderToCaseMap.put(cs.Order__c, cs.Id);
                }

                Set<String> targetRoleNames = new Set<String>{
                    'BL User',
                    'OM User',
                    'Logistics User'
                };
                
            
            List<CaseTeamMember> ctmList = [
                    SELECT  ParentID,MemberId, TeamRole.Name
                    FROM CaseTeamMember
                    WHERE ParentID IN :orderToCaseMap.values()
                      AND TeamRole.Name IN :targetRoleNames
                ];
            
            
            Map<Id, Map<String, Id>> caseIdToRoleUser = new Map<Id, Map<String, Id>>();
                for (CaseTeamMember ctm : ctmList) {
                    if (ctm.MemberId == null) continue;
            
                    // Only stamp Users. (Groups/Queues are not valid for User lookups.)
                    if (ctm.MemberId.getSObjectType() != User.SObjectType) continue;
            
                    Map<String, Id> roleMap = caseIdToRoleUser.get(ctm.ParentID);
                    if (roleMap == null) {
                        roleMap = new Map<String, Id>();
                        caseIdToRoleUser.put(ctm.ParentID, roleMap);
                    }
                                            
                    if (!roleMap.containsKey(ctm.TeamRole.Name)) {
                                roleMap.put(ctm.TeamRole.Name, ctm.MemberId);
                            }
                        }

                // Update Orders with Parent Case lookup
                List<Order> ordersToUpdate = new List<Order>();
                for (Order ord : orderList) {
                    if (orderToCaseMap.containsKey(ord.Id)) {
                        ord.ParentCase__c = orderToCaseMap.get(ord.Id); // Assuming ParentCase__c is the lookup field
                        //CBM-213 start
						id caseIDNew=orderToCaseMap.get(ord.Id); 
                        
                        Map<String, Id> roleMap = caseIdToRoleUser.get(caseIDNew);
                         if (roleMap != null) {
                 
                             
                             Id blUserId = roleMap.get('BL User');
                             if (ord.BLOwner__c != blUserId) {
                                 ord.BLOwner__c = blUserId;
                                 
                             }
                             
                         Id omUserId = roleMap.get('OM User');
                                     if (ord.OMOwner__c != omUserId) {
                                         ord.OMOwner__c = omUserId;
                                         
                                 }
                             
                              Id logUserId = roleMap.get('Logistics User');
                                     if (ord.LogisticsOwner__C != logUserId) {
                                         ord.LogisticsOwner__C = logUserId;
                                         
                                 }
                         } //End
                        ordersToUpdate.add(ord);
                    }
                }

                if (!ordersToUpdate.isEmpty()) {
                    update ordersToUpdate;
                }
            }

        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateCaseHandler', 'createCase', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }
    
    /*************************************************************************************
     * @description  Creates SubCases for Order Lines based on business rules:
     *               - Capital Line → Always creates a new subcase.
     *               - Service Installation → Creates a new subcase only if no existing case
     *                 or existing case is Cancelled/Invoiced. Otherwise links existing case.
     *
     * @param        orderNumbers - List of OrderNumber__c values (Text) for which SubCases need to be created.
     * @return       void     
     ************************************************************************************/

    /**
     * @description Creates Subcases for Order Lines that require Capital Line or Service Installation handling.
     *              Ensures only one active Service Installation subcase per Parent Case.
     * @param orderNumbers List of OrderNumber__c values driving subcase creation.
     * @return void
     */
    public static void createSubCase(List<String> orderNumbers) {
        try {
            if (orderNumbers == null || orderNumbers.isEmpty()) {
                return;
            }

            //  Query Orders
            List<Order> orderList = [
                SELECT Id, OrderNumber__c, AccountId, Account.Name, AllCapitalLinesClosed__c, CurrencyIsoCode, 
                IsReprocessingExists__c, IsReprocessingScheduleDateMissing__c, AllReprocessingScheduledDate__c, IsProceduralMixedExists__c, IsProceduralMixedScheduleDateMissing__c, ProceduralMixedScheduleDate__c,
                BLOwnerTasks__c, LogisticsTasks__c
                FROM Order
                WHERE OrderNumber__c IN :orderNumbers
            ];
            Map<Id, Order> orderMap = new Map<Id, Order>();
            for (Order ord : orderList) {
                orderMap.put(ord.Id, ord);
            }

            //  Query Parent Cases
            Map<Id, Case> orderIdToParentCaseId = new Map<Id, Case>();
            set<Id> caseIds = new set<Id>();
            for (Case c : [
                SELECT Id, Order__c, Customer_Want_Date__c
                FROM Case
                WHERE RecordType.Name = 'CBM Case'
                AND Order__c IN :orderMap.keySet()
            ]) {
                orderIdToParentCaseId.put(c.Order__c, c);
                caseIds.add(c.Id);
            }

            //  Query OrderItems needing subcases
            List<OrderItem> orderLines = [
                SELECT Id, OrderId, CreateSubcase__c, LineNumber__c, Product2.Name,Product2.ProductCode,Product2.Description, Subcase__c, Case__c
                FROM OrderItem
                WHERE OrderId IN :orderMap.keySet()
                AND CreateSubcase__c IN ('yes - Capital line', 'yes - Service Installation', 'yes - SC Capital line')
                AND Subcase__c = NULL AND Case__c = NULL
            ];

            // Pre-detect Orders that have at least one Service Installation line to guarantee we only create one SI subcase per Order
            Set<Id> ordersNeedingServiceCase = new Set<Id>();
            for (OrderItem oi : orderLines) {
                if (oi.CreateSubcase__c == 'yes - Service Installation') {
                    ordersNeedingServiceCase.add(oi.OrderId);
                }
            }

            // Pre-detect Orders that have at least one SC Capital Line to guarantee we only create one SC Capital Line subcase per Order
            Set<Id> ordersNeedingScCapitalCase = new Set<Id>();
            for (OrderItem oi : orderLines) {
                if (oi.CreateSubcase__c == 'yes - SC Capital line') {
                    ordersNeedingScCapitalCase.add(oi.OrderId);
                }
            }

            // Query existing Service Installation subcases
            Map<Id, Case> existingServiceCasesByOrder = new Map<Id, Case>();
            for (Case sc : [
                SELECT Id, Order__c, Status
                FROM Case
                WHERE RecordType.Name = 'Service Installation Sub Case'
                AND Order__c IN :orderMap.keySet()
            ]) {
                existingServiceCasesByOrder.put(sc.Order__c, sc);
            }
            // Track if we already planned a Service Installation subcase creation per Order in this run
            Set<Id> plannedServiceCaseOrders = new Set<Id>();

            // Query existing SC Capital Line subcases
            Map<Id, Case> existingScCapitalCasesByOrder = new Map<Id, Case>();
            for (Case sc : [
                SELECT Id, Order__c, Status
                FROM Case
                WHERE RecordType.Name = 'Capital Line Sub Case' AND Order__r.Account.CustomerClassCode__c='SC'
                AND Order__c IN :orderMap.keySet()
            ]) {
                existingScCapitalCasesByOrder.put(sc.Order__c, sc);
            }
            // Track if we already planned an SC Capital Line subcase creation per Order in this run
            Set<Id> plannedScCapitalCaseOrders = new Set<Id>();

            // Enforce at most one Service Installation subcase DIRECT child under each Parent Case (defensive)
            // Build a set of Parent Case Ids that already have an active Service Installation subcase
            Map<Id, Boolean> parentHasActiveServiceSI = new Map<Id, Boolean>();
            for (Case sc : [
                SELECT Id, ParentId, Status
                FROM Case
                WHERE RecordType.Name = 'Service Installation Sub Case'
                AND ParentId IN :caseIds
            ]) {
                // Consider active if not Cancelled and not Invoiced/Closed
                Boolean isActive = !(sc.Status == 'Cancelled' || sc.Status == 'Invoiced/Closed');
                if (isActive) {
                    parentHasActiveServiceSI.put(sc.ParentId, true);
                }
            }

            // Enforce at most one SC Capital Line subcase DIRECT child under each Parent Case (defensive)
            // Build a set of Parent Case Ids that already have an active SC Capital Line subcase
            Map<Id, Boolean> parentHasActiveScCapital = new Map<Id, Boolean>();
            for (Case sc : [
                SELECT Id, ParentId, Status
                FROM Case
                WHERE RecordType.Name = 'Capital Line Sub Case' AND Order__r.Account.CustomerClassCode__c='SC'
                AND ParentId IN :caseIds
            ]) {
                Boolean isActive = !(sc.Status == 'Cancelled' || sc.Status == 'Invoiced/Closed');
                if (isActive) {
                    parentHasActiveScCapital.put(sc.ParentId, true);
                }
            }

            // Prepare Sub Cases
            List<Case> subCases = new List<Case>();
            Id capitalRTId = getRecordTypeId('Case', 'Capital Line Sub Case');
            Id serviceRTId = getRecordTypeId('Case', 'Service Installation Sub Case');
         

            List<OrderItem> orderItemsToUpdate = new List<OrderItem>();
            Map<Id, Id> orderIdToNewServiceCaseId = new Map<Id, Id>();
            Map<Id, Id> orderIdToNewScCapitalCaseId = new Map<Id, Id>();

            for (OrderItem ol : orderLines) {
                Id orderId = ol.OrderId;
                Order ord = orderMap.get(orderId);
				Id parentCaseId = orderIdToParentCaseId?.get(orderId)?.Id;
                if (ord == null || parentCaseId == null) {
                    continue;
                }

                ol.Case__c = parentCaseId;

                if (ol.CreateSubcase__c == 'yes - Capital line') {
                    Case capitalCase = new Case();
                    capitalCase.Subject = ol.LineNumber__c + ' ' + ol.Product2.ProductCode +' ' + ol.Product2.Description + ' Capital Line'; //CBM-915
                    capitalCase.RecordTypeId = capitalRTId;
                    capitalCase.ParentId = parentCaseId;
                    capitalCase.Order__c = orderId;
                    capitalCase.OrderLine__c = ol.Id;
                    capitalCase.accountId = ord.accountId; //CBM - 847
                    capitalCase.Status = 'Unscheduled';
                    capitalCase.Customer_Want_Date__c = orderIdToParentCaseId.get(orderId).Customer_Want_Date__c;
                    capitalCase.CurrencyIsoCode = ord.CurrencyIsoCode;
                    subCases.add(capitalCase);
                    orderItemsToUpdate.add(ol);

                } else if (ol.CreateSubcase__c == 'yes - Service Installation') {
                    Case existingServiceCase = existingServiceCasesByOrder.get(orderId);

                    if (existingServiceCase == null || 
                        existingServiceCase.Status == 'Cancelled' || 
                        existingServiceCase.Status == 'Invoiced/Closed') {

                        // Only create one Service Installation subcase per Order for this transaction.
                        // Additionally, ensure we only create if this Order actually has Service Installation lines.
                        if (ordersNeedingServiceCase.contains(orderId) 
                            && !plannedServiceCaseOrders.contains(orderId)
                            && parentHasActiveServiceSI.get(parentCaseId) != true) {
                            Case serviceCase = new Case();
                            serviceCase.Subject = ord.OrderNumber__c + ' Service Installation';
                            serviceCase.RecordTypeId = serviceRTId;
                            serviceCase.ParentId = parentCaseId;
                            serviceCase.Order__c = orderId;
                            serviceCase.AccountId = ord.AccountId; //CBM - 847 
                            serviceCase.Status = 'Pre-Installation';
                            serviceCase.CurrencyIsoCode = ord.CurrencyIsoCode;
                            subCases.add(serviceCase);
                            orderIdToNewServiceCaseId.put(orderId, null);
                            plannedServiceCaseOrders.add(orderId);
                            parentHasActiveServiceSI.put(parentCaseId, true); // mark so no further SI subcases get added under same parent
                        }
                        // For all Service Installation lines (first and subsequent), defer linking until post-insert
                        // unless an existing active Service Installation case was found.

                    } else {
                        // Link to the existing active Service Installation subcase
                        ol.Subcase__c = existingServiceCase.Id;
                    }

                    orderItemsToUpdate.add(ol);

                } else if (ol.CreateSubcase__c == 'yes - SC Capital line') {
                    Case existingScCapitalCase = existingScCapitalCasesByOrder.get(orderId);

                    if (existingScCapitalCase == null ||
                        existingScCapitalCase.Status == 'Cancelled' ||
                        existingScCapitalCase.Status == 'Invoiced/Closed') {

                        // Only create one SC Capital Line subcase per Order for this transaction.
                        // Additionally, ensure we only create if this Order actually has SC Capital Line lines.
                        if (ordersNeedingScCapitalCase.contains(orderId)
                            && !plannedScCapitalCaseOrders.contains(orderId)
                            && parentHasActiveScCapital.get(parentCaseId) != true) {
                            Case scCapitalCase = new Case();
                            scCapitalCase.Subject = ord.OrderNumber__c + ' SC Capital Line';
                            scCapitalCase.RecordTypeId = capitalRTId;
                            scCapitalCase.ParentId = parentCaseId;
                            scCapitalCase.Order__c = orderId;
                            scCapitalCase.AccountId = ord.AccountId;
                            scCapitalCase.Status = 'Unscheduled';
                            scCapitalCase.CurrencyIsoCode = ord.CurrencyIsoCode;
                            subCases.add(scCapitalCase);
                            orderIdToNewScCapitalCaseId.put(orderId, null);
                            plannedScCapitalCaseOrders.add(orderId);
                            parentHasActiveScCapital.put(parentCaseId, true); // mark so no further SC Capital subcases get added under same parent
                        }
                        // For all SC Capital Line lines (first and subsequent), defer linking until post-insert
                        // unless an existing active SC Capital Line case was found.

                    } else {
                        // Link to the existing active SC Capital Line subcase
                        ol.Subcase__c = existingScCapitalCase.Id;
                    }

                    orderItemsToUpdate.add(ol);
                }
            }

            //  Insert new subcases if any
            if (!subCases.isEmpty()) {
                insert subCases;

                for (Case sc : subCases) {
                    if (sc.RecordTypeId == serviceRTId) {
                        orderIdToNewServiceCaseId.put(sc.Order__c, sc.Id);
                    }
                    if (sc.Subject.contains('SC Capital Line')) {
                        orderIdToNewScCapitalCaseId.put(sc.Order__c, sc.Id);  
                    }
                }

                for (OrderItem ol : orderItemsToUpdate) {
                    if (ol.CreateSubcase__c == 'yes - Capital line') {
                        for (Case sc : subCases) {
                            if (sc.RecordTypeId == capitalRTId && sc.Order__c == ol.OrderId && sc.OrderLine__c == ol.Id) {
                                ol.Subcase__c = sc.Id;
                                break;
                            }
                        }
                    } else if (ol.CreateSubcase__c == 'yes - Service Installation' && ol.Subcase__c == null) {
                        ol.Subcase__c = orderIdToNewServiceCaseId.get(ol.OrderId);
                    } else if (ol.CreateSubcase__c == 'yes - SC Capital line' && ol.Subcase__c == null) {
                        ol.Subcase__c = orderIdToNewScCapitalCaseId.get(ol.OrderId);
                    }
                }
            }

            
            if (!orderItemsToUpdate.isEmpty()) {
                update orderItemsToUpdate;
            }

            // Post-processing: populate parent Case lookup on ALL remaining order lines for these Orders
            // without impacting existing subcase creation logic above.
            // Bulk-safe: single SOQL + single DML, and do not overwrite existing values.
            if (!orderIdToParentCaseId.isEmpty()) {
                List<OrderItem> remainingOrderItemsNeedingParentCase = [
                    SELECT Id, OrderId, Case__c
                    FROM OrderItem
                    WHERE OrderId IN :orderIdToParentCaseId.keySet()
                    AND Case__c = NULL
                ];
                if (!remainingOrderItemsNeedingParentCase.isEmpty()) {
                    List<OrderItem> oiToUpdateWithParent = new List<OrderItem>();
                    for (OrderItem oi : remainingOrderItemsNeedingParentCase) {
                        Id parentId = orderIdToParentCaseId.get(oi.OrderId).Id;
                        if (parentId != null) {
                            oi.Case__c = parentId;
                            oiToUpdateWithParent.add(oi);
                        }
                    }
                    if (!oiToUpdateWithParent.isEmpty()) {
                        update oiToUpdateWithParent;
                    }
                }
            }

            // call populateOrderFields method to Populate/Update Order fields.
            populateOrderFields(orderMap,capitalRTId);

           
            
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'CreateCaseHandler', 'createSubCase', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }

    /**
     * @description Populates and updates Order fields derived from current Case/Subcase processing.
     * @param orderMap Map of Orders involved in processing
     * @param capitalRTId RecordTypeId for 'Capital Line Sub Case' used by aggregate queries
     * @return void
     */
    private static void populateOrderFields(Map<Id, Order> orderMap, Id capitalRTId) {
        if (capitalRTId == null || orderMap.isEmpty()) {
            return;
        }    

        // Collect Orders and their OrderNumbers for the aggregate query
        Set<Id> evalOrderIds = new Set<Id>(orderMap.keySet());

        // Build map OrderId -> OrderNumber for filtering by Order__r.OrderNumber__c
        Map<Id, String> orderIdToNumber = new Map<Id, String>();
        for (Order o : orderMap.values()) {
            orderIdToNumber.put(o.Id, o.OrderNumber__c);
        }

        // ─────────────────────────────────────────────────────────────
        // Aggregate: Open BL Task count per Order
        // Counts Tasks with Status=Open, CBM_Task RecordType,
        // TaskTeam__c IN ('BL User', 'OM and BL') → stored in BLOwnerTasks__c
        // ─────────────────────────────────────────────────────────────
        Id cbmTaskRtId = Schema.SObjectType.Task
                               .getRecordTypeInfosByDeveloperName()
                               .get('CBM_Task')
                               .getRecordTypeId();

        Map<Id, Decimal> blTaskCountByOrderId = new Map<Id, Decimal>();
        for (AggregateResult ar : [SELECT   Order__c ordId, COUNT(Id) cnt FROM     Task
            WHERE Order__c IN :evalOrderIds AND	Status ='Open' AND RecordTypeId =  :cbmTaskRtId AND
		TaskTeam__c  IN ('BL User', 'OM and BL') AND Whatid!=null
            GROUP BY Order__c
        ]) {
            blTaskCountByOrderId.put((Id) ar.get('ordId'), (Decimal) ar.get('cnt'));
        }

        // ─────────────────────────────────────────────────────────────
        // Aggregate: Open Logistics Task count per Order
        // Counts Tasks with Status=Open, CBM_Task RecordType,
        // TaskTeam__c = 'Logistics User' → stored in LogisticsTasks__c
        // ─────────────────────────────────────────────────────────────
        Map<Id, Decimal> logisticsTaskCountByOrderId = new Map<Id, Decimal>();
        for (AggregateResult ar : [ SELECT   Order__c ordId, COUNT(Id) cnt FROM Task
            WHERE Order__c IN :evalOrderIds AND Status =  'Open' AND RecordTypeId =  :cbmTaskRtId AND TaskTeam__c  =  'Logistics User' AND Whatid!=null
            GROUP BY Order__c
        ]) {
            logisticsTaskCountByOrderId.put((Id) ar.get('ordId'), (Decimal) ar.get('cnt'));
        }

        // Aggregate counts of open capital subcases per OrderNumber
        Map<String, Integer> openCapByOrdNum = new Map<String, Integer>();
        for (AggregateResult ar : [
            SELECT Order__r.OrderNumber__c ordNum, COUNT(Id) cnt, Order__r.AllCapitalLinesClosed__c areClosed
            FROM Case
            WHERE RecordTypeId = :capitalRTId
                AND Order__r.Id IN :evalOrderIds
                AND Status NOT IN ('Invoiced/Closed', 'Cancelled')
            GROUP BY Order__r.OrderNumber__c, Order__r.AllCapitalLinesClosed__c
        ]) {
            openCapByOrdNum.put((String)ar.get('ordNum'), (Integer)ar.get('cnt'));
        }

        // Aggregate min scheduled date for non-preinstall capital lines
        Map<String, Date> minScheduledDateByOrder = new Map<String, Date>();
        // Aggregate min ship date for non-preinstall capital lines
        Map<String, Date> minShipDateByOrder = new Map<String, Date>();
        // Aggregate max ship date for non-preinstall capital lines
        Map<String, Date> maxShipDateByOrder = new Map<String, Date>();
        for (AggregateResult ar : [
            SELECT Order.OrderNumber__c ordNum, MIN(ScheduledDate__c) minDate, MIN(ActualShipmentDate__c) minShipDate
            FROM OrderItem
            WHERE Order.Id IN :evalOrderIds
                AND Subcase__r.RecordTypeId = :capitalRTId
                AND Subcase__r.PreInstallItem__c = false
                AND OrderLineStatus__c NOT IN ('Closed', 'Cancelled')
            GROUP BY Order.OrderNumber__c
        ]) {
            //minScheduledDateByOrder.put((String)ar.get('ordNum'), (Date)ar.get('minDate'));
            //minScheduledDateByOrder.put(String.valueOf(ar.get('ordNum')), ((Datetime) ar.get('minDate')).date());
            Object ordNum = ar.get('ordNum');
            Object minDateObj = ar.get('minDate');
            if (ordNum != null && minDateObj instanceof Date) {
                Date minDate = (Date) minDateObj;
                if (minDate != null) {
                    minScheduledDateByOrder.put(String.valueOf(ordNum), minDate);
                }
            }
            Object minShipDateObj = ar.get('minShipDate');
            if(ordNum != null && minShipDateObj != null && minShipDateObj instanceof Date) {
                Date minShipDate = (Date) minShipDateObj;
                minShipDateByOrder.put(String.valueOf(ordNum), minShipDate);
            }
        }
        for (AggregateResult ar : [
            SELECT Order.OrderNumber__c ordNum, MAX(ActualShipmentDate__c) maxShipDate
            FROM OrderItem
            WHERE Order.Id IN :evalOrderIds
                AND Subcase__r.RecordTypeId = :capitalRTId
                AND Subcase__r.PreInstallItem__c = false
                AND OrderLineStatus__c NOT IN ('Cancelled')
            GROUP BY Order.OrderNumber__c
        ]) {
            Object ordNum = ar.get('ordNum');
            Object maxShipDateObj = ar.get('maxShipDate');
            if(ordNum != null && maxShipDateObj != null && maxShipDateObj instanceof Date) {
                Date maxShipDate = (Date) maxShipDateObj;
                maxShipDateByOrder.put(String.valueOf(ordNum), maxShipDate);
            }
        }

        // Guard object and field access before SOQL to satisfy Security-ApexCRUDViolation
        // Object-level access
        if (!Schema.sObjectType.Order.isAccessible() || !Schema.sObjectType.OrderItem.isAccessible()) {
            return;
        }
        // Field-level access for fields referenced in query/logic
        Schema.DescribeFieldResult orderNumberFdr = Order.OrderNumber__c.getDescribe();
        Schema.DescribeFieldResult actShipDateFdr = OrderItem.ActualShipmentDate__c.getDescribe();
        if (!orderNumberFdr.isAccessible() || !actShipDateFdr.isAccessible()) {
            return;
        }

        List<String> ordersHaveLinesWithBlankShipDate = new List<String>();
        for (Order ord : [
            SELECT Id, OrderNumber__c
            FROM Order
            WHERE Id IN (
                SELECT OrderId
                FROM OrderItem
                WHERE Order.Id IN :evalOrderIds
                AND ActualShipmentDate__c = null
                AND Subcase__r.RecordTypeId = :capitalRTId
                AND Subcase__r.PreInstallItem__c = false
                AND OrderLineStatus__c NOT IN ('Closed', 'Cancelled')
            )
        ]) {
            ordersHaveLinesWithBlankShipDate.add(ord.OrderNumber__c);
        }
        
        Map<Id, List<OrderItem>> nonCapSvcTrdLinesByOrder = new Map<Id, List<OrderItem>>();
        Map<Id, List<OrderItem>> capLinesByOrder = new Map<Id, List<OrderItem>>();
        for (OrderItem oItem : [
            SELECT OrderId, Order.OrderNumber__c, OrderLineType__c, OrderLineStatus__c, CreateSubcase__c, Active__c 
            FROM OrderItem
            WHERE Order.Id IN :evalOrderIds
        ]) {
            List<OrderItem> oItemTemp = new List<OrderItem>();
            if (oItem.CreateSubcase__c == 'yes - Capital line' && oItem.Active__c) {
                if (capLinesByOrder.containsKey(oItem.OrderId)) {
                    oItemTemp = capLinesByOrder.get(oItem.OrderId);
                    oItemTemp.add(oItem);
                    capLinesByOrder.put(oItem.OrderId, oItemTemp);
                } else {
                    oItemTemp.add(oItem);
                    capLinesByOrder.put(oItem.OrderId, oItemTemp);
                }
            } else if (oItem.CreateSubcase__c != 'yes - Capital line' && oItem.OrderLineType__c != 'Service – Installation' && oItem.OrderLineType__c != 'Trade In Lines' && oItem.Active__c) {
                if (nonCapSvcTrdLinesByOrder.containsKey(oItem.OrderId)) {
                    oItemTemp = nonCapSvcTrdLinesByOrder.get(oItem.OrderId);
                    oItemTemp.add(oItem);
                    nonCapSvcTrdLinesByOrder.put(oItem.OrderId, oItemTemp);
                } else {
                    oItemTemp.add(oItem);
                    nonCapSvcTrdLinesByOrder.put(oItem.OrderId, oItemTemp);
                }
            }
        }

        // Aggregate no of Order holds
        Map<String, Integer> noOfOrderHoldsByOrder = new Map<String, Integer>();
        // Aggregate no of Capital Line holds
        Map<String, Integer> noOfCapitalLineHoldsByOrder = new Map<String, Integer>();

        Map<String, List<OrderAndOrderLineHold__c>> orderLineHoldsByOrder = new Map<String, List<OrderAndOrderLineHold__c>>();
                
        for (OrderAndOrderLineHold__c hold : [
            SELECT Name, Order__r.OrderNumber__c, Order__c, OrderLine__c, OrderLine__r.CreateSubcase__c
            FROM OrderAndOrderLineHold__c
            WHERE Order__c IN :evalOrderIds
            AND Active__c = true
        ]) {
            String ordNum = hold.Order__r.OrderNumber__c;
            if (ordNum != null) {
                if (orderLineHoldsByOrder.containsKey(ordNum)) {
                    orderLineHoldsByOrder.get(ordNum).add(hold);
                } else {
                    orderLineHoldsByOrder.put(ordNum, new List<OrderAndOrderLineHold__c>{ hold });
                }
            }
        }

        for(String orderNumber : orderIdToNumber.values()){
            List<OrderAndOrderLineHold__c> holdList = new List<OrderAndOrderLineHold__c>();
            holdList = orderLineHoldsByOrder.get(orderNumber);
            Integer noOfOrderHolds = 0;
            Integer noOfCapitalLineHolds = 0;
            if(holdList != null)
            {
                for(OrderAndOrderLineHold__c hold : holdList){
                    if(hold.OrderLine__c == null && !(hold.Name == 'MONTGOMERY SHIP HOLD' || hold.Name == 'Service Hold'))
                    {
                        noOfOrderHolds++;
                    }else if(hold.OrderLine__c != null && hold.OrderLine__r.CreateSubcase__c == 'yes - Capital line' && !(hold.Name == 'MONTGOMERY SHIP HOLD' || hold.Name == 'Service Hold'))
                    {
                        noOfCapitalLineHolds++;
                    }
                }
            }
            noOfOrderHoldsByOrder.put(orderNumber, noOfOrderHolds);
            noOfCapitalLineHoldsByOrder.put(orderNumber, noOfCapitalLineHolds);
        }

        // Aggregate no of Service Lines
        Map<String, Integer> noOfServiceLinesByOrder = new Map<String, Integer>();
        for(AggregateResult ar : [SELECT Order.OrderNumber__c ordNum, COUNT(Id) serviceLines FROM OrderItem WHERE OrderId IN :evalOrderIds AND Active__c = true AND OrderLineTypeRollup__c = 'Service – Installation' AND ScheduledDate__c < TODAY Group by Order.OrderNumber__c]){
            Integer numOfServiceLines = 0;
            Object ordNum = ar.get('ordNum');
            Object numOfServiceLinesObj = ar.get('serviceLines');
            if(numOfServiceLinesObj != null){
                numOfServiceLines = (Integer)numOfServiceLinesObj;
            }
            noOfServiceLinesByOrder.put(String.valueOf(ordNum), numOfServiceLines);            
        }

        // Prepare Order updates
        List<Order> ordersToUpdate = new List<Order>();
        for (Order o : orderMap.values()) {
            // Update AllCapitalLinesClosed__c
            Order upd = new Order(Id = o.Id);
            if (!o.AllCapitalLinesClosed__c) {
                
                Integer openCnt = openCapByOrdNum.containsKey(o.OrderNumber__c) ? openCapByOrdNum.get(o.OrderNumber__c) : 0;
                Boolean areClosed = (openCnt == 0);
                
                upd.put('AllCapitalLinesClosed__c', areClosed);
                if (areClosed) {
                    upd.put('AllCapitalLinesClosedDate__c', SYSTEM.TODAY());
                }
            }
            // Update FirstScheduledDateNonPreinstall__c
            Date minScheduledDate = minScheduledDateByOrder.containsKey(o.OrderNumber__c) ? minScheduledDateByOrder.get(o.OrderNumber__c) : null;
            upd.put('FirstScheduledDateNonPreinstall__c', minScheduledDate);

            Boolean allActShipDateBlank = true;
            if(minShipDateByOrder.containsKey(o.OrderNumber__c)) {
                allActShipDateBlank = false;
            }
            upd.put('AllNonPreinstaLinsHavBlnkActualShipDate__c', allActShipDateBlank);

            Boolean anyActShipDateBlank = false;
            if(ordersHaveLinesWithBlankShipDate.contains(o.OrderNumber__c)) {
                anyActShipDateBlank = true;
            }else{
                Date maxShipDate = maxShipDateByOrder.containsKey(o.OrderNumber__c) ? maxShipDateByOrder.get(o.OrderNumber__c) : null;
                upd.put('FinalShipmentDateNonPreinstall__c', maxShipDate);
            }
            upd.put('AnyPreinstaLinsHavBlnkActualShipDate__c', anyActShipDateBlank);

            upd.put('noOfOrderLevelHolds__c', noOfOrderHoldsByOrder.containsKey(o.OrderNumber__c) ? noOfOrderHoldsByOrder.get(o.OrderNumber__c) : 0);
            upd.put('noOfCapitalLineHolds__c', noOfCapitalLineHoldsByOrder.containsKey(o.OrderNumber__c) ? noOfCapitalLineHoldsByOrder.get(o.OrderNumber__c) : 0);
            upd.put('NoOfServiceLinesWithPastScheduleDate__c', noOfServiceLinesByOrder.containsKey(o.OrderNumber__c) ? noOfServiceLinesByOrder.get(o.OrderNumber__c) : 0);
            if (o.IsReprocessingExists__c > 0 && o.IsProceduralMixedExists__c == 0 && o.IsReprocessingScheduleDateMissing__c == 0 && o.AllReprocessingScheduledDate__c == null) {
                upd.put('AllReprocessingScheduledDate__c', Date.TODAY());
            }
            if (o.IsProceduralMixedExists__c > 0 && o.IsProceduralMixedScheduleDateMissing__c == 0 && o.IsReprocessingScheduleDateMissing__c == 0 && o.ProceduralMixedScheduleDate__c == null) {
                upd.put('ProceduralMixedScheduleDate__c', Date.TODAY()); 
            }

            // ── Open BL Task count (BL User + OM and BL) ──
            Decimal newBLCount = blTaskCountByOrderId.containsKey(o.Id) ? blTaskCountByOrderId.get(o.Id) : 0;
            if (o.BLOwnerTasks__c != newBLCount) {
                upd.put('BLOwnerTasks__c', newBLCount);
            }
            // ── Open Logistics Task count ──
            Decimal newLogisticsCount = logisticsTaskCountByOrderId.containsKey(o.Id) ? logisticsTaskCountByOrderId.get(o.Id) : 0;
            if (o.LogisticsTasks__c != newLogisticsCount) {
                upd.put('LogisticsTasks__c', newLogisticsCount);
            }
            // Update AreAllNonFeeAndDiscountClosed__c
            List<OrderItem> capLines = capLinesByOrder.containsKey(o.Id) ? capLinesByOrder.get(o.Id) : null;
            List<OrderItem> nonCapSvcTrdLines = nonCapSvcTrdLinesByOrder.containsKey(o.Id) ? nonCapSvcTrdLinesByOrder.get(o.Id) : null;

            if (capLines != null && !capLines.isEmpty()){
                upd.put('AreAllNonFeeAndDiscountClosed__c', false);
			}else if(nonCapSvcTrdLines != null && !nonCapSvcTrdLines.isEmpty()){
			    upd.put('AreAllNonFeeAndDiscountClosed__c', true);
            }
            ordersToUpdate.add(upd);
        }

        if (!ordersToUpdate.isEmpty()) {
            update ordersToUpdate;
        }

    }

        /**
         * @description Retrieves RecordType Id for a given sObject and RecordType Name.
         * @param sObjectType API name of the sObject (e.g., 'Case')
         * @param recordTypeName Record Type Name to lookup
         * @return Id of the matching RecordType
         */
		private static Id getRecordTypeId(String sObjectType, String recordTypeName) {
        return [
            SELECT Id 
            FROM RecordType 
            WHERE SObjectType = :sObjectType 
            AND Name = :recordTypeName 
            LIMIT 1
        ].Id;
    }
}