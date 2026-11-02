/**
 * @author Sagar Anand
 * @date 2026-10-29
 * @description GW-6099 - Constants shared by the Service Appointment Realignment Analysis classes
 *              (service, batch and selectors). Values are the org's picklist API values.
 * @group Field Service
 * @see ServiceAppointmentRealignmentService
 */
public with sharing class ServiceAppointmentRealignmentConstants {
    /** @description Service Appointment statuses included in the analysis. */
    public static final List<String> ELIGIBLE_STATUSES = new List<String>{
        'Scheduled',
        'Dispatched',
        'Accepted',
        'En Route',
        'In Progress'
    };
    /** @description Service Territory Member types that count as working territories (Primary, Secondary). */
    public static final List<String> WORKING_TERRITORY_TYPES = new List<String>{ 'P', 'S' };
    /** @description AddressResourcePreference__c.PreferenceLevel__c value for preferred resources. */
    public static final String PREFERENCE_LEVEL_PREFERRED = 'Preferred';
    /** @description RealignmentConflictCategory__c value when the territory does not match. */
    public static final String CATEGORY_TERRITORY_MISALIGNMENT = 'Territory Misalignment';
    /** @description RealignmentConflictCategory__c value when the preferred resource does not match. */
    public static final String CATEGORY_PREFERRED_RESOURCE_MISALIGNMENT = 'Preferred Resource Misalignment';
    /** @description RealignmentConflictAction__c value when the appointment can be reassigned automatically. */
    public static final String ACTION_AUTO_REASSIGN_ELIGIBLE = 'Auto-reassign eligible';
    /** @description RealignmentConflictAction__c value when a dispatcher must review the appointment. */
    public static final String ACTION_MANUAL_REVIEW = 'Manual Review';
    /** @description Apex class name of the batch, used to detect a run that is still in progress. */
    public static final String BATCH_CLASS_NAME = 'ServiceAppointmentRealignmentBatch';
    /** @description Nebula Logger scenario for every transaction of the analysis. */
    public static final String LOGGER_SCENARIO = 'GW-6099 Realignment Analysis';

    private ServiceAppointmentRealignmentConstants() {
    }
}