/**
 * @description GW-2137: Queues the TrackWise create complaint callout after the Complaint Intake save commits.
 *              The record-triggered flow calls enqueue. The queueable performs the callout.
 */
public with sharing class ComplaintIntakeTrackwiseQueueable implements Queueable, Database.AllowsCallouts {
	public List<Id> complaintIntakeIds;

	/**
	 * @description Builds a queueable for one or more Complaint Intakes.
	 * @param complaintIntakeIds Complaint Intake Ids to submit.
	 */
	public ComplaintIntakeTrackwiseQueueable(List<Id> complaintIntakeIds) {
		this.complaintIntakeIds = complaintIntakeIds == null ? new List<Id>() : complaintIntakeIds.clone();
	}

	/**
	 * @description Runs the TrackWise submit after the triggering transaction has committed.
	 * @param context Queueable context.
	 */
	public void execute(QueueableContext context) {
		List<ComplaintIntakeTrackwiseService.SubmitRequest> requests = new List<ComplaintIntakeTrackwiseService.SubmitRequest>();
		for (Id intakeId : complaintIntakeIds) {
			ComplaintIntakeTrackwiseService.SubmitRequest req = new ComplaintIntakeTrackwiseService.SubmitRequest();
			req.complaintIntakeId = intakeId;
			req.performCallout = true;
			requests.add(req);
		}
		if (!requests.isEmpty()) {
			ComplaintIntakeTrackwiseService.submitToTrackwise(requests);
		}
	}

	/**
	 * @description Flow input for one Complaint Intake.
	 */
	public class Request {
		@InvocableVariable(required=true label='Complaint Intake Id')
		public Id complaintIntakeId;
	}

	/**
	 * @description GW-2137: Invocable entry for ComplaintIntake_AfterSave_SubmitToTrackwise.
	 * @param requests Complaint Intake ids from the record-triggered flow.
	 */
	@InvocableMethod(
		label='Complaint Intake - Queue TrackWise Create'
		description='GW-2137: Queues the TrackWise create complaint callout after the Complaint Intake save commits.'
	)
	public static void enqueue(List<Request> requests) {
		List<Id> ids = new List<Id>();
		if (requests != null) {
			for (Request req : requests) {
				if (req != null && req.complaintIntakeId != null) {
					ids.add(req.complaintIntakeId);
				}
			}
		}
		if (!ids.isEmpty()) {
			System.enqueueJob(new ComplaintIntakeTrackwiseQueueable(ids));
		}
	}
}