/**
 * Performs Lead TAS callouts and owner assignment.
 *
 * @author Abhishek Mishra
 * @date 06-08-2026
 * @description #GC-3279 Sends each Lead through TasAssignmentGateway to TAS
 *              and updates Lead Owner from territory[0] salesRepEmployeeNumber when
 *              an active Healthcare Sales user matches.
 */    
public with sharing class LeadTasIntegrationService {

    private static final String CLASS_NAME = 'LeadTasIntegrationService';
    private static final String EMPTY_STRING = '';

    /**
     * @description Performs one TAS callout per Lead, bulk-resolves users by employee
     *              number, and updates OwnerId in a single DML when needed.
     * @param leads List of Leads to process.
     */
    public static void processLeads(List<Lead> leads) {
        try {
            if (leads != null && !leads.isEmpty()) {
                Map<Id, Lead> leadById = new Map<Id, Lead>();
                Map<Id, String> employeeNumberByLeadId = new Map<Id, String>();

                for (Lead leadRecord : leads) {
                    if (leadRecord == null || leadRecord.Id == null) {
                        continue;
                    }

                    leadById.put(leadRecord.Id, leadRecord);
                    String employeeNumber = resolveEmployeeNumber(leadRecord);
                    if (String.isNotBlank(employeeNumber)) {
                        employeeNumberByLeadId.put(leadRecord.Id, employeeNumber);
                    }
                }

                List<Lead> leadsToUpdate = buildOwnerUpdates(leadById, employeeNumberByLeadId);
                if (!leadsToUpdate.isEmpty()) {
                    logSaveResults(Database.update(leadsToUpdate, false));
                }
            }
        } catch (Exception e) {
            Logger.error(CLASS_NAME + '.processLeads', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Calls TAS for one Lead and returns the trimmed salesRepEmployeeNumber,
     *              or blank when the callout fails or no usable territory is returned.
     * @param leadRecord Lead to send to TAS.
     * @return Employee number from territory[0], or blank.
     */
    private static String resolveEmployeeNumber(Lead leadRecord) {
        String employeeNumber = EMPTY_STRING;

        try {
            TasAssignmentGateway.CalloutResult calloutResult =
                TasAssignmentGateway.sendAssignmentRequest(
                    TasAssignmentRequest.fromLead(leadRecord)
                );

            if (!calloutResult.calloutSuccess) {
                Logger.error(
                    CLASS_NAME + '.resolveEmployeeNumber: TAS callout failed LeadId=' +
                    leadRecord.Id +
                    ', detail=' +
                    calloutResult.errorDetail
                )
                .addTag('Lead')
                .setRecord(leadRecord);
            } else {
                employeeNumber = extractEmployeeNumber(calloutResult.parsedResponse);
            }
        } catch (Exception leadException) {
            Logger.error(
                CLASS_NAME + '.resolveEmployeeNumber: failed processing LeadId=' + leadRecord.Id,
                leadException
            );
        }

        return employeeNumber;
    }

    /**
     * @description Reads salesRepEmployeeNumber from territory[0] when present.
     * @param responseFromCallout Parsed TAS response.
     * @return Trimmed employee number, or blank.
     */
    private static String extractEmployeeNumber(TasAssignmentResponse responseFromCallout) {
        String employeeNumber = EMPTY_STRING;

        if (
            responseFromCallout != null &&
            responseFromCallout.territoryData != null &&
            !responseFromCallout.territoryData.isEmpty() &&
            responseFromCallout.territoryData[0] != null &&
            String.isNotBlank(responseFromCallout.territoryData[0].salesRepEmployeeNumber)
        ) {
            employeeNumber = responseFromCallout.territoryData[0].salesRepEmployeeNumber.trim();
        }

        return employeeNumber;
    }

    /**
     * @description Builds Lead OwnerId updates from a bulk User lookup by employee number.
     * @param leadById Leads keyed by Id.
     * @param employeeNumberByLeadId Employee numbers keyed by Lead Id.
     * @return Leads that need an OwnerId change.
     */
    private static List<Lead> buildOwnerUpdates(
        Map<Id, Lead> leadById,
        Map<Id, String> employeeNumberByLeadId
    ) {
        List<Lead> leadsToUpdate = new List<Lead>();

        if (employeeNumberByLeadId != null && !employeeNumberByLeadId.isEmpty()) {
            Map<String, User> usersByEmployeeNumber =
                UserSelector.selectActiveUsersByEmployeeNumber(
                    new Set<String>(employeeNumberByLeadId.values())
                );

            for (Id leadId : employeeNumberByLeadId.keySet()) {
                Lead leadRecord = leadById.get(leadId);
                User ownerUser = usersByEmployeeNumber.get(employeeNumberByLeadId.get(leadId));

                if (ownerUser != null && leadRecord.OwnerId != ownerUser.Id) {
                    Lead leadForUpdate = new Lead();
                    leadForUpdate.Id = leadId;
                    leadForUpdate.OwnerId = ownerUser.Id;
                    leadsToUpdate.add(leadForUpdate);
                }
            }
        }

        return leadsToUpdate;
    }

    /**
     * @description Records success and failure counts for partial Lead owner updates.
     * @param saveResults DML save results.
     */
    @TestVisible
    private static void logSaveResults(Database.SaveResult[] saveResults) {
        if (saveResults != null && !saveResults.isEmpty()) {
            Integer successCount = 0;
            Integer failureCount = 0;

            for (Integer index = 0; index < saveResults.size(); index++) {
                Database.SaveResult saveResult = saveResults[index];
                if (saveResult.isSuccess()) {
                    successCount++;
                } else {
                    failureCount++;
                    for (Database.Error error : saveResult.getErrors()) {
                        Logger.error(
                            CLASS_NAME + '.logSaveResults: failed Lead owner update index=' +
                            index +
                            ' statusCode=' +
                            error.getStatusCode() +
                            ' message=' +
                            error.getMessage()
                        );
                    }
                }
            }

            Logger.info(
                CLASS_NAME + '.logSaveResults: successCount=' +
                successCount +
                ' failureCount=' +
                failureCount
            );
        }
    }
}