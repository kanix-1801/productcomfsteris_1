/**
 * @description Controller class for Installation Project Management LWC
 */
public with sharing class InstallationProjectMgmtController {

	/**
	 * @description Wrapper class for project data transfer
	 */
	private class ProjectDataWrapper {
		String projectName;
		String projectDescription;
		String accountId;
		String ownerId;
		String projectStartDate;
		String projectShippedDate;
		String projectRequestedDate;
		String projectTemplateId;
		String projectContactId;
		String primaryEst;
		String primaryInstaller;
		String districtServiceManager;
		String capitalAccountManager;
		List<String> caseIds;
		List<Map<String, Object>> items;
	}

	/**
	 * @description Retrieve case details with related information
	 * @param caseId The Case record ID
	 * @return Case record with relevant fields
	 */
	@AuraEnabled(cacheable=true)
	public static Case getCaseDetails(Id caseId) {
		try {
			if (caseId == null) {
				throw new AuraHandledException('Case ID is required');
			}

			List<Case> cases = [
				SELECT
					Id,
					CaseNumber,
					Subject,
					Description,
					Status,
					Priority,
					AccountId,
					Account.Name,
					ContactId,
					OwnerId,
					Owner.Name,
					RecordType.Name,
					OracleOrderNumber__c,
					RegistrationNumber__c
				FROM Case
				WHERE Id = :caseId
				WITH USER_MODE
				LIMIT 1
			];

			if (cases.isEmpty()) {
				throw new AuraHandledException('Case not found');
			}

			return cases[0];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving case details: ' + e.getMessage());
		}
	}

	/**
	 * @description Retrieve account information
	 * @param accountId The Account record ID
	 * @return Account record with relevant fields
	 */
	@AuraEnabled(cacheable=true)
	public static Account getAccountDetails(Id accountId) {
		try {
			if (accountId == null) {
				throw new AuraHandledException('Account ID is required');
			}

			List<Account> accounts = [
				SELECT
					Id,
					Name,
					OwnerId,
					Owner.Name
				FROM Account
				WHERE Id = :accountId
				WITH USER_MODE
				LIMIT 1
			];

			if (accounts.isEmpty()) {
				throw new AuraHandledException('Account not found');
			}

			return accounts[0];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving account details: ' + e.getMessage());
		}
	}

	/**
	 * @description Retrieve all project templates
	 * @return List of ProjectTemplate__c records
	 */
	@AuraEnabled(cacheable=true)
	public static List<ProjectTemplate__c> getProjectTemplates() {
		try {
			return [
				SELECT
					Id,
					Name,
					TemplateDescription__c
				FROM ProjectTemplate__c
				WHERE Active__c = true
				WITH USER_MODE
				ORDER BY Name ASC
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving project templates: ' + e.getMessage());
		}
	}

	/**
	 * @description Retrieve contacts for a specific account
	 * @param accountId The Account record ID
	 * @return List of Contact records for the account
	 */
	@AuraEnabled(cacheable=true)
	public static List<Contact> getContactsForAccount(Id accountId) {
		try {
			if (accountId == null) {
				return new List<Contact>();
			}

			return [
				SELECT Id, Name, Email, Phone
				FROM Contact
				WHERE AccountId = :accountId
				WITH USER_MODE
				ORDER BY Name ASC
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving contacts: ' + e.getMessage());
		}
	}

	/**
	 * @description Retrieve cases available to link when creating a project.
	 * Includes Service Installation Sub Cases for the account. CBM Cases are included
	 * only when a registration number is provided and they share that number.
	 * Capital Line Sub Cases and cases in Cancelled stage are never included.
	 * @param accountId The Account record ID
	 * @param registrationNumber Registration number from the starting case
	 * @return List of Case records for the account
	 */
	@AuraEnabled(cacheable=true)
	public static List<Case> getCasesForAccount(Id accountId, String registrationNumber) {
		try {
			if (accountId == null) {
				return new List<Case>();
			}

			registrationNumber = registrationNumber != null ? registrationNumber.trim() : null;

			if (String.isNotBlank(registrationNumber)) {
				return [
					SELECT
						Id,
						CaseNumber,
						Subject,
						RegistrationNumber__c
					FROM Case
					WHERE AccountId = :accountId
					AND Status != 'Cancelled'
					AND (
						RecordType.DeveloperName = 'Service_Installation_Sub_Case'
						OR (
							RecordType.DeveloperName = 'CBMCase'
							AND RegistrationNumber__c = :registrationNumber
						)
					)
					WITH USER_MODE
					ORDER BY CaseNumber ASC
				];
			}

			return [
				SELECT
					Id,
					CaseNumber,
					Subject,
					RegistrationNumber__c
				FROM Case
					WHERE AccountId = :accountId
					AND Status != 'Cancelled'
					AND RecordType.DeveloperName = 'Service_Installation_Sub_Case'
				WITH USER_MODE
				ORDER BY CaseNumber ASC
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving cases: ' + e.getMessage());
		}
	}

	/**
	 * @description Retrieve template items for a specific template
	 * @param templateId The ProjectTemplate__c record ID
	 * @return List of ProjectTemplateItem__c records ordered by ItemNumber__c
	 */
	@AuraEnabled(cacheable=true)
	public static List<ProjectTemplateItem__c> getTemplateItems(Id templateId) {
		try {
			if (templateId == null) {
				return new List<ProjectTemplateItem__c>();
			}

			return [
				SELECT
					Id,
					Name,
					ItemNumber__c,
					Type__c,
					Duration__c,
					AutoFilledStartDays__c,
					DependencyType__c,
					ItemDependency__c,
					ProjectTemplate__c,
					DefaultQueue__c,
					CannotBeDeleted__c
				FROM ProjectTemplateItem__c
				WHERE ProjectTemplate__c = :templateId
				WITH USER_MODE
				ORDER BY ItemNumber__c ASC
			];
		} catch (Exception e) {
			throw new AuraHandledException('Error retrieving template items: ' + e.getMessage());
		}
	}

	/**
	 * @description Parse and extract data from JSON string
	 * @param projectData JSON string containing project details
	 * @return ProjectDataWrapper containing parsed data
	 */
	private static ProjectDataWrapper parseProjectData(String projectData) {
		Map<String, Object> dataMap = (Map<String, Object>) JSON.deserializeUntyped(projectData);

		ProjectDataWrapper wrapper = new ProjectDataWrapper();
		wrapper.projectName = (String) dataMap.get('projectName');
		wrapper.projectDescription = (String) dataMap.get('projectDescription');
		wrapper.accountId = (String) dataMap.get('accountId');
		// Ignore any incoming ownerId to avoid client-side spoofing
		wrapper.ownerId = null;
		wrapper.projectStartDate = (String) dataMap.get('projectStartDate');
		wrapper.projectShippedDate = (String) dataMap.get('projectShippedDate');
		wrapper.projectRequestedDate = (String) dataMap.get('projectRequestedDate');
		wrapper.projectTemplateId = (String) dataMap.get('projectTemplateId');
		wrapper.projectContactId = (String) dataMap.get('projectContactId');
		wrapper.primaryEst = (String) dataMap.get('primaryEst');
		wrapper.primaryInstaller = (String) dataMap.get('primaryInstaller');
		wrapper.districtServiceManager = (String) dataMap.get('districtServiceManager');
		wrapper.capitalAccountManager = (String) dataMap.get('capitalAccountManager');

		// Extract case IDs
		List<Object> caseIdObjects = (List<Object>) dataMap.get('caseIds');
		wrapper.caseIds = new List<String>();
		if (caseIdObjects != null) {
			for (Object caseIdObj : caseIdObjects) {
				wrapper.caseIds.add((String) caseIdObj);
			}
		}

		// Extract project items
		List<Object> itemObjects = (List<Object>) dataMap.get('items');
		wrapper.items = new List<Map<String, Object>>();
		if (itemObjects != null) {
			for (Object itemObj : itemObjects) {
				wrapper.items.add((Map<String, Object>) itemObj);
			}
		}

		return wrapper;
	}

	/**
	 * @description Assign ProjectItemSequence__c for Text or Number field definitions.
	 */
	private static void putProjectItemSequence(SObject rec, Object rawItemNumber) {
		String seqString = ProjectItemSequenceUtil.sequenceToString(rawItemNumber);
		if (String.isBlank(seqString)) {
			return;
		}
		Map<String, Schema.SObjectField> fm = rec.getSObjectType().getDescribe().fields.getMap();
		Schema.SObjectField f = fm.get('projectitemsequence__c');
		if (f == null) {
			return;
		}
		Schema.DisplayType ft = f.getDescribe().getType();
		if (
			ft == Schema.DisplayType.DOUBLE ||
			ft == Schema.DisplayType.INTEGER ||
			ft == Schema.DisplayType.CURRENCY ||
			ft == Schema.DisplayType.PERCENT
		) {
			rec.put('ProjectItemSequence__c', Decimal.valueOf(seqString));
		} else {
			rec.put('ProjectItemSequence__c', seqString);
		}
	}

	/**
	 * @description Calculate the project end date from item dates
	 * @param items List of project item data
	 * @return Date Maximum end date from all items
	 */
	private static Date calculateProjectEndDate(List<Map<String, Object>> items) {
		Date projectEndDate = null;
		for (Map<String, Object> item : items) {
			String itemEndDateStr = (String) item.get('calculatedEndDate');
			if (itemEndDateStr != null) {
				Date itemEndDate = Date.valueOf(itemEndDateStr);
				if (projectEndDate == null || itemEndDate > projectEndDate) {
					projectEndDate = itemEndDate;
				}
			}
		}
		return projectEndDate;
	}

	/**
	 * @description Read the assignee chosen in the LWC for a project item
	 * @param item Project item data
	 * @return Id User ID, or null when no valid assignee was sent
	 */
	private static Id readAssigneeId(Map<String, Object> item) {
		Object rawAssignee = item.get('assigneeId');
		if (rawAssignee == null || String.isBlank(String.valueOf(rawAssignee))) {
			return null;
		}
		try {
			Id assigneeId = (Id) String.valueOf(rawAssignee);
			return assigneeId.getSobjectType() == User.SObjectType ? assigneeId : null;
		} catch (Exception e) {
			return null;
		}
	}

	/**
	 * @description Map each item to its owner: the chosen assignee, or the current user when none was chosen
	 * @param items List of project item data
	 * @return Map<Integer, Id> Item index to owner ID
	 */
	@TestVisible
	private static Map<Integer, Id> resolveItemOwnerIds(List<Map<String, Object>> items) {
		Map<Integer, Id> ownerIdsByIndex = new Map<Integer, Id>();
		Set<Id> requestedAssigneeIds = new Set<Id>();
		for (Integer i = 0; i < items.size(); i++) {
			Id assigneeId = readAssigneeId(items[i]);
			ownerIdsByIndex.put(i, assigneeId != null ? assigneeId : UserInfo.getUserId());
			if (assigneeId != null) {
				requestedAssigneeIds.add(assigneeId);
			}
		}

		Set<Id> assignableIds = ProjectItemSequenceUtil.filterAssignableUserIds(requestedAssigneeIds);
		if (assignableIds.size() != requestedAssigneeIds.size()) {
			throw new AuraHandledException(
				'One or more assignees are not available for assignment. Choose an active user that is not an integration or generic account.'
			);
		}
		return ownerIdsByIndex;
	}

	/**
	 * @description Parse selected case IDs and confirm the running user can read each Case.
	 */
	@TestVisible
	private static Set<Id> resolveValidatedCaseIds(List<String> caseIds) {
		Set<Id> validatedCaseIds = new Set<Id>();
		if (caseIds == null || caseIds.isEmpty()) {
			return validatedCaseIds;
		}

		Set<Id> requestedCaseIds = new Set<Id>();
		for (String caseIdStr : caseIds) {
			if (String.isBlank(caseIdStr)) {
				continue;
			}
			try {
				Id caseId = (Id) caseIdStr;
				if (caseId != null && caseId.getSobjectType() == Case.SObjectType) {
					requestedCaseIds.add(caseId);
				}
			} catch (Exception e) {
				continue;
			}
		}

		if (requestedCaseIds.isEmpty()) {
			return validatedCaseIds;
		}

		for (Case accessibleCase : [
			SELECT Id
			FROM Case
			WHERE Id IN :requestedCaseIds
			WITH USER_MODE
		]) {
			validatedCaseIds.add(accessibleCase.Id);
		}

		if (validatedCaseIds.size() != requestedCaseIds.size()) {
			throw new AuraHandledException(
				'One or more selected Cases are not accessible. Verify Case sharing and object permissions.'
			);
		}

		return validatedCaseIds;
	}

	private static Id resolvePrimaryCaseId(List<String> caseIds, Set<Id> validatedCaseIds) {
		if (caseIds == null || validatedCaseIds == null || validatedCaseIds.isEmpty()) {
			return null;
		}

		for (String caseIdStr : caseIds) {
			if (String.isBlank(caseIdStr)) {
				continue;
			}
			try {
				Id caseId = (Id) caseIdStr;
				if (validatedCaseIds.contains(caseId)) {
					return caseId;
				}
			} catch (Exception e) {
				continue;
			}
		}

		return null;
	}

	/**
	 * @description Build the Project__c record without DML.
	 */
	private static Project__c buildProjectRecord(
		ProjectDataWrapper wrapper,
		Date projectEndDate,
		Id primaryCaseId
	) {
		Project__c newProject = new Project__c();
		newProject.Name = wrapper.projectName;
		newProject.ProjectDescription__c = wrapper.projectDescription;
		newProject.Account__c = wrapper.accountId;
		// Force owner to current user to prevent spoofing from client
		newProject.OwnerId = UserInfo.getUserId();
		newProject.ProjectStartDate__c = wrapper.projectStartDate != null ? Date.valueOf(wrapper.projectStartDate) : null;
		newProject.ProjectEndDate__c = projectEndDate;
		newProject.ProjectShippedDate__c = wrapper.projectShippedDate != null ? Date.valueOf(wrapper.projectShippedDate) : null;
		newProject.ProjectRequestedDate__c = wrapper.projectRequestedDate != null ? Date.valueOf(wrapper.projectRequestedDate) : null;
		newProject.ProjectTemplate__c = wrapper.projectTemplateId;
		newProject.ProjectContact__c = wrapper.projectContactId;
		newProject.PrimaryEST__c = wrapper.primaryEst;
		newProject.PrimaryInstaller__c = wrapper.primaryInstaller;
		newProject.DistrictServiceManager__c = wrapper.districtServiceManager;
		newProject.CapitalAccountManager__c = wrapper.capitalAccountManager;
		newProject.PrimaryCase__c = primaryCaseId;
		return newProject;
	}

	/**
	 * @description Build ProjectCases__c junction rows for validated Case IDs (no DML).
	 */
	private static List<SObject> buildProjectCaseJunctionRows(Set<Id> caseIds, Id projectId) {
		List<SObject> junctionRows = new List<SObject>();
		if (caseIds == null || caseIds.isEmpty() || projectId == null) {
			return junctionRows;
		}

		Schema.SObjectType junctionType = resolveProjectCasesJunctionType();
		if (junctionType == null || !junctionType.getDescribe().isCreateable()) {
			return junctionRows;
		}

		Map<String, Schema.SObjectField> fieldMap = junctionType.getDescribe().fields.getMap();
		if (!fieldMap.containsKey('project__c') || !fieldMap.containsKey('case__c')) {
			return junctionRows;
		}

		for (Id caseId : caseIds) {
			SObject junction = junctionType.newSObject();
			junction.put('Project__c', projectId);
			junction.put('Case__c', caseId);
			junctionRows.add(junction);
		}

		return junctionRows;
	}

	/**
	 * @description Performs Case-linked DML without sharing so record-level Case sharing
	 * does not block lookup population after the user has selected accessible Cases in the UI.
	 */
	private without sharing class ProjectCreateDml {
		private void insertProject(Project__c project) {
			Database.insert(project, AccessLevel.SYSTEM_MODE);
		}

		private void insertProjectCaseJunctions(List<SObject> junctionRows) {
			if (junctionRows == null || junctionRows.isEmpty()) {
				return;
			}
			Database.insert(junctionRows, AccessLevel.SYSTEM_MODE);
		}
	}

	@TestVisible
	private static Schema.SObjectType resolveProjectCasesJunctionType() {
		return Schema.getGlobalDescribe().get('ProjectCases__c');
	}

	/**
	 * @description Load the template items marked "Cannot be Deleted" and confirm each one is in the submitted items
	 * @param templateId The ProjectTemplate__c record ID
	 * @param items List of project item data
	 * @return Set<String> IDs of the mandatory template items
	 */
	@TestVisible
	private static Set<String> resolveCannotBeDeletedItemIds(String templateId, List<Map<String, Object>> items) {
		Set<String> mandatoryItemIds = new Set<String>();
		if (String.isBlank(templateId)) {
			return mandatoryItemIds;
		}

		Map<String, String> mandatoryItemNames = new Map<String, String>();
		for (ProjectTemplateItem__c templateItem : [
			SELECT Id, Name
			FROM ProjectTemplateItem__c
			WHERE ProjectTemplate__c = :templateId
			AND CannotBeDeleted__c = true
			WITH USER_MODE
		]) {
			mandatoryItemNames.put(String.valueOf(templateItem.Id), templateItem.Name);
		}
		mandatoryItemIds.addAll(mandatoryItemNames.keySet());

		Set<String> submittedItemIds = new Set<String>();
		for (Map<String, Object> item : items) {
			Object rawId = item.get('Id');
			if (rawId != null) {
				submittedItemIds.add(String.valueOf(rawId));
			}
		}

		List<String> missingItemNames = new List<String>();
		for (String mandatoryItemId : mandatoryItemIds) {
			if (!submittedItemIds.contains(mandatoryItemId)) {
				missingItemNames.add(mandatoryItemNames.get(mandatoryItemId));
			}
		}
		if (!missingItemNames.isEmpty()) {
			throw new AuraHandledException(
				'These template items cannot be deleted: ' + String.join(missingItemNames, ', ')
			);
		}

		return mandatoryItemIds;
	}

	private static Boolean isCannotBeDeletedItem(Map<String, Object> item, Set<String> mandatoryItemIds) {
		Object rawId = item.get('Id');
		return rawId != null && mandatoryItemIds.contains(String.valueOf(rawId));
	}

	/**
	 * @description Create Task records from project items
	 * @param items List of project item data
	 * @param projectId The project ID to associate with tasks
	 * @param ownerIdsByIndex Item index to owner ID
	 * @param mandatoryItemIds IDs of template items marked "Cannot be Deleted"
	 * @return List<Task> List of tasks to insert
	 */
	private static List<Task> createTasksFromItems(
		List<Map<String, Object>> items,
		Id projectId,
		Map<Integer, Id> ownerIdsByIndex,
		Set<String> mandatoryItemIds
	) {
		List<Task> tasksToInsert = new List<Task>();

		for (Integer i = 0; i < items.size(); i++) {
			Map<String, Object> item = items[i];
			String itemType = (String) item.get('Type__c');

			if (itemType != null && itemType.equalsIgnoreCase('Task')) {
				String itemName = (String) item.get('Name');
				String itemStartDateStr = (String) item.get('calculatedStartDate');

				Task newTask = new Task();
				newTask.OwnerId = ownerIdsByIndex.get(i);
				newTask.Project__c = projectId;
				newTask.WhatId = projectId;
				putProjectItemSequence(newTask, item.get('ItemNumber__c'));
				ProjectItemSequenceUtil.putTemplateItemNumber(newTask, item.get('ItemNumber__c'));
				newTask.Status = 'Open';
				newTask.ActivityDate = itemStartDateStr != null ? Date.valueOf(itemStartDateStr) : null;
				newTask.Subject = itemName;
				newTask.CannotBeDeleted__c = isCannotBeDeletedItem(item, mandatoryItemIds);

				// Assign record type IPMTask
				Schema.RecordTypeInfo taskRecordTypeInfo = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('IPMTask');
				if (taskRecordTypeInfo != null) {
					newTask.RecordTypeId = taskRecordTypeInfo.getRecordTypeId();
				}

				tasksToInsert.add(newTask);
			}
		}

		return tasksToInsert;
	}

	/**
	 * @description Create Event records from project items
	 * @param items List of project item data
	 * @param projectId The project ID to associate with events
	 * @param ownerIdsByIndex Item index to owner ID
	 * @param mandatoryItemIds IDs of template items marked "Cannot be Deleted"
	 * @return List<Event> List of events to insert
	 */
	private static List<Event> createEventsFromItems(
		List<Map<String, Object>> items,
		Id projectId,
		Map<Integer, Id> ownerIdsByIndex,
		Set<String> mandatoryItemIds
	) {
		List<Event> eventsToInsert = new List<Event>();

		for (Integer i = 0; i < items.size(); i++) {
			Map<String, Object> item = items[i];
			String itemType = (String) item.get('Type__c');

			if (itemType != null && itemType.equalsIgnoreCase('Event')) {
				String itemName = (String) item.get('Name');
				String itemStartDateStr = (String) item.get('calculatedStartDate');
				String itemEndDateStr = (String) item.get('calculatedEndDate');

				Event newEvent = new Event();
				newEvent.OwnerId = ownerIdsByIndex.get(i);
				newEvent.Project__c = projectId;
				newEvent.WhatId = projectId;
				putProjectItemSequence(newEvent, item.get('ItemNumber__c'));
				ProjectItemSequenceUtil.putTemplateItemNumber(newEvent, item.get('ItemNumber__c'));
				newEvent.Subject = itemName;
				newEvent.CannotBeDeleted__c = isCannotBeDeletedItem(item, mandatoryItemIds);

				// Assign record type IPMEvent
				Schema.RecordTypeInfo eventRecordTypeInfo = Schema.SObjectType.Event.getRecordTypeInfosByDeveloperName().get('IPMEvent');
				if (eventRecordTypeInfo != null) {
					newEvent.RecordTypeId = eventRecordTypeInfo.getRecordTypeId();
				}

				// Use dates calculated from UI
				if (itemStartDateStr != null) {
					Date activityDate = Date.valueOf(itemStartDateStr);
					newEvent.ActivityDate = activityDate;
					Decimal durationDays = ProjectItemSequenceUtil.coerceToDecimal(item.get('Duration__c'));
					if (durationDays == null) {
						durationDays = 0;
					}

					if (durationDays == 0) {
						// Zero-duration template events: 10:00 AM for 2 hours
						DateTime startDateTime = DateTime.newInstance(activityDate, Time.newInstance(10, 0, 0, 0));
						newEvent.StartDateTime = startDateTime;
						newEvent.EndDateTime = startDateTime.addHours(2);
					} else {
						DateTime startDateTime = DateTime.newInstance(activityDate, Time.newInstance(0, 0, 0, 0));
						newEvent.StartDateTime = startDateTime;

						if (itemEndDateStr != null) {
							DateTime endDateTime = DateTime.newInstance(Date.valueOf(itemEndDateStr), Time.newInstance(0, 0, 0, 0));
							newEvent.EndDateTime = endDateTime;
						} else {
							newEvent.EndDateTime = startDateTime.addHours(2);
						}
					}
				}

				eventsToInsert.add(newEvent);
			}
		}

		return eventsToInsert;
	}

	/**
	 * @description Surfaces Apex failures to LWC without masking AuraHandledException messages.
	 */
	private static void throwCreateProjectException(Exception e) {
		if (e instanceof AuraHandledException) {
			throw (AuraHandledException) e;
		}
		if (e instanceof DmlException) {
			DmlException dml = (DmlException) e;
			if (dml.getNumDml() > 0) {
				throw new AuraHandledException(formatCaseLinkDmlError(dml.getDmlMessage(0)));
			}
		}
		throw new AuraHandledException('Error creating project: ' + e.getMessage());
	}

	private static String formatCaseLinkDmlError(String dmlMessage) {
		if (String.isBlank(dmlMessage)) {
			return 'Error creating project.';
		}
		if (dmlMessage.contains('INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY') && dmlMessage.contains('Case')) {
			return 'Unable to link the selected Case(s) to this project. You may need Read or Edit access on those Case records. Ask your Salesforce administrator to review Case object permissions and sharing.';
		}
		return 'Error creating project: ' + dmlMessage;
	}

	/**
	 * @description Insert tasks and events in bulk
	 * @param tasks List of tasks to insert
	 * @param events List of events to insert
	 */
	private static void insertTasksAndEvents(List<Task> tasks, List<Event> events) {
		if (!tasks.isEmpty()) {
			Database.insert(tasks, AccessLevel.USER_MODE);
		}

		if (!events.isEmpty()) {
			Database.insert(events, AccessLevel.USER_MODE);
		}
	}

	/**
	 * @description Creates a new project with associated tasks and events
	 * @param projectData JSON string containing project details
	 * @return ID of the newly created Project__c record
	 */
	@AuraEnabled
	public static Id createProject(String projectData) {
		try {
			ProjectDataWrapper wrapper = parseProjectData(projectData);
			Date projectEndDate = calculateProjectEndDate(wrapper.items);
			Map<Integer, Id> ownerIdsByIndex = resolveItemOwnerIds(wrapper.items);
			Set<String> mandatoryItemIds = resolveCannotBeDeletedItemIds(wrapper.projectTemplateId, wrapper.items);

			Set<Id> validatedCaseIds = resolveValidatedCaseIds(wrapper.caseIds);
			Id primaryCaseId = resolvePrimaryCaseId(wrapper.caseIds, validatedCaseIds);

			Project__c newProject = buildProjectRecord(wrapper, projectEndDate, primaryCaseId);
			ProjectCreateDml projectDml = new ProjectCreateDml();
			projectDml.insertProject(newProject);
			projectDml.insertProjectCaseJunctions(
				buildProjectCaseJunctionRows(validatedCaseIds, newProject.Id)
			);

			List<Task> tasks = createTasksFromItems(wrapper.items, newProject.Id, ownerIdsByIndex, mandatoryItemIds);
			List<Event> events = createEventsFromItems(wrapper.items, newProject.Id, ownerIdsByIndex, mandatoryItemIds);
			insertTasksAndEvents(tasks, events);

			return newProject.Id;
		} catch (Exception e) {
			throwCreateProjectException(e);
			return null;
		}
	}

	/**
	 * @description Check if a case already has related projects
	 * @param caseId The Case record ID
	 * @return Boolean true if the case has at least one related project
	 */
	@AuraEnabled
	public static Boolean hasRelatedProjects(Id caseId) {
		try {
			if (caseId == null) {
				return false;
			}

			if (resolveProjectCasesJunctionType() != null) {
				Integer junctionCount = Database.countQuery(
					'SELECT COUNT() FROM ProjectCases__c WHERE Case__c = :caseId WITH USER_MODE'
				);
				if (junctionCount > 0) {
					return true;
				}
			}

			Integer projectCount = [
				SELECT COUNT()
				FROM Project__c
				WHERE PrimaryCase__c = :caseId
				WITH USER_MODE
			];

			return projectCount > 0;
		} catch (Exception e) {
			throw new AuraHandledException('Error checking related projects: ' + e.getMessage());
		}
	}
}