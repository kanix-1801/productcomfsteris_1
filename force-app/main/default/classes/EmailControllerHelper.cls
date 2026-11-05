/**
 * @author PSL
 * @date 12-04-2025
 * @description Helper class for email-related operations in the system
 */
public without Sharing class EmailControllerHelper {

    /**
     * @description Custom exception class for email controller operations
     */
    public class EmailControllerException extends Exception{}    
        @testVisible
    /**
     * @description Throws exception if test exception is requested
     * @param caseId The case ID to check for test exception
     * @return void
     */
    public static void throwIfTestException(String caseId){
        
        if(Test.isRunningTest() && '5FORCE000EXCEPTION'.equals(caseId)){
            throw new EmailControllerException('Forced Exception for Unit Test');
        }
    } 
			
    /**
     * @description Gets department manager name for a case
     * @param caseId The ID of the case to get department manager for
     * @return Name of the department manager
     */
    public static String getDepartmentManager(id caseId) {
        try {
            List<CaseContactRole> ccrList = [
                SELECT Role, Contact.Name,Contact.FirstName
                FROM CaseContactRole
                WHERE CasesId = :caseId
                AND Role = 'Departmental Contact'
                LIMIT 1
            ];
    
            if (!ccrList.isEmpty()  && ccrList[0].Contact.FirstName != null) {
                return ccrList[0].Contact.FirstName;
            }
            throwIfTestException(caseId);
            return '';
        } catch (Exception ex) {
           ErrorLogger.logException(ex, 'EmailControllerHelper', 'getDepartmentManager');
            throw ex;
        }
    }
    
    /**
     * @description Gets department manager whole name for a case for COA Turns Template
     * @param caseId The ID of the case to get department manager for
     * @return Name of the department manager
     */
    public static String getDepartmentManagerTurns(id caseId) {
        try {
            List<CaseContactRole> ccrList = [
                SELECT Role, Contact.Name,Contact.FirstName
                FROM CaseContactRole
                WHERE CasesId = :caseId
                AND Role = 'Departmental Contact'
                LIMIT 1
            ];
    
            if (!ccrList.isEmpty()  && ccrList[0].Contact.Name != null) {
                return ccrList[0].Contact.Name;
            }
            throwIfTestException(caseId);
            return '';
        } catch (Exception ex) {
           ErrorLogger.logException(ex, 'EmailControllerHelper', 'getDepartmentManagerTurns');
            throw ex;
        }
    }
    
    
	/**
     * @description receiving contact phone for DF template
     * @param caseId The ID of the case to get receving contact phone
     * @return receving contact  phone
     */
    
public static List<CaseContactRole> getReceivingAndInstallContacts(Id caseId) {
        try {
            throwIfTestException(caseId);
            return [
                SELECT Role, Contact.Id, Contact.Name, Contact.Phone, Contact.MobilePhone, Contact.Email
                FROM CaseContactRole
                WHERE CasesId = :caseId
                AND Role IN ('Receiving Contact', 'Install Contact')
                ORDER BY Role
            ];
        } catch (Exception ex) {
            System.debug('Error in getReceivingAndInstallContacts: ' + ex.getMessage());
            throw ex;
        }
    }

   //if true then return name and for false return name + email
    
    public static String getRegionalSalesCoOrdinatorBlUser(Id caseId, Boolean nameOnly) {
        try {
            List<CaseTeamMember> ctmList = [
                SELECT Member.Name, Member.Email
                FROM CaseTeamMember
                WHERE TeamRole.Name = 'BL User' AND ParentId = :caseId
                LIMIT 1
            ];
            if (!ctmList.isEmpty()) {
                CaseTeamMember ctm = ctmList[0];
                return nameOnly ? ctm.Member.Name : (ctm.Member.Name + ' at ' + ctm.Member.Email);
            }
            throwIfTestException(caseId);
            return '';
        } catch (Exception e) {
            ErrorLogger.logException(e, 'EmailControllerHelper', 'getRegionalSalesCoOrdinatorBlUser');
            throw e;
        }
    }
    
      /**
     * @description Gets regional BL user name for a case 
	 * @if true then return name and for false return name + email for french
     * @param caseId The ID of the case to get regional BL user
     * @return Name of the regional BL user
     */
     
    
    public static String getRegionalSalesCoOrdinatorBlUserFrnch(Id caseId, Boolean nameOnly) {
        try {
            List<CaseTeamMember> ctmList = [
                SELECT Member.Name, Member.Email
                FROM CaseTeamMember
                WHERE TeamRole.Name = 'BL User' AND ParentId = :caseId
                LIMIT 1
            ];
            if (!ctmList.isEmpty()) {
                CaseTeamMember ctm = ctmList[0];
                return nameOnly ? ctm.Member.Name : (ctm.Member.Name + ' à ' + ctm.Member.Email);
            }
            throwIfTestException(caseId);
            return '';
        } catch (Exception e) {
            ErrorLogger.logException(e, 'EmailControllerHelper', 'getRegionalSalesCoOrdinatorBlUserFrnch');
            throw e;
        }
    }
    
    	//Account manager for capital lines sales rep with highest count

		public static String getAccountManagerCapLineSalesRep(id caseId) {
            try {
                
                List<AggregateResult> aggResults = [
                    SELECT SalesRep__c, COUNT(Id) cnt, MIN(CreatedDate) earliestDate
                    FROM OrderLineContact__c
                    WHERE OrderLine__r.Order.parentCase__c = :caseId
                    AND OrderLine__r.CreateSubcase__c = 'yes - Capital line'
                    AND SalesRep__c != null
                    GROUP BY SalesRep__c
                ];
					
                if(!aggResults.isEmpty()){
                AggregateResult topRep;
                Integer maxCount = 0;
                Datetime earliest = null;
        
               
                for (AggregateResult ar : aggResults) {
                    Integer count = (Integer) ar.get('cnt');
                    Datetime created = (Datetime) ar.get('earliestDate');
        
                    if (count > maxCount || (count == maxCount && (earliest == null || created < earliest))) {
                        maxCount = count;
                        earliest = created;
                        topRep = ar;
                    }
                }
        
                if (topRep != null) {
                    Id topSalesRepId = (Id) topRep.get('SalesRep__c');
                    
                    Contact salesRep = [SELECT Name,email FROM Contact WHERE Id = :topSalesRepId LIMIT 1];
                    
                    string accMngr= salesRep.name + ' at '+salesRep.email;
                     
                    return accMngr;
                }
                }
            	throwIfTestException(caseId);
                return ''; 
            } catch (Exception ex) {
                
                
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'getAccountManagerCapLineSalesRep');
               
            	throw ex;
            }
		}
    
    /**
     * @description Account manager for capital lines sales rep with highest count for french
     * @param caseId The ID of the case to get acc manager
     * @return Name of the acc manager 
     */
    
    public static String getAccountManagerCapLineSalesRepFrnch(id caseId) {
            try {
                
                List<AggregateResult> aggResults = [
                    SELECT SalesRep__c, COUNT(Id) cnt, MIN(CreatedDate) earliestDate
                    FROM OrderLineContact__c
                    WHERE OrderLine__r.Order.parentCase__c = :caseId
                    AND OrderLine__r.CreateSubcase__c = 'yes - Capital line'
                    AND SalesRep__c != null
                    GROUP BY SalesRep__c
                ];
					
                if(!aggResults.isEmpty()){
                AggregateResult topRep;
                Integer maxCount = 0;
                Datetime earliest = null;
        
               
                for (AggregateResult ar : aggResults) {
                    Integer count = (Integer) ar.get('cnt');
                    Datetime created = (Datetime) ar.get('earliestDate');
        
                    if (count > maxCount || (count == maxCount && (earliest == null || created < earliest))) {
                        maxCount = count;
                        earliest = created;
                        topRep = ar;
                    }
                }
        
                if (topRep != null) {
                    Id topSalesRepId = (Id) topRep.get('SalesRep__c');
                    
                    Contact salesRep = [SELECT Name,email FROM Contact WHERE Id = :topSalesRepId LIMIT 1];
                    
                    string accMngr= salesRep.name + ' à '+salesRep.email;
                     
                    return accMngr;
                }
                }
            	throwIfTestException(caseId);
                return ''; 
            } catch (Exception ex) {
                
                
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'getAccountManagerCapLineSalesRepFrnch');
               
            	throw ex;
            }
		}
    			
    				
    		public static String getAccountManagerCapSerLineSalesRep(id caseId) {
                try {
                    
                    // Query all SalesRep__c for the given CaseId via OrderLineContact__c
                    List<OrderLineContact__c> olContacts = [
                        SELECT SalesRep__r.Name,SalesRep__r.FirstName
                        FROM OrderLineContact__c
                        WHERE OrderLine__r.Order.ParentCase__c = :caseId and (OrderLine__r.CreateSubcase__c = 'yes - Capital line' 
                                                                              OR OrderLine__r.CreateSubcase__c = 'yes - Service Installation')
                        AND SalesRep__c != null
                    ];
            
                    // Collect unique Sales Rep names
                    if(!olContacts.isEmpty()){
                    Set<String> salesRepNames = new Set<String>();
                    for (OrderLineContact__c olc : olContacts) {
                        if (olc.SalesRep__r.FirstName != null) {
                            salesRepNames.add(olc.SalesRep__r.FirstName.trim());
                        }
                    }
            
                    // Join names with "/" separator
                    return String.join(new List<String>(salesRepNames), ' / ');
                    }
            		throwIfTestException(caseId);
                    return '';

                }catch(exception ex){
                    
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'getAccountManagerCapSerLineSalesRep');
               
            	throw ex;
                }
            }
    
    //if order Line is GI
    public static Boolean getGiReprocessingOrders(id caseId) {
        try {
            List<OrderItem> items = [
                SELECT Id
                FROM OrderItem
                WHERE order.ParentCase__c  = :caseId
                AND  OrderLineType__c = 'GI Reprocessing'
                LIMIT 1
            ];
			 
            throwIfTestException(caseId);
            return !items.isEmpty();
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'getGiReprocessingOrders');
            throw ex;
        }
        }
    
		//returns all the active holds on the case   
    public static String activeHolds(Id caseId) {
        try {
            // Query all reason codes for active holds related to the case
            List<OrderAndOrderLineHold__c> holdList = [
                SELECT toLabel(reasonCode__c) 
                FROM OrderAndOrderLineHold__c 
                WHERE Active__c = true 
                AND order__r.parentCase__c = :caseId
            ];
    
            // Collect all reason codes into a list of strings
            if(!holdList.isEmpty()){
            set<String> reasonCodes = new set<String>();
            for (OrderAndOrderLineHold__c h : holdList) {
                if (h.reasonCode__c != null) {
                    reasonCodes.add(h.reasonCode__c);
                }
            }
    
            // Return as a comma-separated string
            return String.join(reasonCodes, ', ');
            }
            throwIfTestException(caseId);
            return '';
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'activeHolds');
            throw ex;
        }
    }
    
    //check the plannig hold on order
    public static boolean isPlannigHold(id caseId){
        try{
            List<OrderAndOrderLineHold__c> holdList = [
                SELECT name 
                FROM OrderAndOrderLineHold__c 
                WHERE Active__c = true AND name ='Planning Hold'
                AND order__r.parentCase__c = :caseId
            ];
            
            throwIfTestException(caseId);
            return !holdList.isEmpty();
            
        }catch(exception ex){
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'isPlannigHold');
            throw ex;

        }
    }
    
    //planning hold details: orderline.LineNumber__c , Product.Item Number , Product.Description  --> planning hold will be always on order line
    
   
    public static String planningHoldDetails(Id caseId) {
        try {
            // Check if Planning Hold exists
            if (EmailControllerHelper.isPlannigHold(caseId)) {
                // Query all Planning Hold records for the case
                List<OrderAndOrderLineHold__c> holdList = [
                    SELECT orderLine__r.lineNumber__c,
                           orderLine__r.Product2.ProductCode,
                           orderLine__r.Product2.Description
                    FROM OrderAndOrderLineHold__c
                    WHERE Active__c = true
                    AND Name = 'Planning Hold'
                    AND order__r.parentCase__c = :caseId
                ];
    
                // Build the details string
                String details = '';
                for (OrderAndOrderLineHold__c h : holdList) {
                    String lineInfo = '';
                    if (h.orderLine__r.lineNumber__c != null) {
                        lineInfo +=  h.orderLine__r.lineNumber__c + ' - ';
                    }
                    if (h.orderLine__r.Product2.ProductCode != null) {
                        lineInfo += h.orderLine__r.Product2.ProductCode + ' - ';
                    }
                    if (h.orderLine__r.Product2.Description != null) {
                        lineInfo += h.orderLine__r.Product2.Description;
                    }
                    details += lineInfo +'	'; // Add line break after each line
                }
                if(String.isNotBlank(details)){
                    return details;
                }
    
                return '';
            }
    
            throwIfTestException(caseId);
            return '';
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'planningHoldDetails');
            throw ex;
        }
	}
    
    //check if service line is present 
   
        public static Boolean isServiceLine(Id caseId) {
            try {
                List<orderItem> oli = [
                    SELECT id
                    FROM orderItem
                    WHERE Order.ParentCase__c = :caseId
                    AND CreateSubcase__c = 'yes - Service Installation'
                    LIMIT 1
                ];
        
                // If list is not empty, return true
            	throwIfTestException(caseId);
                return !oli.isEmpty();
            } catch (Exception ex) {
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'isServiceLine');
                throw ex;
            }
        }
    
		//    return the install conatct from case
    
        public static String installContact(Id caseId) {
            try {
                List<CaseContactRole> ccrList = [
                    SELECT Role, Contact.Name
                    FROM CaseContactRole
                    WHERE CasesId = :caseId
                    AND Role = 'Install Contact'
                    LIMIT 1
                ];
        
                // If record exists, return Contact Name
                if (!ccrList.isEmpty() && ccrList[0].Contact.Name != null) {
                    return ccrList[0].Contact.Name;
                }
            	throwIfTestException(caseId);
                return ''; // Return empty if no Install Contact found
            } catch (Exception ex) {
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'installContact');
                throw ex;
            }
        }

    
    /**
     * @description receving contact for DF template
     * @param caseId The ID of the case to get receving contact 
     * @return receving contact  
     */
    
	public static CaseContactRole getReceivingContactRole(Id caseId) {
        if (caseId == null) return null;

        try {
            throwIfTestException(caseId);
            return [
                SELECT Id,
                       CasesId,
                       Role,
                       ContactId,
                       Contact.FirstName,
                       Contact.LastName,
                       Contact.Name,
                       Contact.Phone,
                	   Contact.MobilePhone,
                       Contact.Email
                FROM CaseContactRole
                WHERE CasesId = :caseId
                  AND Role   = 'Receiving Contact'
                LIMIT 1
            ];
        } catch (QueryException qe) {
            // No record found -> return null for easy reuse
            return null;
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'getReceivingContactRole');
            throw ex;
        }
    }

    /**
     * Convenience: returns a display full name.
     * Prefers FirstName, then LastName.
     */
    public static String getReceivingContactDisplayName(Id caseId) {
        CaseContactRole ccr = getReceivingContactRole(caseId);
        // CBM-236 
       /* if(CaseId != null && ccr.ContactId != null) {
        Case cs=new Case(id=ccr.CasesId,ContactId=ccr.ContactId);
        update cs;
        }*/
        
        if (ccr == null || ccr.Contact == null) return null;

        if (String.isNotBlank(ccr.Contact.FirstName)) return ccr.Contact.FirstName;
        
        return ccr.Contact.FirstName; 
    }
    
    //receiving contact full name
    
    public static String receivingConName(Id caseId) {
        CaseContactRole ccr = getReceivingContactRole(caseId);
        if (ccr == null || ccr.Contact == null) return null;

        if (String.isNotBlank(ccr.Contact.name)) return ccr.Contact.name;
        
        return ''; 
    }
    
    
    /**
     * @description receiving contact phone for DF template
     * @param caseId The ID of the case to get receving contact phone
     * @return receving contact  phone
     */
    
    public static String receivingConPhone(Id caseId) {
        CaseContactRole ccr = getReceivingContactRole(caseId);
        if (ccr == null || ccr.Contact == null) return null;

        if (String.isNotBlank(ccr.Contact.MobilePhone)) return ccr.Contact.MobilePhone;
        
        return ''; 
    }
    
    //receiving contact email
    
    public static String receivingConEmail(Id caseId) {
        CaseContactRole ccr = getReceivingContactRole(caseId);
        if (ccr == null || ccr.Contact == null) return null;

        if (String.isNotBlank(ccr.Contact.Email)) return ccr.Contact.Email;
        
        return ''; 
    }
    
    //current logged in user signature for emails 
    
    public static string emailSignature(id caseID){
        
	
	try {
        User u = [SELECT Signature FROM User WHERE Id = :UserInfo.getUserId() LIMIT 1];
        String s = u.Signature;
        if (String.isBlank(s)) return '';

        // Normalize Windows CRLF and Unix LF to <br/> so email clients honor line breaks
        s = s.replace('\r\n', '\n');       // normalize first
        s = s.replace('\n', '<br/>');      // newline -> <br/>

        // If some users use pipes as separators, put each part on a new line
        s = s.replace(' | ', '<br/>');

            return s; // HTML string
        } catch (Exception ex) {
            return '';
        }
    }
    
    //returns true if procedural line is present
    
        public static boolean isProcedural(id caseID){
            
            try{
                
                list<orderItem> OLI = [select id,OrderLineType__c from orderItem where Order.ParentCase__c =:caseID and OrderLineType__c ='Procedural'];
                
                if(!oli.isEmpty()){
                    return true;
                }
                throwIfTestException(caseId);
                return false;
                
            }catch(exception ex){
                 ErrorLogger.logException(ex, 'EmailControllerHelper', 'isProcedural');
                throw ex;
            }
        }
		
    
    
        public static CaseContactRole getInstallContactRole(Id caseId) {
            if (caseId == null) return null;
        
            try {
                throwIfTestException(caseId);
                return [
                    SELECT Id,
                           /* Use CaseId if that's the correct API name in your org */
                           CasesId,
                           Role,
                           ContactId,
                           Contact.FirstName,
                           Contact.LastName,
                           Contact.Name,
                           Contact.Phone,
                    	   Contact.MobilePhone,
                           Contact.Email
                    FROM CaseContactRole
                    WHERE CasesId = :caseId
                      AND Role    = 'Install Contact'
                    LIMIT 1
                ];
               
            } catch (QueryException qe) {
                // No record found -> return null for easy reuse
                return null;
            } catch (Exception ex) {
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'getInstallContactRole');
                throw ex;
            }
        }
        
        /**
         * Convenience: returns a display name (prefers FirstName, then LastName, else Name).
         */
        public static String getInstallContactDisplayName(Id caseId) {
            CaseContactRole ccr = getInstallContactRole(caseId);
            if (ccr == null || ccr.Contact == null) return null;
        
            if (String.isNotBlank(ccr.Contact.FirstName)) return ccr.Contact.FirstName;
            if (String.isNotBlank(ccr.Contact.LastName))  return ccr.Contact.LastName;
            return ''; // may be null/blank; caller should guard
        }
        
        /**
         * Install contact full name (returns Contact.Name if available else empty string)
         */
        public static String installConName(Id caseId) {
            CaseContactRole ccr = getInstallContactRole(caseId);
            if (ccr == null || ccr.Contact == null) return '';
        
            if (String.isNotBlank(ccr.Contact.Name)) return ccr.Contact.Name;
            return '';
        }
        
        /**
         * Install contact phone (returns Contact.Phone if available else empty string)
         */
        public static String installConPhone(Id caseId) {
            CaseContactRole ccr = getInstallContactRole(caseId);
            if (ccr == null || ccr.Contact == null) return '';
            
            system.debug('conPhone'+ccr.Contact.MobilePhone);
        
            if (String.isNotBlank(ccr.Contact.MobilePhone)) return ccr.Contact.MobilePhone;
            return '';
        }
    
    
    
    
     public static List<OrderItem>equipmentShippingDetails(Id caseId) {
        try {
            
		List<OrderItem> result = new List<OrderItem>();
    
            if (caseId == null) return result;

            throwIfTestException(caseId);

            result = [
                SELECT id,LineNumber__c,
                       Product2.ProductCode,
                       Product2.Description,
                       Quantity,
                       ActualShipmentDate__c,
                       MailSent__c, 
                       ShipToAddressID__r.Street, ShipToAddressID__r.City, ShipToAddressID__r.State, ShipToAddressID__r.PostalCode, ShipToAddressID__r.Country
                FROM OrderItem
                WHERE  OrderLineType__c != 'Trade In Lines'
                  AND ActualShipmentDate__c != null
                  AND MailSent__c = false
                  AND Order.ParentCase__c = :caseId
                  AND OrderLineStatus__c NOT IN('Cancelled')
                  AND orderLineNumber__C !=0 order by orderLineNumber__C ASC
            ];
            if(result==null){
                return new list<orderitem>();
            }
            return result;


            }
        
	catch(exception ex){
                 ErrorLogger.logException(ex, 'EmailControllerHelper', 'equipmentShippingDetails');
                throw ex;
            }
        }
    
    public static String getAccountManagerSerLineSalesRep(id caseId) {
            try {
                
                List<AggregateResult> aggResults = [
                    SELECT SalesRep__c, COUNT(Id) cnt, MIN(CreatedDate) earliestDate
                    FROM OrderLineContact__c
                    WHERE OrderLine__r.Order.parentCase__c = :caseId
                    AND OrderLine__r.CreateSubcase__c = 'yes - Service Installation'
                    AND SalesRep__c != null
                    GROUP BY SalesRep__c
                ];
					
                if(!aggResults.isEmpty()){
                AggregateResult topRep;
                Integer maxCount = 0;
                Datetime earliest = null;
        
               
                for (AggregateResult ar : aggResults) {
                    Integer count = (Integer) ar.get('cnt');
                    Datetime created = (Datetime) ar.get('earliestDate');
        
                    if (count > maxCount || (count == maxCount && (earliest == null || created < earliest))) {
                        maxCount = count;
                        earliest = created;
                        topRep = ar;
                    }
                }
        
                if (topRep != null) {
                    Id topSalesRepId = (Id) topRep.get('SalesRep__c');
                    
                    Contact salesRep = [SELECT Name,email FROM Contact WHERE Id = :topSalesRepId LIMIT 1];
                    
                    string accMngr= salesRep.name + ' at '+salesRep.email;
                     
                    return accMngr;
                }
                }
            	throwIfTestException(caseId);
                return ''; 
            } catch (Exception ex) {
                
                
                ErrorLogger.logException(ex, 'EmailControllerHelper', 'getAccountManagerSerLineSalesRep');
               
            	throw ex;
            }
		}
    
    	//returns trade in Lines where mail sent=false	
    
    	public static List<OrderItem> tradeInEquipmentDetails(Id caseId) {
            try {
                
            List<OrderItem> result = new List<OrderItem>();
        
                if (caseId == null) return result;
    
                
    
                result = [
                    SELECT id,LineNumber__c,
                           Product2.ProductCode,
                           Product2.Description,
                           Quantity,
                           ActualShipmentDate__c,
                    	   MailSent__c, 
                           ShipToAddressID__r.Street, ShipToAddressID__r.City, ShipToAddressID__r.State, ShipToAddressID__r.PostalCode, ShipToAddressID__r.Country

                    FROM OrderItem
                    WHERE  OrderLineType__c = 'Trade In Lines'                  
                      AND MailSent__c = false
                      AND Order.ParentCase__c = :caseId
                      AND OrderLineStatus__c NOT IN('Cancelled')
                      AND orderLineNumber__C !=0 order by orderLineNumber__C ASC
                ];
                
                if(result==null){
                return new list<orderitem>();
            }
                throwIfTestException(caseId); 
                
            return result;
                
    
    
                }
            
        catch(exception ex){
                     ErrorLogger.logException(ex, 'EmailControllerHelper', 'tradeInEquipmentDetails');
                    throw ex;
                }
            }
		
    
	
 
    public static DateTime calculateActualShipDate(Id caseId) {
        try {
            if (caseId == null) return null;
    
            // Query into a list so we can handle zero-row results safely
            List<OrderItem> items = [
                SELECT ActualShipmentDate__c,
                       Warehouse__c
                FROM OrderItem
                WHERE Order.ParentCase__c = :caseId
                  AND OrderLineType__c != 'Trade In Lines'
                  AND ActualShipmentDate__c != null
                  AND MailSent__c = false
                  AND OrderLineStatus__c NOT IN ('Cancelled')
                ORDER BY ActualShipmentDate__c ASC
                LIMIT 1
            ];
    
            if (items.isEmpty() || items[0].ActualShipmentDate__c == null) {
                return null;
            }
    
            OrderItem oi = items[0];
    
            // Determine weeks to add based on warehouse/plant code
            String plant = oi.Warehouse__c;
            Integer weeksToAdd = (plant != null && plant.equalsIgnoreCase('MMX')) ? 3 : 2;
    
            // Add weeks (7 days per week)
            Date shipped = oi.ActualShipmentDate__c;
            DateTime projected = (Datetime)shipped.addDays(weeksToAdd * 7);
    
            // Optional test hook
            throwIfTestException(caseId);
    
            return projected;
    
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'calculateActualShipDate');
            throw ex;
        }
    }


	
    
    //generic method for banner image respectively called from controllers with required string
    
    public static string bannerLoader(string devName){
        try{
        CBM_Generic_Configuration__mdt cfg;
        
            cfg = [
                SELECT key__C
                FROM CBM_Generic_Configuration__mdt
                WHERE DeveloperName = :devName
                LIMIT 1
            ];
            
            
            
            id orgId = UserInfo.getOrganizationId();
            return URL.getOrgDomainUrl().toExternalForm()+'/servlet/servlet.ImageServer?id='
            + cfg.key__C + '&oid=' + orgId;
        }catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'calculateActualShipDate');
            throw ex;
        }
    }
    
    /**
     * @description Retrieves scheduled equipment Order Items associated with the given Case.
     *              This method returns Order Items where the scheduled date is available,
     *              shipment has not yet occurred, the line is not cancelled/closed,
     *              and the line is not a Trade-In line.
     *
     * @param caseId Id of the Case used to identify related Orders through Order.ParentCase__c.
     * @return List<OrderItem> List of matching scheduled equipment Order Items.
     *
     * @throws Exception Logs and rethrows any exception encountered during processing.
     */
    public static List<OrderItem> equipmentScheduleDetails(Id caseId) {
        try {
            // Return an empty list if Case Id is not provided.
            if (caseId == null) {
                return new List<OrderItem>();
            }

            // Used to simulate exception scenarios during test execution, if applicable.
            throwIfTestException(caseId);

            // Fetch scheduled equipment Order Items related to the Case.
            return [
                SELECT Id,
                    LineNumber__c,
                    Product2.ProductCode,
                    Product2.Description,
                    Quantity,
                    ScheduledDate__c, 
                    ShipToAddressID__r.Street, ShipToAddressID__r.City, ShipToAddressID__r.State, ShipToAddressID__r.PostalCode, ShipToAddressID__r.Country
                FROM OrderItem
                WHERE OrderLineType__c != 'Trade In Lines'
                AND ScheduledDate__c != null
                AND ActualShipmentDate__c = null
                AND Order.ParentCase__c = :caseId
                AND OrderLineStatus__c NOT IN ('Cancelled', 'Closed')
                AND OrderLineNumber__c != 0
                ORDER BY OrderLineNumber__c ASC
            ];
        } catch (Exception ex) {
            // Log exception details for troubleshooting and rethrow to preserve existing behavior.
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'equipmentScheduleDetails');
            throw ex;
        }
    }
    
    public static DateTime firstNonPreInstallScheduleDate(Id caseId) {
        try {
            
            // Used to simulate exception scenarios during test execution, if applicable.
            throwIfTestException(caseId);

            // Fetch scheduled equipment Order Items related to the Case.
            List<Order> orderList = [SELECT id, FirstScheduledDateNonPreinstall__c from Order WHERE ParentCase__c =: caseId];
            return (DateTime)orderList[0].FirstScheduledDateNonPreinstall__c;
            
        } catch (Exception ex) {
            // Log exception details for troubleshooting and rethrow to preserve existing behavior.
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'firstNonPreInstallScheduleDate');
            throw ex;
        }
    } 
    
    public static List<OrderItem> equipmentScheduleDetail(Id caseId) {
        try {
            // Return an empty list if Case Id is not provided.
            if (caseId == null) {
                return new List<OrderItem>();
            }

            // Used to simulate exception scenarios during test execution, if applicable.
            throwIfTestException(caseId);

            // Fetch scheduled equipment Order Items related to the Case.
            return [
                SELECT Id,
                    LineNumber__c,
                    Product2.ProductCode,
                    Product2.Description,
                    Quantity,
                    ScheduledDate__c, 
                    ShipToAddressID__r.Street, ShipToAddressID__r.City, ShipToAddressID__r.State, ShipToAddressID__r.PostalCode, ShipToAddressID__r.Country
                FROM OrderItem
                WHERE OrderLineType__c = 'Trade In Lines'
                AND ScheduledDate__c != null
                AND ScheduledDate__c != 2049-12-31
                AND ActualShipmentDate__c = null
                AND Order.ParentCase__c = :caseId
                AND OrderLineStatus__c NOT IN ('Cancelled', 'Closed')
                AND OrderLineNumber__c != 0
                ORDER BY OrderLineNumber__c ASC
            ];
        } catch (Exception ex) {
            // Log exception details for troubleshooting and rethrow to preserve existing behavior.
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'equipmentScheduleDetail');
            throw ex;
        }
    }
    
    /**
     * @description Calculates Scheduled ship date based on product line and lead-time rules.
     * @param caseId Controller property used to identify the Case
     * @return DateTime Calculated Scheduled ship date
     */
    public static DateTime calculateScheduledShipDate(Id caseId, Boolean isSoonest) {
        try {
            if (caseId == null) return null;

            if(isSoonest){
                List<OrderItem> items = [
                    SELECT ScheduledDate__c,
                        Warehouse__c, Order.Country__c
                    FROM OrderItem
                    WHERE Order.ParentCase__c = :caseId
                        AND OrderLineType__c != 'Trade In Lines'
                        AND ScheduledDate__c != null
                        AND ScheduledDate__c != 2049-12-31
                        AND ActualShipmentDate__c = null
                        AND Active__c = true
                        AND CreateSubcase__c = 'yes - Capital line'
                        AND Subcase__r.PreInstallItem__c = false
                    ORDER BY ScheduledDate__c ASC
                    LIMIT 1
                    ];
                if (items.isEmpty() || items[0].ScheduledDate__c == null) {
                    return null;
                }
                return (Datetime)items[0].ScheduledDate__c.addDays(7);
            }
    
            // Query into a list so we can handle zero-row results safely
            List<OrderItem> items = [
                SELECT ScheduledDate__c,
                       Warehouse__c, Order.Country__c
                FROM OrderItem
                WHERE Order.ParentCase__c = :caseId
                    AND OrderLineType__c != 'Trade In Lines'
                    AND ScheduledDate__c != null
                    AND ScheduledDate__c != 2049-12-31
                    AND ActualShipmentDate__c = null
                    AND Active__c = true
                    AND CreateSubcase__c = 'yes - Capital line'
                    AND Subcase__r.PreInstallItem__c = false
                ORDER BY ScheduledDate__c DESC
                LIMIT 1
            ];
    
            if (items.isEmpty() || items[0].ScheduledDate__c == null) {
                return null;
            }
    
            OrderItem oi = items[0];
            DateTime projected;
    
            // Determine weeks to add based on warehouse/plant code
            String plant = oi.Warehouse__c;
            String country = oi.Order.Country__c;
            Integer weeksToAdd = ((country != null && country.equalsIgnoreCase('USA')) ? 
                            ((plant != null && plant.equalsIgnoreCase('MMX')) ? 3 : 2) : 
                            (country != null && country.equalsIgnoreCase('Canada')) ? 
                            ((plant != null && plant.equalsIgnoreCase('MQU')) ? 2 : 3) : null);    
            // Add weeks (7 days per week)
            Date shipped = oi.ScheduledDate__c;
            projected = (Datetime)shipped.addDays(weeksToAdd * 7);
    
            // Optional test hook
            throwIfTestException(caseId);
    
            return projected;
    
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'EmailControllerHelper', 'calculateScheduledShipDate');
            throw ex;
        }
    }

}