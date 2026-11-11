/**
 * @description GW-4117 / GW-5832: Generates the Repair Center quote document after the quote insert commits.
 *              The pricing procedure is no longer called. Quote line prices are mapped from the Work Order
 *              Line Items, and pre-approval is evaluated in Sub Flow - Generate Repair Center WO Quote.
 */
public with sharing class RepairCenterQuotePricingQueueable implements Queueable, Database.AllowsCallouts {
	public static final String LOGGER_TAG = 'RepairCenterQuotePricing';
	public static final String SCENARIO = 'Repair Center Quote Pricing';

	private final List<Request> requests;

	/**
	 * @description Quote id passed from the quote generation flow.
	 */
	public class Request {
		@InvocableVariable(required=true label='Quote Id' description='Repair Center Quote to generate the document for after the create transaction commits.')
		public Id quoteId;
	}

	/**
	 * @description Enqueues one job for the quotes created in the current transaction.
	 * @param documentRequests Quote ids from the quote flow.
	 */
	@InvocableMethod(label='Enqueue Repair Center Quote Document' description='Generates the Repair Center quote document after the quote insert commits.' category='Repair Center')
	public static void enqueue(List<Request> documentRequests) {
		// Nothing to schedule when the flow passes an empty collection.
		if (documentRequests == null || documentRequests.isEmpty()) return;
		System.enqueueJob(new RepairCenterQuotePricingQueueable(documentRequests));
	}

	/**
	 * @description Stores the flow requests for the asynchronous transaction.
	 * @param documentRequests Quote ids to process.
	 */
	public RepairCenterQuotePricingQueueable(List<Request> documentRequests) {
		this.requests = documentRequests == null ? new List<Request>() : new List<Request>(documentRequests);
	}

	/**
	 * @description Generates the quote document for each quote in one call to the document service.
	 * @param context Queueable context provided by the platform.
	 */
	public void execute(QueueableContext context) {
		Logger.setScenario(SCENARIO);
		List<RepairCenterDocGenService.DocumentGenerationRequest> documentRequests = new List<RepairCenterDocGenService.DocumentGenerationRequest>();
		for (Request request : requests) {
			// Skip blank rows so one empty invocable input does not stop the job.
			if (request?.quoteId == null) continue;
			RepairCenterDocGenService.DocumentGenerationRequest documentRequest = new RepairCenterDocGenService.DocumentGenerationRequest();
			documentRequest.quoteId = request.quoteId;
			documentRequests.add(documentRequest);
		}
		try {
			if (!documentRequests.isEmpty()) RepairCenterDocGenService.generateDocuments(documentRequests);
		} catch (Exception e) {
			Logger.error('RepairCenterQuotePricingQueueable.execute', e).addTag(LOGGER_TAG);
		} finally {
			Logger.saveLog();
		}
	}
}