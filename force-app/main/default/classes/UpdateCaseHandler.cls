/**
 * @author PSL
 * @date 01-02-2026
 * @description handler to evaluate and update Case Status based on active Case Stage Configs.
 * @group Case Stage
 * @notes
 * - Bulkified: accepts multiple Case Ids
 * - Uses CreateCaseHelper to evaluate rules and apply decisions
 */
public with sharing class UpdateCaseHandler {

    public static void evaluateAndUpdateCaseStatus(List<String> orderNumbers) {
        try {     
            if (orderNumbers.isEmpty()) {
                return;
            }

            Set<String> orderNumbersSet = new Set<String>(orderNumbers);

            // Evaluate using helper
            Map<Id, UpdateCaseHelper.EvaluationResult> evalById = UpdateCaseHelper.evaluateCasesForStatus(orderNumbersSet);

            // Apply decisions (bulk DML in USER_MODE)
            Database.SaveResult[] dmlResults = UpdateCaseHelper.applyDecisions(evalById);
            
            for (Database.SaveResult r : dmlResults) {
                if (!r.isSuccess()) { for (Database.Error e : r.getErrors()) { Errorlogger.logMessage(e.getMessage(), 'UpdateCaseHandler', 'evaluateAndUpdateCaseStatus', ErrorLogger.Level.ERROR, r.getId(), null); } }
            }
        } catch (Exception e) {
            // Log the exception with recordId if available
            ErrorLogger.logException(e, 'UpdateCaseHandler', 'evaluateAndUpdateCaseStatus', ErrorLogger.Level.ERROR, null, null);
            // Re-throw the exception to maintain original behavior
            throw e;
        }
    }
}