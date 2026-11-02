/**
 * @description
 * GC-3489 - Loads, searches, and saves Event attendees for the Healthcare Sales detail flow.
 * People are Users, Contacts, and Leads. Resources are active Calendar records whose Type is Resource.
 * The event owner is shown as already selected and is never inserted as an invitee.
 * Insert and delete faults, and any other unexpected exception, are written to Nebula Logger against the Event.
 */
public with sharing class EventAttendeeService {
    private static final String CLASS_NAME = 'EventAttendeeService';
    private static final Integer SEARCH_LIMIT = 20;
    private static final String KIND_USER = 'User';
    private static final String KIND_CONTACT = 'Contact';
    private static final String KIND_LEAD = 'Lead';
    private static final String KIND_RESOURCE = 'Resource';
    private static final String TAB_RESOURCES = 'Resources';
    private static final String USER_PREFIX = User.SObjectType.getDescribe().getKeyPrefix();
    private static final String CONTACT_PREFIX = Contact.SObjectType.getDescribe().getKeyPrefix();
    private static final String LEAD_PREFIX = Lead.SObjectType.getDescribe().getKeyPrefix();
    private static final String RESOURCE_PREFIX = Calendar.SObjectType.getDescribe().getKeyPrefix();
    private static final String EVENT_PREFIX = Event.SObjectType.getDescribe().getKeyPrefix();

    /**
     * @description One person or resource shown in the attendee panel.
     */
    public class AttendeeRow {
        /** @description EventRelation Id. Null when the row is the owner and no invitee relation exists. */
        @AuraEnabled public String relationId;
        /** @description User, Contact, Lead, or Calendar Id. */
        @AuraEnabled public String recordId;
        /** @description Display name resolved from the related record. */
        @AuraEnabled public String name;
        /** @description User, Contact, Lead, or Resource. */
        @AuraEnabled public String kind;
        /** @description True when this row is the Event owner. The owner cannot be removed. */
        @AuraEnabled public Boolean isOwner;
    }

    /**
     * @description One search hit from the People or Resources tab.
     */
    public class SearchResult {
        /** @description User, Contact, Lead, or Calendar Id. */
        @AuraEnabled public String recordId;
        /** @description Display name of the search hit. */
        @AuraEnabled public String name;
        /** @description User, Contact, Lead, or Resource. */
        @AuraEnabled public String kind;
    }

    /**
     * @description Flow input for applying staged attendee adds and removes.
     */
    public class ChangeRequest {
        /** @description Event Id passed from the screen flow. */
        @InvocableVariable(label='Event Id' required=true)
        public String eventId;
        /** @description JSON with addIds and removeRelationIds. Blank when nothing changed. */
        @InvocableVariable(label='Attendee Changes')
        public String changePayload;
    }

    /**
     * @description JSON shape published by the attendee component.
     */
    private class ChangeSet {
        /** @description Record Ids to insert as EventRelation invitees. */
        public List<String> addIds;
        /** @description EventRelation Ids to delete. */
        public List<String> removeRelationIds;
    }

    /**
     * @description Expected validation failure. These are returned to the user and are not written to Nebula Logger.
     */
    public class AttendeeException extends Exception {}

    /**
     * @description Private constructor. All entry points are static.
     */
    private EventAttendeeService() {
    }

    /**
     * @description Loads invitees for the Event, with the owner first when they are not already an invitee.
     * @param eventId Event Id.
     * @return Attendee rows the panel can render. The owner row has isOwner = true and may have a null relationId.
     */
    @AuraEnabled
    public static List<AttendeeRow> getAttendees(String eventId) {
        try {
            return loadAttendees(eventId);
        } catch (Exception ex) {
            logUnexpected(ex, 'getAttendees', eventId);
            throw auraError(ex);
        }
    }

    /**
     * @description Queries invitee EventRelation rows and prepends the owner when no invitee row exists for them.
     * @param eventId Event Id.
     * @return Attendee rows, owner first when the owner was not already an invitee.
     */
    private static List<AttendeeRow> loadAttendees(String eventId) {
        assertEventId(eventId);
        Id ownerId = eventOwnerId(eventId);
        List<EventRelation> relations = [
            SELECT Id, RelationId
            FROM EventRelation
            WHERE EventId = :eventId AND IsInvitee = true
            WITH USER_MODE
            ORDER BY CreatedDate
        ];
        Set<Id> ids = relationIds(relations);
        if (ownerId != null) {
            ids.add(ownerId);
        }
        Map<Id, String> names = namesFor(ids);
        List<AttendeeRow> rows = new List<AttendeeRow>();
        Boolean ownerListed = false;
        for (EventRelation relation : relations) {
            AttendeeRow row = rowFor(relation.RelationId, relation.Id, names);
            if (row == null) {
                continue;
            }
            row.isOwner = ownerId != null && relation.RelationId == ownerId;
            ownerListed = ownerListed || row.isOwner;
            rows.add(row);
        }
        if (ownerId != null && !ownerListed) {
            AttendeeRow ownerRow = rowFor(ownerId, null, names);
            if (ownerRow != null) {
                ownerRow.isOwner = true;
                List<AttendeeRow> withOwner = new List<AttendeeRow>{ ownerRow };
                withOwner.addAll(rows);
                return withOwner;
            }
        }
        return rows;
    }

    /**
     * @description Searches people or resources. Terms shorter than two characters return no rows.
     * @param eventId Event Id.
     * @param term Text entered in the search box.
     * @param tab People or Resources.
     * @return Matching Users, Contacts, and Leads, or active resource Calendars.
     */
    @AuraEnabled
    public static List<SearchResult> search(String eventId, String term, String tab) {
        try {
            return findAttendees(eventId, term, tab);
        } catch (Exception ex) {
            logUnexpected(ex, 'search', eventId);
            throw auraError(ex);
        }
    }

    /**
     * @description Routes a search to the Resources calendar query or the People SOSL query.
     * @param eventId Event Id.
     * @param term Raw search text.
     * @param tab People or Resources.
     * @return Search hits, or an empty list when the term is shorter than two characters.
     */
    private static List<SearchResult> findAttendees(String eventId, String term, String tab) {
        assertEventId(eventId);
        String cleanTerm = cleanTerm(term);
        if (cleanTerm.length() < 2) {
            return new List<SearchResult>();
        }
        if (tab == TAB_RESOURCES) {
            return searchResources(cleanTerm);
        }
        return searchPeople(cleanTerm);
    }

    /**
     * @description Applies staged attendee changes after the screen flow is saved.
     *              Deletes run before inserts. The Event owner is removed from the insert list.
     * @param requests One request per flow interview. Each payload is JSON from the attendee component.
     */
    @InvocableMethod(label='Apply Healthcare Sales Event Attendees' description='GC-3489 - Adds and removes Event attendees after the detail flow is saved.')
    public static void applyChanges(List<ChangeRequest> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }
        for (ChangeRequest request : requests) {
            applyOne(request);
        }
    }

    /**
     * @description Applies one Event's attendee payload. Unexpected faults are written to Nebula Logger.
     *              DML faults are logged by the insert and delete methods so they are not logged twice.
     * @param request Event Id and JSON change payload.
     */
    private static void applyOne(ChangeRequest request) {
        String eventId = request == null ? null : request.eventId;
        try {
            applyOneChange(request);
        } catch (Exception ex) {
            logUnexpected(ex, 'applyOne', eventId);
            throw ex;
        }
    }

    /**
     * @description Deletes requested invitees, then inserts the remaining people and resources.
     * @param request Event Id and JSON change payload.
     */
    private static void applyOneChange(ChangeRequest request) {
        if (request == null) {
            throw new AttendeeException('Open this panel from an Event.');
        }
        assertEventId(request.eventId);
        if (String.isBlank(request.changePayload)) {
            return;
        }
        ChangeSet changes = (ChangeSet) JSON.deserialize(request.changePayload, ChangeSet.class);
        List<Id> removeIds = toIds(changes.removeRelationIds);
        Set<Id> addIds = new Set<Id>(toIds(changes.addIds));
        if (!removeIds.isEmpty()) {
            List<EventRelation> removable = [
                SELECT Id
                FROM EventRelation
                WHERE Id IN :removeIds AND EventId = :request.eventId AND IsInvitee = true
                WITH USER_MODE
            ];
            if (removable.size() != removeIds.size()) {
                throw new AttendeeException('An attendee on this event could not be removed.');
            }
            deleteAttendees(removable, request.eventId);
        }
        if (addIds.isEmpty()) {
            return;
        }
        Id ownerId = eventOwnerId(request.eventId);
        if (ownerId != null) {
            addIds.remove(ownerId);
        }
        validateAdditions(addIds);
        Set<Id> alreadyThere = new Set<Id>();
        for (EventRelation existing : [
            SELECT RelationId
            FROM EventRelation
            WHERE EventId = :request.eventId AND RelationId IN :addIds AND IsInvitee = true
            WITH USER_MODE
        ]) {
            alreadyThere.add(existing.RelationId);
        }
        List<EventRelation> toInsert = new List<EventRelation>();
        for (Id relationId : addIds) {
            if (alreadyThere.contains(relationId)) {
                continue;
            }
            EventRelation relation = new EventRelation();
            relation.EventId = request.eventId;
            relation.RelationId = relationId;
            relation.IsInvitee = true;
            if (kindFor(relationId) == KIND_RESOURCE) {
                relation.Status = 'Accepted';
            }
            toInsert.add(relation);
        }
        if (!toInsert.isEmpty()) {
            insertAttendees(toInsert, request.eventId);
        }
    }

    /**
     * @description Inserts invitee EventRelation rows. A DML fault is written to Nebula Logger and then rethrown.
     * @param rows New invitee relations.
     * @param eventId Event the relations belong to.
     */
    private static void insertAttendees(List<EventRelation> rows, String eventId) {
        try {
            Database.insert(rows, AccessLevel.SYSTEM_MODE);
        } catch (Exception ex) {
            logAttendeeFault('insertAttendees', eventId, ex);
            throw ex;
        }
    }

    /**
     * @description Deletes invitee EventRelation rows. A DML fault is written to Nebula Logger and then rethrown.
     * @param rows Invitee relations confirmed to belong to this Event.
     * @param eventId Event the relations belong to.
     */
    private static void deleteAttendees(List<EventRelation> rows, String eventId) {
        try {
            Database.delete(rows, AccessLevel.SYSTEM_MODE);
        } catch (Exception ex) {
            logAttendeeFault('deleteAttendees', eventId, ex);
            throw ex;
        }
    }

    /**
     * @description Writes an unexpected exception to Nebula Logger.
     *              AttendeeException is a user-facing validation message and is not logged.
     *              DmlException is logged by insertAttendees or deleteAttendees before it reaches here.
     * @param ex Exception from a public entry point.
     * @param action Method name included in the log message.
     * @param eventId Event Id stored on the log when it is an Event Id.
     */
    private static void logUnexpected(Exception ex, String action, String eventId) {
        if (ex instanceof AttendeeException || ex instanceof DmlException) {
            return;
        }
        logAttendeeFault(action, eventId, ex);
    }

    /**
     * @description Saves one Nebula error log against the Event, then commits it so the entry survives a rollback.
     * @param action Method or DML action included in the log message.
     * @param eventId Event Id. The log is linked to the Event only when this is an Event Id.
     * @param ex Exception being logged.
     */
    private static void logAttendeeFault(String action, String eventId, Exception ex) {
        if (String.isNotBlank(eventId) && eventId.startsWith(EVENT_PREFIX)) {
            Logger.error(CLASS_NAME + '.' + action, ex)
                .addTag('GC-3489')
                .setRecord(new Event(Id = eventId));
        } else {
            Logger.error(CLASS_NAME + '.' + action, ex).addTag('GC-3489');
        }
        Logger.saveLog();
    }

    /**
     * @description Allows only User, Contact, Lead, and active Resource Calendar Ids.
     * @param addIds Record Ids staged for insert.
     */
    private static void validateAdditions(Set<Id> addIds) {
        Set<Id> resourceIds = new Set<Id>();
        for (Id relationId : addIds) {
            String kind = kindFor(relationId);
            if (kind == null) {
                throw new AttendeeException('Select a user, contact, lead, or resource.');
            }
            if (kind == KIND_RESOURCE) {
                resourceIds.add(relationId);
            }
        }
        if (resourceIds.isEmpty()) {
            return;
        }
        Set<Id> available = new Map<Id, Calendar>([
            SELECT Id
            FROM Calendar
            WHERE Id IN :resourceIds AND Type = 'Resource' AND IsActive = true
            WITH USER_MODE
        ]).keySet();
        if (available.size() != resourceIds.size()) {
            throw new AttendeeException('That resource is not available.');
        }
    }

    /**
     * @description SOSL search for active Users, Contacts, and unconverted Leads.
     * @param term Sanitized search text. A trailing wildcard is added.
     * @return Up to SEARCH_LIMIT hits of each type.
     */
    private static List<SearchResult> searchPeople(String term) {
        String findTerm = term + '*';
        List<List<SObject>> found = [
            FIND :findTerm IN NAME FIELDS RETURNING
                User(Id, Name WHERE IsActive = true LIMIT :SEARCH_LIMIT),
                Contact(Id, Name LIMIT :SEARCH_LIMIT),
                Lead(Id, Name WHERE IsConverted = false LIMIT :SEARCH_LIMIT)
            WITH USER_MODE
        ];
        List<SearchResult> results = new List<SearchResult>();
        addResults(results, found[0], KIND_USER);
        addResults(results, found[1], KIND_CONTACT);
        addResults(results, found[2], KIND_LEAD);
        return results;
    }

    /**
     * @description SOQL search for active resource calendars.
     * @param term Sanitized search text, matched with a contains filter.
     * @return Up to SEARCH_LIMIT resource calendars.
     */
    private static List<SearchResult> searchResources(String term) {
        String likeTerm = '%' + term + '%';
        List<SearchResult> results = new List<SearchResult>();
        for (Calendar resource : [
            SELECT Id, Name
            FROM Calendar
            WHERE Type = 'Resource' AND IsActive = true AND Name LIKE :likeTerm
            WITH USER_MODE
            LIMIT :SEARCH_LIMIT
        ]) {
            SearchResult result = new SearchResult();
            result.recordId = resource.Id;
            result.name = resource.Name;
            result.kind = KIND_RESOURCE;
            results.add(result);
        }
        return results;
    }

    /**
     * @description Copies Id and Name from SOSL rows into search results.
     * @param results List being filled.
     * @param records User, Contact, or Lead rows.
     * @param kind User, Contact, or Lead.
     */
    private static void addResults(List<SearchResult> results, List<SObject> records, String kind) {
        for (SObject record : records) {
            SearchResult result = new SearchResult();
            result.recordId = (String) record.get('Id');
            result.name = (String) record.get('Name');
            result.kind = kind;
            results.add(result);
        }
    }

    /**
     * @description Resolves display names for mixed User, Contact, Lead, and Calendar Ids.
     * @param relationIds Ids to name.
     * @return Id to Name. Ids the user cannot read are omitted.
     */
    private static Map<Id, String> namesFor(Set<Id> relationIds) {
        Map<Id, String> names = new Map<Id, String>();
        Set<Id> userIds = idsOfKind(relationIds, KIND_USER);
        Set<Id> contactIds = idsOfKind(relationIds, KIND_CONTACT);
        Set<Id> leadIds = idsOfKind(relationIds, KIND_LEAD);
        Set<Id> resourceIds = idsOfKind(relationIds, KIND_RESOURCE);
        if (!userIds.isEmpty()) {
            for (User person : [SELECT Id, Name FROM User WHERE Id IN :userIds WITH USER_MODE]) {
                names.put(person.Id, person.Name);
            }
        }
        if (!contactIds.isEmpty()) {
            for (Contact person : [SELECT Id, Name FROM Contact WHERE Id IN :contactIds WITH USER_MODE]) {
                names.put(person.Id, person.Name);
            }
        }
        if (!leadIds.isEmpty()) {
            for (Lead person : [SELECT Id, Name FROM Lead WHERE Id IN :leadIds WITH USER_MODE]) {
                names.put(person.Id, person.Name);
            }
        }
        if (!resourceIds.isEmpty()) {
            for (Calendar resource : [SELECT Id, Name FROM Calendar WHERE Id IN :resourceIds WITH USER_MODE]) {
                names.put(resource.Id, resource.Name);
            }
        }
        return names;
    }

    /**
     * @description Reads the Event owner. The owner may be a User or a Calendar.
     * @param eventId Event Id.
     * @return OwnerId, or null when the Event is not visible.
     */
    private static Id eventOwnerId(String eventId) {
        List<Event> events = [
            SELECT OwnerId
            FROM Event
            WHERE Id = :eventId
            WITH USER_MODE
            LIMIT 1
        ];
        return events.isEmpty() ? null : events[0].OwnerId;
    }

    /**
     * @description Builds one panel row. Unsupported Id prefixes are skipped.
     * @param recordId Related record Id.
     * @param relationId EventRelation Id, or null for an owner who is not an invitee.
     * @param names Id to display name.
     * @return Row, or null when the Id is not a User, Contact, Lead, or Resource.
     */
    private static AttendeeRow rowFor(Id recordId, Id relationId, Map<Id, String> names) {
        String kind = kindFor(recordId);
        if (kind == null) {
            return null;
        }
        AttendeeRow row = new AttendeeRow();
        row.relationId = relationId;
        row.recordId = recordId;
        row.kind = kind;
        row.isOwner = false;
        row.name = names.containsKey(recordId) ? names.get(recordId) : kind;
        return row;
    }

    /**
     * @description Collects RelationId values from invitee rows.
     * @param relations Invitee EventRelation rows.
     * @return Related record Ids.
     */
    private static Set<Id> relationIds(List<EventRelation> relations) {
        Set<Id> ids = new Set<Id>();
        for (EventRelation relation : relations) {
            ids.add(relation.RelationId);
        }
        return ids;
    }

    /**
     * @description Filters Ids down to one kind.
     * @param relationIds Mixed record Ids.
     * @param kind User, Contact, Lead, or Resource.
     * @return Ids of that kind.
     */
    private static Set<Id> idsOfKind(Set<Id> relationIds, String kind) {
        Set<Id> ids = new Set<Id>();
        for (Id relationId : relationIds) {
            if (kindFor(relationId) == kind) {
                ids.add(relationId);
            }
        }
        return ids;
    }

    /**
     * @description Converts payload strings to Ids and drops blanks.
     * @param values Id strings from the JSON payload.
     * @return Ids safe to bind in SOQL.
     */
    private static List<Id> toIds(List<String> values) {
        List<Id> ids = new List<Id>();
        if (values == null) {
            return ids;
        }
        for (String value : values) {
            if (String.isNotBlank(value)) {
                ids.add((Id) value);
            }
        }
        return ids;
    }

    /**
     * @description Maps a key prefix to an attendee kind.
     * @param recordId Record Id.
     * @return User, Contact, Lead, Resource, or null when the prefix is not one of those objects.
     */
    private static String kindFor(Id recordId) {
        if (recordId == null) {
            return null;
        }
        String prefix = String.valueOf(recordId).substring(0, 3);
        if (prefix == USER_PREFIX) {
            return KIND_USER;
        }
        if (prefix == CONTACT_PREFIX) {
            return KIND_CONTACT;
        }
        if (prefix == LEAD_PREFIX) {
            return KIND_LEAD;
        }
        if (prefix == RESOURCE_PREFIX) {
            return KIND_RESOURCE;
        }
        return null;
    }

    /**
     * @description Trims the search text and removes characters that are not letters, numbers, spaces, or .@_-
     * @param term Raw search text.
     * @return Sanitized text, or an empty string when the input is blank.
     */
    private static String cleanTerm(String term) {
        if (String.isBlank(term)) {
            return '';
        }
        return term.trim().replaceAll('[^\\p{L}\\p{N} .@_-]', '');
    }

    /**
     * @description Turns a service exception into an AuraHandledException the component can display.
     *              Validation messages pass through. Every other exception uses a generic message.
     * @param ex Exception caught by an AuraEnabled method.
     * @return Exception whose message is set for the Lightning client.
     */
    private static AuraHandledException auraError(Exception ex) {
        String message = ex instanceof AttendeeException ? ex.getMessage() : 'Attendees could not be loaded.';
        AuraHandledException aura = new AuraHandledException(message);
        aura.setMessage(message);
        return aura;
    }

    /**
     * @description Requires an Event Id. Other Id prefixes are rejected before any query runs.
     * @param eventId Value passed from the flow or the component.
     */
    private static void assertEventId(String eventId) {
        if (String.isBlank(eventId) || !eventId.startsWith(EVENT_PREFIX)) {
            throw new AttendeeException('Open this panel from an Event.');
        }
    }
}