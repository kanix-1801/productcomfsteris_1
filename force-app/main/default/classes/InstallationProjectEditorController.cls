/**
 * @description Controller class for Installation Project Editor LWC
 */
public with sharing class InstallationProjectEditorController {

    /**
     * @description Wrapper class for project item data
     */
    public class ProjectItemWrapper {
        @AuraEnabled public String id;
        @AuraEnabled public String recordType; // 'Task' or 'Event'
        @AuraEnabled public Decimal sequence;
        @AuraEnabled public String subject;
        @AuraEnabled public Date activityDate;
        @AuraEnabled public Decimal duration;
        @AuraEnabled public String ownerId;
        @AuraEnabled public String ownerName;
        @AuraEnabled public String status;
        @AuraEnabled public Decimal itemNumber; // From template item
        @AuraEnabled public String type; // From template item
        @AuraEnabled public Decimal templateDuration; // From template item
        @AuraEnabled public String dependencyType; // From template item
        @AuraEnabled public Decimal autoFilledStartDays; // From template item
        @AuraEnabled public String itemDependency; // From template item
    }

    /**
     * @description Wrapper class for project data
     */
    public class ProjectDataWrapper {
        @AuraEnabled public String projectId;
        @AuraEnabled public String projectName;
        @AuraEnabled public String templateId;
        @AuraEnabled public String templateName;
        @AuraEnabled public Date projectStartDate;
        @AuraEnabled public Date projectShippedDate;
        @AuraEnabled public Date projectRequestedDate;
        @AuraEnabled public List<ProjectItemWrapper> items;
    }

    /**
     * @description Retrieve all active users for picklist
     * @return List of User records with Id and Name
     */
    @AuraEnabled(cacheable=true)
    public static List<User> getActiveUsers() {
        try {
            return [
                SELECT Id, Name
                FROM User
                WHERE IsActive = true
                WITH USER_MODE
                ORDER BY Name ASC
            ];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving active users: ' + e.getMessage());
        }
    }

    /**
     * @description Retrieve project data with associated tasks, events, and template items
     * @param projectId The Project__c record ID
     * @return ProjectDataWrapper containing project and item data
     */
    @AuraEnabled(cacheable=true)
    public static ProjectDataWrapper getProjectData(Id projectId) {

            System.debug('projectId: ' + projectId);
            if (projectId == null) {
                throw new AuraHandledException('Project ID is required');
            }

            // Get project with template reference
            List<Project__c> projects = [
                SELECT
                    Id,
                    Name,
                    ProjectTemplate__c,           // Added this
    ProjectTemplate__r.Name,      // Added this for line 219
                    ProjectStartDate__c,
                    ProjectShippedDate__c,
                    ProjectRequestedDate__c
                FROM Project__c
                WHERE Id = :projectId
                WITH USER_MODE
                LIMIT 1
            ];

            if (projects.isEmpty()) {
                throw new AuraHandledException('Project not found');
            }

            Project__c project = projects[0];

            // Get template items if template exists
            Map<Decimal, ProjectTemplateItem__c> templateItemMap = new Map<Decimal, ProjectTemplateItem__c>();
            if (project.ProjectTemplate__c != null) {
                List<ProjectTemplateItem__c> templateItems = [
                    SELECT
                        Id,
                        Name,
                        ItemNumber__c,
                        Type__c,
                        Duration__c,
                        DependencyType__c,
                        AutoFilledStartDays__c,
                        ItemDependency__c
                    FROM ProjectTemplateItem__c
                    WHERE ProjectTemplate__c = :project.ProjectTemplate__c
                    WITH USER_MODE
                    ORDER BY ItemNumber__c ASC
                ];

                for (ProjectTemplateItem__c item : templateItems) {
                    templateItemMap.put(item.ItemNumber__c, item);
                }
            }

            // Get all tasks for the project
            List<Task> tasks = [
                SELECT
                    Id,
                    Subject,
                    ActivityDate,
                    Status,
                    OwnerId,
                    Owner.Name,
                    Owner.Type,
                    ProjectItemSequence__c,
                    TemplateItemNumber__c
                FROM Task
                WHERE Project__c = :projectId
                WITH USER_MODE
                ORDER BY ProjectItemSequence__c ASC
            ];
            system.debug('tasks: ' + tasks);

            // Get all events for the project (Status__c only when present in target org)
            Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();
            List<String> eventSelectParts = new List<String>{
                'Id',
                'Subject',
                'ActivityDate',
                'StartDateTime',
                'EndDateTime',
                'OwnerId',
                'Owner.Name',
                'Owner.Type',
                'ProjectItemSequence__c',
                'TemplateItemNumber__c'
            };
            if (eventFields.containsKey('status__c')) {
                eventSelectParts.add('Status__c');
            }
            String eventSoql =
                'SELECT ' +
                String.join(eventSelectParts, ', ') +
                ' FROM Event WHERE Project__c = :projectId WITH USER_MODE ORDER BY ProjectItemSequence__c ASC';
            List<Event> events = Database.query(eventSoql);
            system.debug('events: ' + events);
            // Build map of Owner IDs to Names for both Users and Queues
            Set<Id> ownerIds = new Set<Id>();
            for (Task t : tasks) {
                if (t.OwnerId != null) {
                    ownerIds.add(t.OwnerId);
                }
            }
            for (Event e : events) {
                if (e.OwnerId != null) {
                    ownerIds.add(e.OwnerId);
                }
            }
            
            Map<Id, String> ownerNameMap = new Map<Id, String>();
            // Query Users
            List<User> users = [
                SELECT Id, Name
                FROM User
                WHERE Id IN :ownerIds
                WITH USER_MODE
            ];
            system.debug('users: ' + users);
            for (User u : users) {
                ownerNameMap.put(u.Id, u.Name);
            }
            
            // Query Groups (Queues)
            List<Group> queues = [
                SELECT Id, Name
                FROM Group
                WHERE Id IN :ownerIds AND Type = 'Queue'
                WITH USER_MODE
            ];
            for (Group g : queues) {
                ownerNameMap.put(g.Id, g.Name);
            }

            // Combine tasks and events into wrapper list
            List<ProjectItemWrapper> items = new List<ProjectItemWrapper>();

            // Process tasks
            for (Task t : tasks) {
                ProjectItemWrapper wrapper = new ProjectItemWrapper();
                wrapper.id = t.Id;
                wrapper.recordType = 'Task';
                wrapper.sequence = t.ProjectItemSequence__c;
                wrapper.subject = t.Subject;
                wrapper.activityDate = t.ActivityDate;
                wrapper.ownerId = t.OwnerId;
                // Use ownerNameMap from Users/Queues queries (Owner.Name not available in Task/Event queries)
                wrapper.ownerName = t.OwnerId != null ? ownerNameMap.get(t.OwnerId) : null;
                wrapper.status = t.Status;

                // Default itemNumber from persisted sequence to ensure LWC receives the stored sequence
                wrapper.itemNumber = t.ProjectItemSequence__c;

                // Template rules keyed by stable TemplateItemNumber__c (not display sequence).
                Decimal templateItemNumber = ProjectItemSequenceUtil.getTemplateItemNumber(t);
                if (templateItemNumber != null && templateItemMap.containsKey(templateItemNumber)) {
                    ProjectTemplateItem__c templateItem = templateItemMap.get(templateItemNumber);
                    wrapper.itemNumber = templateItem.ItemNumber__c != null ? templateItem.ItemNumber__c : wrapper.itemNumber;
                    wrapper.type = templateItem.Type__c;
                    wrapper.templateDuration = templateItem.Duration__c;
                    wrapper.dependencyType = templateItem.DependencyType__c;
                    wrapper.autoFilledStartDays = templateItem.AutoFilledStartDays__c;
                    wrapper.itemDependency = templateItem.ItemDependency__c;
                    
                    // Calculate duration from template or dates
                    wrapper.duration = templateItem.Duration__c != null ? templateItem.Duration__c : 0;
                } else {
                    wrapper.duration = 0;
                }

                items.add(wrapper);
            }

            // Process events
            for (Event e : events) {
                ProjectItemWrapper wrapper = new ProjectItemWrapper();
                wrapper.id = e.Id;
                wrapper.recordType = 'Event';
                wrapper.sequence = e.ProjectItemSequence__c;
                wrapper.subject = e.Subject;
                wrapper.activityDate = e.ActivityDate;
                wrapper.ownerId = e.OwnerId;
                // Use ownerNameMap from Users/Queues queries (Owner.Name not available in Event queries)
                wrapper.ownerName = e.OwnerId != null ? ownerNameMap.get(e.OwnerId) : null;
                wrapper.status =
                    eventFields.containsKey('status__c') && e.get('Status__c') != null
                        ? String.valueOf(e.get('Status__c'))
                        : '';

                // Default itemNumber from persisted sequence to ensure LWC receives the stored sequence
                wrapper.itemNumber = e.ProjectItemSequence__c;

                Decimal templateItemNumber = ProjectItemSequenceUtil.getTemplateItemNumber(e);
                if (templateItemNumber != null && templateItemMap.containsKey(templateItemNumber)) {
                    ProjectTemplateItem__c templateItem = templateItemMap.get(templateItemNumber);
                    wrapper.itemNumber = templateItem.ItemNumber__c != null ? templateItem.ItemNumber__c : wrapper.itemNumber;
                    wrapper.type = templateItem.Type__c;
                    wrapper.templateDuration = templateItem.Duration__c;
                    wrapper.dependencyType = templateItem.DependencyType__c;
                    wrapper.autoFilledStartDays = templateItem.AutoFilledStartDays__c;
                    wrapper.itemDependency = templateItem.ItemDependency__c;
                    
                    // Calculate duration from template or dates
                    if (templateItem.Duration__c != null) {
                        wrapper.duration = templateItem.Duration__c;
                    } else if (e.StartDateTime != null && e.EndDateTime != null) {
                        // Calculate from event dates
                        Long diffInMs = e.EndDateTime.getTime() - e.StartDateTime.getTime();
                        wrapper.duration = Decimal.valueOf(diffInMs / (1000 * 60 * 60 * 24)); // Convert to days
                    } else {
                        wrapper.duration = 0;
                    }
                } else {
                    wrapper.duration = 0;
                }

                items.add(wrapper);
            }

            // Sort items by sequence
            items.sort(new SequenceComparator());

            // Build wrapper
            ProjectDataWrapper dataWrapper = new ProjectDataWrapper();
            dataWrapper.projectId = project.Id;
            dataWrapper.projectName = project.Name;
            dataWrapper.templateId = project.ProjectTemplate__c;
            dataWrapper.templateName = project.ProjectTemplate__r != null ? project.ProjectTemplate__r.Name : null;
            dataWrapper.projectStartDate = project.ProjectStartDate__c;
            dataWrapper.projectShippedDate = project.ProjectShippedDate__c;
            dataWrapper.projectRequestedDate = project.ProjectRequestedDate__c;
            dataWrapper.items = items;

            return dataWrapper;
    }

    /**
     * @description Update project items (tasks and events) and create new ones
     * @param itemsJson JSON string containing array of items to update/create
     * @param projectId The Project__c record ID
     * @return String Success message
     */
    @AuraEnabled
    public static String updateProjectItems(String itemsJson, Id projectId) {
            if (projectId == null) {
                throw new AuraHandledException('Project ID is required');
            }

            Map<String, Schema.SObjectField> eventFields = Schema.SObjectType.Event.fields.getMap();
            Boolean eventHasStatusField = eventFields.containsKey('status__c');
            
            List<Object> rawItems = (List<Object>) JSON.deserializeUntyped(itemsJson);
            List<Map<String, Object>> items = new List<Map<String, Object>>();
            for (Object rawItem : rawItems) {
                items.add((Map<String, Object>) rawItem);
            }
            
            List<Task> tasksToUpdate = new List<Task>();
            List<Event> eventsToUpdate = new List<Event>();
            List<Task> tasksToInsert = new List<Task>();
            List<Event> eventsToInsert = new List<Event>();

            for (Map<String, Object> item : items) {
                String recordType = (String) item.get('recordType');
                String id = (String) item.get('id');
                String status = (String) item.get('status');
                String ownerId = (String) item.get('ownerId');
                String activityDateStr = (String) item.get('activityDate');
                Decimal sequence = item.get('sequence') != null ? Decimal.valueOf(String.valueOf(item.get('sequence'))) : null;
                String subject = (String) item.get('subject');
                Boolean isNew = item.get('isNew') != null ? Boolean.valueOf(item.get('isNew')) : false;
                Decimal duration = item.get('duration') != null ? Decimal.valueOf(String.valueOf(item.get('duration'))) : null;

                // Check if this is a new item (temp ID)
                Boolean isNewItem = isNew || (id != null && id.startsWith('temp_'));

                if (recordType == 'Task') {
                    if (isNewItem) {
                        // Create new Task
                        Task t = new Task();
                        t.Project__c = projectId;
                        t.WhatId = projectId;
                        t.Subject = subject != null ? subject : 'New Task';
                        t.Status = status != null ? status : 'Open';
                        
                        // Assign record type IPMTask
                        Schema.RecordTypeInfo taskRecordTypeInfo = Schema.SObjectType.Task.getRecordTypeInfosByDeveloperName().get('IPMTask');
                        if (taskRecordTypeInfo != null) {
                            t.RecordTypeId = taskRecordTypeInfo.getRecordTypeId();
                        }
                        
                        if (ownerId != null && ownerId != '') {
                            t.OwnerId = ownerId;
                        }
                        if (activityDateStr != null) {
                            t.ActivityDate = Date.valueOf(activityDateStr);
                        }
                        if (sequence != null) {
                            t.ProjectItemSequence__c = sequence;
                        }
                        tasksToInsert.add(t);
                    } else {
                        // Update existing Task
                        Task t = new Task(Id = id);
                        if (subject != null) {
                            t.Subject = subject;
                        }
                        if (status != null) {
                            t.Status = status;
                        }
                        if (ownerId != null) {
                            t.OwnerId = ownerId;
                        }
                        if (activityDateStr != null) {
                            t.ActivityDate = Date.valueOf(activityDateStr);
                        }
                        if (sequence != null) {
                            t.ProjectItemSequence__c = sequence;
                        }
                        tasksToUpdate.add(t);
                    }
                } else if (recordType == 'Event') {
                    if (isNewItem) {
                        // Create new Event
                        Event e = new Event();
                        e.Project__c = projectId;
                        e.WhatId = projectId;
                        e.Subject = subject != null ? subject : 'New Event';
                        if (eventHasStatusField) {
                            String statusToSet = status != null ? status : resolveDefaultEventOpenStatus();
                            if (statusToSet != null) {
                                e.put('Status__c', statusToSet);
                            }
                        }

                        // Assign record type IPMEvent
                        Schema.RecordTypeInfo eventRecordTypeInfo = Schema.SObjectType.Event.getRecordTypeInfosByDeveloperName().get('IPMEvent');
                        if (eventRecordTypeInfo != null) {
                            e.RecordTypeId = eventRecordTypeInfo.getRecordTypeId();
                        }
                        
                        if (ownerId != null && ownerId != '') {
                            e.OwnerId = ownerId;
                        }
                        if (activityDateStr != null) {
                            Date activityDate = Date.valueOf(activityDateStr);
                            e.ActivityDate = activityDate;
                            DateTime startDateTime = DateTime.newInstance(activityDate, Time.newInstance(0, 0, 0, 0));
                            e.StartDateTime = startDateTime;
                            // Set end date based on duration if available
                            if (duration != null && duration > 0) {
                                DateTime endDateTime = startDateTime.addDays(Integer.valueOf(duration));
                                e.EndDateTime = endDateTime;
                            } else {
                                e.EndDateTime = startDateTime.addHours(2);
                            }
                        }
                        if (sequence != null) {
                            e.ProjectItemSequence__c = sequence;
                        }
                        eventsToInsert.add(e);
                    } else {
                        // Update existing Event
                        Event e = new Event(Id = id);
                        if (subject != null) {
                            e.Subject = subject;
                        }
                        if (eventHasStatusField && status != null) {
                            e.put('Status__c', status);
                        }
                        if (ownerId != null) {
                            e.OwnerId = ownerId;
                        }
                        if (activityDateStr != null) {
                            Date activityDate = Date.valueOf(activityDateStr);
                            e.ActivityDate = activityDate;
                            DateTime startDateTime = DateTime.newInstance(activityDate, Time.newInstance(0, 0, 0, 0));
                            e.StartDateTime = startDateTime;
                            // Set end date based on duration if available
                            if (duration != null && duration > 0) {
                                DateTime endDateTime = startDateTime.addDays(Integer.valueOf(duration));
                                e.EndDateTime = endDateTime;
                            } else {
                                e.EndDateTime = startDateTime.addHours(2);
                            }
                        }
                        if (sequence != null) {
                            e.ProjectItemSequence__c = sequence;
                        }
                        eventsToUpdate.add(e);
                    }
                }
            }

            // Handle task updates with proper field access checks
            if (!tasksToUpdate.isEmpty()) {
                try {
                    Database.update(tasksToUpdate, AccessLevel.USER_MODE);
                } catch (DmlException e) {
                    // Log the error and rethrow with more context
                    System.debug('Task update failed: ' + e.getMessage());
                    throw new AuraHandledException('Failed to update tasks: ' + e.getMessage());
                }
            }

            // Handle event updates with proper field access checks
            if (!eventsToUpdate.isEmpty()) {
                try {
                    Database.update(eventsToUpdate, AccessLevel.USER_MODE);
                } catch (DmlException e) {
                    // Log the error and rethrow with more context
                    System.debug('Event update failed: ' + e.getMessage());
                    throw new AuraHandledException('Failed to update events: ' + e.getMessage());
                }
            }

            // Handle task inserts with proper field access checks
            if (!tasksToInsert.isEmpty()) {
                try {
                    Database.insert(tasksToInsert, AccessLevel.USER_MODE);
                } catch (DmlException e) {
                    // Log the error and rethrow with more context
                    System.debug('Task insert failed: ' + e.getMessage());
                    throw new AuraHandledException('Failed to create tasks: ' + e.getMessage());
                }
            }

            // Handle event inserts with proper field access checks
            if (!eventsToInsert.isEmpty()) {
                try {
                    Database.insert(eventsToInsert, AccessLevel.USER_MODE);
                } catch (DmlException e) {
                    // Log the error and rethrow with more context
                    System.debug('Event insert failed: ' + e.getMessage());
                    throw new AuraHandledException('Failed to create events: ' + e.getMessage());
                }
            }

            return 'Project items updated successfully';
    }

    /** First active "Open" picklist value for Event.Status__c when the field exists in the org. */
    private static String resolveDefaultEventOpenStatus() {
        Map<String, Schema.SObjectField> fields = Schema.SObjectType.Event.fields.getMap();
        if (!fields.containsKey('status__c')) {
            return null;
        }
        Schema.DescribeFieldResult statusDescribe = fields.get('status__c').getDescribe();
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

    /**
     * @description Comparator class for sorting items by sequence
     */
    private class SequenceComparator implements Comparator<ProjectItemWrapper> {
        public Integer compare(ProjectItemWrapper a, ProjectItemWrapper b) {
            if (a.sequence == null && b.sequence == null) {
                return 0;
            }
            if (a.sequence == null) {
                return 1;
            }
            if (b.sequence == null) {
                return -1;
            }
            if (a.sequence < b.sequence) {
                return -1;
            }
            if (a.sequence > b.sequence) {
                return 1;
            }
            return 0;
        }
    }
}