/**
 * @author Vinay
 * @date 2026/06/05
 *
 * @group Account Management
 *
 * @description
 * Service layer for Account page visibility logic.
 * Determines user access level based on Account Team membership and
 * retrieves matching custom metadata configuration for page elements.
 */
public with sharing class AccountPageVisibilityService {

    /**
     * @description
     * Aura-enabled response wrapper containing access level and page element configurations.
     */
    public class VisibilityResponse {
        @AuraEnabled public String accessLevel;
        @AuraEnabled public List<VisibilityItem> configs;
    }

    /**
     * @description
     * Aura-enabled wrapper representing a single page element visibility configuration item.
     */
    public class VisibilityItem {
        @AuraEnabled public String elementType;
        @AuraEnabled public String tabApiName;
        @AuraEnabled public String componentApiName;
        @AuraEnabled public Boolean isVisible;
        @AuraEnabled public Boolean isEditable;
        @AuraEnabled public Decimal displayOrder;
    }

    /**
     * @description
     * Retrieves page visibility configuration for the provided Account and page name.
     *
     * @param accountId Account record Id used to determine user access.
     * @param pageName Page name used to retrieve matching custom metadata records.
     * @return Visibility response containing access level and page element configuration.
     */
    public static VisibilityResponse getVisibilityConfig(Id accountId, String pageName) {
        try {
            if (accountId == null) {
                throw new AuraHandledException('Account Id is required.');
            }

            if (String.isBlank(pageName)) {
                throw new AuraHandledException('Page name is required.');
            }

            Logger.info('Retrieving account page visibility configuration.')
                .addTag('Account')
                .addTag('AccountPageVisibility')
                .setRecord(new Account(Id = accountId));

            Boolean isFullAccess =
                AccountPageVisibilitySelector.isCurrentUserAccountTeamMember(accountId);

            String accessLevel = isFullAccess ? 'Full' : 'Base';

            List<Account_Page_Visibility_Config__mdt> records =
                AccountPageVisibilitySelector.getVisibilityConfigs(pageName, accessLevel);

            VisibilityResponse response = new VisibilityResponse();
            response.accessLevel = accessLevel;
            response.configs = new List<VisibilityItem>();

            for (Account_Page_Visibility_Config__mdt rec : records) {
                VisibilityItem item = new VisibilityItem();
                item.elementType = rec.Element_Type__c;
                item.tabApiName = rec.TabAPIName__c;
                item.componentApiName = rec.ComponentAPIName__c;
                item.isVisible = rec.IsVisible__c;
                item.displayOrder = rec.DisplayOrder__c;
                response.configs.add(item);
            }

            Logger.info('Account page visibility configuration retrieved successfully.')
                .addTag('Account')
                .addTag('AccountPageVisibility');

            return response;
        } catch (Exception ex) {
            Logger.error('Error retrieving account page visibility configuration.', ex)
                .addTag('Account')
                .addTag('AccountPageVisibility');

            throw ex;
        }
    }
}