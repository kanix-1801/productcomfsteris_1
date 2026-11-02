/**
 * @author PSL
 * @date 11-26-2025
 * @description Handler for setting quick action defaults for email sending
 */
public class QuickActionDefaultsHandler implements QuickAction.QuickActionDefaultsHandler {

    /**
     * @description Sets default email addresses based on case email type
     * @param defaults Array of quick action defaults
     */
    public void onInitDefaults(QuickAction.QuickActionDefaults[] defaults) {
        try {
        QuickAction.SendEmailQuickActionDefaults sendEmailDefaults;

        for (QuickAction.QuickActionDefaults def : defaults) {
            if (def instanceof QuickAction.SendEmailQuickActionDefaults &&
                def.getTargetSObject().getSObjectType() == EmailMessage.sObjectType) {
                sendEmailDefaults = (QuickAction.SendEmailQuickActionDefaults) def;
                break;
            }
        }

        if (sendEmailDefaults == null) return;

        Id caseId = sendEmailDefaults.getContextId();
        Case c = [SELECT Id, EmailType__c,emailLanguage__C, Order__c FROM Case WHERE Id = :caseId LIMIT 1];

        
            if (c.EmailType__c == 'SOA' || c.EmailType__c == 'No Charge SOA') {
                EmailAddressDefaultController.defaultSOAEmailAddresses(sendEmailDefaults, c);
            }
            
            if(c.EmailType__c == 'CANPRESHIP') {
				EmailAddressDefaultController.defaultSDNEmailAddresses(sendEmailDefaults, c,'Pre-Ship');
            }
            
            if (c.EmailType__c == 'COA Project' && c.EmailLanguage__c=='English'){
                
                EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'COA Projects' LIMIT 1];
                sendEmailDefaults.setInsertTemplateBody(true);
                sendEmailDefaults.setTemplateId(template.Id);
                EmailAddressDefaultController.defaultCOAProjectEmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'COA Turns' && c.EmailLanguage__c=='English'){
                EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'COA US CAN Eng' LIMIT 1];
                sendEmailDefaults.setInsertTemplateBody(true);
                sendEmailDefaults.setTemplateId(template.Id);
                EmailAddressDefaultController.defaultCOATurnsEmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'C1' && c.EmailLanguage__c=='English'){
                EmailAddressDefaultController.defaultC1EmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'C2' && c.EmailLanguage__c=='English'){
                EmailAddressDefaultController.defaultC2EmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'DF' && c.EmailLanguage__c=='English'){
                EmailAddressDefaultController.defaultDFEmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'Ship Date Notification' && c.EmailLanguage__c=='English'){
                EmailAddressDefaultController.defaultSDNEmailAddresses(sendEmailDefaults, c,'Ship Date Notification');
            }
            if (c.EmailType__c == 'COA Project' && c.EmailLanguage__c=='French'){
                
                EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'COA Project French' LIMIT 1];
                sendEmailDefaults.setInsertTemplateBody(true);
                sendEmailDefaults.setTemplateId(template.Id);
                 
                EmailAddressDefaultController.defaultCOAProjectEmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'COA Turns' && c.EmailLanguage__c=='French'){
                
                EmailTemplate template = [SELECT Id FROM EmailTemplate WHERE Name = 'CAN COA French' LIMIT 1];
                sendEmailDefaults.setInsertTemplateBody(true);
                sendEmailDefaults.setTemplateId(template.Id);
                 
                EmailAddressDefaultController.defaultCOAProjectEmailAddresses(sendEmailDefaults, c);
            }
            if (c.EmailType__c == 'Go/No-Go' && c.EmailLanguage__c=='English'){
                EmailAddressDefaultController.defaultGoNoGoEmailAddresses(sendEmailDefaults, c);
            }
        
        } catch (Exception ex) {
            ErrorLogger.logException(ex, 'QuickActionDefaultsHandler', 'onInitDefaults');
            throw ex;
        }
    }
}