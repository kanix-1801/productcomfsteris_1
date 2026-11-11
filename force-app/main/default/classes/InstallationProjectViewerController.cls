/**
 * Loads Tasks and Events tied to a Project for installationProjectViewer LWC.
 * New root lines are Events; new sublines are Tasks.
 * Event "completed" filtering uses Status__c or Completed__c when those fields exist.
 */
public with sharing class InstallationProjectViewerController {
	private static final String OBJECT_API_TASK = 'Task';
	private static final String OBJECT_API_EVENT = 'Event';
	private static final String TYPE_LABEL_TASK = 'Task';
	private static final String TYPE_LABEL_EVENT = 'Event';

	/**
	 * Task Status API values treated as terminal (completed/cancelled) when IsClosed is false.
	 * Uses exact picklist API value match (trimmed, lowercased), not substring matching.
	 */
	private static final Set<String> TASK_TERMINAL_STATUS_LOWER = new Set<String>{
		'completed',
		'cancelled',
		'canceled',
		'done',
		'closed'
	};

	/** Existing permission set API name: Read Installation Projects (read-only viewer). */
	public static final String READ_INSTALLATION_PROJECTS_PERMISSION_SET_NAME = 'ReadInstallationProjects';

	/**
	 * True when the running user has read-only installation project viewer access.
	 */
	@AuraEnabled
	public static Boolean isReadOnlyInstallationProjectViewer() {
		return InstallationProjectViewerAccessService.hasReadOnlyInstallationProjectViewerAccess();
	}

	private static void assertCanEditInstallationProjectViewer() {
		if (InstallationProjectViewerAccessService.hasReadOnlyInstallationProjectViewerAccess()) {
			throw new AuraHandledException(
				'You have read-only access to installation projects and cannot change project activities.'
			);
		}
	}

	@TestVisible
	private static Boolean isCancelledStatus(String statusValue) {
		return String.isNotBlank(statusValue) && statusValue.trim().toLowerCase().contains('cancel');
	}

	private static void assertStatusAllowedForCannotBeDeleted(Boolean cannotBeDeleted, String statusValue) {
		if (cannotBeDeleted == true && isCancelledStatus(statusValue)) {
			throw new AuraHandledException(
				'This item is required by the project template and cannot be cancelled.'
			);
		}
	}

	private static void assertAssignableOwnerId(Id ownerId) {
		if (!ProjectItemSequenceUtil.isAssignableUserId(ownerId)) {
			throw new AuraHandledException(
				'Selected user is not available for assignment. Choose an active user that is not an integration or generic account.'
			);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<ProjectItemRow> getProjectItems(
		Id projectId,
		Boolean hideCompleted,
		Boolean hidePastDue
	) {
		if (projectId == null) {
			return new List<ProjectItemRow>();
		}
		hideCompleted = hideCompleted == true;
		hidePastDue = hidePastDue == true;

		List<ProjectItemRow> rows = new List<ProjectItemRow>();
		rows.addAll(queryProjectLineActivities(projectId, OBJECT_API_TASK, hideCompleted, hidePastDue));
		rows.addAll(queryProjectLineActivities(projectId, OBJECT_API_EVENT, hideCompleted, hidePastDue));

		rows.sort(new ProjectItemSequenceComparator());
		return rows;
	}

	/** Loads Task or Event rows for the viewer; pass OBJECT_API_TASK or OBJECT_API_EVENT. */
	private static List<ProjectItemRow> queryProjectLineActivities(
		Id projectId,
		String activityObjectApiName,
		Boolean hideCompleted,
		Boolean hidePastDue
	) {
		List<ProjectItemRow> out = new List<ProjectItemRow>();
		if (OBJECT_API_TASK.equals(activityObjectApiName)) {
			List<String> selectParts = new List<String>{
				'Id',
				'Subject',
				'ProjectItemSequence__c',
				'ActivityDate',
				'Status',
				'IsClosed',
				'OwnerId',
				'Owner.Name',
				'CannotBeDeleted__c'
			};
			String soql =
				'SELECT ' +
				String.join(selectParts, ', ') +
				' FROM Task WHERE Project__c = :projectId WITH USER_MODE';
			List<Task> tasks = Database.query(soql);
			Date today = Date.today();
			for (Task t : tasks) {
				if (hideCompleted && isTaskCompleted(t)) {
					continue;
				}
				if (hidePastDue && t.ActivityDate != null && t.ActivityDate < today) {
					continue;
				}
				ProjectItemRow r = new ProjectItemRow();
				r.recordId = t.Id;
				r.objectApiName = OBJECT_API_TASK;
				r.typeLabel = TYPE_LABEL_TASK;
				r.sequence = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
				r.title = t.Subject;
				r.dueDate = t.ActivityDate;
				r.ownerId = t.OwnerId;
				r.assignedToName = t.Owner != null ? t.Owner.Name : null;
				r.status = t.Status;
				r.isCompleted = isTaskCompleted(t);
				r.cannotBeDeleted = t.CannotBeDeleted__c == true;
				out.add(r);
			}
			return out;
		}
		if (OBJECT_API_EVENT.equals(activityObjectApiName)) {
			Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();
			List<String> selectParts = new List<String>{
				'Id',
				'Subject',
				'ProjectItemSequence__c',
				'StartDateTime',
				'EndDateTime',
				'OwnerId',
				'Owner.Name',
				'CannotBeDeleted__c'
			};
			if (eventFields.containsKey('status__c')) {
				selectParts.add('Status__c');
			}
			if (eventFields.containsKey('completed__c')) {
				selectParts.add('Completed__c');
			}
			String soql =
				'SELECT ' +
				String.join(selectParts, ', ') +
				' FROM Event WHERE Project__c = :projectId WITH USER_MODE';
			List<Event> events = Database.query(soql);
			Datetime nowDt = Datetime.now();
			for (Event e : events) {
				if (hideCompleted && isEventCompleted(e, eventFields)) {
					continue;
				}
				if (hidePastDue && e.EndDateTime != null && e.EndDateTime < nowDt) {
					continue;
				}
				ProjectItemRow r = new ProjectItemRow();
				r.recordId = e.Id;
				r.objectApiName = OBJECT_API_EVENT;
				r.typeLabel = TYPE_LABEL_EVENT;
				r.sequence = ProjectItemSequenceUtil.sequenceToString(e.get('ProjectItemSequence__c'));
				r.title = e.Subject;
				if (e.EndDateTime != null) {
					r.dueDate = e.EndDateTime.date();
				}
				r.ownerId = e.OwnerId;
				r.assignedToName = e.Owner != null ? e.Owner.Name : null;
				r.status = eventStatusDisplay(e, eventFields);
				r.isCompleted = isEventCompleted(e, eventFields);
				r.cannotBeDeleted = e.CannotBeDeleted__c == true;
				out.add(r);
			}
			return out;
		}
		return out;
	}

	private enum ProjectLineDateCascadeScope {
		AD_HOC_ONLY,
		TEMPLATE_ONLY
	}

	/** Template-backed rows keep dates from template rules; manual viewer cascade/shift must not move them. */
	private static Boolean isTemplateBackedProjectLine(SObject rec) {
		return ProjectItemSequenceUtil.getTemplateItemNumber(rec) != null;
	}

	private static Boolean matchesDateCascadeScope(SObject rec, ProjectLineDateCascadeScope scope) {
		Boolean templateBacked = isTemplateBackedProjectLine(rec);
		return scope == ProjectLineDateCascadeScope.TEMPLATE_ONLY ? templateBacked : !templateBacked;
	}

	private static ProjectLineDateCascadeScope resolveDateCascadeScope(SObject anchor) {
		return isTemplateBackedProjectLine(anchor)
			? ProjectLineDateCascadeScope.TEMPLATE_ONLY
			: ProjectLineDateCascadeScope.AD_HOC_ONLY;
	}

	/**
	 * When a parent line's due date changes, align sequence descendants under that line (same scope as anchor).
	 */
	private static void cascadeDueDateToDescendantProjectItems(
		Id projectId,
		String parentSequence,
		Date targetDate,
		Id excludeRecordId,
		ProjectLineDateCascadeScope scope
	) {
		if (projectId == null || String.isBlank(parentSequence) || targetDate == null) {
			return;
		}
		String ancestor = ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(parentSequence.trim());
		if (String.isBlank(ancestor)) {
			return;
		}
		Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();

		List<Task> taskUpdates = new List<Task>();
		for (Task t : [
			SELECT Id, ProjectItemSequence__c, TemplateItemNumber__c, ActivityDate, Status, IsClosed
			FROM Task
			WHERE Project__c = :projectId AND Id != :excludeRecordId
			WITH USER_MODE
		]) {
			if (isTaskCompleted(t)) {
				continue;
			}
			if (!matchesDateCascadeScope(t, scope)) {
				continue;
			}
			String childSeq = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
			if (!ProjectItemSequenceUtil.isSequenceStrictDescendantOf(ancestor, childSeq)) {
				continue;
			}
			if (t.ActivityDate != targetDate) {
				t.ActivityDate = targetDate;
				taskUpdates.add(t);
			}
		}
		if (!taskUpdates.isEmpty()) {
			update taskUpdates;
		}

		List<String> eventSelectParts = buildEventCascadeSelectParts(eventFields);
		String eventSoql =
			'SELECT ' +
			String.join(eventSelectParts, ', ') +
			' FROM Event WHERE Project__c = :projectId AND Id != :excludeRecordId WITH USER_MODE';

		List<Event> eventUpdates = new List<Event>();
		for (Event ev : Database.query(eventSoql)) {
			if (isEventCompleted(ev, eventFields)) {
				continue;
			}
			if (!matchesDateCascadeScope(ev, scope)) {
				continue;
			}
			String childSeq = ProjectItemSequenceUtil.sequenceToString(ev.get('ProjectItemSequence__c'));
			if (!ProjectItemSequenceUtil.isSequenceStrictDescendantOf(ancestor, childSeq)) {
				continue;
			}
			if (applyCascadeTargetDateToEvent(ev, targetDate)) {
				eventUpdates.add(ev);
			}
		}
		if (!eventUpdates.isEmpty()) {
			update eventUpdates;
		}
	}

	private static List<String> buildEventCascadeSelectParts(Map<String, Schema.SObjectField> eventFields) {
		List<String> parts = new List<String>{
			'Id',
			'ProjectItemSequence__c',
			'TemplateItemNumber__c',
			'EndDateTime',
			'StartDateTime',
			'IsAllDayEvent',
			'ActivityDate'
		};
		if (eventFields.containsKey('status__c')) {
			parts.add('Status__c');
		}
		if (eventFields.containsKey('completed__c')) {
			parts.add('Completed__c');
		}
		return parts;
	}

	/**
	 * Due date used for Event delta when the viewer edits the date (all-day: ActivityDate; timed: End date).
	 */
	private static Date resolveEventDueDateBeforeUpdate(Event e) {
		if (e.IsAllDayEvent == true) {
			return e.ActivityDate;
		}
		if (e.EndDateTime != null) {
			return e.EndDateTime.date();
		}
		return e.ActivityDate;
	}

	/**
	 * Shifts later Tasks/Events in sequence order by the same calendar delta (same scope as edited anchor).
	 */
	private static void shiftOpenProjectItemsAfterSequenceByDelta(
		Id projectId,
		String anchorSequence,
		Integer deltaDays,
		Id excludeRecordId,
		ProjectLineDateCascadeScope scope
	) {
		if (projectId == null || deltaDays == null || deltaDays == 0) {
			return;
		}
		if (String.isBlank(anchorSequence)) {
			return;
		}
		String anchorKey = ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(anchorSequence.trim());
		if (String.isBlank(anchorKey)) {
			return;
		}
		Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();

		List<Task> taskUpdates = new List<Task>();
		for (Task t : [
			SELECT Id, ProjectItemSequence__c, TemplateItemNumber__c, ActivityDate, Status, IsClosed
			FROM Task
			WHERE Project__c = :projectId AND Id != :excludeRecordId
			WITH USER_MODE
		]) {
			if (isTaskCompleted(t)) {
				continue;
			}
			if (!matchesDateCascadeScope(t, scope)) {
				continue;
			}
			String childSeq = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
			if (String.isBlank(childSeq)) {
				continue;
			}
			childSeq = childSeq.trim();
			if (ProjectItemSequenceUtil.compareSequences(childSeq, anchorKey) <= 0) {
				continue;
			}
			if (ProjectItemSequenceUtil.isSequenceStrictDescendantOf(anchorKey, childSeq)) {
				continue;
			}
			if (t.ActivityDate != null) {
				t.ActivityDate = t.ActivityDate.addDays(deltaDays);
				taskUpdates.add(t);
			}
		}
		if (!taskUpdates.isEmpty()) {
			update taskUpdates;
		}

		String eventSoql =
			'SELECT ' +
			String.join(buildEventCascadeSelectParts(eventFields), ', ') +
			' FROM Event WHERE Project__c = :projectId AND Id != :excludeRecordId WITH USER_MODE';

		List<Event> eventUpdates = new List<Event>();
		for (Event ev : Database.query(eventSoql)) {
			if (isEventCompleted(ev, eventFields)) {
				continue;
			}
			if (!matchesDateCascadeScope(ev, scope)) {
				continue;
			}
			String childSeq = ProjectItemSequenceUtil.sequenceToString(ev.get('ProjectItemSequence__c'));
			if (String.isBlank(childSeq)) {
				continue;
			}
			childSeq = childSeq.trim();
			if (ProjectItemSequenceUtil.compareSequences(childSeq, anchorKey) <= 0) {
				continue;
			}
			if (ProjectItemSequenceUtil.isSequenceStrictDescendantOf(anchorKey, childSeq)) {
				continue;
			}
			if (applyDeltaDaysToOpenEvent(ev, deltaDays)) {
				eventUpdates.add(ev);
			}
		}
		if (!eventUpdates.isEmpty()) {
			update eventUpdates;
		}
	}

	/**
	 * @return true if the event was modified and should be included in an update DML.
	 */
	private static Boolean applyDeltaDaysToOpenEvent(Event ev, Integer deltaDays) {
		if (deltaDays == null || deltaDays == 0) {
			return false;
		}
		if (ev.IsAllDayEvent == true) {
			if (ev.ActivityDate == null) {
				return false;
			}
			ev.ActivityDate = ev.ActivityDate.addDays(deltaDays);
			syncAllDayEventStartEndFromActivityDate(ev);
			return true;
		}
		Boolean changed = false;
		if (ev.EndDateTime != null) {
			ev.EndDateTime = ev.EndDateTime.addDays(deltaDays);
			changed = true;
		}
		if (ev.StartDateTime != null) {
			ev.StartDateTime = ev.StartDateTime.addDays(deltaDays);
			changed = true;
		}
		return changed;
	}

	/**
	 * Moves the event to the given calendar date; preserves same-day duration for timed events.
	 * @return true if any field was changed and the row should be included in an update DML.
	 */
	private static Boolean applyCascadeTargetDateToEvent(Event ev, Date targetDate) {
		if (ev.IsAllDayEvent == true) {
			if (ev.ActivityDate != targetDate) {
				ev.ActivityDate = targetDate;
				syncAllDayEventStartEndFromActivityDate(ev);
				return true;
			}
			return false;
		}

		Datetime oldEnd = ev.EndDateTime;
		Datetime oldStart = ev.StartDateTime;
		Time endT = oldEnd != null ? oldEnd.time() : Time.newInstance(17, 0, 0, 0);
		Datetime newEnd = DateTime.newInstance(targetDate, endT);

		if (oldEnd != null && oldEnd.getTime() == newEnd.getTime()) {
			return false;
		}

		ev.EndDateTime = newEnd;
		if (oldStart != null && oldEnd != null) {
			Long durMs = oldEnd.getTime() - oldStart.getTime();
			if (durMs > 0) {
				Long durSecLong = durMs / 1000;
				Integer durSec = durSecLong > 2147483647L ? 2147483647 : (Integer) durSecLong;
				ev.StartDateTime = newEnd.addSeconds(-durSec);
			} else if (ev.StartDateTime != null && ev.EndDateTime < ev.StartDateTime) {
				ev.StartDateTime = ev.EndDateTime.addHours(-1);
			}
		} else if (ev.StartDateTime != null && ev.EndDateTime < ev.StartDateTime) {
			ev.StartDateTime = ev.EndDateTime.addHours(-1);
		}
		return true;
	}

	/** Keeps StartDateTime/EndDateTime aligned with ActivityDate for all-day Event DML. */
	private static void syncAllDayEventStartEndFromActivityDate(Event ev) {
		if (ev == null || ev.IsAllDayEvent != true || ev.ActivityDate == null) {
			return;
		}
		Date d = ev.ActivityDate;
		ev.StartDateTime = Datetime.newInstanceGmt(d.year(), d.month(), d.day(), 0, 0, 0);
		ev.EndDateTime = ev.StartDateTime.addDays(1);
	}

	private static Boolean isTaskCompleted(Task t) {
		if (t.IsClosed == true) {
			return true;
		}
		if (String.isNotBlank(t.Status)) {
			String taskStatus = t.Status.trim().toLowerCase();
			if (TASK_TERMINAL_STATUS_LOWER.contains(taskStatus)) {
				return true;
			}
		}
		return false;
	}

	private static Boolean isEventCompleted(Event e, Map<String, Schema.SObjectField> eventFields) {
		if (eventFields.containsKey('completed__c')) {
			Object v = e.get('Completed__c');
			if (v instanceof Boolean && (Boolean) v == true) {
				return true;
			}
			if (v instanceof String) {
				String vs = ((String) v).trim().toLowerCase();
				if (vs == 'true' || vs == 'yes' || vs == '1') {
					return true;
				}
			}
		}
		if (eventFields.containsKey('status__c')) {
			String s = (String) e.get('Status__c');
			if (String.isNotBlank(s) && eventStatusLooksCompleted(s)) {
				return true;
			}
		}
		return false;
	}

	/**
	 * Aligns with common Event status picklist API values and phrases (org-specific labels may differ).
	 */
	private static Boolean eventStatusLooksCompleted(String status) {
		String t = status.trim().toLowerCase();
		if (t.contains('complete') || t.contains('cancel')) {
			return true;
		}
		if (t == 'done' || t == 'closed' || t == 'completed') {
			return true;
		}
		return false;
	}

	private static String eventStatusDisplay(Event e, Map<String, Schema.SObjectField> eventFields) {
		if (eventFields.containsKey('status__c') && e.get('Status__c') != null) {
			return String.valueOf(e.get('Status__c'));
		}
		return '';
	}

	public class ProjectItemRow {
		@AuraEnabled public Id recordId;
		@AuraEnabled public String objectApiName;
		@AuraEnabled public String typeLabel;
		@AuraEnabled public String sequence;
		@AuraEnabled public String title;
		@AuraEnabled public Date dueDate;
		@AuraEnabled public Id ownerId;
		@AuraEnabled public String assignedToName;
		@AuraEnabled public String status;
		@AuraEnabled public Boolean isCompleted;
		@AuraEnabled public Boolean cannotBeDeleted;
	}

	public class PicklistOption {
		@AuraEnabled public String label;
		@AuraEnabled public String value;
	}

	@AuraEnabled(cacheable=true)
	public static List<PicklistOption> getStatusPicklistOptions(String objectApiName) {
		List<PicklistOption> opts = new List<PicklistOption>();
		if (String.isBlank(objectApiName)) {
			return opts;
		}
		if (OBJECT_API_TASK.equals(objectApiName)) {
			for (Schema.PicklistEntry pe : Task.Status.getDescribe().getPicklistValues()) {
				if (pe.isActive()) {
					PicklistOption o = new PicklistOption();
					o.label = pe.getLabel();
					o.value = pe.getValue();
					opts.add(o);
				}
			}
		} else if (OBJECT_API_EVENT.equals(objectApiName)) {
			Map<String, Schema.SObjectField> fm = Schema.SObjectType.Event.fields.getMap();
			if (!fm.containsKey('status__c')) {
				return opts;
			}
			Schema.DescribeFieldResult dfr = fm.get('status__c').getDescribe();
			for (Schema.PicklistEntry pe : dfr.getPicklistValues()) {
				if (pe.isActive()) {
					PicklistOption o = new PicklistOption();
					o.label = pe.getLabel();
					o.value = pe.getValue();
					opts.add(o);
				}
			}
		}
		return opts;
	}

	/**
	 * Active assignable users for Assigned To (delegates to ProjectItemSequenceUtil).
	 */
	@AuraEnabled(cacheable=true)
	public static List<PicklistOption> getInternalUsersPicklist() {
		return ProjectItemSequenceUtil.getAssignableUsersPicklist();
	}

	private static void throwViewerSaveException(Exception e) {
		if (e instanceof AuraHandledException) {
			throw (AuraHandledException) e;
		}
		if (e instanceof DmlException) {
			DmlException dml = (DmlException) e;
			if (dml.getNumDml() > 0) {
				throw new AuraHandledException(dml.getDmlMessage(0));
			}
		}
		if (e instanceof QueryException) {
			throw new AuraHandledException('Could not save project item: ' + e.getMessage());
		}
		throw new AuraHandledException(
			String.isNotBlank(e.getMessage()) ? e.getMessage() : 'Could not save project item.'
		);
	}

	@AuraEnabled
	public static void updateProjectItem(
		Id recordId,
		String objectApiName,
		String statusValue,
		Id ownerId,
		String dueDateIso,
		String subjectValue
	) {
		try {
			updateProjectItemInternal(
				recordId,
				objectApiName,
				statusValue,
				ownerId,
				dueDateIso,
				subjectValue
			);
		} catch (Exception e) {
			throwViewerSaveException(e);
		}
	}

	private static void updateProjectItemInternal(
		Id recordId,
		String objectApiName,
		String statusValue,
		Id ownerId,
		String dueDateIso,
		String subjectValue
	) {
		assertCanEditInstallationProjectViewer();
		if (recordId == null || String.isBlank(objectApiName)) {
			throw new AuraHandledException('Invalid record.');
		}
		if (OBJECT_API_TASK.equals(objectApiName)) {
			Task t = [
				SELECT
					Id,
					Subject,
					Status,
					OwnerId,
					ActivityDate,
					Project__c,
					ProjectItemSequence__c,
					TemplateItemNumber__c,
					CannotBeDeleted__c
				FROM Task
				WHERE Id = :recordId
				WITH USER_MODE
				LIMIT 1
			];
			Date oldActivityDate = t.ActivityDate;
			if (subjectValue != null) {
				t.Subject = subjectValue;
			}
			if (String.isNotBlank(statusValue)) {
				assertStatusAllowedForCannotBeDeleted(t.CannotBeDeleted__c, statusValue);
				t.Status = statusValue;
			}
			if (ownerId != null) {
				assertAssignableOwnerId(ownerId);
				t.OwnerId = ownerId;
			}
			Boolean dateChanged = false;
			if (String.isNotBlank(dueDateIso)) {
				Date newD = Date.valueOf(dueDateIso);
				dateChanged = oldActivityDate != newD;
				t.ActivityDate = newD;
			}
			update t;
			if (dateChanged && t.Project__c != null && t.ActivityDate != null) {
				String anchorSequence = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
				ProjectLineDateCascadeScope scope = resolveDateCascadeScope(t);
				cascadeDueDateToDescendantProjectItems(
					t.Project__c,
					anchorSequence,
					t.ActivityDate,
					t.Id,
					scope
				);
				if (
					ProjectItemSequenceUtil.isRootMainProjectLineSequence(anchorSequence) &&
					oldActivityDate != null
				) {
					Integer deltaDays = oldActivityDate.daysBetween(t.ActivityDate);
					if (deltaDays != 0) {
						shiftOpenProjectItemsAfterSequenceByDelta(
							t.Project__c,
							anchorSequence,
							deltaDays,
							t.Id,
							scope
						);
					}
				}
			}
		} else if (OBJECT_API_EVENT.equals(objectApiName)) {
			Event e = [
				SELECT
					Id,
					Subject,
					OwnerId,
					EndDateTime,
					StartDateTime,
					IsAllDayEvent,
					ActivityDate,
					Project__c,
					ProjectItemSequence__c,
					TemplateItemNumber__c,
					CannotBeDeleted__c
				FROM Event
				WHERE Id = :recordId
				WITH USER_MODE
				LIMIT 1
			];
			if (subjectValue != null) {
				e.Subject = subjectValue;
			}
			Map<String, Schema.SObjectField> fm = Schema.SObjectType.Event.fields.getMap();
			if (fm.containsKey('status__c') && String.isNotBlank(statusValue)) {
				assertStatusAllowedForCannotBeDeleted(e.CannotBeDeleted__c, statusValue);
				e.put('Status__c', statusValue);
			}
			if (ownerId != null) {
				assertAssignableOwnerId(ownerId);
				e.OwnerId = ownerId;
			}
			Date oldEventDue = resolveEventDueDateBeforeUpdate(e);
			Date requestedDueDate = null;
			Boolean hasDueDateUpdate = String.isNotBlank(dueDateIso);
			if (hasDueDateUpdate) {
				requestedDueDate = Date.valueOf(dueDateIso);
				applyCascadeTargetDateToEvent(e, requestedDueDate);
			}
			update e;
			Integer deltaDays = 0;
			if (hasDueDateUpdate && oldEventDue != null && requestedDueDate != null) {
				deltaDays = oldEventDue.daysBetween(requestedDueDate);
			}
			if (hasDueDateUpdate && e.Project__c != null) {
				Date cascadeAnchorDate = requestedDueDate != null
					? requestedDueDate
					: (
						e.IsAllDayEvent == true
							? e.ActivityDate
							: (e.EndDateTime != null ? e.EndDateTime.date() : null)
					);
				if (cascadeAnchorDate != null) {
					ProjectLineDateCascadeScope scope = resolveDateCascadeScope(e);
					cascadeDueDateToDescendantProjectItems(
						e.Project__c,
						ProjectItemSequenceUtil.sequenceToString(e.get('ProjectItemSequence__c')),
						cascadeAnchorDate,
						e.Id,
						scope
					);
					if (deltaDays != 0) {
						shiftOpenProjectItemsAfterSequenceByDelta(
							e.Project__c,
							ProjectItemSequenceUtil.sequenceToString(e.get('ProjectItemSequence__c')),
							deltaDays,
							e.Id,
							scope
						);
					}
				}
			}
		} else {
			throw new AuraHandledException('Unsupported record type.');
		}
	}

	public class MassActionResult {
		@AuraEnabled public Integer updatedCount = 0;
		@AuraEnabled public List<String> skippedRequired = new List<String>();
		@AuraEnabled public List<String> skippedCompleted = new List<String>();
	}

	/**
	 * Sets the selected Tasks/Events to the cancelled status. Skips completed rows and rows marked Cannot be Deleted.
	 */
	@AuraEnabled
	public static MassActionResult massCancelProjectItems(List<Id> recordIds) {
		try {
			assertCanEditInstallationProjectViewer();
			MassActionResult result = new MassActionResult();
			Set<Id> taskIds = filterIdsByType(recordIds, Task.SObjectType);
			Set<Id> eventIds = filterIdsByType(recordIds, Event.SObjectType);
			Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();

			List<Task> taskUpdates = new List<Task>();
			if (!taskIds.isEmpty()) {
				String taskCancelStatus = resolveCancelledStatus(Task.Status.getDescribe());
				for (Task t : [
					SELECT Id, Subject, Status, IsClosed, CannotBeDeleted__c
					FROM Task
					WHERE Id IN :taskIds
					WITH USER_MODE
				]) {
					if (t.CannotBeDeleted__c == true) {
						result.skippedRequired.add(t.Subject);
					} else if (isTaskCompleted(t)) {
						result.skippedCompleted.add(t.Subject);
					} else {
						t.Status = taskCancelStatus;
						taskUpdates.add(t);
					}
				}
			}

			List<Event> eventUpdates = new List<Event>();
			if (!eventIds.isEmpty() && eventFields.containsKey('status__c')) {
				String eventCancelStatus = resolveCancelledStatus(eventFields.get('status__c').getDescribe());
				List<String> selectParts = buildEventCascadeSelectParts(eventFields);
				selectParts.addAll(new List<String>{ 'Subject', 'CannotBeDeleted__c' });
				String eventSoql =
					'SELECT ' +
					String.join(selectParts, ', ') +
					' FROM Event WHERE Id IN :eventIds WITH USER_MODE';
				for (Event e : Database.query(eventSoql)) {
					if (e.CannotBeDeleted__c == true) {
						result.skippedRequired.add(e.Subject);
					} else if (isEventCompleted(e, eventFields)) {
						result.skippedCompleted.add(e.Subject);
					} else {
						e.put('Status__c', eventCancelStatus);
						eventUpdates.add(e);
					}
				}
			}

			if (!taskUpdates.isEmpty()) {
				update taskUpdates;
			}
			if (!eventUpdates.isEmpty()) {
				update eventUpdates;
			}
			result.updatedCount = taskUpdates.size() + eventUpdates.size();
			return result;
		} catch (Exception e) {
			throwViewerSaveException(e);
			return null;
		}
	}

	/**
	 * Assigns the selected open Tasks/Events to ownerId. Completed rows are skipped.
	 */
	@AuraEnabled
	public static MassActionResult massUpdateProjectItemOwner(List<Id> recordIds, Id ownerId) {
		try {
			assertCanEditInstallationProjectViewer();
			assertAssignableOwnerId(ownerId);
			MassActionResult result = new MassActionResult();
			Set<Id> taskIds = filterIdsByType(recordIds, Task.SObjectType);
			Set<Id> eventIds = filterIdsByType(recordIds, Event.SObjectType);
			Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();

			List<Task> taskUpdates = new List<Task>();
			if (!taskIds.isEmpty()) {
				for (Task t : [
					SELECT Id, Subject, Status, IsClosed, OwnerId
					FROM Task
					WHERE Id IN :taskIds
					WITH USER_MODE
				]) {
					if (isTaskCompleted(t)) {
						result.skippedCompleted.add(t.Subject);
					} else {
						t.OwnerId = ownerId;
						taskUpdates.add(t);
					}
				}
			}

			List<Event> eventUpdates = new List<Event>();
			if (!eventIds.isEmpty()) {
				List<String> selectParts = buildEventCascadeSelectParts(eventFields);
				selectParts.addAll(new List<String>{ 'Subject', 'OwnerId' });
				String eventSoql =
					'SELECT ' +
					String.join(selectParts, ', ') +
					' FROM Event WHERE Id IN :eventIds WITH USER_MODE';
				for (Event e : Database.query(eventSoql)) {
					if (isEventCompleted(e, eventFields)) {
						result.skippedCompleted.add(e.Subject);
					} else {
						e.OwnerId = ownerId;
						eventUpdates.add(e);
					}
				}
			}

			if (!taskUpdates.isEmpty()) {
				update taskUpdates;
			}
			if (!eventUpdates.isEmpty()) {
				update eventUpdates;
			}
			result.updatedCount = taskUpdates.size() + eventUpdates.size();
			return result;
		} catch (Exception e) {
			throwViewerSaveException(e);
			return null;
		}
	}

	private static Set<Id> filterIdsByType(List<Id> recordIds, Schema.SObjectType targetType) {
		Set<Id> out = new Set<Id>();
		if (recordIds == null) {
			return out;
		}
		for (Id recordId : recordIds) {
			if (recordId != null && recordId.getSobjectType() == targetType) {
				out.add(recordId);
			}
		}
		return out;
	}

	private static String resolveCancelledStatus(Schema.DescribeFieldResult statusDescribe) {
		for (Schema.PicklistEntry pe : statusDescribe.getPicklistValues()) {
			if (pe.isActive() && isCancelledStatus(pe.getValue())) {
				return pe.getValue();
			}
		}
		throw new AuraHandledException('No cancelled status is available for ' + statusDescribe.getLabel() + '.');
	}

	/**
	 * Creates a new Task under parentSequence as the next direct child (e.g. 2 → 2.1 or 2.3 when 2.1 and 2.2 exist).
	 * Activity date matches the anchor row; Subject defaults so Details can be edited in the viewer.
	 */
	@AuraEnabled
	public static Id createProjectSubline(
		Id projectId,
		String parentSequence,
		Id anchorRecordId,
		String anchorObjectApiName
	) {
		assertCanEditInstallationProjectViewer();
		if (projectId == null || String.isBlank(parentSequence) || anchorRecordId == null || String.isBlank(anchorObjectApiName)) {
			throw new AuraHandledException('Missing required values.');
		}
		if (!Task.sObjectType.getDescribe().isCreateable()) {
			throw new AuraHandledException('You cannot create tasks.');
		}
		String parentKey = ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(parentSequence.trim());
		if (String.isBlank(parentKey)) {
			throw new AuraHandledException('Set a sequence on the parent row before adding a subline.');
		}

		Date dueDate = resolveAnchorActivityDate(anchorRecordId, anchorObjectApiName);
		Decimal maxDirectSuffix = -1;

		for (Task t : [
			SELECT ProjectItemSequence__c
			FROM Task
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String childSeq = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
			if (!isDirectChildSequence(parentKey, childSeq)) {
				continue;
			}
			String rest = childSeq.substring(parentKey.length() + 1);
			try {
				Decimal suf = Decimal.valueOf(rest.trim());
				if (suf > maxDirectSuffix) {
					maxDirectSuffix = suf;
				}
			} catch (Exception ignore) {
			}
		}
		for (Event ev : [
			SELECT ProjectItemSequence__c
			FROM Event
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String childSeq = ProjectItemSequenceUtil.sequenceToString(ev.get('ProjectItemSequence__c'));
			if (!isDirectChildSequence(parentKey, childSeq)) {
				continue;
			}
			String rest = childSeq.substring(parentKey.length() + 1);
			try {
				Decimal suf = Decimal.valueOf(rest.trim());
				if (suf > maxDirectSuffix) {
					maxDirectSuffix = suf;
				}
			} catch (Exception ignore) {
			}
		}

		Decimal nextSuffix = maxDirectSuffix < 0 ? 1 : maxDirectSuffix + 1;
		String newSeq = parentKey + '.' + formatSequenceSegment(nextSuffix);

		Task nt = buildProjectLineTask(projectId, newSeq, dueDate, 'New task');
		try {
			insert nt;
		} catch (DmlException dex) {
			String msg = dex.getNumDml() > 0 ? dex.getDmlMessage(0) : dex.getMessage();
			throw new AuraHandledException(String.isNotBlank(msg) ? msg : 'Could not create subline.');
		}
		return nt.Id;
	}

	/**
	 * Inserts a new root-level Event at (root + 1) and shifts ProjectItemSequence__c only (4→5, 4.1→5.1).
	 * TemplateItemNumber__c is not modified so template dependency identity stays stable.
	 */
	@AuraEnabled
	public static Id insertProjectRootLineAfterAndShift(
		Id projectId,
		String anchorSequence,
		Id anchorRecordId,
		String anchorObjectApiName
	) {
		assertCanEditInstallationProjectViewer();
		if (projectId == null || String.isBlank(anchorSequence) || anchorRecordId == null || String.isBlank(anchorObjectApiName)) {
			throw new AuraHandledException('Missing required values.');
		}
		if (!Event.sObjectType.getDescribe().isCreateable()) {
			throw new AuraHandledException('You cannot create events.');
		}
		Decimal rootVal = parseFirstSegmentAsDecimal(anchorSequence.trim());
		if (rootVal == null) {
			throw new AuraHandledException('Could not read the line number from this row.');
		}
		Decimal newRootInsert = rootVal + 1;

		Date dueDate = resolveAnchorActivityDate(anchorRecordId, anchorObjectApiName);

		List<Task> taskUpdates = new List<Task>();
		for (Task t : [
			SELECT Id, ProjectItemSequence__c
			FROM Task
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String seq = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
			if (String.isBlank(seq)) {
				continue;
			}
			Decimal r = parseFirstSegmentAsDecimal(seq);
			if (r == null || r < newRootInsert) {
				continue;
			}
			putProjectItemSequence(t, bumpSequenceRootUpByOne(seq));
			taskUpdates.add(t);
		}

		List<Event> eventUpdates = new List<Event>();
		for (Event ev : [
			SELECT Id, ProjectItemSequence__c
			FROM Event
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String seq = ProjectItemSequenceUtil.sequenceToString(ev.get('ProjectItemSequence__c'));
			if (String.isBlank(seq)) {
				continue;
			}
			Decimal r = parseFirstSegmentAsDecimal(seq);
			if (r == null || r < newRootInsert) {
				continue;
			}
			putProjectItemSequence(ev, bumpSequenceRootUpByOne(seq));
			eventUpdates.add(ev);
		}

		try {
			if (!taskUpdates.isEmpty()) {
				update taskUpdates;
			}
			if (!eventUpdates.isEmpty()) {
				update eventUpdates;
			}

			Event ne = buildProjectLineEvent(projectId, formatSequenceSegment(newRootInsert), dueDate, 'New event');
			insert ne;
			return ne.Id;
		} catch (DmlException dex) {
			String msg = dex.getNumDml() > 0 ? dex.getDmlMessage(0) : dex.getMessage();
			throw new AuraHandledException(String.isNotBlank(msg) ? msg : 'Could not insert or renumber lines.');
		}
	}

	/**
	 * Inserts a new root-level Event as line 1 and shifts every Task/Event whose root segment is >= 1 up by 1 (1→2, 1.1→2.1).
	 * Only valid when the anchor row is root line 1 (including 1.0 stored form).
	 */
	@AuraEnabled
	public static Id insertNewFirstRootLineAndShift(
		Id projectId,
		String anchorSequence,
		Id anchorRecordId,
		String anchorObjectApiName
	) {
		assertCanEditInstallationProjectViewer();
		if (projectId == null || String.isBlank(anchorSequence) || anchorRecordId == null || String.isBlank(anchorObjectApiName)) {
			throw new AuraHandledException('Missing required values.');
		}
		if (!Event.sObjectType.getDescribe().isCreateable()) {
			throw new AuraHandledException('You cannot create events.');
		}
		String anchorCanon = ProjectItemSequenceUtil.canonicalRootSequenceKeyForCascade(anchorSequence.trim());
		Decimal rootVal = parseFirstSegmentAsDecimal(anchorCanon);
		if (rootVal == null || rootVal != 1) {
			throw new AuraHandledException('This action is only available on line 1.');
		}

		Date dueDate = resolveAnchorActivityDate(anchorRecordId, anchorObjectApiName);
		Decimal newRootInsert = 1;

		List<Task> taskUpdates = new List<Task>();
		for (Task t : [
			SELECT Id, ProjectItemSequence__c
			FROM Task
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String seq = ProjectItemSequenceUtil.sequenceToString(t.get('ProjectItemSequence__c'));
			if (String.isBlank(seq)) {
				continue;
			}
			Decimal r = parseFirstSegmentAsDecimal(seq);
			if (r == null || r < newRootInsert) {
				continue;
			}
			putProjectItemSequence(t, bumpSequenceRootUpByOne(seq));
			taskUpdates.add(t);
		}

		List<Event> eventUpdates = new List<Event>();
		for (Event ev : [
			SELECT Id, ProjectItemSequence__c
			FROM Event
			WHERE Project__c = :projectId
			WITH USER_MODE
		]) {
			String seq = ProjectItemSequenceUtil.sequenceToString(ev.get('ProjectItemSequence__c'));
			if (String.isBlank(seq)) {
				continue;
			}
			Decimal r = parseFirstSegmentAsDecimal(seq);
			if (r == null || r < newRootInsert) {
				continue;
			}
			putProjectItemSequence(ev, bumpSequenceRootUpByOne(seq));
			eventUpdates.add(ev);
		}

		try {
			if (!taskUpdates.isEmpty()) {
				update taskUpdates;
			}
			if (!eventUpdates.isEmpty()) {
				update eventUpdates;
			}

			Event ne = buildProjectLineEvent(projectId, formatSequenceSegment(newRootInsert), dueDate, 'New event');
			insert ne;
			return ne.Id;
		} catch (DmlException dex) {
			String msg = dex.getNumDml() > 0 ? dex.getDmlMessage(0) : dex.getMessage();
			throw new AuraHandledException(String.isNotBlank(msg) ? msg : 'Could not insert or renumber lines.');
		}
	}

	private static Boolean isDirectChildSequence(String parentSeq, String childSeq) {
		if (String.isBlank(parentSeq) || String.isBlank(childSeq)) {
			return false;
		}
		String p = parentSeq.trim();
		String c = childSeq.trim();
		if (!c.startsWith(p + '.')) {
			return false;
		}
		String rest = c.substring(p.length() + 1);
		return !rest.contains('.');
	}

	private static Decimal parseFirstSegmentAsDecimal(String seq) {
		if (String.isBlank(seq)) {
			return null;
		}
		List<String> parts = seq.trim().split('\\.');
		if (parts.isEmpty()) {
			return null;
		}
		try {
			return Decimal.valueOf(parts[0].trim());
		} catch (Exception e) {
			return null;
		}
	}

	private static String bumpSequenceRootUpByOne(String seq) {
		if (String.isBlank(seq)) {
			return seq;
		}
		List<String> parts = seq.trim().split('\\.');
		if (parts.isEmpty()) {
			return seq;
		}
		Decimal d0 = Decimal.valueOf(parts[0].trim()) + 1;
		parts[0] = formatSequenceSegment(d0);
		return String.join(parts, '.');
	}

	private static String formatSequenceSegment(Decimal d) {
		if (d == null) {
			return '';
		}
		return String.valueOf(d);
	}

	private static void putProjectItemSequence(SObject rec, String seqString) {
		if (String.isBlank(seqString)) {
			throw new AuraHandledException('Sequence value is blank.');
		}
		Map<String, Schema.SObjectField> fm = rec.getSObjectType().getDescribe().fields.getMap();
		Schema.SObjectField f = fm.get('projectitemsequence__c');
		if (f == null) {
			throw new AuraHandledException('ProjectItemSequence__c was not found.');
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

	private static Date resolveAnchorActivityDate(Id anchorId, String objectApiName) {
		if (anchorId == null) {
			return Date.today();
		}
		if (OBJECT_API_TASK.equals(objectApiName)) {
			Task t = [
				SELECT ActivityDate
				FROM Task
				WHERE Id = :anchorId
				WITH USER_MODE
				LIMIT 1
			];
			return t.ActivityDate != null ? t.ActivityDate : Date.today();
		}
		if (OBJECT_API_EVENT.equals(objectApiName)) {
			Event e = [
				SELECT EndDateTime, ActivityDate, IsAllDayEvent
				FROM Event
				WHERE Id = :anchorId
				WITH USER_MODE
				LIMIT 1
			];
			if (e.IsAllDayEvent == true && e.ActivityDate != null) {
				return e.ActivityDate;
			}
			if (e.EndDateTime != null) {
				return e.EndDateTime.date();
			}
			return Date.today();
		}
		return Date.today();
	}

	private static Id ipmTaskRecordTypeId() {
		Map<String, Schema.RecordTypeInfo> byDev = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName();
		if (!byDev.containsKey('IPMTask')) {
			return null;
		}
		Schema.RecordTypeInfo rti = byDev.get('IPMTask');
		return rti != null && rti.isAvailable() ? rti.getRecordTypeId() : null;
	}

	private static Id ipmEventRecordTypeId() {
		Map<String, Schema.RecordTypeInfo> byDev = Schema.SObjectType.Event.getRecordTypeInfosByDeveloperName();
		if (!byDev.containsKey('IPMEvent')) {
			return null;
		}
		Schema.RecordTypeInfo rti = byDev.get('IPMEvent');
		return rti != null && rti.isAvailable() ? rti.getRecordTypeId() : null;
	}

	/**
	 * Timed Event on the given calendar date (10:00–12:00 local) for new project lines.
	 */
	private static Event buildProjectLineEvent(Id projectId, String newSeqString, Date onDate, String subjectLine) {
		Event ne = new Event();
		ne.Project__c = projectId;
		ne.WhatId = projectId;
		Id evtRt = ipmEventRecordTypeId();
		if (evtRt != null) {
			ne.RecordTypeId = evtRt;
		}
		ne.Subject = String.isNotBlank(subjectLine) ? subjectLine : 'New event';
		ne.OwnerId = UserInfo.getUserId();
		Datetime startDt = DateTime.newInstance(onDate, Time.newInstance(10, 0, 0, 0));
		ne.StartDateTime = startDt;
		ne.EndDateTime = startDt.addHours(2);
		ne.IsAllDayEvent = false;
		String defaultEventStatus = resolveDefaultEventOpenStatus();
		if (String.isNotBlank(defaultEventStatus)) {
			ne.put('Status__c', defaultEventStatus);
		}
		putProjectItemSequence(ne, newSeqString);
		return ne;
	}

	/** Task row for a project subline (same activity anchor date pattern as viewer defaults). */
	private static Task buildProjectLineTask(Id projectId, String newSeqString, Date onDate, String subjectLine) {
		Task nt = new Task();
		nt.put('Project__c', projectId);
		nt.WhatId = projectId;
		Id taskRt = ipmTaskRecordTypeId();
		if (taskRt != null) {
			nt.RecordTypeId = taskRt;
		}
		nt.Subject = String.isNotBlank(subjectLine) ? subjectLine : 'New task';
		nt.OwnerId = UserInfo.getUserId();
		nt.ActivityDate = onDate != null ? onDate : Date.today();
		nt.Status = resolveDefaultTaskOpenStatus();
		nt.Priority = 'Normal';
		putProjectItemSequence(nt, newSeqString);
		return nt;
	}

	private static String resolveDefaultTaskOpenStatus() {
		for (Schema.PicklistEntry pe : Task.Status.getDescribe().getPicklistValues()) {
			if (pe.isActive() && pe.getValue() != null && pe.getValue().equalsIgnoreCase('Open')) {
				return pe.getValue();
			}
		}
		return 'Not Started';
	}

	private static String resolveDefaultEventOpenStatus() {
		Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();
		if (!eventFields.containsKey('status__c')) {
			return null;
		}
		Schema.DescribeFieldResult statusDescribe = eventFields.get('status__c').getDescribe();
		if (!statusDescribe.isCreateable()) {
			return null;
		}
		for (Schema.PicklistEntry pe : statusDescribe.getPicklistValues()) {
			if (pe.isActive() && pe.getValue() != null && pe.getValue().equalsIgnoreCase('Open')) {
				return pe.getValue();
			}
		}
		return null;
	}

	public class ProjectItemSequenceComparator implements Comparator<ProjectItemRow> {
		public Integer compare(ProjectItemRow a, ProjectItemRow b) {
			return ProjectItemSequenceUtil.compareSequences(a != null ? a.sequence : null, b != null ? b.sequence : null);
		}
	}
}