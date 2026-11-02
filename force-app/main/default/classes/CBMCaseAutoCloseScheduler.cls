public class CBMCaseAutoCloseScheduler implements Schedulable {
    public void execute(SchedulableContext sc) {
        Database.executeBatch(new CBMCaseAutoCloseBatch(), 200);
    }
}