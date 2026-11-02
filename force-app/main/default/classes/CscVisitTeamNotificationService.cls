/**
 * @author Abhishek Mishra
 * @date 20-10-2026
 * @description #GC-3518 Sends a bell notification to visit Team Members.
 *              STERIS attendee calendar events stay in the existing visit confirmation service.
 */
public inherited sharing class CscVisitTeamNotificationService {
    public static final String NOTIFICATION_TYPE = 'Visit_Team_Status_Update';

    @TestVisible
    private static List<Id> lastNotifiedUserIds = new List<Id>();
    private static Id cachedNotificationTypeId;
    private static Boolean notificationTypeLoaded = false;

    /**
     * @description Notifies active Team Members when an ORC, IMS, or OSV visit changes.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     */
    public static void notifyAfterSave(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        Map<Id, String> noticeByVisit = noticesFor(visits, oldVisits);
        if (noticeByVisit.isEmpty()) {
            return;
        }

        Map<Id, CSC_Visit_Request__c> visitsById = new Map<Id, CSC_Visit_Request__c>([
            SELECT Id, Name, VisitType__c, AccountFacility__r.Name
            FROM CSC_Visit_Request__c
            WHERE Id IN :noticeByVisit.keySet()
        ]);
        Map<Id, Set<String>> usersByVisit = teamUsersByVisit(noticeByVisit.keySet());
        Id notificationTypeId = notificationTypeId();

        for (Id visitId : noticeByVisit.keySet()) {
            CSC_Visit_Request__c visit = visitsById.get(visitId);
            Set<String> userIds = usersByVisit.get(visitId);
            if (visit == null || userIds == null || userIds.isEmpty()) {
                continue;
            }
            for (String userId : userIds) {
                lastNotifiedUserIds.add((Id) userId);
            }
            sendNotification(visit, userIds, noticeByVisit.get(visitId), notificationTypeId);
        }
    }

    /**
     * @description Status changes that Team Members need to see.
     * @param visits Saved visit records.
     * @param oldVisits Prior visit records. Null on insert.
     * @return Map<Id, String> notice text by visit Id.
     */
    private static Map<Id, String> noticesFor(
        List<CSC_Visit_Request__c> visits,
        Map<Id, CSC_Visit_Request__c> oldVisits
    ) {
        Map<Id, String> noticeByVisit = new Map<Id, String>();
        if (visits == null) {
            return noticeByVisit;
        }
        for (CSC_Visit_Request__c visit : visits) {
            if (visit.Id == null || !CscVisitRequestSelector.isNonCscRequest(visit.VisitType__c)) {
                continue;
            }
            CSC_Visit_Request__c priorVisit = oldVisits == null ? null : oldVisits.get(visit.Id);
            String notice = noticeFor(visit, priorVisit);
            if (notice != null) {
                noticeByVisit.put(visit.Id, notice);
            }
        }
        return noticeByVisit;
    }

    /**
     * @description Notice for one visit, or null when Team Members are not notified.
     * @param visit Current visit.
     * @param priorVisit Prior visit. Null on insert.
     * @return String bell text.
     */
    private static String noticeFor(
        CSC_Visit_Request__c visit,
        CSC_Visit_Request__c priorVisit
    ) {
        String priorStatus = priorVisit == null ? null : priorVisit.Status__c;
        if (visit.Status__c == CscVisitRequestSelector.STATUS_REQUESTED
            && priorStatus != CscVisitRequestSelector.STATUS_REQUESTED
        ) {
            return 'Requested';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorStatus != CscVisitRequestSelector.STATUS_CONFIRMED
        ) {
            return 'Confirmed';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorVisit != null
            && priorStatus == CscVisitRequestSelector.STATUS_CONFIRMED
            && priorVisit.Confirmed_Date__c != visit.Confirmed_Date__c
        ) {
            return 'Confirmed date updated';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_POSTPONED
            && priorStatus != CscVisitRequestSelector.STATUS_POSTPONED
        ) {
            return 'Postponed';
        }
        if (visit.Status__c == CscVisitRequestSelector.STATUS_CANCELLED
            && priorStatus != CscVisitRequestSelector.STATUS_CANCELLED
        ) {
            return 'Cancelled';
        }
        return null;
    }

    /**
     * @description Active Team Member users grouped by visit.
     * @param visitIds Visit Ids that need a bell notification.
     * @return Map<Id, Set<String>> user Ids grouped by visit.
     */
    private static Map<Id, Set<String>> teamUsersByVisit(Set<Id> visitIds) {
        Map<Id, Set<String>> usersByVisit = new Map<Id, Set<String>>();
        for (TeamMember__c member : [
            SELECT CSCVisitRequest__c, User__c
            FROM TeamMember__c
            WHERE CSCVisitRequest__c IN :visitIds
              AND User__c != null
              AND User__r.IsActive = true
        ]) {
            if (!usersByVisit.containsKey(member.CSCVisitRequest__c)) {
                usersByVisit.put(member.CSCVisitRequest__c, new Set<String>());
            }
            usersByVisit.get(member.CSCVisitRequest__c).add(String.valueOf(member.User__c));
        }
        return usersByVisit;
    }

    /**
     * @description Sends one bell notification. A send fault does not roll back the visit.
     * @param visit Visit opened by the notification.
     * @param userIds Team Member user Ids.
     * @param notice Status text.
     * @param notificationTypeId Custom notification type Id.
     */
    private static void sendNotification(
        CSC_Visit_Request__c visit,
        Set<String> userIds,
        String notice,
        Id notificationTypeId
    ) {
        if (notificationTypeId == null) {
            return;
        }
        try {
            Messaging.CustomNotification notification = new Messaging.CustomNotification();
            notification.setNotificationTypeId(notificationTypeId);
            notification.setTargetId(visit.Id);
            notification.setTitle(limitText(requestTypeLabel(visit.VisitType__c) + ' ' + notice, 250));
            notification.setBody(limitText(notificationBody(visit, notice), 750));
            notification.send(userIds);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR, 'Visit team notification failed: ' + ex.getMessage());
        }
    }

    /**
     * @description Notification type for this story.
     * @return Id type Id, or null when the type has not been deployed.
     */
    private static Id notificationTypeId() {
        if (!notificationTypeLoaded) {
            notificationTypeLoaded = true;
            List<CustomNotificationType> types = [
                SELECT Id
                FROM CustomNotificationType
                WHERE DeveloperName = :NOTIFICATION_TYPE
                LIMIT 1
            ];
            cachedNotificationTypeId = types.isEmpty() ? null : types[0].Id;
        }
        return cachedNotificationTypeId;
    }

    /**
     * @description Short text shown in the bell.
     * @param visit Visit with its account name.
     * @param notice Status text.
     * @return String notification body.
     */
    private static String notificationBody(CSC_Visit_Request__c visit, String notice) {
        String accountName = visit.AccountFacility__r == null ? null : visit.AccountFacility__r.Name;
        String text = requestTypeLabel(visit.VisitType__c) + ' ' + visit.Name;
        if (String.isNotBlank(accountName)) {
            text += ' - ' + accountName;
        }
        return text + ' is ' + notice + '.';
    }

    /**
     * @description User-facing request type.
     * @param requestType Stored Visit Type value.
     * @return String label used in the bell.
     */
    private static String requestTypeLabel(String requestType) {
        if (requestType == CscVisitRequestSelector.REQUEST_ORC) {
            return 'ORC Visit';
        }
        if (requestType == CscVisitRequestSelector.REQUEST_IMS) {
            return 'IMS Visit';
        }
        if (requestType == CscVisitRequestSelector.REQUEST_OSV) {
            return 'OSV Visit';
        }
        return 'CSC Visit';
    }

    /**
     * @description Cuts text at the notification field limit.
     * @param value Text to show.
     * @param maxLength Maximum characters.
     * @return String trimmed text.
     */
    private static String limitText(String value, Integer maxLength) {
        if (value == null) {
            return null;
        }
        return value.length() <= maxLength ? value : value.substring(0, maxLength);
    }
}