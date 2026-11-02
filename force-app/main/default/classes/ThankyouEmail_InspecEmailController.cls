/**
 * @description Controller for the ThankyouEmail_InspecEmailVFComponent.
 * Handles fetching Project, Contact, and User details for the installation follow-up email.
 */
public with sharing class ThankyouEmail_InspecEmailController {

    /**
     * @description The ID of the Project record, passed from the Visualforce Component.
     */
    public Id targetId { get; set; }

    /**
     * @description The ID of the Recipient (Contact), passed from the Visualforce Component.
     */
    public Id targetContactId { get; set; }

    /**
     * @description Fetches the Current User's details (Name, Title, Phone) and their Manager's details.
     * @return User The current user record with manager fields populated.
     */
    public User currentUser {
        get {
            if (currentUser == null) {
                currentUser = [SELECT FirstName, LastName, Title, Phone, CompanyName, Email,
                                      Manager.Name, Manager.Email, Manager.Phone
                               FROM User 
                               WHERE Id = :UserInfo.getUserId()];
            }
            return currentUser;
        }
        private set;
    }

    /**
     * @description Fetches the related Project record details based on targetId.
     * @return Project__c The project record with Name and Id.
     */
    public Project__c relatedRec {
        get {
            if (relatedRec == null && targetId != null) {
                relatedRec = [SELECT Id, Name 
                              FROM Project__c 
                              WHERE Id = :targetId 
                              LIMIT 1];
            }
            return relatedRec;
        }
        private set;
    }

    /**
     * @description Fetches the Recipient Contact details based on targetContactId.
     * @return Contact The contact record with Name.
     */
    public Contact recipientRec {
        get {
            if (recipientRec == null && targetContactId != null) {
                recipientRec = [SELECT Id, Name 
                                FROM Contact 
                                WHERE Id = :targetContactId 
                                LIMIT 1];
            }
            return recipientRec;
        }
        private set;
    }

    /**
     * @description Retrieves the URL for the STERIS banner image from the helper class.
     * @return String The URL of the banner image.
     */
    public String getSterisBannerURL() {
        // We pass the DeveloperName 'SterisBanner' to the helper class
        return EmailControllerHelper.bannerLoader('SterisBanner');
    }
}