/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Selector for NonconformanceReportLineItem__c. Queries use SoqlQueryBuilder.
 */
public with sharing class NonconformanceReportLineItemsSelector extends SoqlQueryBuilder {
    private static final List<String> BY_REPORT_FIELDS = new List<String>{
        'Id',
        'Name',
        'NonconformanceReport__c',
        'NonconformanceReport__r.Name',
        'RepairRelated__c',
        'NCRDate__c',
        'InitiatedBy__c',
        'InitiatedBy__r.Name',
        'QualityInspector__c',
        'QualityInspector__r.Name',
        'ProductLine__c',
        'NCRReason__c',
        'NCRLocationContext__c',
        'Comments__c',
        'NCRStatus__c',
        'NCRSource__c',
        'SeverityRating__c',
        'SeverityJustification__c',
        'OccurrenceRating__c',
        'RiskRating__c',
        'QuantityRejected__c',
        'CAPANumber__c',
        'NCROwner__c',
        'NCRDescription__c',
        'RiskJustification__c',
        'CreatedDate'
    };

    /**
     * @description Binds this selector to NonconformanceReportLineItem__c for SoqlQueryBuilder queries.
     */
    public NonconformanceReportLineItemsSelector() {
        this.objectName = 'NonconformanceReportLineItem__c';
    }

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
        return (List<NonconformanceReportLineItem__c>) SoqlQueryBuilder.fromObject(
                'NonconformanceReportLineItem__c'
            )
            .selectFields(BY_REPORT_FIELDS)
            .whereField('NonconformanceReport__c', 'IN', new List<Id>(reportIds))
            .orderBy('NonconformanceReport__r.Name')
            .orderBy('NCRDate__c', true, true)
            .orderByDesc('CreatedDate')
            .orderByDesc('Name')
            .execute();
    }
}