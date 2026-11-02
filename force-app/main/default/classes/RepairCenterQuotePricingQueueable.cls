/**
 * @description Generates the Repair Center quote document after the quote insert commits.
 *              Pricing and pre-approval are bypassed for this sprint so the quote stays
 *              Waiting for Approval. The quote flow enqueues this job after commit.
 */
public with sharing class RepairCenterQuotePricingQueueable implements Queueable, Database.AllowsCallouts {
    public static final String LOGGER_TAG = 'RepairCenterQuotePricing';
    public static final String SCENARIO = 'Repair Center Quote Pricing';

    private static final String PRICING_FLOW_NAME = 'Pricing_SubFlow_ExecutePricing';
    private static final String WORKSTREAM_SERVICE_SALES = 'ServiceSales';
    private static final String CONTEXT_DEFINITION_ID = '11OOu000001Z0cTMAS';
    private static final String CONTEXT_MAPPING_ID = '11jOu000006VrFtIAK';
    private static final String PRICING_PROCEDURE_ID = '9QAOu000000nrKvOAI';

    private final List<Request> requests;

    /**
     * @description Quote and account ids passed from the quote generation flow.
     */
    public class Request {
        @InvocableVariable(
            required=true
            label='Quote Id'
            description='Repair Center Quote to price after the create transaction commits.'
        )
        public Id quoteId;

        @InvocableVariable(
            label='Account Id'
            description='Parent Work Order account passed to pricing.'
        )
        public Id accountId;

        @InvocableVariable(
            label='Bill To Account Id'
            description='Parent Work Order bill-to account passed to pricing.'
        )
        public Id billToAccountId;
    }

    /**
     * @description Enqueues one job for the quotes created in the current transaction.
     * @param pricingRequests Quote and account ids from the quote flow.
     */
    @InvocableMethod(
        label='Enqueue Repair Center Quote Pricing'
        description='Generates the Repair Center quote document after commit. Pricing and pre-approval are bypassed for this sprint.'
        category='Repair Center'
    )
    public static void enqueue(List<Request> pricingRequests) {
        // Nothing to schedule when the flow passes an empty collection.
        if (pricingRequests == null || pricingRequests.isEmpty()) {
            return;
        }
        System.enqueueJob(new RepairCenterQuotePricingQueueable(pricingRequests));
    }

    /**
     * @description Stores the flow requests for the asynchronous transaction.
     * @param pricingRequests Quote and account ids to process.
     */
    public RepairCenterQuotePricingQueueable(List<Request> pricingRequests) {
        this.requests = pricingRequests == null
            ? new List<Request>()
            : new List<Request>(pricingRequests);
    }

    /**
     * @description Generates the document for each quote. Pricing and pre-approval stay
     *              off until those stories return next sprint.
     * @param context Queueable context provided by the platform.
     */
    public void execute(QueueableContext context) {
        Logger.setScenario(SCENARIO);
        try {
            // Each request is an independent quote created by the generation flow.
            for (Request request : requests) {
                // Skip blank rows so one empty invocable input does not stop the job.
                if (request == null || request.quoteId == null) {
                    continue;
                }
                // GW-4585 and GW-4117 are deferred. Skip pricing and pre-approval so the
                // quote remains Waiting for Approval, then generate the document.
                runDocumentGeneration(request.quoteId);
            }
        } catch (Exception e) {
            Logger.error('RepairCenterQuotePricingQueueable.execute', e).addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Starts Pricing SubFlow - Execute Pricing in this committed transaction.
     * @param request Quote and account ids for the pricing subflow.
     */
    private void runPricing(Request request) {
        try {
            Map<String, Object> inputs = new Map<String, Object>();
            inputs.put('varRecordId', String.valueOf(request.quoteId));
            inputs.put('varAccountId', toFlowId(request.accountId));
            inputs.put('varBillToAccountId', toFlowId(request.billToAccountId));
            inputs.put('varWorkstream', WORKSTREAM_SERVICE_SALES);
            inputs.put('varContextDefinitionId', CONTEXT_DEFINITION_ID);
            inputs.put('varContextMappingId', CONTEXT_MAPPING_ID);
            inputs.put('varPricingProcedureId', PRICING_PROCEDURE_ID);

            Flow.Interview pricingInterview = Flow.Interview.createInterview(PRICING_FLOW_NAME, inputs);
            pricingInterview.start();

            Boolean isSuccess = (Boolean) pricingInterview.getVariableValue('varIsSuccess');
            // Pricing failure must not stop pre-approval or document generation.
            if (isSuccess != true) {
                String errorMessage = (String) pricingInterview.getVariableValue('varErrorMessage');
                Logger.error(
                        'Repair Center quote pricing did not succeed. quoteId=' +
                        request.quoteId +
                        ' error=' +
                        errorMessage
                    )
                    .addTag(LOGGER_TAG);
            }
        } catch (Exception e) {
            Logger.error(
                    'RepairCenterQuotePricingQueueable.runPricing quoteId=' + request.quoteId,
                    e
                )
                .addTag(LOGGER_TAG);
        }
    }

    /**
     * @description Evaluates pre-approval limits for the priced quote.
     * @param quoteId Repair Center Quote Id.
     */
    private void runPreApproval(Id quoteId) {
        try {
            RepairCenterQuotePreApprovalService.Request preApprovalRequest =
                new RepairCenterQuotePreApprovalService.Request();
            preApprovalRequest.quoteId = quoteId;
            RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits(
                new List<RepairCenterQuotePreApprovalService.Request>{ preApprovalRequest }
            );
        } catch (Exception e) {
            Logger.error(
                    'RepairCenterQuotePricingQueueable.runPreApproval quoteId=' + quoteId,
                    e
                )
                .addTag(LOGGER_TAG);
        }
    }

    /**
     * @description Generates the Repair Center quote document after pre-approval.
     * @param quoteId Repair Center Quote Id.
     */
    private void runDocumentGeneration(Id quoteId) {
        try {
            RepairCenterDocGenService.DocumentGenerationRequest documentRequest =
                new RepairCenterDocGenService.DocumentGenerationRequest();
            documentRequest.quoteId = quoteId;
            RepairCenterDocGenService.generateDocuments(
                new List<RepairCenterDocGenService.DocumentGenerationRequest>{ documentRequest }
            );
        } catch (Exception e) {
            Logger.error(
                    'RepairCenterQuotePricingQueueable.runDocumentGeneration quoteId=' + quoteId,
                    e
                )
                .addTag(LOGGER_TAG);
        }
    }

    /**
     * @description Converts an Id to the String input used by the pricing flow.
     * @param recordId Account or quote id. Null stays null.
     * @return String value for a flow input variable.
     */
    private static String toFlowId(Id recordId) {
        // Flow string inputs accept a blank value when the work order has no bill-to account.
        if (recordId == null) {
            return null;
        }
        return String.valueOf(recordId);
    }
}