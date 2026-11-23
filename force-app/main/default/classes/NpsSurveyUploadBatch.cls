/**
 * @author PWC Developer
 * @date 2026/11/20
 *
 * @group Survey Management
 *
 * @description
 * GC-3506. Processes a large NPS recipient file in groups so a biannual upload can reach about 40,000 rows.
 */
public with sharing class NpsSurveyUploadBatch implements Database.Batchable<String>, Database.Stateful {

    private Id distributionId;
    private Id contentDocumentId;
    private String headerLine;
    private String headerError;

    public NpsSurveyUploadBatch(Id distributionId, Id contentDocumentId) {
        this.distributionId = distributionId;
        this.contentDocumentId = contentDocumentId;
    }

    public Iterable<String> start(Database.BatchableContext context) {
        ContentVersion version = [
            SELECT VersionData
            FROM ContentVersion
            WHERE ContentDocumentId = :contentDocumentId
            AND IsLatest = true
            LIMIT 1
        ];
        List<String> lines = NpsSurveyDistributionService.splitLines(version.VersionData.toString());
        if (lines.isEmpty()) {
            headerError = 'Upload a recipient file before sending.';
            return new List<String>();
        }
        headerLine = lines.remove(0);
        try {
            NpsSurveyDistributionService.assertHeaders(headerLine);
        } catch (Exception exceptionValue) {
            headerError = exceptionValue.getMessage();
            return new List<String>();
        }
        return lines;
    }

    public void execute(Database.BatchableContext context, List<String> lines) {
        NpsSurveyDistributionService.processDataLines(distributionId, headerLine, lines);
    }

    public void finish(Database.BatchableContext context) {
        if (headerError != null) {
            insert new Survey_Distribution_Recipient__c(
                Survey_Distribution__c = distributionId,
                Delivery_Status__c = 'Failed',
                Failure_Reason__c = headerError
            );
        }
        NpsSurveyDistributionService.rollup(distributionId);
    }
}