global class EventLogScheduler implements Schedulable {
    global void execute(SchedulableContext sc) {
        EventLogReportLoader.loadReportEvents();
    }
}