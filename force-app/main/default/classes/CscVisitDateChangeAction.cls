/**
 * @author Abhishek Mishra
 * @date 02-11-2026
 * @description #GC-3579 Flow entry point for the Change Date quick action.
 */
public with sharing class CscVisitDateChangeAction {
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
     * @description Saves the selected date and rejects a pending approval when one exists.
     * @param requests List<Request> visits from the Change Date flow
     * @return void
     */
    @InvocableMethod(
        label='Change CSC Visit Date'
        description='Saves one confirmed date, rejects a pending approval, and sets the visit to Approved.'
    )
    public static void changeDates(List<Request> requests) {
        if (requests == null) {
            return;
        }
        for (Request request : requests) {
            if (request == null) {
                continue;
            }
            CscVisitStatusAction.changeVisitDate(request.recordId, request.confirmedDate);
        }
    }
}