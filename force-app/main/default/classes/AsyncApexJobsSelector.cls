/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Selector for AsyncApexJob (Apex job status). Used to check whether a batch is
 *              already running. The query runs in SYSTEM_MODE; see selectActiveBatchJobsByClassName.
 * @group Platform
 */
public with sharing class AsyncApexJobsSelector extends SoqlQueryBuilder {
    /** @description AsyncApexJob statuses of a batch that has not finished yet. */
    private static final List<String> ACTIVE_STATUSES = new List<String>{
        'Holding',
        'Queued',
        'Preparing',
        'Processing'
    };

    /**
     * @description Binds this selector to AsyncApexJob for SoqlQueryBuilder queries.
     */
    public AsyncApexJobsSelector() {
        this.objectName = 'AsyncApexJob';
    }

    /**
     * @description Selects batch jobs of the given Apex class that are still queued or running.
     *              Runs in SYSTEM_MODE on purpose: it is a read-only job-status check, and the filter on
     *              ApexClass.Name needs access to the ApexClass setup object, which dispatchers do not have
     *              (USER_MODE / SoqlQueryBuilder would fail for them). No business data is returned.
     * @param apexClassName Name of the batch Apex class
     * @return Active batch jobs (empty when none, or when the class name is blank)
     * @example
     * Boolean isRunning = !AsyncApexJobsSelector.selectActiveBatchJobsByClassName('MyBatch').isEmpty();
     */
    public static List<AsyncApexJob> selectActiveBatchJobsByClassName(String apexClassName) {
        if (String.isBlank(apexClassName)) {
            return new List<AsyncApexJob>();
        }

        return [
            SELECT Id, Status
            FROM AsyncApexJob
            WHERE ApexClass.Name = :apexClassName AND JobType = 'BatchApex' AND Status IN :ACTIVE_STATUSES
            WITH SYSTEM_MODE
        ];
    }
}