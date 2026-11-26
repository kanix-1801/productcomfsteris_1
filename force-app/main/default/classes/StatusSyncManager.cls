/**
 * @author Uptima
 * @date 2026-11-24
 * @description Genesys CX Cloud enhanced status sync extension (GW-6502 / GW-6581).
 * Maps Omni-Channel ServicePresenceStatus values to Genesys Cloud presence definitions
 * using CustomerTechnicalCareSettings__mdt.CoreSetting.GenesysStatusMap__c. Omni status
 * Ids are resolved by DeveloperName at runtime. Wire this class under Genesys Admin
 * Settings > Status Management > Enhanced Status Syncing.
 * @see https://developer.genesys.cloud/blueprints/enhanced-status-syncing-with-salesforce-service-cloud-voice/
 */
global with sharing class StatusSyncManager implements genesyscloud.GenesysSCVExtension.Status {
	private static final String SCENARIO = 'Genesys Status Sync';
	private static final String SETTINGS_DEVELOPER_NAME = 'CoreSetting';

	@TestVisible
	private static Map<String, String> genesysStatusMapOverride;
	@TestVisible
	private static String genesysStatusMapJsonOverride;
	@TestVisible
	private static List<ServicePresenceStatus> presenceStatusesOverride;

	private static Map<String, String> genesysIdByOmniDevName;
	private static Map<String, Id> omniIdByDevName;
	private static Map<String, String> omniDevNameByGenesysId;
	private static Map<String, String> omniDevNameByMasterLabel;
	private static Boolean mapsLoaded = false;

	/**
	 * @description Maps an Omni-Channel status change to a Genesys Cloud presence Id.
	 * @param data JSON payload from the Genesys CX Cloud package
	 * @return JSON response with target Salesforce and Genesys status Ids
	 */
	global String onSalesforceStatusChange(String data) {
		Logger.setScenario(SCENARIO);
		try {
			IncomingStatusChange statusUpdate = (IncomingStatusChange) JSON.deserialize(
				data,
				IncomingStatusChange.class
			);
			loadMaps();

			String salesforceTargetStatusId = statusUpdate.salesforceStatus.targetStatus.statusId;
			String genesysTargetId = statusUpdate.genesysCloudStatus.targetStatus.id;
			String salesforceResponseTargetStatusId = salesforceTargetStatusId;
			String genesysResponseTargetStatusId = genesysTargetId;

			String omniDevName = resolveOmniDeveloperName(statusUpdate.salesforceStatus.targetStatus);
			if (String.isBlank(omniDevName)) {
				Logger.warn('StatusSyncManager.onSalesforceStatusChange: Offline / unresolved Omni status');
			} else if (genesysIdByOmniDevName.containsKey(omniDevName)) {
				genesysResponseTargetStatusId = genesysIdByOmniDevName.get(omniDevName);
			} else {
				Logger.warn(
					new LogMessage(
						'StatusSyncManager.onSalesforceStatusChange: unhandled Omni status {0}',
						omniDevName
					)
				);
			}

			return JSON.serialize(
				new Response(genesysResponseTargetStatusId, salesforceResponseTargetStatusId)
			);
		} catch (Exception e) {
			Logger.error('StatusSyncManager.onSalesforceStatusChange: Unexpected error.', e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Maps a Genesys Cloud presence change to a Salesforce ServicePresenceStatus Id.
	 * @param data JSON payload from the Genesys CX Cloud package
	 * @return JSON response with target Salesforce and Genesys status Ids
	 */
	global String onGenesysCloudStatusChange(String data) {
		Logger.setScenario(SCENARIO);
		try {
			IncomingStatusChange statusUpdate = (IncomingStatusChange) JSON.deserialize(
				data,
				IncomingStatusChange.class
			);
			loadMaps();

			String salesforceTargetStatusId = statusUpdate.salesforceStatus.targetStatus.statusId;
			String genesysTargetId = statusUpdate.genesysCloudStatus.targetStatus.id;
			String salesforceResponseTargetStatusId = salesforceTargetStatusId;
			String genesysResponseTargetStatusId = genesysTargetId;

			String omniDevName = omniDevNameByGenesysId.get(genesysTargetId);
			if (String.isBlank(omniDevName)) {
				Logger.warn(
					new LogMessage(
						'StatusSyncManager.onGenesysCloudStatusChange: unhandled Genesys id {0}',
						genesysTargetId
					)
				);
			} else if (!omniIdByDevName.containsKey(omniDevName)) {
				Logger.warn(
					new LogMessage(
						'StatusSyncManager.onGenesysCloudStatusChange: Omni status {0} not found in org',
						omniDevName
					)
				);
			} else {
				salesforceResponseTargetStatusId = omniIdByDevName.get(omniDevName);
			}

			return JSON.serialize(
				new Response(genesysResponseTargetStatusId, salesforceResponseTargetStatusId)
			);
		} catch (Exception e) {
			Logger.error('StatusSyncManager.onGenesysCloudStatusChange: Unexpected error.', e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Clears cached maps so the next call reloads CMDT and Omni statuses.
	 */
	@TestVisible
	private static void resetMaps() {
		mapsLoaded = false;
		genesysIdByOmniDevName = null;
		omniIdByDevName = null;
		omniDevNameByGenesysId = null;
		omniDevNameByMasterLabel = null;
	}

	private static void loadMaps() {
		if (mapsLoaded) {
			return;
		}

		genesysIdByOmniDevName = loadGenesysStatusMap();
		omniIdByDevName = new Map<String, Id>();
		omniDevNameByGenesysId = new Map<String, String>();
		omniDevNameByMasterLabel = new Map<String, String>();

		for (String omniDevName : genesysIdByOmniDevName.keySet()) {
			String genesysId = genesysIdByOmniDevName.get(omniDevName);
			if (String.isNotBlank(genesysId)) {
				omniDevNameByGenesysId.put(genesysId, omniDevName);
			}
		}

		for (ServicePresenceStatus presenceStatus : queryPresenceStatuses(genesysIdByOmniDevName.keySet())) {
			omniIdByDevName.put(presenceStatus.DeveloperName, presenceStatus.Id);
			if (String.isNotBlank(presenceStatus.MasterLabel)) {
				omniDevNameByMasterLabel.put(presenceStatus.MasterLabel.toUpperCase(), presenceStatus.DeveloperName);
			}
		}

		mapsLoaded = true;
	}

	private static Map<String, String> loadGenesysStatusMap() {
		if (genesysStatusMapOverride != null) {
			return new Map<String, String>(genesysStatusMapOverride);
		}

		String rawJson = genesysStatusMapJsonOverride;
		if (rawJson == null) {
			CustomerTechnicalCareSettings__mdt settings = CustomerTechnicalCareSettings__mdt.getInstance(
				SETTINGS_DEVELOPER_NAME
			);
			rawJson = settings == null ? null : settings.GenesysStatusMap__c;
		}
		if (String.isBlank(rawJson)) {
			Logger.warn(
				'StatusSyncManager: GenesysStatusMap__c missing on CustomerTechnicalCareSettings.CoreSetting'
			);
			return new Map<String, String>();
		}

		try {
			Map<String, Object> raw = (Map<String, Object>) JSON.deserializeUntyped(rawJson);
			Map<String, String> parsed = new Map<String, String>();
			for (String key : raw.keySet()) {
				Object value = raw.get(key);
				if (value != null) {
					parsed.put(key, String.valueOf(value));
				}
			}
			return parsed;
		} catch (Exception e) {
			Logger.error('StatusSyncManager: failed to parse GenesysStatusMap__c.', e);
			return new Map<String, String>();
		}
	}

	private static List<ServicePresenceStatus> queryPresenceStatuses(Set<String> developerNames) {
		if (presenceStatusesOverride != null) {
			return presenceStatusesOverride;
		}
		if (developerNames == null || developerNames.isEmpty()) {
			return new List<ServicePresenceStatus>();
		}
		return [
			SELECT Id, DeveloperName, MasterLabel
			FROM ServicePresenceStatus
			WHERE DeveloperName IN :developerNames AND IsDeleted = FALSE
		];
	}

	private static String resolveOmniDeveloperName(IncomingSalesforceStatusObj targetStatus) {
		if (targetStatus == null) {
			return null;
		}
		if (String.isNotBlank(targetStatus.statusApiName)) {
			return targetStatus.statusApiName;
		}
		if (String.isNotBlank(targetStatus.statusName)) {
			String byLabel = omniDevNameByMasterLabel.get(targetStatus.statusName.toUpperCase());
			if (String.isNotBlank(byLabel)) {
				return byLabel;
			}
		}
		return null;
	}

	/**
	 * @description Response envelope expected by Genesys enhanced status sync.
	 */
	public class Response {
		public ResponseGenesysCloudStatusObj genesysCloudStatus;
		public ResponseSalesforceStatusObj salesforceStatus;

		/**
		 * @description Builds the package response for both target statuses.
		 * @param genesysResponseTargetStatusId Genesys presence definition Id
		 * @param salesforceResponseTargetStatusId Salesforce ServicePresenceStatus Id
		 */
		public Response(String genesysResponseTargetStatusId, String salesforceResponseTargetStatusId) {
			this.genesysCloudStatus = new ResponseGenesysCloudStatusObj(genesysResponseTargetStatusId);
			this.salesforceStatus = new ResponseSalesforceStatusObj(salesforceResponseTargetStatusId);
		}
	}

	/**
	 * @description Genesys target status Id wrapper.
	 */
	public class ResponseGenesysCloudStatus {
		public String id;

		/**
		 * @description Sets the Genesys target presence Id.
		 * @param id Genesys presence definition Id
		 */
		public ResponseGenesysCloudStatus(String id) {
			this.id = id;
		}
	}

	/**
	 * @description Genesys targetStatus object wrapper.
	 */
	public class ResponseGenesysCloudStatusObj {
		public ResponseGenesysCloudStatus targetStatus;

		/**
		 * @description Wraps the Genesys target status.
		 * @param genesysResponseTargetStatusId Genesys presence definition Id
		 */
		public ResponseGenesysCloudStatusObj(String genesysResponseTargetStatusId) {
			this.targetStatus = new ResponseGenesysCloudStatus(genesysResponseTargetStatusId);
		}
	}

	/**
	 * @description Salesforce target status Id wrapper.
	 */
	public class ResponseSalesforceStatus {
		public String statusId;

		/**
		 * @description Sets the Salesforce target status Id.
		 * @param statusId ServicePresenceStatus Id
		 */
		public ResponseSalesforceStatus(String statusId) {
			this.statusId = statusId;
		}
	}

	/**
	 * @description Salesforce targetStatus object wrapper.
	 */
	public class ResponseSalesforceStatusObj {
		public ResponseSalesforceStatus targetStatus;

		/**
		 * @description Wraps the Salesforce target status.
		 * @param salesforceResponseTargetStatusId ServicePresenceStatus Id
		 */
		public ResponseSalesforceStatusObj(String salesforceResponseTargetStatusId) {
			this.targetStatus = new ResponseSalesforceStatus(salesforceResponseTargetStatusId);
		}
	}

	/**
	 * @description Incoming status-change payload from the Genesys package.
	 */
	public class IncomingStatusChange {
		public IncomingSalesforceStatus salesforceStatus;
		public IncomingGenesysCloudStatus genesysCloudStatus;
	}

	/**
	 * @description Salesforce current/target status fields on the incoming payload.
	 */
	public class IncomingSalesforceStatusObj {
		public String statusApiName;
		public String statusId;
		public String statusName;
	}

	/**
	 * @description Salesforce status block on the incoming payload.
	 */
	public class IncomingSalesforceStatus {
		public IncomingSalesforceStatusObj targetStatus;
		public IncomingSalesforceStatusObj currentStatus;
	}

	/**
	 * @description Genesys current/target presence fields on the incoming payload.
	 */
	public class IncomingGenesysCloudStatusObj {
		public String id;
		public String systemPresence;
	}

	/**
	 * @description Genesys status block on the incoming payload.
	 */
	public class IncomingGenesysCloudStatus {
		public IncomingGenesysCloudStatusObj targetStatus;
		public IncomingGenesysCloudStatusObj currentStatus;
	}
}