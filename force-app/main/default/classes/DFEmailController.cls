/**
 * @author PSL
 * @date 01-15-2026
 * @description Controller for DF emails. Exposes getters used by VF templates to retrieve
 *              Receiving Contact details, email signature, and DF Order Preparation banner.
 *              Delegates business logic to EmailControllerHelper.
 */
public with sharing class DFEmailController {
	public String caseId { get; set; }
    
    /**
     * @description Returns receiving contact display name for the given Case.
     * @param none Uses controller property caseId as input
     * @return String Receiving contact display name
     */
    
    public string getRecevingContactName(){
        return EmailControllerHelper.getReceivingContactDisplayName(caseId);
    }
    /**
     * @description Returns receiving contact full name for the given Case.
     * @param none Uses controller property caseId as input
     * @return String Receiving contact full name
     */
     public string getRecevingContactFullName(){
        return EmailControllerHelper.receivingConName(caseId);
    }
    
    /**
     * @description Returns receiving contact phone number for the given Case.
     * @param none Uses controller property caseId as input
     * @return String Receiving contact phone
     */
   
    public string getRecevingContactPhone(){
        return EmailControllerHelper.receivingConPhone(caseId);
    }
    
    /**
     * @description Returns receiving contact email address for the given Case.
     * @param none Uses controller property caseId as input
     * @return String Receiving contact email
     */
    
    public string getRecevingContactEmail(){
        return EmailControllerHelper.receivingConEmail(caseId);
    }
    
    /**
     * @description Returns email signature HTML/text for the given Case.
     * @param none Uses controller property caseId as input
     * @return String Email signature content
     */
    
    public string getSignature(){
        return EmailControllerHelper.emailSignature(caseId);
    }
    
    /**
     * @description Retrieves banner URL/content for DF Order Preparation using CMDT developer name.
     * @param none Uses fixed CMDT DeveloperName 'OrderPreparationbanner'
     * @return String Banner URL/content
     */
   
     public String getDFOrderPreparationBanner() {
            // Use the CMDT DeveloperName (no spaces), e.g., 'COAFrench'
            String devName = 'OrderPreparationbanner' ;
            return EmailControllerHelper.bannerLoader(devName);
        }
}