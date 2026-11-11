/**
 * @description GW-375 - Adds a Mobile Device Picture to a parent work order the technician does not own.
 *              The file stays where it was saved. This inserts only a ContentDocumentLink.
 */
public without sharing class MobileDevicePictureLinkHandler {
    /**
     * @description GW-375 - Queues the parent link until the picture file has committed.
     * @param contentDocumentId File already stored on the child work order or instrument line
     * @param linkedEntityId Parent work order
     */
    public static void publishParentLink(Id contentDocumentId, Id linkedEntityId) {
        if (contentDocumentId == null || linkedEntityId == null) {
            return;
        }
        Database.SaveResult result = EventBus.publish(new MobileDevicePictureLink__e(
            ContentDocumentId__c = String.valueOf(contentDocumentId),
            LinkedEntityId__c = String.valueOf(linkedEntityId)
        ));
        if (result != null && !result.isSuccess()) {
            String message = result.getErrors().isEmpty()
                ? 'The parent work order link was not queued.'
                : result.getErrors()[0].getMessage();
            Logger.error('MobileDevicePictureLinkHandler.publishParentLink failed: ' + message);
            Logger.saveLog();
            throw new MobileDevicePictureLinkException(message);
        }
    }

    /**
     * @description GW-375 - Inserts parent links from the platform event. Runs without sharing
     *              so the technician does not need access to the parent work order.
     * @param events Queued parent links
     */
    public static void linkFromEvents(List<MobileDevicePictureLink__e> events) {
        if (events == null || events.isEmpty()) {
            return;
        }
        Set<Id> documentIds = new Set<Id>();
        Set<Id> entityIds = new Set<Id>();
        List<ContentDocumentLink> requested = new List<ContentDocumentLink>();
        for (MobileDevicePictureLink__e eventRow : events) {
            Id documentId = toId(eventRow.ContentDocumentId__c);
            Id entityId = toId(eventRow.LinkedEntityId__c);
            if (documentId == null || entityId == null || documentId == entityId) {
                continue;
            }
            documentIds.add(documentId);
            entityIds.add(entityId);
            requested.add(new ContentDocumentLink(
                ContentDocumentId = documentId,
                LinkedEntityId = entityId,
                ShareType = 'V',
                Visibility = 'AllUsers'
            ));
        }
        if (requested.isEmpty()) {
            return;
        }
        Set<String> existingKeys = new Set<String>();
        for (ContentDocumentLink existingLink : [
            SELECT ContentDocumentId, LinkedEntityId
            FROM ContentDocumentLink
            WHERE ContentDocumentId IN :documentIds
                AND LinkedEntityId IN :entityIds
        ]) {
            existingKeys.add(linkKey(existingLink.ContentDocumentId, existingLink.LinkedEntityId));
        }
        List<ContentDocumentLink> toInsert = new List<ContentDocumentLink>();
        Set<String> pendingKeys = new Set<String>();
        for (ContentDocumentLink link : requested) {
            String key = linkKey(link.ContentDocumentId, link.LinkedEntityId);
            if (existingKeys.contains(key) || pendingKeys.contains(key)) {
                continue;
            }
            pendingKeys.add(key);
            toInsert.add(link);
        }
        if (toInsert.isEmpty()) {
            return;
        }
        try {
            insert toInsert;
        } catch (Exception ex) {
            Logger.error('MobileDevicePictureLinkHandler.linkFromEvents failed', ex);
            Logger.saveLog();
        }
    }

    /**
     * @description Finishes Mobile Device Pictures the mobile app linked itself, for example a picture
     *              taken offline and synced after its instrument line. Updates the line picture count and
     *              queues the site visit work order link, the same as a picture saved through Apex.
     * @param links New ContentDocumentLinks
     */
    public static void completeMobileAppPictureLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (link.ContentDocumentId != null && isPictureRecord(link.LinkedEntityId)) {
                documentIds.add(link.ContentDocumentId);
            }
        }
        if (documentIds.isEmpty()) {
            return;
        }
        Set<Id> pictureDocumentIds = new Set<Id>();
        List<ContentVersion> pictureVersions = [
            SELECT Id, ContentDocumentId, Description
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
                AND IsLatest = true
                AND (
                    Description = :WoDebriefIMSchildWOController.MOBILE_DEVICE_PICTURE_MARKER
                    OR Title IN :WoDebriefIMSchildWOController.PICTURE_TITLES
                )
        ];
        for (ContentVersion version : pictureVersions) {
            pictureDocumentIds.add(version.ContentDocumentId);
        }
        if (pictureDocumentIds.isEmpty()) {
            return;
        }
        try {
            WoDebriefIMSchildWOController.applyPictureDetailsFromDescription(pictureVersions);
        } catch (Exception ex) {
            Logger.error('MobileDevicePictureLinkHandler.completeMobileAppPictureLinks picture details failed', ex);
            Logger.saveLog();
        }
        List<ContentDocumentLink> pictureLinks = new List<ContentDocumentLink>();
        Set<Id> lineIds = new Set<Id>();
        Set<Id> workOrderIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (!pictureDocumentIds.contains(link.ContentDocumentId) || !isPictureRecord(link.LinkedEntityId)) {
                continue;
            }
            pictureLinks.add(link);
            if (link.LinkedEntityId.getSobjectType() == WorkOrderLineItem.SObjectType) {
                lineIds.add(link.LinkedEntityId);
            } else {
                workOrderIds.add(link.LinkedEntityId);
            }
        }
        Map<Id, Id> siteVisitByRecordId = new Map<Id, Id>();
        if (!lineIds.isEmpty()) {
            for (WorkOrderLineItem line : [
                SELECT Id, WorkOrder.ParentWorkOrderId
                FROM WorkOrderLineItem
                WHERE Id IN :lineIds
            ]) {
                siteVisitByRecordId.put(line.Id, line.WorkOrder?.ParentWorkOrderId);
            }
        }
        if (!workOrderIds.isEmpty()) {
            for (WorkOrder workOrder : [
                SELECT Id, ParentWorkOrderId
                FROM WorkOrder
                WHERE Id IN :workOrderIds
            ]) {
                siteVisitByRecordId.put(workOrder.Id, workOrder.ParentWorkOrderId);
            }
        }
        for (ContentDocumentLink link : pictureLinks) {
            Id siteVisitId = siteVisitByRecordId.get(link.LinkedEntityId);
            if (siteVisitId == null || siteVisitId == link.LinkedEntityId) {
                continue;
            }
            try {
                publishParentLink(link.ContentDocumentId, siteVisitId);
            } catch (Exception ex) {
                Logger.error('MobileDevicePictureLinkHandler.completeMobileAppPictureLinks parent link failed', ex);
                Logger.saveLog();
            }
        }
        if (!lineIds.isEmpty()) {
            WoDebriefIMSchildWOController.refreshMobileDevicePictureCount(lineIds);
        }
    }

    /**
     * @description True when a Mobile Device Picture can be stored on this record.
     * @param recordId Linked record
     * @return True for a Work Order or Work Order Line Item
     */
    private static Boolean isPictureRecord(Id recordId) {
        if (recordId == null) {
            return false;
        }
        Schema.SObjectType recordType = recordId.getSobjectType();
        return recordType == WorkOrderLineItem.SObjectType || recordType == WorkOrder.SObjectType;
    }

    /**
     * @description GW-375 - Turns an event value into an Id.
     * @param value Raw id
     * @return Id, or null when the value is not an id
     */
    private static Id toId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value.trim();
        } catch (Exception ex) {
            return null;
        }
    }

    /**
     * @description GW-375 - One key for a file and the record it is linked to.
     * @param contentDocumentId File
     * @param linkedEntityId Record
     * @return Key
     */
    private static String linkKey(Id contentDocumentId, Id linkedEntityId) {
        return String.valueOf(contentDocumentId) + ':' + String.valueOf(linkedEntityId);
    }

    /**
     * @description GW-375 - The parent link could not be queued.
     */
    public class MobileDevicePictureLinkException extends Exception {}
}