/**
 * @description GC-3441 / GC-3500 - Maps a Prospect Account to the Sales Connection
 *              Boomi payload.
 */
public with sharing class ProspectAccountScSyncMapper {
    /**
     * @description Builds the outbound request from the latest Account query result.
     * @param accountRecord Account with Price List, Created By, and Last Modified By.
     * @return Payload DTO for SO_Callout.
     */
    public static ProspectAccountScSyncRequest toRequest(Account accountRecord) {
        if (accountRecord == null || accountRecord.Id == null) {
            throw new IllegalArgumentException('Account is required.');
        }

        return ProspectAccountScSyncRequest.create(
            String.valueOf(accountRecord.Id),
            accountRecord.Name,
            accountRecord.Price_List__r == null
                ? null
                : accountRecord.Price_List__r.Price_List_ID__c,
            accountRecord.OrgIDs__c,
            accountRecord.BillingStreet,
            accountRecord.BillingCity,
            accountRecord.BillingState,
            accountRecord.BillingPostalCode,
            accountRecord.BillingCountry,
            accountRecord.CustomerClassCode__c,
            resolveHrisId(accountRecord.LastModifiedBy),
            formatUtc(accountRecord.LastModifiedDate),
            resolveHrisId(accountRecord.CreatedBy),
            formatUtc(accountRecord.CreatedDate)
        );
    }

    @TestVisible
    private static String formatUtc(Datetime dateTimeValue) {
        return dateTimeValue == null
            ? null
            : dateTimeValue.formatGmt('yyyy-MM-dd HH:mm:ss');
    }

    @TestVisible
    private static String resolveHrisId(User sourceUser) {
        if (sourceUser == null) {
            return null;
        }

        if (String.isNotBlank(sourceUser.EmployeeNumber__c)) {
            return sourceUser.EmployeeNumber__c.trim();
        }

        if (String.isNotBlank(sourceUser.EmployeeNumber)) {
            return sourceUser.EmployeeNumber.trim();
        }

        return null;
    }
}