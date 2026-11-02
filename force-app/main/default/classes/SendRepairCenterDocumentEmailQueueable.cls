/**
 * @description GW-4189 / GW-3591: Starts ContentDocumentLink_AfterSave_SendQuoteEmail after a
 *              Repair Center doc-gen PDF is linked to a Quote or Work Order. Runs in a new
 *              transaction so the email action is not blocked by uncommitted file DML.
 */
public with sharing class SendRepairCenterDocumentEmailQueueable implements Queueable, Database.AllowsCallouts {
    @TestVisible
    private static final String FLOW_API_NAME = 'ContentDocumentLink_AfterSave_SendQuoteEmail';

    private final List<Id> contentDocumentLinkIds;

    /**
     * @description Stores Content Document Link Ids to evaluate for customer email.
     * @param contentDocumentLinkIds ContentDocumentLink Ids linked to a Quote or Work Order
     */
    public SendRepairCenterDocumentEmailQueueable(List<Id> contentDocumentLinkIds) {
        this.contentDocumentLinkIds = contentDocumentLinkIds == null
            ? new List<Id>()
            : new List<Id>(contentDocumentLinkIds);
    }

    /**
     * @description Reloads each file link and starts the email flow.
     * @param context Queueable context
     */
    public void execute(QueueableContext context) {
        if (contentDocumentLinkIds.isEmpty()) {
            return;
        }
        List<ContentDocumentLink> links = ContentDocumentLinksService.selectForRepairCenterDocumentEmail(
            contentDocumentLinkIds
        );
        for (ContentDocumentLink link : links) {
            startEmailFlow(link);
        }
    }

    /**
     * @description Starts the email flow when the file is linked to a Quote or Work Order.
     * @param link Content Document Link to evaluate
     */
    @TestVisible
    static void startEmailFlow(ContentDocumentLink link) {
        if (
            link == null ||
            link.LinkedEntityId == null ||
            !RepairCenterDocumentEmailService.isSupportedLinkedEntity(link.LinkedEntityId)
        ) {
            return;
        }
        Map<String, Object> inputs = new Map<String, Object>{
            'IN_OBJ_ContentDocumentLink' => link
        };
        Flow.Interview interview = Flow.Interview.createInterview(FLOW_API_NAME, inputs);
        interview.start();
    }
}