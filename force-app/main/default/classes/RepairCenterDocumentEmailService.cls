/**
 * @description GW-4189 / GW-3591: Enqueues Repair Center customer email after a
 *              Design Document PDF is linked to a Quote or Work Order.
 */
public with sharing class RepairCenterDocumentEmailService {
    @TestVisible
    private static final Pattern QUOTE_DOC_GEN_TITLE_PATTERN = Pattern.compile(
        '^(\\d+-.*-V\\d+|RepairCenterQuote-.+|0Q0.+)$'
    );
    @TestVisible
    private static final Pattern WORK_ORDER_DOC_GEN_TITLE_PATTERN = Pattern.compile(
        '^(\\d+-.*|RepairCenterWorkOrder.*|0WO.+)$'
    );
    @TestVisible
    private static final Pattern QUOTE_VERSIONED_TITLE_PATTERN = Pattern.compile('^.+-.*-V\\d+$');

    /**
     * @description After a Repair Center doc-gen PDF is linked to a Quote or Work Order,
     *              enqueue email send so the PDF is committed before the email goes out.
     * @param links Newly inserted ContentDocumentLink records.
     */
    public static void handleNewContentDocumentLinks(List<ContentDocumentLink> links) {
        if (links == null || links.isEmpty()) {
            return;
        }

        List<ContentDocumentLink> candidateLinks = new List<ContentDocumentLink>();
        Set<Id> contentDocumentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            if (
                link == null ||
                link.Id == null ||
                link.LinkedEntityId == null ||
                link.ContentDocumentId == null ||
                !isSupportedLinkedEntity(link.LinkedEntityId)
            ) {
                continue;
            }
            candidateLinks.add(link);
            contentDocumentIds.add(link.ContentDocumentId);
        }
        if (candidateLinks.isEmpty()) {
            return;
        }

        Map<Id, String> titleByContentDocumentId = getLatestPdfTitlesByContentDocumentId(
            contentDocumentIds
        );
        List<Id> eligibleLinkIds = new List<Id>();
        for (ContentDocumentLink link : candidateLinks) {
            String title = titleByContentDocumentId.get(link.ContentDocumentId);
            if (isRepairCenterDocGenTitle(title, link.LinkedEntityId)) {
                eligibleLinkIds.add(link.Id);
            }
        }
        if (eligibleLinkIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new SendRepairCenterDocumentEmailQueueable(eligibleLinkIds));
    }

    /**
     * @description True when the linked entity is a Quote or Work Order.
     * @param linkedEntityId Linked entity Id from ContentDocumentLink.
     * @return True when Quote or Work Order.
     */
    public static Boolean isSupportedLinkedEntity(Id linkedEntityId) {
        if (linkedEntityId == null) {
            return false;
        }
        Schema.SObjectType linkedType = linkedEntityId.getSObjectType();
        return linkedType == Quote.SObjectType || linkedType == WorkOrder.SObjectType;
    }

    /**
     * @description True when Title matches Repair Center Quote or Work Order doc-gen naming.
     * @param title Latest ContentVersion Title.
     * @param linkedEntityId Quote or Work Order Id.
     * @return True when the file should trigger customer email.
     */
    @TestVisible
    public static Boolean isRepairCenterDocGenTitle(String title, Id linkedEntityId) {
        if (String.isBlank(title) || linkedEntityId == null) {
            return false;
        }
        Schema.SObjectType linkedType = linkedEntityId.getSObjectType();
        if (linkedType == Quote.SObjectType) {
            return QUOTE_DOC_GEN_TITLE_PATTERN.matcher(title).matches();
        }
        if (linkedType == WorkOrder.SObjectType) {
            if (QUOTE_VERSIONED_TITLE_PATTERN.matcher(title).matches()) {
                return false;
            }
            return WORK_ORDER_DOC_GEN_TITLE_PATTERN.matcher(title).matches();
        }
        return false;
    }

    private static Map<Id, String> getLatestPdfTitlesByContentDocumentId(
        Set<Id> contentDocumentIds
    ) {
        Map<Id, String> titleByContentDocumentId = new Map<Id, String>();
        if (contentDocumentIds == null || contentDocumentIds.isEmpty()) {
            return titleByContentDocumentId;
        }
        for (
            ContentVersion version : ContentVersionsService.selectLatestPdfsByContentDocumentIds(
                contentDocumentIds
            )
        ) {
            if (!titleByContentDocumentId.containsKey(version.ContentDocumentId)) {
                titleByContentDocumentId.put(version.ContentDocumentId, version.Title);
            }
        }
        return titleByContentDocumentId;
    }
}