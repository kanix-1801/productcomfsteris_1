/**
 * @description Runs the Lead SLA due check. Schedule it hourly. It does not reassign Leads.
 * @author      Vinay
 * @date        2026-10-13
 */
public class LeadSlaScheduler implements Schedulable {

    /**
     * @description Marks due clocks and sends the individual reminders.
     * @param context Schedule context. Unused.
     */
    public void execute(SchedulableContext context) {
        LeadSlaService.markDueClocks();
    }
}