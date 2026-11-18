/**
 * @description GW-2137: Sends a Complaint Intake to TrackWise through ShoutOut / BOOMI and stamps
 *              Submission Status, Integration Status, Integration Message, and TrackWise Complaint Number.
 *              BOOMI upserts the Part in TrackWise, then creates the complaint with the Part Id, then returns the number.
 */
public with sharing class ComplaintIntakeTrackwiseService {

	private static final String CALLOUT_OPERATION = 'TRACKWISE_CREATE_COMPLAINT_DEV';
	private static final String SERVICE_TIMEOUT_MS = '60000';
	private static final String INTEGRATION_SUCCESS = 'Success Create';
	private static final String INTEGRATION_FAIL = 'Fail Create';
	private static final String SUBMISSION_SUBMITTED = 'Submitted';

	/** GW-2137: Optional ShoutOut response override for unit tests (null = default success mock). */
	@TestVisible
	private static Map<String, Object> testResponseOverride;

	/**
	 * @description GW-2137: Invocable input.
	 */
	public class SubmitRequest {
		@InvocableVariable(required=true label='Complaint Intake Id')
		public Id complaintIntakeId;
		@InvocableVariable(label='Perform Callout' description='If false, only builds JSON (for testing).')
		public Boolean performCallout;
	}

	/**
	 * @description GW-2137: Invocable output.
	 */
	public class SubmitResult {
		@InvocableVariable(label='Success')
		public Boolean success;
		@InvocableVariable(label='Integration Status')
		public String integrationStatus;
		@InvocableVariable(label='Integration Message')
		public String integrationMessage;
		@InvocableVariable(label='TrackWise Complaint Number')
		public String trackwiseComplaintNumber;
		public String requestJson;
		public String responsePayload;
	}

	/**
	 * @description GW-2137: Builds the create complaint JSON, calls BOOMI/TrackWise via SO_Callout, and stamps the intake.
	 * @param requests Complaint Intake submit requests.
	 * @return One result per request.
	 */
	@InvocableMethod(
		label='Complaint Intake - Submit to TrackWise'
		description='GW-2137: Builds the create complaint JSON and calls BOOMI/TrackWise via SO_Callout.'
	)
	public static List<SubmitResult> submitToTrackwise(List<SubmitRequest> requests) {
		List<SubmitResult> results = new List<SubmitResult>();
		if (requests == null) {
			return results;
		}
		for (SubmitRequest req : requests) {
			results.add(processSubmit(req));
		}
		return results;
	}

	@TestVisible
	private static SubmitResult processSubmit(SubmitRequest req) {
		SubmitResult result = new SubmitResult();
		result.success = false;
		Boolean doCallout = req.performCallout == null ? true : req.performCallout;

		try {
			ComplaintIntake__c intake = queryComplaintIntake(req.complaintIntakeId);

			if (String.isNotBlank(intake.TrackwiseComplaintNumber__c)) {
				result.success = true;
				result.integrationStatus = intake.IntegrationStatus__c;
				result.trackwiseComplaintNumber = intake.TrackwiseComplaintNumber__c;
				result.integrationMessage =
					'Already created in TrackWise as ' + intake.TrackwiseComplaintNumber__c + '. Create was not sent again.';
				update new ComplaintIntake__c(Id = intake.Id, SubmissionStatus__c = SUBMISSION_SUBMITTED);
				return result;
			}

			String restBody = JSON.serialize(buildRequestBody(intake));
			result.requestJson = restBody;

			if (!doCallout) {
				result.success = true;
				result.integrationMessage = 'JSON built; callout skipped.';
				return result;
			}

			Map<String, Object> responseMap;
			if (Test.isRunningTest()) {
				responseMap = testResponseOverride != null
					? testResponseOverride
					: new Map<String, Object>{
						  'SO_SUCCESS' => true,
						  'SERVICE_DATA' => new Map<String, Object>{
							  'TrackwiseComplaintNumber' => 'TW-TEST-001',
							  'message' => 'Complaint created.'
						  }
					  };
			} else {
				SO_Callout callout = new SO_Callout();
				callout
					.addToRequestMap(SO_Constants.CALLOUTOPERATION, CALLOUT_OPERATION)
					.addToRequestMap(SO_Constants.SERVICETIMEOUT, SERVICE_TIMEOUT_MS)
					.addToRequestMap(SO_Constants.RESTBODY, restBody);
				callout.callWebService();
				responseMap = callout.serviceResponseMap;
			}

			return applyResponse(intake.Id, result, responseMap);
		} catch (Exception e) {
			result.success = false;
			result.integrationStatus = INTEGRATION_FAIL;
			result.integrationMessage = e.getMessage();
			try {
				stamp(req.complaintIntakeId, INTEGRATION_FAIL, e.getMessage(), null);
			} catch (Exception ignore) {
				// keep original error
			}
			return result;
		}
	}

	/**
	 * @description GW-2137: Request body. BOOMI upserts Part into the TrackWise Parts table, then creates
	 *              Complaint with Product_Number_SKU_Lookup__c set to the Part Id. Part is null when the
	 *              intake has no Asset; BOOMI then skips the upsert and leaves the lookup blank.
	 *              Keys inside Part and Complaint are TrackWise field names.
	 * @param intake Complaint Intake (from queryComplaintIntake).
	 * @return JSON body map.
	 */
	@TestVisible
	private static Map<String, Object> buildRequestBody(ComplaintIntake__c intake) {
		Map<String, Object> part = buildPart(intake);

		Map<String, Object> complaint = new Map<String, Object>{
			'CMPL123CME__Customer__c' => intake.Account__r?.SystemID__c,
			'Customer_Address_ID__c' => intake.Account__r?.OracleAddressId__c,
			'Customer_Primary_Contact_Phone__c' => intake.CustomerPhone__c,
			'Complainant_Name__c' => intake.ComplainantName__c,
			'Customer_Primary_Contact__c' => intake.Contact__r?.Name,
			'Issue_Description__c' => intake.IssueDescription__c,
			'Date_of_Event__c' => formatDate(intake.DateofEvent__c),
			'Date_STERIS_Notified__c' => formatDate(intake.DateNotified__c),
			'Product_Number_SKU_Lookup__c' => null
		};

		return new Map<String, Object>{
			'ComplaintIntakeId' => String.valueOf(intake.Id),
			'ComplaintIntakeNumber' => intake.Name,
			'Part' => part,
			'Complaint' => complaint
		};
	}

	/**
	 * @description GW-2137: TrackWise Parts record from the intake Asset. EQUIPMENT_NUM falls back to the
	 *              Asset Id when the legacy equipment number is blank.
	 */
	private static Map<String, Object> buildPart(ComplaintIntake__c intake) {
		if (intake.Asset__c == null) {
			return null;
		}
		Asset a = intake.Asset__r;
		return new Map<String, Object>{
			'ITEM_NUM' => a?.Product2?.ProductCode,
			'SERIAL_NUM' => a?.SerialNumber,
			'EQUIPMENT_NUM' => String.isNotBlank(a?.LegacyEquipmentNumber__c)
				? a.LegacyEquipmentNumber__c
				: String.valueOf(intake.Asset__c)
		};
	}

	private static String formatDate(Date d) {
		return d == null ? null : Datetime.newInstance(d, Time.newInstance(0, 0, 0, 0)).format('yyyy-MM-dd');
	}

	private static ComplaintIntake__c queryComplaintIntake(Id complaintIntakeId) {
		return [
			SELECT Id, Name, SubmissionStatus__c, IntegrationStatus__c, TrackwiseComplaintNumber__c,
				   Account__c, Account__r.SystemID__c, Account__r.OracleAddressId__c,
				   CustomerPhone__c, ComplainantName__c, Contact__r.Name,
				   IssueDescription__c, DateofEvent__c, DateNotified__c,
				   Asset__c, Asset__r.SerialNumber, Asset__r.LegacyEquipmentNumber__c, Asset__r.Product2.ProductCode
			FROM ComplaintIntake__c
			WHERE Id = :complaintIntakeId
			LIMIT 1
		];
	}

	private static SubmitResult applyResponse(Id intakeId, SubmitResult result, Map<String, Object> responseMap) {
		result.responsePayload = responseMap == null ? null : JSON.serialize(responseMap);

		Boolean soSuccess = responseMap != null && responseMap.get('SO_SUCCESS') == true;
		Object serviceData = responseMap == null ? null : responseMap.get('SERVICE_DATA');
		if (serviceData == null && responseMap != null) {
			serviceData = responseMap.get('SO_RETURN');
		}
		Map<String, Object> data = coerceMap(serviceData);

		try {
			Logger.setScenario('Complaint Intake TrackWise Submit');
			Logger.info(
				new LogMessage(
					'GW-2137 ShoutOut response keys={0}; SERVICE_DATA={1}',
					responseMap == null ? 'null' : String.valueOf(responseMap.keySet()),
					serviceData == null ? 'null' : String.valueOf(serviceData).left(500)
				)
			);
			Logger.saveLog();
		} catch (Exception ignore) {
			// logging must not break submit
		}

		String complaintNumber = findValue(data, new Set<String>{ 'trackwisecomplaintnumber', 'complaintnumber' });
		String message = findValue(data, new Set<String>{ 'message', 'integrationmessage', 'errormessage', 'error' });
		if (String.isBlank(message) && serviceData instanceof String && data == null) {
			message = ((String) serviceData).left(32000);
		}

		if (soSuccess && String.isNotBlank(complaintNumber)) {
			result.success = true;
			result.integrationStatus = INTEGRATION_SUCCESS;
			result.trackwiseComplaintNumber = complaintNumber;
			result.integrationMessage = String.isBlank(message) ? 'TrackWise complaint created.' : message;
			stamp(intakeId, INTEGRATION_SUCCESS, result.integrationMessage, complaintNumber);
		} else {
			result.success = false;
			result.integrationStatus = INTEGRATION_FAIL;
			if (String.isBlank(message)) {
				message = soSuccess
					? 'TrackWise/BOOMI call completed but no complaint number was returned (treated as Fail).'
					: 'TrackWise/BOOMI call failed.';
			}
			result.integrationMessage = message;
			stamp(intakeId, INTEGRATION_FAIL, message, null);
		}
		return result;
	}

	private static void stamp(Id intakeId, String integrationStatus, String integrationMessage, String complaintNumber) {
		ComplaintIntake__c rec = new ComplaintIntake__c(Id = intakeId);
		rec.SubmissionStatus__c = SUBMISSION_SUBMITTED;
		rec.IntegrationStatus__c = integrationStatus;
		rec.IntegrationMessage__c = integrationMessage == null ? null : integrationMessage.left(32768);
		if (complaintNumber != null) {
			rec.TrackwiseComplaintNumber__c = complaintNumber.trim().left(50);
		}
		update rec;
	}

	private static Map<String, Object> coerceMap(Object value) {
		if (value instanceof Map<String, Object>) {
			return (Map<String, Object>) value;
		}
		if (value instanceof String) {
			String s = ((String) value).trim();
			if (s.startsWith('{')) {
				try {
					Object parsed = JSON.deserializeUntyped(s);
					if (parsed instanceof Map<String, Object>) {
						return (Map<String, Object>) parsed;
					}
				} catch (Exception e) {
					return null;
				}
			}
		}
		return null;
	}

	/**
	 * @description Returns the first non-blank value whose key, lower-cased with underscores removed,
	 *              is in the given set. Searches nested maps.
	 */
	private static String findValue(Map<String, Object> data, Set<String> normalizedKeys) {
		if (data == null) {
			return null;
		}
		for (String key : data.keySet()) {
			Object v = data.get(key);
			if (normalizedKeys.contains(key.toLowerCase().replace('_', '')) && v != null && !(v instanceof Map<String, Object>)) {
				String s = String.valueOf(v).trim();
				if (String.isNotBlank(s)) {
					return s;
				}
			}
		}
		for (Object v : data.values()) {
			if (v instanceof Map<String, Object>) {
				String nested = findValue((Map<String, Object>) v, normalizedKeys);
				if (String.isNotBlank(nested)) {
					return nested;
				}
			}
		}
		return null;
	}
}