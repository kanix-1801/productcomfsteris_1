/**
* @author PWC Developer
* @date 2026/06/05
*
* @group Overlay Assignment
*
* @description
* GC-3088 - LWC controller for Overlay Assignment. This class contains only UI-facing operations.
*/
public with sharing class OverlayAssignmentController {
    
    /**
* @description
* GC-3088 - Logger constants used in the class.
*/
    public static final String SCENARIO = 'Overlay Assignment';
    public static final String LOGGER_TAG = 'OverlayAssignment';
    
    /**
* @description
* GC-3088 - Territory search result returned to the Overlay Assignment LWC.
*
* @modified By Pwc Developer
* GC-3108 - Updated to remove ZoneName__c field and add TasZone__c.
*/
    public class TerritoryWrapper {
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
        @AuraEnabled public String tasAddressId;
        @AuraEnabled public String tasZone;
        @AuraEnabled public String regionName;
    }
    
    /**
* @description
* GC-3088 - Account result returned to the Overlay Assignment LWC.
*/
    public class AccountWrapper implements Comparable {
        @AuraEnabled public Id accountId;
        @AuraEnabled public String accountName;
        @AuraEnabled public String accountNumber;
        @AuraEnabled public String accountType;
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
        @AuraEnabled public String tasAddressId;
        
        /**
* @description
* GC-3088 - Sorts accounts by Territory ID, then Account Name.
* 
* @param compareTo Object to compare against.
* @return Integer comparison result used by List.sort().
* 
* @example
* thisAccountName.compareTo(otherAccountName);
*/
        public Integer compareTo(Object compareTo) {
            try{
                AccountWrapper other = (AccountWrapper) compareTo;
                String thisTerritory = String.isBlank(this.territoryId) ? '' : this.territoryId.toLowerCase();
                String otherTerritory = String.isBlank(other.territoryId) ? '' : other.territoryId.toLowerCase();
                Integer territoryCompare = thisTerritory.compareTo(otherTerritory);
                
                if (territoryCompare != 0) {
                    return territoryCompare;
                }
                
                String thisAccountName = String.isBlank(this.accountName) ? '' : this.accountName.toLowerCase();
                String otherAccountName = String.isBlank(other.accountName) ? '' : other.accountName.toLowerCase();
                return thisAccountName.compareTo(otherAccountName);
            }catch (Exception ex) {
                Logger.error('Error comparing/sorting territories', ex);
                throw new OverlayAssignmentException('Error comparing/sorting territories');
            } finally {
                Logger.saveLog();
            }
        }
    }
    
    /**
* @description 
* GC-3088 -  Account result returned to the Overlay Assignment LWC.
*/
    public class AccountPageResult {
        @AuraEnabled public List<AccountWrapper> accounts;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer totalPages;
    }
    
    /**
* @description 
* GC-3088 -  Overlay user search result returned to the Overlay Assignment LWC.
*/
    public class UserWrapper {
        @AuraEnabled public Id userId;
        @AuraEnabled public String userName;
        @AuraEnabled public String email;
        @AuraEnabled public String phone;
        @AuraEnabled public String role;
        @AuraEnabled public String title;
        @AuraEnabled public String country;
        @AuraEnabled public String managerName;
    }
    
    /**
@description 
* GC-3088 - Territory summary returned to the Overlay Assignment LWC before final submission.
*/
    public class SummaryTerritoryWrapper {
        @AuraEnabled public String territoryId;
        @AuraEnabled public String territoryDescription;
        @AuraEnabled public List<AccountWrapper> selectedAccounts;
    }
    
    /**
* @description
* GC-3088 -  Searches TAS territory records for matching Territory ID, Description, or Number.
* 
* @param searchKey User-entered search text.
* @return Matching territories for selection.
* 
* @example
* OverlayAssignmentController.searchTerritories(searchKey);
*/
    @AuraEnabled
    public static List<TerritoryWrapper> searchTerritories(String searchKey) {
        try {
            return OverlayAssignmentService.searchTerritories(searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search territories.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 -  Searches TAS territory records for matching Territory ID, Description, or Number.
* 
* @param accountSearchKey account name/number search key
* @param accountType account type selected if any
* @param territoryIds Territory ids selected if any
* @return Matching accounts based on search account section.
* 
* @example
* OverlayAssignmentController.searchAccounts(accountSearchKey, accountType, territoryIds);
*/
    @AuraEnabled
    public static List<AccountWrapper> searchAccounts(String accountSearchKey, String accountType, List<String> territoryIds) {
        try {
            return OverlayAssignmentService.searchAccounts(accountSearchKey, accountType, territoryIds);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search accounts.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Retrieves a list of Accounts related to selected territories/accounts.
* 
* @param territoryIds Selected Territory IDs.
* @param accountSearchKey account search key.
* @param accountType account type if selected.
* @param selectedSearchAccountIds selected account ids from step 1
* @return Account Data
* 
* @example
* OverlayAssignmentController.retrieveAccounts(territoryIds, accountSearchKey, accountType, selectedSearchAccountIds);
*/
    @AuraEnabled
    public static AccountPageResult retrieveAccounts(
        List<String> territoryIds,
        String accountSearchKey,
        String accountType,
        List<Id> selectedSearchAccountIds
    ) {
        try {
            return OverlayAssignmentService.retrieveAccounts(
                territoryIds,
                accountSearchKey,
                accountType,
                selectedSearchAccountIds
            );
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to retrieve accounts.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Searches active users eligible for overlay assignment selection.
* 
* @param searchKey User-entered search text.
* @return Matching users for selection.
* 
* @example
* OverlayAssignmentController.searchOverlayUsers(searchKey);
*/
    @AuraEnabled
    public static List<UserWrapper> searchOverlayUsers(String searchKey) {
        try {
            return OverlayAssignmentService.searchOverlayUsers(searchKey);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to search overlay users.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Builds the review summary before final overlay assignment submission.
* 
* @param territoryIds Selected Territory IDs.
* @param deselectedAccountIds Accounts explicitly deselected by the user.
* @return Territory grouped account summary.
*
* @example
* OverlayAssignmentController.getAssignmentSummary(territoryIds, deselectedAccountIds);
*/
    @AuraEnabled
    public static List<SummaryTerritoryWrapper> getAssignmentSummary(
        List<String> territoryIds,
        List<Id> selectedAccountIds
    ) {
        try {
            return OverlayAssignmentService.getAssignmentSummary(territoryIds, selectedAccountIds);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to build overlay assignment summary.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Creates Account Team, Opportunity Team, and TAS writeback records for overlay assignments.
* 
* @param territoryIds Selected Territory IDs.
* @param selectedAccountIds Final selected accounts by user.
* @param userIds Selected overlay User IDs.
* @return Void.
*
* @example
* OverlayAssignmentController.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds);
*/
    @AuraEnabled
    public static void submitOverlayAssignments(
        List<String> territoryIds,
        List<Id> selectedAccountIds,
        List<Id> userIds
    ) {
        try {
            OverlayAssignmentService.submitOverlayAssignments(territoryIds, selectedAccountIds, userIds);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to submit overlay assignments.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }
    
    /**
* @description
* GC-3088 - Helper exception handling method
* 
* @param message exception/error message.
* @param exceptionValue exception record.
* @return AuraHandledException exception to throw to the LWC caller.
*
* @example
* throw buildHandledException(message, exceptionValue);
*/
    private static AuraHandledException buildHandledException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message + ' ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);
        
        if (exceptionValue instanceof AuraHandledException) {
            return (AuraHandledException) exceptionValue;
        }
        
        return new AuraHandledException(message);
    }
}