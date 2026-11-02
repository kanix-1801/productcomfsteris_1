/**
 * @author PSL
 * @date 12-04-2025
 * @description Controller class for handling C1 email related operations
 */
public with sharing class C1EmailController {
    /**
     * @description Case ID for email operations
     * @param caseId The ID of the case to operate on
     */
    public String caseId { get; set; }

   		
	/**
     * @description Retrieves case contact roles for receiving and install contacts
     * @param caseId The ID of the case to retrieve contact roles for
     * @return List of CaseContactRole records
     */
	public List<CaseContactRole> getCaseContactRoles() {
        if (String.isNotBlank(caseId)) {
            return EmailControllerHelper.getReceivingAndInstallContacts(caseId);
        }
        return new List<CaseContactRole>();
    }

    


	/**
     * @description Gets department manager name for a case
     * @param caseId The ID of the case to get department manager for
     * @return Name of the department manager
     */
	public String getDepartmentManagerName() {
        return EmailControllerHelper.getDepartmentManager(caseId);
    }
	
	
    /**
     * @description Gets regional sales coordinator BL user for a case
     * @param caseId The ID of the case to get regional sales coordinator for
     * @return Name of the regional sales coordinator BL user
     */
    public String getRegionalSalesCoOrdinatorBlUser() {
            try {
                
                return EmailControllerHelper.getRegionalSalesCoOrdinatorBlUser(caseId,true);
                
                
            } catch (Exception e) {
               ErrorLogger.logException(e, 'COAEmailController', 'getRegionalSalesCoOrdinatorBlUser');
            	
                throw e;
               
            }
        }
    
    public String getC1OrderPreparationBanner() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'OrderPreparationbanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
    
      /**
     * @description Returns the email signature for the current running user or context.
     * @return String HTML/text signature block
     */
	public string getEmailSignature(){
        return EmailControllerHelper.emailSignature(caseId);
    } 

}