/**
 * @author Sagar Anand
 * @date 2026-11-05
 * @description GW-2707: Processes technician-to-district realignment for the next fiscal year from the Tech District
 *              Alignment Excel file. Validates the technician HRIS ID (ServiceResource.ExternalID__c), the current
 *              territory membership and the ASM HRIS IDs (User.EmployeeNumber__c). Creates next-year territories,
 *              updates Territory Managers, ends the current membership at the time of upload and adds the
 *              technician to the next-year territory from the first day of the next fiscal year.
 *              Processes only IPTLS, Low Temp, Procedural and Endoscopy territories.
 *              Invalid rows are skipped and written to a user-specific error file, which is emailed to the
 *              uploader. "-" is treated as blank; name columns are reference-only.
 *              User-facing problems are thrown as AuraHandledException; unexpected errors are logged here.
 * @group Field Service
 * @see TechDistrictAlignmentController
 */
public with sharing class TechDistrictAlignmentService {
	public static final String TEMPLATE_TITLE = 'Tech District Alignment Template';
	public static final String TEMPLATE_RESOURCE_NAME = 'TechDistrictAlignmentTemplate';
	public static final String TEMPLATE_FILE_NAME = 'Tech_District_Alignment_Template.xlsx';
	public static final String ERROR_FILE_TITLE = 'Tech District Alignment Errors';
	public static final String ERROR_FILE_NAME = 'Tech_District_Alignment_Errors.csv';
	public static final String DOWNLOAD_URL_PREFIX = '/sfc/servlet.shepherd/document/download/';
	public static final Set<String> SUPPORTED_TERRITORY_TYPES = new Set<String>{
		'IPTLS',
		'Low Temp',
		'Procedural',
		'Endoscopy'
	};
	public static final List<String> LOG_TAGS = new List<String>{
		'Service Territory',
		'Service Territory Member',
		'Service Resource'
	};
	@TestVisible
	private static final Integer MAX_ROWS = 2000;
	@TestVisible
	private static Date runDate = Date.today();
	private static final Integer NAME_MAX_LENGTH = 80;
	private static final String LOG_SCENARIO = 'Tech District Alignment';
	private static final List<String> TERRITORY_FIELDS = new List<String>{
		'Id',
		'Name',
		'RegionNumber__c',
		'TerritoryType__c',
		'TerritoryManager__c',
		'ParentTerritoryId',
		'OperatingHoursId',
		'IsActive'
	};
	private static final String PRIMARY_MEMBER = 'P';
	private static final String SECONDARY_MEMBER = 'S';
	private static final List<String> TECH_HRIS_COLUMNS = new List<String>{
		'techhris',
		'techhrisid',
		'techhrisnumber'
	};
	private static final List<String> CURRENT_TERRITORY_COLUMNS = new List<String>{
		'currentterritory',
		'currentterritoryid',
		'currentterritorynumber'
	};
	private static final List<String> CURRENT_ASM_HRIS_COLUMNS = new List<String>{
		'currentasmhris',
		'currentasmhrisid',
		'currentasmhrisnumber'
	};
	private static final List<String> NEXT_TERRITORY_COLUMNS = new List<String>{
		'nextyearterritory',
		'nextyearterritoryid',
		'nextyearterritorynumber'
	};
	private static final List<String> NEXT_ASM_HRIS_COLUMNS = new List<String>{
		'nextyearasmhris',
		'nextyearasmhrisid',
		'nextyearasmhrisnumber'
	};

	/**
	 * @description Counts, skip messages and error file returned to the LWC after Process Data.
	 */
	public class ProcessResult {
		@AuraEnabled
		public Integer processedCount = 0;
		@AuraEnabled
		public Integer movedCount = 0;
		@AuraEnabled
		public Integer territoryCreatedCount = 0;
		@AuraEnabled
		public Integer managerUpdatedCount = 0;
		@AuraEnabled
		public Integer unchangedCount = 0;
		@AuraEnabled
		public Integer skippedCount = 0;
		@AuraEnabled
		public List<String> errors = new List<String>();
		@AuraEnabled
		public Id errorFileDocumentId;
		@AuraEnabled
		public Boolean emailSent = false;
		@AuraEnabled
		public Date nextFiscalYearStart;
		@AuraEnabled
		public String summary;
	}

	private class AlignmentRow {
		Integer rowNumber;
		List<String> cells;
		String techHris;
		String currentTerritory;
		String currentAsmHris;
		String nextTerritory;
		String nextAsmHris;
		String errorMessage;
		ServiceResource resource;
		ServiceTerritoryMember currentMember;
		ServiceTerritory targetTerritory;
		Boolean createMember = false;
		Boolean endMember = false;
		Boolean updatesManager = false;
	}

	/**
	 * @description Returns the template file, copying the packaged template into Salesforce Files and sharing it
	 *              with all internal users the first time. To ship a new template, upload it to Files and put its
	 *              Id on the org default FieldServiceBackofficeConfig__c.TechDistrictAlignmentTemplateId__c.
	 * @return ContentDocument Id of the template file.
	 * @throws AuraHandledException When neither a stored template nor the packaged template exists.
	 */
	public static Id ensureTemplateDocumentId() {
		try {
			FieldServiceBackofficeConfig__c config = FieldServiceBackofficeConfig__c.getOrgDefaults();
			String storedId = config.TechDistrictAlignmentTemplateId__c;
			Id documentId = PlatformUtilities.parseId(PlatformUtilities.trimToNull(storedId));
			if (isAccessibleDocument(documentId)) {
				return documentId;
			}
			List<ContentDocument> titledDocs = ContentDocumentsSelector.selectLatestByTitle(TEMPLATE_TITLE);
			documentId = titledDocs.isEmpty() ? createTemplateDocument() : titledDocs[0].Id;
			if (config.Id == null) {
				config.SetupOwnerId = UserInfo.getOrganizationId();
			}
			config.TechDistrictAlignmentTemplateId__c = documentId;
			// System mode: back-office users have no edit access to custom settings.
			Database.upsert(config, AccessLevel.SYSTEM_MODE);
			return documentId;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description ContentDocument Id of the running user's error file, or null before their first upload.
	 * @return ContentDocument Id, or null.
	 */
	public static Id errorFileDocumentId() {
		try {
			String storedId = FieldServiceBackofficeConfig__c.getInstance().TechDistrictAlignmentErrorFileId__c;
			Id documentId = PlatformUtilities.parseId(PlatformUtilities.trimToNull(storedId));
			return isAccessibleDocument(documentId) ? documentId : null;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	private static Id createTemplateDocument() {
		List<StaticResource> resources = StaticResourcesSelector.selectByName(TEMPLATE_RESOURCE_NAME);
		if (resources.isEmpty()) {
			throw PlatformUtilities.buildAuraException(Label.TDA_TemplateUnavailable);
		}
		ContentVersion version = new ContentVersion(
			Title = TEMPLATE_TITLE,
			PathOnClient = TEMPLATE_FILE_NAME,
			VersionData = resources[0].Body,
			IsMajorVersion = true
		);
		Database.insert(version, AccessLevel.USER_MODE);
		Id documentId = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0].ContentDocumentId;
		// Shared with the whole org so every back-office user downloads the same template.
		Database.insert(
			new ContentDocumentLink(
				ContentDocumentId = documentId,
				LinkedEntityId = UserInfo.getOrganizationId(),
				ShareType = 'V',
				Visibility = 'AllUsers'
			),
			AccessLevel.USER_MODE
		);
		return documentId;
	}

	private static Boolean isAccessibleDocument(Id documentId) {
		return documentId != null &&
			!ContentDocumentsSelector.selectIdAndTitleByIds(new Set<Id>{ documentId }).isEmpty();
	}

	/**
	 * @description First day of the next fiscal year, from the org's fiscal year start month: this year's start
	 *              when it is still ahead, otherwise next year's.
	 * @return Next fiscal year start date.
	 */
	@TestVisible
	private static Date nextFiscalYearStart() {
		Organization org = (Organization) SoqlQueryBuilder.fromObject('Organization')
			.selectField('FiscalYearStartMonth')
			.first();
		Date thisYearStart = Date.newInstance(runDate.year(), org.FiscalYearStartMonth, 1);
		return runDate < thisYearStart ? thisYearStart : thisYearStart.addYears(1);
	}

	/**
	 * @description Midnight (running user's time zone) at the start of the next fiscal year.
	 * @return Effective start date for new Service Territory Members.
	 */
	@TestVisible
	private static Datetime nextFiscalYearStartDatetime() {
		return Datetime.newInstance(nextFiscalYearStart(), Time.newInstance(0, 0, 0, 0));
	}

	/**
	 * @description Processes the uploaded file, writes the error file and emails it to the running user.
	 *              Side effects: inserts/updates ServiceTerritory and ServiceTerritoryMember records, adds a
	 *              version to the user's error file, upserts the user-level custom setting and sends an email.
	 * @param contentDocumentId Salesforce Files document Id from lightning-file-upload.
	 * @return Counts, row-level skip messages and the error file Id.
	 * @throws AuraHandledException When the file is missing, unreadable, lacks required columns or
	 *         exceeds the row limit.
	 */
	public static ProcessResult processUpload(Id contentDocumentId) {
		Logger.setScenario(LOG_SCENARIO);
		try {
			List<List<String>> table = readUploadedFile(contentDocumentId);
			List<AlignmentRow> rows = toRows(table);
			ProcessResult result = new ProcessResult();
			result.processedCount = rows.size();
			result.nextFiscalYearStart = nextFiscalYearStart();
			applyRows(rows, result);

			for (AlignmentRow row : rows) {
				if (row.errorMessage != null) {
					result.skippedCount++;
					List<Object> rowErrorParams = new List<Object>{ String.valueOf(row.rowNumber), row.errorMessage };
					result.errors.add(String.format(Label.TDA_RowError, rowErrorParams));
				}
			}
			result.summary = String.format(
				Label.TDA_Summary,
				new List<Object>{
					String.valueOf(result.processedCount),
					String.valueOf(result.movedCount),
					String.valueOf(result.territoryCreatedCount),
					String.valueOf(result.managerUpdatedCount),
					String.valueOf(result.unchangedCount),
					String.valueOf(result.skippedCount)
				}
			);

			ContentVersion errorFile = writeErrorFile(table[0], rows);
			result.errorFileDocumentId = errorFile.ContentDocumentId;
			result.emailSent = sendResultEmail(result, errorFile.Id);
			Logger.info('Tech District Alignment ' + result.summary).addTags(LOG_TAGS);
			return result;
		} catch (Exception e) {
			logUnexpectedError(e);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Logs an unexpected error. User messages (AuraHandledException) are shown to the user in the
	 *              screen they're using, so they aren't logged.
	 */
	private static void logUnexpectedError(Exception e) {
		if (!(e instanceof AuraHandledException)) {
			Logger.setScenario(LOG_SCENARIO);
			Logger.error('Tech District Alignment failed', e).addTags(LOG_TAGS);
		}
	}

	/**
	 * @description Reads the first worksheet of the uploaded Excel (.xlsx) file.
	 */
	private static List<List<String>> readUploadedFile(Id contentDocumentId) {
		List<ContentVersion> versions = ContentVersionsSelector.selectLatestByContentDocumentId(contentDocumentId);
		if (versions.isEmpty() || versions[0].FileExtension?.toLowerCase() != 'xlsx') {
			throw PlatformUtilities.buildAuraException(Label.TDA_FileUnreadable);
		}
		try {
			return ExcelFileParser.readFirstSheet(versions[0].VersionData);
		} catch (ExcelFileParser.ParseException e) {
			throw PlatformUtilities.buildAuraException(Label.TDA_FileUnreadable);
		}
	}

	private static void applyRows(List<AlignmentRow> rows, ProcessResult result) {
		AlignmentPlan plan = new AlignmentPlan(rows);
		for (AlignmentRow row : rows) {
			row.errorMessage = plan.planRow(row);
		}
		result.unchangedCount = plan.unchangedCount;

		List<Database.SaveResult> saveResults = Database.insert(plan.newTerritories, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (!saveResults[i].isSuccess()) {
				ServiceTerritory failed = plan.newTerritories[i];
				List<Object> params = new List<Object>{ failed.RegionNumber__c, firstError(saveResults[i]) };
				failRows(
					plan.rowsByNewTerritory.get(key(failed.RegionNumber__c)),
					String.format(Label.TDA_TerritoryCreateFailed, params)
				);
			}
		}
		result.territoryCreatedCount =
			plan.newTerritories.size() - PlatformUtilities.logSaveFailures(plan.newTerritories, saveResults);

		List<ServiceTerritory> managerUpdates = plan.managerUpdateById.values();
		saveResults = Database.update(managerUpdates, false, AccessLevel.USER_MODE);
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (!saveResults[i].isSuccess()) {
				failRows(
					plan.rowsByManagerUpdate.get(managerUpdates[i].Id),
					String.format(Label.TDA_ManagerUpdateFailed, new List<Object>{ firstError(saveResults[i]) })
				);
			}
		}
		result.managerUpdatedCount =
			managerUpdates.size() - PlatformUtilities.logSaveFailures(managerUpdates, saveResults);

		// End the current membership before creating the next year one: Salesforce rejects a new primary
		// membership while the resource's current primary membership is still open-ended (date overlap).
		Datetime endDatetime = Datetime.now();
		List<ServiceTerritoryMember> endedMembers = new List<ServiceTerritoryMember>();
		List<AlignmentRow> endedMemberRows = new List<AlignmentRow>();
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && row.endMember) {
				endedMembers.add(new ServiceTerritoryMember(Id = row.currentMember.Id, EffectiveEndDate = endDatetime));
				endedMemberRows.add(row);
			}
		}
		saveResults = Database.update(endedMembers, false, AccessLevel.USER_MODE);
		PlatformUtilities.logSaveFailures(endedMembers, saveResults);
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (!saveResults[i].isSuccess()) {
				endedMemberRows[i].errorMessage = String.format(
					Label.TDA_MemberEndFailed,
					new List<Object>{ firstError(saveResults[i]) }
				);
			}
		}

		Datetime startDatetime = nextFiscalYearStartDatetime();
		List<ServiceTerritoryMember> newMembers = new List<ServiceTerritoryMember>();
		List<AlignmentRow> newMemberRows = new List<AlignmentRow>();
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && row.createMember) {
				newMembers.add(buildMember(row, startDatetime));
				newMemberRows.add(row);
			}
		}
		saveResults = Database.insert(newMembers, false, AccessLevel.USER_MODE);
		PlatformUtilities.logSaveFailures(newMembers, saveResults);
		List<ServiceTerritoryMember> restoredMembers = new List<ServiceTerritoryMember>();
		for (Integer i = 0; i < saveResults.size(); i++) {
			if (!saveResults[i].isSuccess()) {
				AlignmentRow row = newMemberRows[i];
				row.errorMessage = String.format(
					Label.TDA_MemberCreateFailed,
					new List<Object>{ firstError(saveResults[i]) }
				);
				if (row.endMember) {
					restoredMembers.add(
						new ServiceTerritoryMember(
							Id = row.currentMember.Id,
							EffectiveEndDate = row.currentMember.EffectiveEndDate
						)
					);
				}
			}
		}
		// Undo the end date so the technician keeps the current territory when the move failed.
		Database.update(restoredMembers, false, AccessLevel.USER_MODE);

		for (AlignmentRow row : rows) {
			if (row.errorMessage == null && (row.createMember || row.endMember)) {
				result.movedCount++;
			}
		}
	}

	private static void failRows(List<AlignmentRow> rows, String message) {
		for (AlignmentRow row : rows) {
			if (row.errorMessage == null) {
				row.errorMessage = message;
			}
		}
	}

	private static String firstError(Database.SaveResult saveResult) {
		return saveResult.getErrors()[0].getMessage();
	}

	private static ServiceTerritoryMember buildMember(AlignmentRow row, Datetime startDatetime) {
		String memberType = row.currentMember.TerritoryType == SECONDARY_MEMBER ? SECONDARY_MEMBER : PRIMARY_MEMBER;
		return new ServiceTerritoryMember(
			ServiceResourceId = row.resource.Id,
			ServiceTerritoryId = row.targetTerritory.Id,
			EffectiveStartDate = startDatetime,
			TerritoryType = memberType,
			OperatingHoursId = row.currentMember.OperatingHoursId
		);
	}

	/**
	 * @description Looks up every technician, user, territory and membership referenced by the file once, then
	 *              turns each row into territory / manager / membership changes, no change, or an error message.
	 */
	private class AlignmentPlan {
		Datetime now = Datetime.now();
		Datetime startOfToday = Datetime.newInstance(Date.today(), Time.newInstance(0, 0, 0, 0));
		Map<String, User> userByHris = new Map<String, User>();
		Map<String, ServiceResource> resourceByExternalId = new Map<String, ServiceResource>();
		Map<String, ServiceTerritory> territoryByNumber = new Map<String, ServiceTerritory>();
		Map<String, List<ServiceTerritoryMember>> membersByKey = new Map<String, List<ServiceTerritoryMember>>();
		Set<Id> claimedResourceIds = new Set<Id>();
		Map<Id, Id> requestedManagerByTerritoryId = new Map<Id, Id>();
		Map<String, ServiceTerritory> newTerritoryByNumber = new Map<String, ServiceTerritory>();
		List<ServiceTerritory> newTerritories = new List<ServiceTerritory>();
		Map<String, List<AlignmentRow>> rowsByNewTerritory = new Map<String, List<AlignmentRow>>();
		Map<Id, ServiceTerritory> managerUpdateById = new Map<Id, ServiceTerritory>();
		Map<Id, List<AlignmentRow>> rowsByManagerUpdate = new Map<Id, List<AlignmentRow>>();
		Integer unchangedCount = 0;

		AlignmentPlan(List<AlignmentRow> rows) {
			Set<String> techHrisValues = new Set<String>();
			Set<String> asmHrisValues = new Set<String>();
			Set<String> territoryNumbers = new Set<String>();
			for (AlignmentRow row : rows) {
				techHrisValues.add(row.techHris);
				asmHrisValues.addAll(new List<String>{ row.currentAsmHris, row.nextAsmHris });
				territoryNumbers.addAll(new List<String>{ row.currentTerritory, row.nextTerritory });
			}
			techHrisValues.remove(null);
			asmHrisValues.remove(null);
			territoryNumbers.remove(null);

			// ASMs: active users of any profile, by Employee Number (HRIS ID).
			List<User> users = (List<User>) SoqlQueryBuilder.fromObject('User')
				.selectFields(new List<String>{ 'Id', 'Name', 'EmployeeNumber__c' })
				.whereEquals('IsActive', true)
				.whereIn('EmployeeNumber__c', new List<String>(asmHrisValues))
				.execute();
			for (User activeUser : users) {
				userByHris.put(key(activeUser.EmployeeNumber__c), activeUser);
			}

			// Technicians: active Service Resources by External ID (HRIS ID).
			List<ServiceResource> resources = (List<ServiceResource>) new ServiceResourcesSelector()
				.selectFields(new List<String>{ 'Id', 'Name', 'ExternalID__c', 'RelatedRecordId' })
				.whereEquals('IsActive', true)
				.whereIn('ExternalID__c', new List<String>(techHrisValues))
				.execute();
			for (ServiceResource resource : resources) {
				resourceByExternalId.put(key(resource.ExternalID__c), resource);
			}

			SoqlQueryBuilder territoryQuery = SoqlQueryBuilder.fromObject('ServiceTerritory')
				.selectFields(TERRITORY_FIELDS)
				.whereIn('RegionNumber__c', new List<String>(territoryNumbers));
			List<ServiceTerritory> territories = (List<ServiceTerritory>) territoryQuery.execute();
			for (ServiceTerritory territory : territories) {
				territoryByNumber.put(key(territory.RegionNumber__c), territory);
			}

			// Memberships of these technicians in these territories that have not ended before today, newest first.
			List<ServiceTerritoryMember> members = (List<ServiceTerritoryMember>) new ServiceTerritoryMembersSelector()
				.selectFields(
					new List<String>{
						'Id',
						'ServiceResourceId',
						'ServiceTerritoryId',
						'TerritoryType',
						'OperatingHoursId',
						'EffectiveStartDate',
						'EffectiveEndDate'
					}
				)
				.whereIn('ServiceResourceId', new List<Id>(new Map<Id, ServiceResource>(resources).keySet()))
				.whereIn('ServiceTerritoryId', new List<Id>(new Map<Id, ServiceTerritory>(territories).keySet()))
				.whereEquals('EffectiveEndDate', null)
				.whereField('EffectiveEndDate', '>=', startOfToday)
				.withFilterLogic('1 AND 2 AND (3 OR 4)')
				.orderByDesc('EffectiveStartDate')
				.execute();
			for (ServiceTerritoryMember member : members) {
				String memberKey = memberKey(member.ServiceResourceId, member.ServiceTerritoryId);
				if (!membersByKey.containsKey(memberKey)) {
					membersByKey.put(memberKey, new List<ServiceTerritoryMember>());
				}
				membersByKey.get(memberKey).add(member);
			}
		}

		String planRow(AlignmentRow row) {
			if (String.isBlank(row.techHris)) {
				return Label.TDA_TechRequired;
			}
			ServiceResource resource = resourceByExternalId.get(key(row.techHris));
			if (resource == null) {
				return String.format(Label.TDA_TechNotFound, new List<Object>{ row.techHris });
			}
			if (claimedResourceIds.contains(resource.Id)) {
				return String.format(Label.TDA_TechDuplicate, new List<Object>{ row.techHris });
			}

			if (String.isBlank(row.currentTerritory)) {
				return Label.TDA_CurrentTerritoryRequired;
			}
			ServiceTerritory current = territoryByNumber.get(key(row.currentTerritory));
			if (current == null) {
				return String.format(Label.TDA_CurrentTerritoryNotFound, new List<Object>{ row.currentTerritory });
			}
			String currentTypeError = typeError(current, Label.TDA_CurrentTerritoryUnsupported);
			if (currentTypeError != null) {
				return currentTypeError;
			}
			ServiceTerritoryMember currentMember = activeMember(resource.Id, current.Id);
			if (currentMember == null) {
				return String.format(Label.TDA_NotAssigned, new List<Object>{ current.RegionNumber__c });
			}

			if (String.isBlank(row.currentAsmHris)) {
				return Label.TDA_CurrentAsmRequired;
			}
			if (!userByHris.containsKey(key(row.currentAsmHris))) {
				return String.format(Label.TDA_CurrentAsmNotFound, new List<Object>{ row.currentAsmHris });
			}

			if (String.isBlank(row.nextTerritory)) {
				return Label.TDA_NextTerritoryRequired;
			}
			User nextAsm;
			if (String.isNotBlank(row.nextAsmHris)) {
				nextAsm = userByHris.get(key(row.nextAsmHris));
				if (nextAsm == null) {
					return String.format(Label.TDA_NextAsmNotFound, new List<Object>{ row.nextAsmHris });
				}
			}

			ServiceTerritory existing = territoryByNumber.get(key(row.nextTerritory));
			String targetError = existing == null
				? planNewTerritory(row, current, nextAsm)
				: planExistingTerritory(row, existing, nextAsm);
			if (targetError != null) {
				return targetError;
			}

			row.resource = resource;
			row.currentMember = currentMember;
			claimedResourceIds.add(resource.Id);
			Boolean moves = row.targetTerritory.Id == null || row.targetTerritory.Id != current.Id;
			if (moves) {
				row.createMember =
					row.targetTerritory.Id == null || openMember(resource.Id, row.targetTerritory.Id) == null;
				row.endMember = currentMember.EffectiveEndDate == null || currentMember.EffectiveEndDate > now;
			}
			if (!row.createMember && !row.endMember && !row.updatesManager) {
				unchangedCount++;
			}
			return null;
		}

		String planNewTerritory(AlignmentRow row, ServiceTerritory current, User nextAsm) {
			if (nextAsm == null) {
				return String.format(Label.TDA_NextAsmRequired, new List<Object>{ row.nextTerritory });
			}
			String territoryKey = key(row.nextTerritory);
			ServiceTerritory pending = newTerritoryByNumber.get(territoryKey);
			if (pending == null) {
				pending = new ServiceTerritory(
					Name = row.nextTerritory.left(NAME_MAX_LENGTH),
					RegionNumber__c = row.nextTerritory,
					TerritoryType__c = current.TerritoryType__c,
					ParentTerritoryId = current.ParentTerritoryId,
					OperatingHoursId = current.OperatingHoursId,
					TerritoryManager__c = nextAsm.Id,
					IsActive = true
				);
				newTerritoryByNumber.put(territoryKey, pending);
				newTerritories.add(pending);
				rowsByNewTerritory.put(territoryKey, new List<AlignmentRow>());
			} else if (pending.TerritoryManager__c != nextAsm.Id) {
				return String.format(Label.TDA_ConflictingAsm, new List<Object>{ row.nextTerritory });
			}
			rowsByNewTerritory.get(territoryKey).add(row);
			row.targetTerritory = pending;
			return null;
		}

		String planExistingTerritory(AlignmentRow row, ServiceTerritory target, User nextAsm) {
			String nextTypeError = typeError(target, Label.TDA_NextTerritoryUnsupported);
			if (nextTypeError != null) {
				return nextTypeError;
			}
			if (!target.IsActive) {
				return String.format(Label.TDA_NextTerritoryInactive, new List<Object>{ target.RegionNumber__c });
			}

			Boolean asmChanged = nextAsm != null && key(row.nextAsmHris) != key(row.currentAsmHris);
			if (asmChanged) {
				Id requested = requestedManagerByTerritoryId.get(target.Id);
				if (requested != null && requested != nextAsm.Id) {
					return String.format(Label.TDA_ConflictingAsm, new List<Object>{ target.RegionNumber__c });
				}
				requestedManagerByTerritoryId.put(target.Id, nextAsm.Id);
				if (target.TerritoryManager__c != nextAsm.Id) {
					if (!managerUpdateById.containsKey(target.Id)) {
						managerUpdateById.put(
							target.Id,
							new ServiceTerritory(Id = target.Id, TerritoryManager__c = nextAsm.Id)
						);
						rowsByManagerUpdate.put(target.Id, new List<AlignmentRow>());
					}
					rowsByManagerUpdate.get(target.Id).add(row);
					row.updatesManager = true;
				}
			}
			row.targetTerritory = target;
			return null;
		}

		String typeError(ServiceTerritory territory, String message) {
			if (SUPPORTED_TERRITORY_TYPES.contains(territory.TerritoryType__c)) {
				return null;
			}
			String typeLabel = String.isBlank(territory.TerritoryType__c) ? '(blank)' : territory.TerritoryType__c;
			return String.format(message, new List<Object>{ territory.RegionNumber__c, typeLabel });
		}

		/**
		 * @description Membership that has started and is not ended before today (newest first).
		 */
		ServiceTerritoryMember activeMember(Id resourceId, Id territoryId) {
			List<ServiceTerritoryMember> members = membersByKey.get(memberKey(resourceId, territoryId));
			for (ServiceTerritoryMember member : members ?? new List<ServiceTerritoryMember>()) {
				if (member.EffectiveStartDate <= now) {
					return member;
				}
			}
			return null;
		}

		/**
		 * @description Any membership not ended before today, including one that starts in the future.
		 */
		ServiceTerritoryMember openMember(Id resourceId, Id territoryId) {
			List<ServiceTerritoryMember> members = membersByKey.get(memberKey(resourceId, territoryId));
			return members == null ? null : members[0];
		}
	}

	private static List<AlignmentRow> toRows(List<List<String>> table) {
		Map<String, Integer> columnIndexByName = columnIndexByName(table.isEmpty() ? new List<String>() : table[0]);
		Boolean hasRequiredColumns =
			hasColumn(columnIndexByName, TECH_HRIS_COLUMNS) &&
			hasColumn(columnIndexByName, CURRENT_TERRITORY_COLUMNS) &&
			hasColumn(columnIndexByName, CURRENT_ASM_HRIS_COLUMNS) &&
			hasColumn(columnIndexByName, NEXT_TERRITORY_COLUMNS) &&
			hasColumn(columnIndexByName, NEXT_ASM_HRIS_COLUMNS);
		if (!hasRequiredColumns) {
			throw PlatformUtilities.buildAuraException(Label.TDA_MissingColumns);
		}
		if (table.size() - 1 > MAX_ROWS) {
			throw PlatformUtilities.buildAuraException(
				String.format(Label.TDA_TooManyRows, new List<Object>{ String.valueOf(MAX_ROWS) })
			);
		}

		List<AlignmentRow> rows = new List<AlignmentRow>();
		for (Integer i = 1; i < table.size(); i++) {
			List<String> cells = table[i];
			AlignmentRow row = new AlignmentRow();
			row.rowNumber = i + 1;
			row.cells = cells;
			row.techHris = normalizeHris(columnValue(cells, columnIndexByName, TECH_HRIS_COLUMNS));
			row.currentTerritory = columnValue(cells, columnIndexByName, CURRENT_TERRITORY_COLUMNS);
			row.currentAsmHris = normalizeHris(columnValue(cells, columnIndexByName, CURRENT_ASM_HRIS_COLUMNS));
			row.nextTerritory = columnValue(cells, columnIndexByName, NEXT_TERRITORY_COLUMNS);
			row.nextAsmHris = normalizeHris(columnValue(cells, columnIndexByName, NEXT_ASM_HRIS_COLUMNS));
			Boolean isBlankRow =
				String.isBlank(row.techHris) &&
				String.isBlank(row.currentTerritory) &&
				String.isBlank(row.currentAsmHris) &&
				String.isBlank(row.nextTerritory) &&
				String.isBlank(row.nextAsmHris);
			if (!isBlankRow) {
				rows.add(row);
			}
		}
		return rows;
	}

	/**
	 * @description Column index keyed by header name in lower case without spaces or symbols ("TECH HRIS#" is
	 *              "techhris").
	 */
	private static Map<String, Integer> columnIndexByName(List<String> header) {
		Map<String, Integer> columnIndexByName = new Map<String, Integer>();
		for (Integer i = 0; i < header.size(); i++) {
			String name = header[i] == null ? '' : header[i].toLowerCase().replaceAll('[^a-z0-9]', '');
			if (String.isNotBlank(name) && !columnIndexByName.containsKey(name)) {
				columnIndexByName.put(name, i);
			}
		}
		return columnIndexByName;
	}

	private static Boolean hasColumn(Map<String, Integer> columnIndexByName, List<String> names) {
		for (String name : names) {
			if (columnIndexByName.containsKey(name)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @description Trimmed value of the first matching column; a blank or dash-only placeholder ("-") is null.
	 */
	private static String columnValue(List<String> cells, Map<String, Integer> columnIndexByName, List<String> names) {
		for (String name : names) {
			Integer index = columnIndexByName.get(name);
			if (index != null && index < cells.size() && cells[index] != null) {
				String value = cells[index].trim();
				return String.isBlank(value.replaceAll('\\p{Pd}', '')) ? null : value;
			}
		}
		return null;
	}

	/**
	 * @description Excel can store an HRIS number as "50708.0"; drop a zero-only decimal part.
	 */
	private static String normalizeHris(String value) {
		return value?.replaceFirst('^(\\d+)\\.0+$', '$1');
	}

	/**
	 * @description Adds a new version to the running user's error file, creating the file on first use. The file
	 *              repeats the uploaded columns for each skipped row, with the row number first and the error last.
	 */
	private static ContentVersion writeErrorFile(List<String> header, List<AlignmentRow> rows) {
		List<String> lines = new List<String>{
			errorFileLine(Label.TDA_ErrorFileRowColumn, header, Label.TDA_ErrorFileErrorColumn, header.size())
		};
		for (AlignmentRow row : rows) {
			if (row.errorMessage != null) {
				lines.add(errorFileLine(String.valueOf(row.rowNumber), row.cells, row.errorMessage, header.size()));
			}
		}

		Id existingDocumentId = errorFileDocumentId();
		ContentVersion version = new ContentVersion(
			Title = ERROR_FILE_TITLE,
			PathOnClient = ERROR_FILE_NAME,
			VersionData = Blob.valueOf(String.join(lines, '\n') + '\n'),
			ReasonForChange = 'Tech District Alignment upload ' + Datetime.now().format(),
			ContentDocumentId = existingDocumentId
		);
		Database.insert(version, AccessLevel.USER_MODE);

		// ContentDocumentId is create-only, so read it back instead of setting it on the inserted record.
		ContentVersion saved = ContentVersionsSelector.selectDocumentIdByVersionId(version.Id)[0];
		if (saved.ContentDocumentId != existingDocumentId) {
			FieldServiceBackofficeConfig__c config =
				FieldServiceBackofficeConfig__c.getValues(UserInfo.getUserId()) ??
				new FieldServiceBackofficeConfig__c(SetupOwnerId = UserInfo.getUserId());
			config.TechDistrictAlignmentErrorFileId__c = saved.ContentDocumentId;
			// System mode: back-office users have no edit access to custom settings.
			Database.upsert(config, AccessLevel.SYSTEM_MODE);
		}
		return saved;
	}

	/**
	 * @description One error file line: the first value, the row's cells padded to the header width, the last value.
	 */
	private static String errorFileLine(String first, List<String> cells, String last, Integer columnCount) {
		List<String> values = new List<String>{ first };
		for (Integer i = 0; i < columnCount; i++) {
			values.add(i < cells.size() ? cells[i] : null);
		}
		values.add(last);
		return PlatformUtilities.toCsvLine(values);
	}

	private static Boolean sendResultEmail(ProcessResult result, Id errorFileVersionId) {
		Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
		mail.setTargetObjectId(UserInfo.getUserId());
		mail.setSaveAsActivity(false);
		mail.setSubject(Label.TDA_EmailSubject);
		List<Object> bodyParams = new List<Object>{ result.summary, result.nextFiscalYearStart.format() };
		mail.setPlainTextBody(String.format(Label.TDA_EmailBody, bodyParams));
		mail.setEntityAttachments(new List<String>{ errorFileVersionId });
		try {
			Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail });
			return true;
		} catch (EmailException e) {
			Logger.warn('Tech District Alignment result email could not be sent.', e).addTags(LOG_TAGS);
			return false;
		}
	}

	private static String key(String value) {
		return value?.trim().toLowerCase();
	}

	private static String memberKey(Id resourceId, Id territoryId) {
		return String.valueOf(resourceId) + '|' + String.valueOf(territoryId);
	}
}