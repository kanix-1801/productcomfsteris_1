/**
 * @author PSL
 * @date 01-02-2026
 * @description Helper engine to evaluate Case Stage Configs (Custom Metadata) and determine target Case.Status.
 * @group Case Stage
 * @notes
 * - Loads active CaseStageConfig__mdt records for Case object.
 * - Supports Record Type Name filtering via allowed enum.
 * - Evaluates StageCriteria__c as a simple boolean expression with equality/inequality, AND/OR, and boolean literals.
 * - Returns decided Status (StageName__c) per Case based on first matching active config in evaluation order.
 */
public with sharing class UpdateCaseHelper {

    /**
     * @description Result for a single Case evaluation
     */
    public class EvaluationResult {
        public Id caseId;
        public Boolean matched;
        public String targetStatus;
        public String matchedConfigDeveloperName;
        public String message;

        public EvaluationResult(Id caseId) {
            this.caseId = caseId;
            this.matched = false;
            this.targetStatus = null;
            this.matchedConfigDeveloperName = null;
            this.message = null;
        }
    }

    /**
     * @description Evaluate cases and compute target Status values using active CaseStageConfig__mdt
     * @param orderNumbers List of order numbers to evaluate
     * @return Map<Id, EvaluationResult> results keyed by Case Id
     */
    public static Map<Id, EvaluationResult> evaluateCasesForStatus(Set<String> orderNumbers) {
        Map<Id, EvaluationResult> results = new Map<Id, EvaluationResult>();
        if (orderNumbers == null || orderNumbers.isEmpty()) {
            return results; // Return Early
        }

        // Query Cases with security enforced and required fields for evaluation
        // Include common fields likely used in criteria; criteria evaluator can access via dynamic get
        Map<Id, Case> casesById = new Map<Id, Case>([
            SELECT Id, Status, Priority, IsEscalated, Origin, Subject, Reason,
                   RecordTypeId, RecordType.DeveloperName, RecordType.Name,
                   Type, SuppliedEmail, SuppliedName, SuppliedPhone, AccountId, ContactId, PreInstallItem__c, 
                   Order__r.OrderNumber__c, OrderLine__r.ScheduledDate__c, OrderLine__r.ActualShipmentDate__c, OrderLine__r.OrderLineStatus__c, Order__r.AllNonPreinstaLinsHavBlnkActualShipDate__c, Order__r.AnyPreinstaLinsHavBlnkActualShipDate__c, Order__r.noOfOrderLevelHolds__c, //CBM-435
                   Order__r.Status, Order__r.EarliestRequestDateServiceLine__c, Order__r.LatestScheduleDateServiceLine__c, Order__r.NoOfClosedServiceLines__c, Order__r.NoofCancelledServiceLines__c, Order__r.noOfCapitalLineHolds__c, 
                   Order__r.NoOfServiceLines__c, Order__r.AllCapitalLinesClosed__c, Order__r.AreNonCapitalsAndServiceLinesOpen__c, Order__r.NoOfServiceLinesWithPastScheduleDate__c, Order__r.IsProceduralMixedScheduleDateMissing__c, Order__r.IsReprocessingScheduleDateMissing__c
            FROM Case
            WHERE Order__r.OrderNumber__c IN :orderNumbers
        ]);

        if (casesById.isEmpty()) {
            return results;
        }

        Map<String,List<Case>> capitalCasesByOrderNumber = new Map<String,List<Case>>();
        for (Case cas : casesById.values()) {
            if (!cas.RecordType.Name.equals('Capital Line Sub Case')) 
                continue;
            if (capitalCasesByOrderNumber.containsKey(cas.Order__r.OrderNumber__c)) {
                capitalCasesByOrderNumber.get(cas.Order__r.OrderNumber__c).add(cas);
            } else {
                capitalCasesByOrderNumber.put(cas.Order__r.OrderNumber__c, new List<Case>{cas});
            }
        }

        // Determine applicable record type names from enum
        Set<String> supportedRecordTypeNames = new Set<String>();
        supportedRecordTypeNames.add('CBM Case');
        supportedRecordTypeNames.add('Capital Line Sub Case');
        supportedRecordTypeNames.add('Service Installation Sub Case');

        // Load active Case Stage Configs for Case object
        // Fields present in repo: Object__c, StageCriteria__c, StageName__c, IsActive__c
        List<CaseStageConfig__mdt> activeConfigs = [
            SELECT DeveloperName, MasterLabel, Object__c, IsActive__c, StageCriteria__c, StageName__c
            FROM CaseStageConfig__mdt
            WHERE IsActive__c = true
            ORDER BY MasterLabel ASC
        ];

        // Pre-compile configs into lightweight DTOs
        List<StageRule> cbmRules = new List<StageRule>();
        List<StageRule> capitalRules = new List<StageRule>();
        List<StageRule> serviceRules = new List<StageRule>();
        for (CaseStageConfig__mdt m : activeConfigs) {
            if (String.isBlank(m.StageName__c)) { continue;
            }
            if (m.MasterLabel.startsWith('CBM')) {
                cbmRules.add(new StageRule(m.DeveloperName, m.StageName__c.trim(), m.StageCriteria__c));
            }else if (m.MasterLabel.startsWith('Capital')) {
                capitalRules.add(new StageRule(m.DeveloperName, m.StageName__c.trim(), m.StageCriteria__c));
            } else if (m.MasterLabel.startsWith('Service')) {
                serviceRules.add(new StageRule(m.DeveloperName, m.StageName__c.trim(), m.StageCriteria__c));
            } else { continue;
            }
            
        }

        // Evaluate each case against rules
        for (Case cas : casesById.values()) {
            EvaluationResult eresult = new EvaluationResult(cas.Id);
            results.put(cas.Id, eresult);

            // Filter by supported record types
            if (cas.RecordType == null || String.isBlank(cas.RecordType.Name) || !supportedRecordTypeNames.contains(cas.RecordType.Name)) {
                eresult.message = 'Record Type not supported for stage evaluation'; continue;
            }

            if (cas.RecordType.DeveloperName == 'Capital_Line_Sub_Case') {
                // Iterate rules in order; first match wins
                for (StageRule rul : capitalRules) {
                    Boolean isMatch = false;
                    try {
                        isMatch = evaluateCriteria(rul.criteria, cas);
                    } catch (Exception ex) {
                        // Continue to next rule on parse/eval error
                        eresult.matchedConfigDeveloperName = rul.developerName;
                        eresult.message = 'Criteria evaluation error for rule ' + rul.criteria + ': ' + ex.getMessage();
                    }
                    if (isMatch == true) {
                        eresult.matched = true;
                        eresult.targetStatus = rul.stageName;
                        eresult.matchedConfigDeveloperName = rul.developerName;
                        eresult.message = 'Matched';
                        break;
                    }
                }

                if (!eresult.matched) {
                    if (String.isBlank(eresult.message)) { eresult.message = 'No active rule matched';
                    }
                }
            } else if (cas.RecordType.DeveloperName == 'Service_Installation_Sub_Case') {
                // Iterate rules in order; first match wins
                for (StageRule rul : serviceRules) {
                    if (capitalCasesByOrderNumber.get(cas.Order__r.OrderNumber__c) != null) {
                        for (Case capCase : capitalCasesByOrderNumber.get(cas.Order__r.OrderNumber__c)) {
                            Boolean isMatch = false;
                            try {
                                isMatch = evaluateCriteria(rul.criteria, capCase);
                            } catch (Exception ex) {
                                // Continue to next rule on parse/eval error
                                eresult.matchedConfigDeveloperName = rul.developerName;
                                eresult.message = 'Criteria evaluation error for rule ' + rul.criteria + ': ' + ex.getMessage();
                            }
                            if (isMatch == true) {
                                eresult.matched = true;
                                eresult.targetStatus = rul.stageName;
                                eresult.matchedConfigDeveloperName = rul.developerName;
                                eresult.message = 'Matched';
                                break;
                            }
                        }
                    }else{
                        Boolean isMatch = false;
                        try {
                            isMatch = evaluateCriteria(rul.criteria, cas);
                        } catch (Exception ex) {
                            // Continue to next rule on parse/eval error
                            eresult.matchedConfigDeveloperName = rul.developerName;
                            eresult.message = 'Criteria evaluation error for rule ' + rul.criteria + ': ' + ex.getMessage();
                        }
                        if (isMatch == true) {
                            eresult.matched = true;
                            eresult.targetStatus = rul.stageName;
                            eresult.matchedConfigDeveloperName = rul.developerName;
                            eresult.message = 'Matched';
                        }
                    }
                }

                if (!eresult.matched) {
                    if (String.isBlank(eresult.message)) { eresult.message = 'No active rule matched';
                    }
                }
            } else if (cas.RecordType.DeveloperName == 'CBMCase' && !cas.Status.equals('Order Entry')) {
                // Iterate rules in order; first match wins
                for (StageRule rul : cbmRules) {
                    if (capitalCasesByOrderNumber.get(cas.Order__r.OrderNumber__c) != null) {
                        for (Case capCase : capitalCasesByOrderNumber.get(cas.Order__r.OrderNumber__c)) {
                            Boolean isMatch = false;
                            try {
                                isMatch = evaluateCriteria(rul.criteria, capCase);
                            } catch (Exception ex) {
                                // Continue to next rule on parse/eval error
                                eresult.matchedConfigDeveloperName = rul.developerName;
                                eresult.message = 'Criteria evaluation error for rule ' + rul.criteria + ': ' + ex.getMessage();
                            }
                            if (isMatch == true) {
                                eresult.matched = true;
                                eresult.targetStatus = rul.stageName;
                                eresult.matchedConfigDeveloperName = rul.developerName;
                                eresult.message = 'Matched';
                                break;
                            }
                        }
                    }
                }

                if (!eresult.matched) {
                    if (String.isBlank(eresult.message)) { eresult.message = 'No active rule matched';
                    }
                }
            } else {
                eresult.message = 'Record Type not supported for stage evaluation';
            }
        }

        return results;
    }

    /**
     * @description Apply decided statuses to Cases. Performs USER_MODE DML.
     * @param evalResults Map of results from evaluateCases
     * @return Database.SaveResult[] update results
     */
    public static Database.SaveResult[] applyDecisions(Map<Id, EvaluationResult> evalResults) {
        if (evalResults == null || evalResults.isEmpty()) { return new List<Database.SaveResult>();
        }

        List<Case> toUpdate = new List<Case>();
        Map<String, ErrorLog__c> errorLogsByDevName = new Map<String, ErrorLog__c>();
        for (EvaluationResult ersul : evalResults.values()) {
            if (ersul != null && ersul.matched && !String.isBlank(ersul.targetStatus)) {
                Case c = new Case(Id = ersul.caseId, Status = ersul.targetStatus);
                toUpdate.add(c);
            } else if (ersul != null && !ersul.matched && !String.isBlank(ersul.message) && !String.isBlank(ersul.matchedConfigDeveloperName)) {
                if (errorLogsByDevName.containsKey(ersul.matchedConfigDeveloperName)) { continue;
                }
                ErrorLog__c el = new ErrorLog__c();
                el.Class_Name__c = 'UpdateCaseHelper'; el.Method_Name__c = 'evaluateCriteria'; el.Level__c = String.valueOf(ErrorLogger.Level.ERROR); el.Record_Id__c = ersul.caseId; el.Message__c = ersul.message;
                errorLogsByDevName.put(ersul.matchedConfigDeveloperName, el);
            }
        }

        List<ErrorLog__c> toInsert = new List<ErrorLog__c>(errorLogsByDevName.values());
        Database.DMLOptions dmlOpts = new Database.DMLOptions();
        // USER_MODE DML per security requirement
        Database.SaveResult[] sr = new List<Database.SaveResult>();
        if (!toInsert.isEmpty()) { sr = Database.insert(toInsert, false, AccessLevel.USER_MODE);
        }
        if (!toUpdate.isEmpty()) {
            sr = Database.update(toUpdate, false, AccessLevel.USER_MODE);
        }

        return sr;
    }

    // ---------- Internal structures and evaluator ----------

    private class StageRule {
        String developerName;
        String stageName;
        String criteria;
        StageRule(String developerName, String stageName, String criteria) {
            this.developerName = developerName;
            this.stageName = stageName;
            this.criteria = criteria;
        }
    }

    /**
     * @description Evaluate a simple criteria string against a record.
     */
    private static Boolean evaluateCriteria(String formulaText, SObject sObj) {
        if (String.isBlank(formulaText)) return false;
        try {
            FormulaEval.FormulaInstance inst = System.Formula.builder()
                .withType(sObj.getSObjectType())
                .withReturnType(FormulaEval.FormulaReturnType.BOOLEAN)
                .withFormula(formulaText)
                .build();
            Object result = inst.evaluate(sObj);
            return (result instanceof Boolean) ? (Boolean)result : false;
        } catch (Exception e) { throw e;
        }
    }

}