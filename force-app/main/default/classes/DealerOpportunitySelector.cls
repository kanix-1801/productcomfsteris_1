/**
 * @author PWC Developer
 * @date 2026/11/02
 *
 * @group Dealer Portal
 *
 * @description
 * Dealer Portal R1 - SOQL for the dealer home page and My Opportunities workspace.
 * Queries run in user mode so totals and lists use the same shared records.
 */
public with sharing class DealerOpportunitySelector {

    public static final String RECORD_TYPE_NAME = 'HCSalesDealer';
    public static final String CLOSED_WON_STAGE = 'Closed Won';
    public static final Integer RECENT_LIMIT = 10;
    public static final Integer PAST_DUE_LIMIT = 5;
    public static final Integer DEFAULT_PAGE_SIZE = 25;
    public static final Integer MAX_PAGE_SIZE = 50;

    public static final List<String> OPEN_STAGES = new List<String>{
        'Evaluation',
        'Proposal',
        'Commit'
    };

    public static final List<String> WORKSPACE_STAGES = new List<String>{
        'Discovery',
        'Evaluation',
        'Proposal',
        'Commit',
        'Closed Won',
        'Closed Lost',
        'Cancelled',
        'Closed-No Bid'
    };

    public static final List<String> CREATE_STAGES = new List<String>{
        'Evaluation',
        'Proposal',
        'Commit',
        'Closed Won',
        'Closed Lost',
        'Cancelled',
        'Closed-No Bid'
    };

    private static final Map<String, String> SORT_FIELDS = new Map<String, String>{
        'Name' => 'Name',
        'EndCustomerName__c' => 'EndCustomerName__c',
        'DealerAccountName__c' => 'DealerAccountName__c',
        'StageName' => 'StageName',
        'CloseDate' => 'CloseDate',
        'Amount' => 'Amount',
        'CreatedDate' => 'CreatedDate'
    };

    private static final String FIELD_LIST =
        'Id, Name, EndCustomerName__c, DealerAccountName__c, StageName, Amount, CurrencyIsoCode, ' +
        'CloseDate, CreatedDate, Expected_Ship_Date__c, InstallationDate__c, Country__c, IsClosed';

    /**
     * @description
     * Dealer Portal R1 - Filter accepted by the My Opportunities workspace.
     */
    public class OpportunityFilter {
        public String search;
        public String stageName;
        public Boolean pastDueOnly;
        public String country;
        public Decimal amountMin;
        public Decimal amountMax;
        public Date closeDateFrom;
        public Date closeDateTo;
        public Date shipDateFrom;
        public Date shipDateTo;
        public String sortField;
        public String sortDirection;
        public Integer pageSize;
        public Integer pageNumber;
    }

    /**
     * @description
     * Dealer Portal R1 - Returns the ten newest Dealer opportunities the user can access.
     *
     * @return Opportunities ordered by Created Date, newest first.
     */
    public static List<Opportunity> selectRecent() {
        String recordTypeName = RECORD_TYPE_NAME;
        return Database.queryWithBinds(
            'SELECT ' + FIELD_LIST +
            ' FROM Opportunity' +
            ' WHERE RecordType.DeveloperName = :recordTypeName' +
            '' +
            ' ORDER BY CreatedDate DESC' +
            ' LIMIT ' + RECENT_LIMIT,
            new Map<String, Object>{ 'recordTypeName' => recordTypeName },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description
     * Dealer Portal R1 - Returns open Dealer opportunities whose Expected Ship Date is before today.
     *
     * @param rowLimit Maximum rows. The home page uses a short list.
     * @return Matching opportunities, earliest ship date first.
     */
    public static List<Opportunity> selectPastDue(Integer rowLimit) {
        String recordTypeName = RECORD_TYPE_NAME;
        Integer safeLimit = sanitizeLimit(rowLimit, PAST_DUE_LIMIT);
        return Database.queryWithBinds(
            'SELECT ' + FIELD_LIST +
            ' FROM Opportunity' +
            ' WHERE RecordType.DeveloperName = :recordTypeName' +
            ' AND IsClosed = false' +
            ' AND Expected_Ship_Date__c != null' +
            ' AND Expected_Ship_Date__c < TODAY' +
            '' +
            ' ORDER BY Expected_Ship_Date__c ASC' +
            ' LIMIT ' + safeLimit,
            new Map<String, Object>{ 'recordTypeName' => recordTypeName },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description
     * Dealer Portal R1 - Returns one page of Dealer opportunities for the workspace filters.
     *
     * @param filter Search, stage, date, amount, and paging values.
     * @return The requested page.
     */
    public static List<Opportunity> selectByFilter(OpportunityFilter filter) {
        OpportunityFilter safeFilter = filter == null ? new OpportunityFilter() : filter;
        QueryParts parts = buildFilterQuery(safeFilter, false);
        return Database.queryWithBinds(parts.soql, parts.binds, AccessLevel.USER_MODE);
    }

    /**
     * @description
     * Dealer Portal R1 - Counts Dealer opportunities matching the workspace filters.
     *
     * @param filter Search, stage, date, and amount values. Paging is ignored.
     * @return Matching record count.
     */
    public static Integer countByFilter(OpportunityFilter filter) {
        OpportunityFilter safeFilter = filter == null ? new OpportunityFilter() : filter;
        QueryParts parts = buildFilterQuery(safeFilter, true);
        return Database.countQueryWithBinds(parts.soql, parts.binds, AccessLevel.USER_MODE);
    }

    /**
     * @description
     * Dealer Portal R1 - Stage counts and converted USD amounts for every accessible Dealer opportunity.
     *
     * @return One aggregate row per stage.
     */
    public static List<AggregateResult> selectStageSummaries() {
        String recordTypeName = RECORD_TYPE_NAME;
        return Database.queryWithBinds(
            'SELECT StageName stageName, COUNT(Id) recordCount, SUM(convertCurrency(Amount)) amountTotal' +
            ' FROM Opportunity' +
            ' WHERE RecordType.DeveloperName = :recordTypeName' +
            '' +
            ' GROUP BY StageName',
            new Map<String, Object>{ 'recordTypeName' => recordTypeName },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description
     * Dealer Portal R1 - Open pipeline value by fiscal quarter of Close Date.
     *
     * @return Aggregate rows for Evaluation, Proposal, and Commit.
     */
    public static List<AggregateResult> selectQuarterSummaries() {
        String recordTypeName = RECORD_TYPE_NAME;
        List<String> openStages = OPEN_STAGES;
        return Database.queryWithBinds(
            'SELECT FISCAL_YEAR(CloseDate) fiscalYear, FISCAL_QUARTER(CloseDate) fiscalQuarter,' +
            ' SUM(convertCurrency(Amount)) amountTotal' +
            ' FROM Opportunity' +
            ' WHERE RecordType.DeveloperName = :recordTypeName' +
            ' AND IsClosed = false' +
            ' AND StageName IN :openStages' +
            ' AND CloseDate != null' +
            '' +
            ' GROUP BY FISCAL_YEAR(CloseDate), FISCAL_QUARTER(CloseDate)',
            new Map<String, Object>{
                'recordTypeName' => recordTypeName,
                'openStages' => openStages
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description
     * Dealer Portal R1 - Open dealer opportunities used to total pipeline by Business Unit.
     * HCBusinessUnit__c is a multi-select, so the values are split in Apex.
     *
     * @return Open Evaluation, Proposal, and Commit opportunities.
     */
    public static List<Opportunity> selectOpenPipeline() {
        String recordTypeName = RECORD_TYPE_NAME;
        List<String> openStages = OPEN_STAGES;
        return Database.queryWithBinds(
            'SELECT HCBusinessUnit__c, convertCurrency(Amount)' +
            ' FROM Opportunity' +
            ' WHERE RecordType.DeveloperName = :recordTypeName' +
            ' AND IsClosed = false' +
            ' AND StageName IN :openStages',
            new Map<String, Object>{
                'recordTypeName' => recordTypeName,
                'openStages' => openStages
            },
            AccessLevel.USER_MODE
        );
    }

    private static QueryParts buildFilterQuery(OpportunityFilter filter, Boolean countOnly) {
        Map<String, Object> binds = new Map<String, Object>{
            'recordTypeName' => RECORD_TYPE_NAME
        };
        List<String> conditions = new List<String>{
            'RecordType.DeveloperName = :recordTypeName'
        };

        if (String.isNotBlank(filter.stageName)) {
            conditions.add('StageName = :stageName');
            binds.put('stageName', filter.stageName);
        }
        if (filter.pastDueOnly == true) {
            conditions.add('IsClosed = false');
            conditions.add('Expected_Ship_Date__c != null');
            conditions.add('Expected_Ship_Date__c < TODAY');
        }
        if (String.isNotBlank(filter.country)) {
            conditions.add('Country__c = :country');
            binds.put('country', filter.country.trim());
        }
        if (filter.amountMin != null) {
            conditions.add('Amount >= :amountMin');
            binds.put('amountMin', filter.amountMin);
        }
        if (filter.amountMax != null) {
            conditions.add('Amount <= :amountMax');
            binds.put('amountMax', filter.amountMax);
        }
        if (filter.closeDateFrom != null) {
            conditions.add('CloseDate >= :closeDateFrom');
            binds.put('closeDateFrom', filter.closeDateFrom);
        }
        if (filter.closeDateTo != null) {
            conditions.add('CloseDate <= :closeDateTo');
            binds.put('closeDateTo', filter.closeDateTo);
        }
        if (filter.shipDateFrom != null) {
            conditions.add('Expected_Ship_Date__c >= :shipDateFrom');
            binds.put('shipDateFrom', filter.shipDateFrom);
        }
        if (filter.shipDateTo != null) {
            conditions.add('Expected_Ship_Date__c <= :shipDateTo');
            binds.put('shipDateTo', filter.shipDateTo);
        }
        if (String.isNotBlank(filter.search)) {
            List<String> searchConditions = new List<String>{
                'Name LIKE :searchTerm',
                'EndCustomerName__c LIKE :searchTerm',
                'Country__c LIKE :searchTerm'
            };
            binds.put('searchTerm', likeTerm(filter.search));

            Decimal searchAmount = parseSearchAmount(filter.search);
            if (searchAmount != null) {
                searchConditions.add('Amount = :searchAmount');
                binds.put('searchAmount', searchAmount);
            }

            Date searchDate = parseSearchDate(filter.search);
            if (searchDate != null) {
                searchConditions.add('CloseDate = :searchDate');
                searchConditions.add('Expected_Ship_Date__c = :searchDate');
                binds.put('searchDate', searchDate);
            }
            conditions.add('(' + String.join(searchConditions, ' OR ') + ')');
        }

        QueryParts parts = new QueryParts();
        parts.binds = binds;
        parts.soql = countOnly
            ? 'SELECT COUNT() FROM Opportunity WHERE ' + String.join(conditions, ' AND ')
            : 'SELECT ' + FIELD_LIST +
                ' FROM Opportunity WHERE ' + String.join(conditions, ' AND ') +
                '' +
                ' ORDER BY ' + sortClause(filter) +
                ' LIMIT ' + pageSize(filter) +
                ' OFFSET ' + offset(filter);
        return parts;
    }

    private static String likeTerm(String search) {
        return '%' + search.trim() + '%';
    }

    private static Decimal parseSearchAmount(String search) {
        String cleaned = search.trim().replace('$', '').replace(',', '').replace(' ', '');
        if (!Pattern.matches('\\d+(\\.\\d+)?', cleaned)) {
            return null;
        }
        return Decimal.valueOf(cleaned);
    }

    private static Date parseSearchDate(String search) {
        String value = search.trim();
        try {
            return Date.valueOf(value);
        } catch (Exception ignored) {
            // The search may use a locale date instead of yyyy-MM-dd.
        }

        Matcher slashDate = Pattern.compile('^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4})$').matcher(value);
        if (slashDate.matches()) {
            try {
                return Date.newInstance(
                    Integer.valueOf(slashDate.group(3)),
                    Integer.valueOf(slashDate.group(1)),
                    Integer.valueOf(slashDate.group(2))
                );
            } catch (Exception ignored) {
                return null;
            }
        }

        try {
            return Date.parse(value);
        } catch (Exception ignored) {
            return null;
        }
    }

    private static String sortClause(OpportunityFilter filter) {
        String fieldName = SORT_FIELDS.containsKey(filter.sortField) ? SORT_FIELDS.get(filter.sortField) : 'Name';
        String direction = filter.sortDirection == 'DESC' ? 'DESC' : 'ASC';
        return fieldName + ' ' + direction + ' NULLS LAST';
    }

    private static Integer pageSize(OpportunityFilter filter) {
        return sanitizeLimit(filter.pageSize, DEFAULT_PAGE_SIZE);
    }

    private static Integer offset(OpportunityFilter filter) {
        Integer pageNumber = filter.pageNumber == null || filter.pageNumber < 1 ? 1 : filter.pageNumber;
        Integer rowOffset = (pageNumber - 1) * pageSize(filter);
        return Math.min(rowOffset, 2000);
    }

    private static Integer sanitizeLimit(Integer requestedLimit, Integer defaultLimit) {
        if (requestedLimit == null || requestedLimit < 1) {
            return defaultLimit;
        }
        return Math.min(requestedLimit, MAX_PAGE_SIZE);
    }

    private class QueryParts {
        public String soql;
        public Map<String, Object> binds;
    }
}