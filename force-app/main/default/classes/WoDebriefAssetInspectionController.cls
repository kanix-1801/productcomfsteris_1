/**
 * @description Controller for woDebrief. Stamps Asset last-inspection fields when a
 *              Product Serviced line is saved. Technicians can read the Asset but not
 *              edit it, so the write runs without sharing after a read check in the
 *              caller's sharing context.
 */
public with sharing class WoDebriefAssetInspectionController {

    /**
     * @description One Product Serviced save to copy onto its Asset.
     */
    public class InspectionStamp {
        /** @description Asset Id from the Product Serviced line. */
        @AuraEnabled public Id assetId { get; set; }
        /** @description Inspection Outcome saved on the line. */
        @AuraEnabled public String inspectionOutcome { get; set; }
        /** @description True when the Product Serviced line was closed as Completed. */
        @AuraEnabled public Boolean markServiced { get; set; }
    }

    /**
     * @description Sets Last Inspection Outcome and Last Inspection Date on each readable Asset.
     * @param stamps Product Serviced lines that were just saved
     */
    @AuraEnabled
    public static void stampAssetInspections(List<InspectionStamp> stamps) {
        Map<Id, String> outcomeByAssetId = new Map<Id, String>();
        Set<Id> servicedAssetIds = new Set<Id>();
        if (stamps != null) {
            for (InspectionStamp stamp : stamps) {
                if (stamp == null || stamp.assetId == null || String.isBlank(stamp.inspectionOutcome)) {
                    continue;
                }
                outcomeByAssetId.put(stamp.assetId, stamp.inspectionOutcome.trim());
                if (stamp.markServiced == true) {
                    servicedAssetIds.add(stamp.assetId);
                }
            }
        }
        if (outcomeByAssetId.isEmpty()) {
            return;
        }

        List<Asset> visibleAssets = (List<Asset>) new AssetsSelector()
            .selectFields(new List<String>{ 'Id' })
            .whereIn('Id', new List<Id>(outcomeByAssetId.keySet()))
            .execute();
        Set<Id> visibleIds = new Map<Id, Asset>(visibleAssets).keySet();
        if (visibleIds.size() != outcomeByAssetId.size()) {
            throw new AuraHandledException('The Asset inspection could not be updated.');
        }
        new InspectionWriter().apply(visibleIds, outcomeByAssetId, servicedAssetIds);
    }

    /**
     * @description Writes inspection fields without record-edit sharing.
     */
    private without sharing class InspectionWriter {
        /**
         * @description Applies today's date and the saved outcome.
         * @param assetIds Assets the caller can read
         * @param outcomeByAssetId Inspection outcome keyed by Asset Id
         * @param servicedAssetIds Assets whose Product Serviced line was completed
         */
        public void apply(Set<Id> assetIds, Map<Id, String> outcomeByAssetId, Set<Id> servicedAssetIds) {
            Date inspectionDate = Date.today();
            List<Asset> updates = new List<Asset>();
            for (Id assetId : assetIds) {
                Asset row = new Asset(
                    Id = assetId,
                    LastInspectionOutcome__c = outcomeByAssetId.get(assetId),
                    LastInspectionDate__c = inspectionDate
                );
                if (servicedAssetIds != null && servicedAssetIds.contains(assetId)) {
                    row.LastServicedDate__c = inspectionDate;
                }
                updates.add(row);
            }
            update updates;
        }
    }
}