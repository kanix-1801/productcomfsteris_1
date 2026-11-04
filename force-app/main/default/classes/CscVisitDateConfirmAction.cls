/**
 * @author Abhishek Mishra
 * @date 03-11-2026
 * @description #GC-3579 Flow entry point for the Confirm Date quick action.
 */
public with sharing class CscVisitDateConfirmAction {
    /**
     * @description One visit and the date selected on the calendar.
     */
    public class Request {
        @InvocableVariable(label='Visit Id' required=true)
        public Id recordId;

        @InvocableVariable(label='Confirmed Date' required=true)
        public Date confirmedDate;
    }

    /**
     * @description Approves the pending approval and saves the selected date.
     * @param requests List<Request> visits from the Confirm Date flow
     * @return void
     */
    @InvocableMethod(
        label='Confirm CSC Visit Date'
        description='Approves the pending visit and saves the confirmed date.'
    )
    public static void confirmDates(List<Request> requests) {
        if (requests == null) {
            return;
        }
        for (Request request : requests) {
            if (request == null) {
                continue;
            }
            CscVisitStatusAction.confirmVisitDate(request.recordId, request.confirmedDate);
        }
    }
}