/**
 * @author PSL
 * @date 11-28-2025
 * @description Controller class for handling COA email related functionality, including retrieving user information and checking order conditions for email notifications.
 */
global with sharing class COAEmailController {
   
    /**
     * @description Case ID for which email-related information is being retrieved
     */
    public String caseId { get; set; }
    
    /**
     * @description Test-visible flag to simulate exceptions during testing
     */
    @TestVisible private static Boolean TEST_Exception_THROW = false;
    
    /**
     * @description Retrieves the regional sales coordinator BL user for a given case ID
     * @param caseId The ID of the case to retrieve the regional sales coordinator BL user for
     * @return String representing the regional sales coordinator BL user name
     * @throws Exception if an error occurs during retrieval
     */
       public String getRegionalSalesCoOrdinatorBlUser() {
            try {
                
                return EmailControllerHelper.getRegionalSalesCoOrdinatorBlUser(caseId,false);
                
                
            } catch (Exception e) {
               ErrorLogger.logException(e, 'COAEmailController', 'getRegionalSalesCoOrdinatorBlUser');
            	
                throw e;
               
            }
        }
    
     /**
     * @description Retrieves the regional sales coordinator BL user for a given case ID for french
     * @param caseId The ID of the case to retrieve the regional sales coordinator BL user for
     * @return String representing the regional sales coordinator BL user name
     * @throws Exception if an error occurs during retrieval
     */
       public String getRegionalSalesCoOrdinatorBlUserFrnch() {
            try {
                
                return EmailControllerHelper.getRegionalSalesCoOrdinatorBlUserFrnch(caseId,false);
                
                
            } catch (Exception e) {
               ErrorLogger.logException(e, 'COAEmailController', 'getRegionalSalesCoOrdinatorBlUserFrnch');
            	
                throw e;
               
            }
        }
        
         
        /**
         * @description Retrieves the account manager Cap Line sales rep for a given case ID
         * @param caseId The ID of the case to retrieve the account manager Cap Line sales rep for
         * @return String representing the account manager Cap Line sales rep name
         * @throws Exception if an error occurs during retrieval
         */
        public String getAccountManagerCapLineSalesRep() {
            try {
                
               return EmailControllerHelper.getAccountManagerCapLineSalesRep(caseId);
            } catch (Exception ex) {
                
                
                ErrorLogger.logException(ex, 'COAEmailController', 'getAccountManagerCapLineSalesRep');
               
            	throw ex;
            }
}
    
    
    /**
         * @description Retrieves the account manager Cap Line sales rep for a given case ID for french
         * @param caseId The ID of the case to retrieve the account manager Cap Line sales rep for
         * @return String representing the account manager Cap Line sales rep name
         * @throws Exception if an error occurs during retrieval
         */
        public String getAccountManagerCapLineSalesRepFrnch() {
            try {
                
               return EmailControllerHelper.getAccountManagerCapLineSalesRepFrnch(caseId);
            } catch (Exception ex) {
                
                
                ErrorLogger.logException(ex, 'COAEmailController', 'getAccountManagerCapLineSalesRepFrnch');
               
            	throw ex;
            }
}
    
    /**
     * @description Checks if there are GI Reprocessing orders associated with the case
     * @param caseId The ID of the case to check for GI Reprocessing orders
     * @return Boolean indicating if GI Reprocessing orders exist
     * @throws Exception if an error occurs during the check
     */
    public Boolean getGiReprocessingOrders() {
        try {
            
            
			if (Test.isRunningTest() && TEST_Exception_THROW) {
                
                throw new NullPointerException();
            }

            List<OrderItem> items = [
                SELECT Id
                FROM OrderItem
                WHERE Order.parentCase__C = :caseId
                AND Warehouse__c = 'DRO'
                AND OrderLineType__c = 'GI Reprocessing'
                LIMIT 1
            ];
            if(items!=null){
                return !items.isEmpty();
                }
            return false;
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'COAEmailController', 'getGiReprocessingOrders');
            throw ex;
        }
        }
	
		

     /**
     * @description Retrieves the department manager for a given case ID
     * @param caseId The ID of the case to retrieve the department manager for
     * @return String representing the department manager name
     */
    public String getDepartmentManager() {
        
        return EmailControllerHelper.getDepartmentManagerTurns(caseId);
       
   }
    
    /**
     * @description Retrieves the purchasing contact for a purchase order for a given case ID
     * @param caseId The ID of the case to retrieve the purchasing contact for
     * @return String representing the purchasing contact name, or empty string if not found
     * @throws Exception if an error occurs during retrieval
     */
    public String getPurchasingContactPO() {
        try {
            
            if (Test.isRunningTest() && TEST_Exception_THROW) {
                
                throw new NullPointerException();
            }

            List<CaseContactRole> ccrList = [
                SELECT Role, Contact.name,Contact.FirstName
                FROM CaseContactRole
                WHERE CasesId = :caseId
                AND Role = 'Purchasing Contact'
                LIMIT 1
            ];
    
            if (!ccrList.isEmpty()  && ccrList[0].Contact.FirstName != null) {
                return ccrList[0].Contact.FirstName;
            }
            return '';
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'COAEmailController', 'getPurchasingContactPO');
            throw ex;
        }
    }
    
    
    
    public String getBannerUrlCOAFrench() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'COAFrench' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
    
    public String getBannerUrlCOAProject() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'SterisBanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
    
    public String getBannerUrlCOATurns() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'AcknowldgementBanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }

   
     
}