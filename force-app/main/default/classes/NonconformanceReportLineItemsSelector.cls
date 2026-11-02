/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Selector for NonconformanceReportLineItem__c records.
 */
public with sharing class NonconformanceReportLineItemsSelector {
    /**
     * @description GW-5497 / GW-5845 - Loads lines for the supplied NCR headers,
     *              grouped by NCR number then newest first within each NCR.
     * @param reportIds NCR header Ids
     * @return Related NCR lines, grouped by NCR, newest first within each group
     */
    public static List<NonconformanceReportLineItem__c> selectByReportIds(Set<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return new List<NonconformanceReportLineItem__c>();
        }
        return [
            SELECT
                Id,
                Name,
                NonconformanceReport__c,
                NonconformanceReport__r.Name,
                RepairRelated__c,
                NCRDate__c,
                InitiatedBy__c,
                InitiatedBy__r.Name,
                QualityInspector__c,
                QualityInspector__r.Name,
                ProductLine__c,
                NCRReason__c,
                NCRLocationContext__c,
                Comments__c,
                NCRStatus__c,
                NCRSource__c,
                SeverityRating__c,
                SeverityJustification__c,
                OccurrenceRating__c,
                RiskRating__c,
                QuantityRejected__c,
                CAPANumber__c,
                NCROwner__c,
                NCRDescription__c,
                RiskJustification__c,
                CreatedDate
            FROM NonconformanceReportLineItem__c
            WHERE NonconformanceReport__c IN :reportIds
            WITH USER_MODE
            ORDER BY
                NonconformanceReport__r.Name ASC,
                NCRDate__c DESC NULLS LAST,
                CreatedDate DESC,
                Name DESC
        ];
    }
}