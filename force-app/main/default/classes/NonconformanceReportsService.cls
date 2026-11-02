/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Service for NonconformanceReport__c operations.
 */
public with sharing class NonconformanceReportsService {
    /** @description Returns NCR headers for a Work Order. */
    public static List<NonconformanceReport__c> getByWorkOrderId(Id workOrderId) {
        return NonconformanceReportsSelector.selectByWorkOrderId(workOrderId);
    }

    /** @description Creates an NCR header in user mode. */
    public static NonconformanceReport__c createReport(NonconformanceReport__c report) {
        if (report == null) {
            throw new NonconformanceReportsServiceException('NCR is required.');
        }
        try {
            Database.insert(report, AccessLevel.USER_MODE);
            return report;
        } catch (DmlException exceptionValue) {
            Logger.error('NonconformanceReportsService.createReport failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to create NCR: ' + exceptionValue.getDmlMessage(0),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Files linked to an NCR header, newest first.
     * @param reportId Nonconformance Report Id
     * @return File rows for the Quality Inspection photos table
     */
    public static List<NonconformanceReportFile> getFiles(Id reportId) {
        if (reportId == null) {
            throw new NonconformanceReportsServiceException(
                'Nonconformance Report is required.'
            );
        }
        return getFiles(new Set<Id>{ reportId });
    }

    /**
     * @description GW-5845 - Files linked to the given NCR headers, grouped by NCR then newest first.
     * @param reportIds Nonconformance Report Ids
     * @return File rows including the NCR number
     */
    public static List<NonconformanceReportFile> getFiles(Set<Id> reportIds) {
        if (reportIds == null || reportIds.isEmpty()) {
            return new List<NonconformanceReportFile>();
        }
        List<NonconformanceReport__c> reports =
            NonconformanceReportsSelector.selectById(reportIds);
        if (reports.isEmpty()) {
            throw new NonconformanceReportsServiceException(
                'Nonconformance Report was not found.'
            );
        }
        Map<Id, String> reportNumberById = new Map<Id, String>();
        for (NonconformanceReport__c report : reports) {
            reportNumberById.put(report.Id, report.Name);
        }
        try {
            List<NonconformanceReportFile> files = new List<NonconformanceReportFile>();
            for (
                ContentDocumentLinksService.DeviceEvaluationFileData row :
                ContentDocumentLinksService.getFilesForLinkedEntities(reportNumberById.keySet())
            ) {
                files.add(toFile(row, reportNumberById));
            }
            files.sort();
            return files;
        } catch (NonconformanceReportsServiceException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error('NonconformanceReportsService.getFiles failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to load files for this Nonconformance Report.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Creates a file and links it to the NCR header immediately.
     * @param reportId Nonconformance Report Id
     * @param base64Data File payload, optionally data-URL prefixed
     * @param fileName File name including extension
     * @return The linked file row
     */
    public static NonconformanceReportFile addFile(
        Id reportId,
        String base64Data,
        String fileName
    ) {
        assertReportAccessible(reportId);
        if (String.isBlank(base64Data)) {
            throw new NonconformanceReportsServiceException('File data is required.');
        }
        try {
            List<ContentVersion> created = ContentVersionsService.createContentVersions(
                new List<ContentVersion>{ buildContentVersion(base64Data, fileName) }
            );
            if (created.isEmpty() || created[0].ContentDocumentId == null) {
                throw new NonconformanceReportsServiceException('Unable to add the file.');
            }
            ContentDocumentLinksService.attachDocumentsToLinkedEntity(
                reportId,
                new List<Id>{ created[0].ContentDocumentId }
            );
            return toFile(
                ContentDocumentLinksService.toFileData(created[0]),
                reportId,
                reportNumberById(reportId)
            );
        } catch (NonconformanceReportsServiceException exceptionValue) {
            throw exceptionValue;
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException exceptionValue) {
            throw new NonconformanceReportsServiceException(
                exceptionValue.getMessage(),
                exceptionValue
            );
        } catch (Exception exceptionValue) {
            Logger.error('NonconformanceReportsService.addFile failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to add the file.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Removes a file from the NCR header and deletes it when nothing else uses it.
     * @param reportId Nonconformance Report Id
     * @param contentDocumentId ContentDocument Id
     */
    public static void removeFile(Id reportId, Id contentDocumentId) {
        assertReportAccessible(reportId);
        try {
            ContentDocumentLinksService.removeDocumentFromLinkedEntity(
                reportId,
                contentDocumentId
            );
        } catch (ContentDocumentLinksService.ContentDocumentLinksServiceException exceptionValue) {
            throw new NonconformanceReportsServiceException(
                exceptionValue.getMessage(),
                exceptionValue
            );
        } catch (Exception exceptionValue) {
            Logger.error('NonconformanceReportsService.removeFile failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to remove the file.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Renames a file linked to the NCR header.
     * @param reportId Nonconformance Report Id
     * @param contentDocumentId ContentDocument Id
     * @param newTitle Title entered by the user
     * @return The updated file row
     */
    public static NonconformanceReportFile renameFile(
        Id reportId,
        Id contentDocumentId,
        String newTitle
    ) {
        assertReportAccessible(reportId);
        NonconformanceReportFile linkedFile = findLinkedFile(reportId, contentDocumentId);
        String cleanedTitle = cleanTitle(newTitle, linkedFile.fileExtension);
        try {
            ContentVersion toUpdate = new ContentVersion();
            toUpdate.Id = linkedFile.contentVersionId;
            toUpdate.Title = cleanedTitle;
            ContentVersionsService.updateContentVersions(new List<ContentVersion>{ toUpdate });
            List<ContentVersion> refreshed = ContentVersionsService.getContentVersionsById(
                new Set<Id>{ linkedFile.contentVersionId }
            );
            if (refreshed.isEmpty()) {
                throw new NonconformanceReportsServiceException('Unable to rename the file.');
            }
            return toFile(
                ContentDocumentLinksService.toFileData(refreshed[0]),
                reportId,
                linkedFile.reportNumber
            );
        } catch (NonconformanceReportsServiceException exceptionValue) {
            throw exceptionValue;
        } catch (Exception exceptionValue) {
            Logger.error('NonconformanceReportsService.renameFile failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to rename the file.',
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /** @description Updates NCR headers in user mode. */
    public static void updateReports(List<NonconformanceReport__c> reports) {
        if (reports == null || reports.isEmpty()) {
            return;
        }
        try {
            Database.update(reports, AccessLevel.USER_MODE);
        } catch (DmlException exceptionValue) {
            Logger.error('NonconformanceReportsService.updateReports failed.', exceptionValue);
            throw new NonconformanceReportsServiceException(
                'Unable to update NCR: ' + exceptionValue.getDmlMessage(0),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /** @description File row shown on the Nonconformance Report header. */
    public class NonconformanceReportFile implements Comparable {
        @AuraEnabled public Id reportId { get; set; }
        @AuraEnabled public String reportNumber { get; set; }
        @AuraEnabled public Id contentDocumentId { get; set; }
        @AuraEnabled public Id contentVersionId { get; set; }
        @AuraEnabled public String title { get; set; }
        @AuraEnabled public String fileExtension { get; set; }
        @AuraEnabled public String fileType { get; set; }
        @AuraEnabled public Datetime lastModifiedDate { get; set; }
        @AuraEnabled public String downloadUrl { get; set; }
        @AuraEnabled public String thumbnailUrl { get; set; }
        @AuraEnabled public String imageDownloadUrl { get; set; }
        @AuraEnabled public Boolean isImage { get; set; }

        /**
         * @description GW-5845 - Group by NCR number, then newest files first within each NCR.
         * @param other Another file row
         * @return Sort order
         */
        public Integer compareTo(Object other) {
            NonconformanceReportFile that = (NonconformanceReportFile) other;
            String thisReport = String.isBlank(this.reportNumber) ? '' : this.reportNumber;
            String thatReport = that == null || String.isBlank(that.reportNumber)
                ? ''
                : that.reportNumber;
            Integer reportCompare = thisReport.compareTo(thatReport);
            if (reportCompare != 0) {
                return reportCompare;
            }
            Long thisTime = this.lastModifiedDate == null
                ? 0
                : this.lastModifiedDate.getTime();
            Long thatTime = that == null || that.lastModifiedDate == null
                ? 0
                : that.lastModifiedDate.getTime();
            if (thisTime == thatTime) {
                return 0;
            }
            return thisTime > thatTime ? -1 : 1;
        }
    }

    /** @description NCR service exception. */
    public class NonconformanceReportsServiceException extends Exception {}

    private static void assertReportAccessible(Id reportId) {
        if (reportId == null) {
            throw new NonconformanceReportsServiceException(
                'Nonconformance Report is required.'
            );
        }
        if (NonconformanceReportsSelector.selectById(new Set<Id>{ reportId }).isEmpty()) {
            throw new NonconformanceReportsServiceException(
                'Nonconformance Report was not found.'
            );
        }
    }

    private static NonconformanceReportFile findLinkedFile(
        Id reportId,
        Id contentDocumentId
    ) {
        if (contentDocumentId == null) {
            throw new NonconformanceReportsServiceException('File is required.');
        }
        for (
            ContentDocumentLinksService.DeviceEvaluationFileData row :
            ContentDocumentLinksService.getFilesForLinkedEntities(new Set<Id>{ reportId })
        ) {
            if (row.contentDocumentId == contentDocumentId) {
                return toFile(row, reportId, reportNumberById(reportId));
            }
        }
        throw new NonconformanceReportsServiceException(
            'The selected file is not attached to this Nonconformance Report.'
        );
    }

    private static String cleanTitle(String newTitle, String fileExtension) {
        if (String.isBlank(newTitle)) {
            throw new NonconformanceReportsServiceException('File title is required.');
        }
        String cleanedTitle = newTitle.trim();
        if (
            String.isNotBlank(fileExtension) &&
            cleanedTitle.toLowerCase().endsWith('.' + fileExtension.toLowerCase())
        ) {
            cleanedTitle = cleanedTitle.substring(
                0,
                cleanedTitle.length() - fileExtension.length() - 1
            ).trim();
        }
        if (String.isBlank(cleanedTitle)) {
            throw new NonconformanceReportsServiceException('File title is required.');
        }
        return cleanedTitle.length() > 255 ? cleanedTitle.substring(0, 255) : cleanedTitle;
    }

    private static ContentVersion buildContentVersion(String base64Data, String fileName) {
        String resolvedFileName = String.isBlank(fileName)
            ? 'NCR-' + Datetime.now().format('yyyy-MM-dd-HHmmss') + '.jpg'
            : fileName.trim();
        if (!resolvedFileName.contains('.')) {
            resolvedFileName += '.jpg';
        }
        if (resolvedFileName.length() > 255) {
            resolvedFileName = resolvedFileName.substring(resolvedFileName.length() - 255);
        }

        String payload = base64Data;
        Integer commaIndex = payload.indexOf(',');
        if (payload.startsWith('data:') && commaIndex > -1) {
            payload = payload.substring(commaIndex + 1);
        }

        ContentVersion version = new ContentVersion();
        String title = resolvedFileName.contains('.')
            ? resolvedFileName.substring(0, resolvedFileName.lastIndexOf('.'))
            : resolvedFileName;
        if (String.isBlank(title)) {
            title = 'File';
        }
        version.Title = title.length() > 255 ? title.substring(0, 255) : title;
        version.PathOnClient = resolvedFileName;
        version.VersionData = EncodingUtil.base64Decode(payload);
        return version;
    }

    private static String reportNumberById(Id reportId) {
        List<NonconformanceReport__c> reports =
            NonconformanceReportsSelector.selectById(new Set<Id>{ reportId });
        return reports.isEmpty() ? null : reports[0].Name;
    }

    private static NonconformanceReportFile toFile(
        ContentDocumentLinksService.DeviceEvaluationFileData source,
        Map<Id, String> reportNumberById
    ) {
        Id reportId = source == null ? null : source.linkedEntityId;
        return toFile(
            source,
            reportId,
            reportNumberById == null ? null : reportNumberById.get(reportId)
        );
    }

    private static NonconformanceReportFile toFile(
        ContentDocumentLinksService.DeviceEvaluationFileData source,
        Id reportId,
        String reportNumber
    ) {
        NonconformanceReportFile file = new NonconformanceReportFile();
        file.reportId = reportId;
        file.reportNumber = reportNumber;
        if (source == null) {
            return file;
        }
        file.contentDocumentId = source.contentDocumentId;
        file.contentVersionId = source.contentVersionId;
        file.title = source.title;
        file.fileExtension = source.fileExtension;
        file.fileType = source.fileType;
        file.lastModifiedDate = source.lastModifiedDate;
        file.downloadUrl = source.downloadUrl;
        file.thumbnailUrl = source.thumbnailUrl;
        file.imageDownloadUrl = source.imageDownloadUrl;
        file.isImage = source.isImage;
        return file;
    }
}