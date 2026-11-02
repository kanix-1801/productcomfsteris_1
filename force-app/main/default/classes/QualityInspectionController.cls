/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Thin LWC boundary for GW-5497 Quality Inspection.
 */
public with sharing class QualityInspectionController {
    /** @description Returns configured Risk Justification sentences. */
    @AuraEnabled(cacheable=true)
    public static WorkOrdersService.QualityInspectionRiskTexts getRiskTexts() {
        return WorkOrdersService.getQualityInspectionRiskTexts();
    }

    /** @description Returns Quality Inspection picklist options. */
    @AuraEnabled(cacheable=true)
    public static Map<String, List<WorkOrdersService.QualityInspectionOption>> getOptions() {
        return WorkOrdersService.getQualityInspectionOptions();
    }

    /** @description Returns NCR Reasons valid for a Product Line. */
    @AuraEnabled(cacheable=true)
    public static List<WorkOrdersService.QualityInspectionOption> getNcrReasonOptions(
        String productLine
    ) {
        return WorkOrdersService.getQualityInspectionNcrReasonOptions(productLine);
    }

    /** @description Returns NCR Location Context options valid for an NCR Reason. */
    @AuraEnabled(cacheable=true)
    public static List<WorkOrdersService.QualityInspectionOption> getNcrLocationOptions(
        String ncrReason
    ) {
        return WorkOrdersService.getQualityInspectionNcrLocationOptions(ncrReason);
    }

    /** @description Starts a Quality Inspection session. */
    @AuraEnabled
    public static WorkOrdersService.QualityInspectionWorkspace initializeInspection(
        String workOrderInput
    ) {
        try {
            return WorkOrdersService.initializeQualityInspection(workOrderInput);
        } catch (WorkOrdersService.WorkOrdersServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /** @description Saves Work Order QC fields and the NCR header when one exists. */
    @AuraEnabled
    public static WorkOrdersService.QualityInspectionWorkspace saveInspection(
        Id workOrderId,
        String subStatus,
        String pressureGaugeSerialNumber,
        String inspectionNotes,
        WorkOrdersService.QualityInspectionNcrInput ncrInput
    ) {
        try {
            return WorkOrdersService.saveQualityInspection(
                workOrderId,
                subStatus,
                pressureGaugeSerialNumber,
                inspectionNotes,
                ncrInput
            );
        } catch (WorkOrdersService.WorkOrdersServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /**
     * @description Creates or updates Quality Inspection NCR data.
     *              Also saves inspection fields entered before the NCR action.
     */
    @AuraEnabled
    public static WorkOrdersService.QualityInspectionWorkspace saveNcr(
        Id workOrderId,
        WorkOrdersService.QualityInspectionNcrInput reportInput,
        WorkOrdersService.QualityInspectionNcrLineInput lineInput,
        WorkOrdersService.QualityInspectionDraft inspectionDraft
    ) {
        try {
            return WorkOrdersService.saveQualityInspectionNcr(
                workOrderId,
                reportInput,
                lineInput,
                inspectionDraft
            );
        } catch (WorkOrdersService.WorkOrdersServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /** @description Returns files linked to the Nonconformance Report header. */
    @AuraEnabled
    public static List<NonconformanceReportsService.NonconformanceReportFile> getNcrFiles(
        Id reportId
    ) {
        try {
            return NonconformanceReportsService.getFiles(reportId);
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /**
     * @description GW-5845 - Returns files linked to all given NCR headers.
     * @param reportIds Nonconformance Report Ids
     * @return File rows including the NCR number
     */
    @AuraEnabled
    public static List<NonconformanceReportsService.NonconformanceReportFile> getNcrFilesForReports(
        List<Id> reportIds
    ) {
        try {
            return NonconformanceReportsService.getFiles(
                reportIds == null ? new Set<Id>() : new Set<Id>(reportIds)
            );
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /** @description Adds a photo or file to the Nonconformance Report header. */
    @AuraEnabled
    public static NonconformanceReportsService.NonconformanceReportFile addNcrFile(
        Id reportId,
        String base64Data,
        String fileName
    ) {
        try {
            return NonconformanceReportsService.addFile(reportId, base64Data, fileName);
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /** @description Renames a file linked to the Nonconformance Report header. */
    @AuraEnabled
    public static NonconformanceReportsService.NonconformanceReportFile renameNcrFile(
        Id reportId,
        Id contentDocumentId,
        String newTitle
    ) {
        try {
            return NonconformanceReportsService.renameFile(
                reportId,
                contentDocumentId,
                newTitle
            );
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    /** @description Removes a file from the Nonconformance Report header. */
    @AuraEnabled
    public static void removeNcrFile(Id reportId, Id contentDocumentId) {
        try {
            NonconformanceReportsService.removeFile(reportId, contentDocumentId);
        } catch (NonconformanceReportsService.NonconformanceReportsServiceException exceptionValue) {
            throw buildAuraException(exceptionValue.getMessage());
        }
    }

    private static AuraHandledException buildAuraException(String message) {
        AuraHandledException result = new AuraHandledException(message);
        result.setMessage(message);
        return result;
    }
}