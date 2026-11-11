/**
 * GCL-102. Daily Life Science checks for TemporaryAccessException__c.
 * AC2 rejects a request that is still waiting for approval on its Start Date.
 * AC5 reminds the manager and Delegated Approver seven days after submission
 * when the Start Date is still after that reminder day.
 */
public without sharing class LSTemporaryAccessPendingService implements Schedulable {

    public static final String JOB_NAME = 'Life Science Temporary Access Pending';
    public static final String STATUS_APPROVAL_REQUESTED = 'Approval Requested';
    public static final String STATUS_PENDING_APPROVAL = 'Pending Approval';
    public static final String STATUS_REJECTED = 'Rejected';
    public static final Integer REMINDER_DAYS = 7;

    /** Runs the daily pending-request check when the scheduled job fires. */
    public void execute(SchedulableContext context) {
        processDaily();
    }

    /** Schedules the daily job for 11:00 PM org time. */
    public static void scheduleDaily() {
        System.schedule(JOB_NAME, '0 0 23 * * ?', new LSTemporaryAccessPendingService());
    }

    /**
     * Runs once per day at 11:00 PM org time. A request submitted on its Start Date
     * stays open until this run. Date comparison only; the time of day is not evaluated.
     */
    public static void processDaily() {
        Date today = Date.today();
        List<TemporaryAccessException__c> waiting = [
            SELECT Id, StartDate__c, CreatedDate
            FROM TemporaryAccessException__c
            WHERE Status__c IN (:STATUS_APPROVAL_REQUESTED, :STATUS_PENDING_APPROVAL)
              AND CreatedBy.Profile.Name = :LSTemporaryAccessExceptionEmailService.LIFE_SCIENCE_SALES_PROFILE
        ];
        List<TemporaryAccessException__c> rejections = new List<TemporaryAccessException__c>();
        List<Id> reminderIds = new List<Id>();
        for (TemporaryAccessException__c row : waiting) {
            if (row.StartDate__c != null && row.StartDate__c <= today) {
                rejections.add(new TemporaryAccessException__c(
                    Id = row.Id,
                    Status__c = STATUS_REJECTED
                ));
                continue;
            }
            if (isReminderDue(row, today)) {
                reminderIds.add(row.Id);
            }
        }
        if (!rejections.isEmpty()) {
            Database.update(rejections, AccessLevel.SYSTEM_MODE);
        }
        if (!reminderIds.isEmpty()) {
            LSTemporaryAccessExceptionEmailService.sendReminder(reminderIds);
        }
    }

    /** True on the seventh day after submission when the Start Date is still later. */
    @TestVisible
    private static Boolean isReminderDue(TemporaryAccessException__c row, Date today) {
        if (row.CreatedDate == null || row.StartDate__c == null) {
            return false;
        }
        Date submitted = row.CreatedDate.date();
        Date reminderDate = submitted.addDays(REMINDER_DAYS);
        return reminderDate == today && row.StartDate__c > reminderDate;
    }
}