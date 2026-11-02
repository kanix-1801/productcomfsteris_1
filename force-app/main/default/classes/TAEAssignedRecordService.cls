/**
 * @author Suraj Thapliyal
 * @date 2026/08/14
 *
 * @group Temporary Access Exception
 *
 * @description
 * GC-3333 - UI service for TAE assigned Account and Opportunity lists on the record page.
 *           Provides server-side name search and pagination over TAE_AssignedRecord__c child rows.
 *           Invoked by taeAssignedRecords LWC; does not use TemporaryAccessExceptionService.
 */
public with sharing class TAEAssignedRecordService {

    public static final String LOGGER_TAG = 'TAEAssignedRecord';
    public static final String RECORD_TYPE_ACCOUNT = 'Account';
    public static final String RECORD_TYPE_OPPORTUNITY = 'Opportunity';
    public static final String SORT_DIRECTION_ASC = 'ASC';
    public static final String SORT_DIRECTION_DESC = 'DESC';

    private static final Integer DEFAULT_PAGE_SIZE = 25;
    private static final Integer DEFAULT_PAGE_NUMBER = 1;
    private static final Integer MIN_PAGE_SIZE = 1;
    private static final Integer MAX_PAGE_SIZE = 100;
    private static final Integer MAX_SOQL_OFFSET = 2000;

    /**
     * @description GC-3333 - DTO for one assigned Account or Opportunity row rendered in the LWC.
     */
    public class AssignedRecordLinkDTO {
        @AuraEnabled public Id id;
        @AuraEnabled public Id assignedRecordId;
        @AuraEnabled public String name;
        @AuraEnabled public String recordUrl;
    }

    /**
     * @description GC-3333 - Paginated result returned to taeAssignedRecords LWC.
     */
    public class AssignedRecordsPageResult {
        @AuraEnabled public List<AssignedRecordLinkDTO> records;
        @AuraEnabled public Integer totalRecords;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
        @AuraEnabled public Integer totalPages;
    }

    /**
     * @description GC-3333 -
     * Loads a paginated, optionally filtered page of assigned Accounts or Opportunities for one TAE row.
     *
     * @param temporaryAccessExceptionId TemporaryAccessException__c Id from the record page or View All host.
     * @param recordType Filter mode: Account (Account__c rows) or Opportunity (Opportunity__c rows).
     * @param searchTerm Optional case-insensitive contains filter on related record Name.
     * @param pageNumber 1-based page index; values below 1 are normalized to 1.
     * @param pageSize Rows per page; clamped between 1 and 100.
     * @param sortDirection ASC or DESC on related Name; defaults to ASC when blank or invalid.
     * @return Paginated AssignedRecordsPageResult for LWC rendering.
     */
    @AuraEnabled
    public static AssignedRecordsPageResult getAssignedRecordsForUi(
        Id temporaryAccessExceptionId,
        String recordType,
        String searchTerm,
        Integer pageNumber,
        Integer pageSize,
        String sortDirection
    ) {
        try {
            Logger.debug(
                'TAEAssignedRecordService.getAssignedRecordsForUi: taeId=' + temporaryAccessExceptionId +
                ', recordType=' + recordType +
                ', searchTerm=' + searchTerm +
                ', pageNumber=' + pageNumber +
                ', pageSize=' + pageSize +
                ', sortDirection=' + sortDirection
            );

            if (temporaryAccessExceptionId == null) {
                Logger.warn('TAEAssignedRecordService.getAssignedRecordsForUi: null taeId');
                return buildEmptyPageResult(DEFAULT_PAGE_NUMBER, normalizePageSize(pageSize));
            }

            String normalizedRecordType = normalizeRecordType(recordType);
            if (normalizedRecordType == null) {
                Logger.warn(
                    LOGGER_TAG + '.getAssignedRecordsForUi: invalid recordType=' + recordType
                );
                throw new AuraHandledException(
                    'Invalid record type. Expected Account or Opportunity.'
                );
            }

            Integer normalizedPageSize = normalizePageSize(pageSize);
            String searchLikeTerm = buildSearchLikeTerm(searchTerm);
            String normalizedSortDirection = normalizeSortDirection(sortDirection);

            Integer totalRecords = countAssignments(
                temporaryAccessExceptionId,
                normalizedRecordType,
                searchLikeTerm
            );
            Integer totalPages = computeTotalPages(totalRecords, normalizedPageSize);
            Integer normalizedPageNumber = normalizePageNumber(pageNumber, totalPages);

            Integer offset = (normalizedPageNumber - 1) * normalizedPageSize;
            List<AssignedRecordLinkDTO> links = new List<AssignedRecordLinkDTO>();
            if (totalRecords > 0 && offset <= MAX_SOQL_OFFSET) {
                List<TAE_AssignedRecord__c> rows = selectAssignmentPage(
                    temporaryAccessExceptionId,
                    normalizedRecordType,
                    searchLikeTerm,
                    normalizedPageSize,
                    offset,
                    normalizedSortDirection
                );
                links = mapRowsToDtoList(rows, normalizedRecordType);
            }

            AssignedRecordsPageResult result = new AssignedRecordsPageResult();
            result.records = links;
            result.totalRecords = totalRecords;
            result.pageNumber = normalizedPageNumber;
            result.pageSize = normalizedPageSize;
            result.totalPages = totalPages;

            Logger.debug(
                'TAEAssignedRecordService.getAssignedRecordsForUi: totalRecords=' + totalRecords +
                ', returned=' + links.size()
            );
            return result;
        } catch (AuraHandledException auraHandledException) {
            throw auraHandledException;
        } catch (Exception e) {
            Logger.error(LOGGER_TAG + '.getAssignedRecordsForUi: ' + e.getMessage(), e);
            throw new AuraHandledException('Unable to load assigned records.');
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GC-3333 - Counts assigned rows for the requested record type and optional name filter.
     *
     * @param temporaryAccessExceptionId TemporaryAccessException__c Id.
     * @param recordType Account or Opportunity filter mode.
     * @param searchLikeTerm Optional escaped LIKE bind term.
     * @return Total matching assigned rows visible to the running user.
     */
    private static Integer countAssignments(
        Id temporaryAccessExceptionId,
        String recordType,
        String searchLikeTerm
    ) {
        if (RECORD_TYPE_ACCOUNT.equals(recordType)) {
            return TAEAssignedRecordSelector.countAccountAssignmentsByTaeId(
                temporaryAccessExceptionId,
                searchLikeTerm
            );
        }
        return TAEAssignedRecordSelector.countOpportunityAssignmentsByTaeId(
            temporaryAccessExceptionId,
            searchLikeTerm
        );
    }

    /**
     * @description GC-3333 - Loads one page of assigned rows for the requested record type.
     *
     * @param temporaryAccessExceptionId TemporaryAccessException__c Id.
     * @param recordType Account or Opportunity filter mode.
     * @param searchLikeTerm Optional escaped LIKE bind term.
     * @param pageSize Maximum rows to return.
     * @param offset SOQL OFFSET for pagination.
     * @param sortDirection ASC or DESC on related Name.
     * @return Assigned rows for the requested page.
     */
    private static List<TAE_AssignedRecord__c> selectAssignmentPage(
        Id temporaryAccessExceptionId,
        String recordType,
        String searchLikeTerm,
        Integer pageSize,
        Integer offset,
        String sortDirection
    ) {
        if (RECORD_TYPE_ACCOUNT.equals(recordType)) {
            return TAEAssignedRecordSelector.selectAccountAssignmentsByTaeId(
                temporaryAccessExceptionId,
                searchLikeTerm,
                pageSize,
                offset,
                sortDirection
            );
        }
        return TAEAssignedRecordSelector.selectOpportunityAssignmentsByTaeId(
            temporaryAccessExceptionId,
            searchLikeTerm,
            pageSize,
            offset,
            sortDirection
        );
    }

    /**
     * @description GC-3333 - Maps TAE_AssignedRecord__c rows to LWC DTOs.
     *
     * @param rows Assigned child rows from the selector.
     * @param recordType Account or Opportunity filter mode.
     * @return Aura-enabled DTO rows for taeAssignedRecords.
     */
    private static List<AssignedRecordLinkDTO> mapRowsToDtoList(
        List<TAE_AssignedRecord__c> rows,
        String recordType
    ) {
        List<AssignedRecordLinkDTO> links = new List<AssignedRecordLinkDTO>();
        if (rows == null || rows.isEmpty()) {
            return links;
        }

        for (TAE_AssignedRecord__c row : rows) {
            AssignedRecordLinkDTO link = new AssignedRecordLinkDTO();
            link.assignedRecordId = row.Id;

            if (RECORD_TYPE_ACCOUNT.equals(recordType)) {
                link.id = row.Account__c;
                link.name = row.Account__r == null ? null : row.Account__r.Name;
                link.recordUrl = row.Account__c == null
                    ? null
                    : '/lightning/r/Account/' + row.Account__c + '/view';
            } else {
                link.id = row.Opportunity__c;
                link.name = row.Opportunity__r == null ? null : row.Opportunity__r.Name;
                link.recordUrl = row.Opportunity__c == null
                    ? null
                    : '/lightning/r/Opportunity/' + row.Opportunity__c + '/view';
            }
            links.add(link);
        }
        return links;
    }

    /**
     * @description GC-3333 - Builds a SOQL LIKE bind term from user-entered search text.
     *
     * @param searchTerm Raw search text from the LWC.
     * @return Escaped LIKE term, or null when search text is blank.
     */
    @TestVisible
    private static String buildSearchLikeTerm(String searchTerm) {
        if (String.isBlank(searchTerm)) {
            return null;
        }
        return '%' + String.escapeSingleQuotes(searchTerm.trim()) + '%';
    }

    /**
     * @description GC-3333 - Normalizes the LWC record type filter to Account or Opportunity.
     *
     * @param recordType Raw record type from the LWC.
     * @return Normalized record type, or null when invalid.
     */
    @TestVisible
    private static String normalizeRecordType(String recordType) {
        if (String.isBlank(recordType)) {
            return null;
        }
        if (RECORD_TYPE_ACCOUNT.equalsIgnoreCase(recordType.trim())) {
            return RECORD_TYPE_ACCOUNT;
        }
        if (RECORD_TYPE_OPPORTUNITY.equalsIgnoreCase(recordType.trim())) {
            return RECORD_TYPE_OPPORTUNITY;
        }
        return null;
    }

    /**
     * @description GC-3333 - Clamps page size to the supported UI range.
     *
     * @param pageSize Requested page size from the LWC.
     * @return Normalized page size between 1 and 100.
     */
    @TestVisible
    private static Integer normalizePageSize(Integer pageSize) {
        if (pageSize == null || pageSize < MIN_PAGE_SIZE) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.min(pageSize, MAX_PAGE_SIZE);
    }

    /**
     * @description GC-3333 - Normalizes page number to a valid 1-based index for the result set.
     *
     * @param pageNumber Requested page number from the LWC.
     * @param totalPages Total pages available for the current filter.
     * @return Normalized page number.
     */
    @TestVisible
    private static Integer normalizePageNumber(Integer pageNumber, Integer totalPages) {
        Integer normalizedPageNumber = pageNumber == null || pageNumber < DEFAULT_PAGE_NUMBER
            ? DEFAULT_PAGE_NUMBER
            : pageNumber;
        if (totalPages != null && totalPages > 0 && normalizedPageNumber > totalPages) {
            return totalPages;
        }
        return normalizedPageNumber;
    }

    /**
     * @description GC-3333 - Normalizes sort direction to ASC or DESC.
     *
     * @param sortDirection Raw sort direction from the LWC.
     * @return ASC or DESC.
     */
    @TestVisible
    private static String normalizeSortDirection(String sortDirection) {
        return SORT_DIRECTION_DESC.equalsIgnoreCase(sortDirection)
            ? SORT_DIRECTION_DESC
            : SORT_DIRECTION_ASC;
    }

    /**
     * @description GC-3333 - Computes total pages from record count and page size.
     *
     * @param totalRecords Total rows matching the current filter.
     * @param pageSize Normalized page size.
     * @return Total pages, or 0 when no rows exist.
     */
    @TestVisible
    private static Integer computeTotalPages(Integer totalRecords, Integer pageSize) {
        if (totalRecords == null || totalRecords <= 0 || pageSize == null || pageSize <= 0) {
            return 0;
        }
        return (Integer) Math.ceil((Decimal) totalRecords / pageSize);
    }

    /**
     * @description GC-3333 - Builds an empty paginated response for invalid or missing parent Ids.
     *
     * @param pageNumber Requested page number.
     * @param pageSize Requested page size.
     * @return Empty AssignedRecordsPageResult.
     */
    private static AssignedRecordsPageResult buildEmptyPageResult(
        Integer pageNumber,
        Integer pageSize
    ) {
        AssignedRecordsPageResult result = new AssignedRecordsPageResult();
        result.records = new List<AssignedRecordLinkDTO>();
        result.totalRecords = 0;
        result.pageNumber = pageNumber == null ? DEFAULT_PAGE_NUMBER : pageNumber;
        result.pageSize = pageSize == null ? DEFAULT_PAGE_SIZE : pageSize;
        result.totalPages = 0;
        return result;
    }
}