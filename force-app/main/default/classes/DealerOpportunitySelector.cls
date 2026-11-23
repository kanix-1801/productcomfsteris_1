/**
* @author PWC Developer
* @date 2026/11/02
*
* @group Dealer Portal
*
* @description
* GC-3603 Dealer Portal R1 - SOQL for the dealer home page and My Opportunities workspace.
* Queries run in user mode so totals and lists use the same shared records.
*/
public with sharing class DealerOpportunitySelector {
    
    public static final String RECORD_TYPE_NAME = 'HCSalesDealer';
    public static final String CLOSED_WON_STAGE = 'Closed Won';
    public static final Integer RECENT_LIMIT = 10;
    public static final Integer PAST_DUE_LIMIT = 5;
    public static final Integer DEFAULT_PAGE_SIZE = 25;
    public static final Integer MAX_PAGE_SIZE = 50;
    
    public static final List<String> OPEN_STAGES = new List<String>{ 'Evaluation', 'Proposal', 'Commit' };
        public static final List<String> WORKSPACE_STAGES = new List<String>{
            'Discovery', 'Evaluation', 'Proposal', 'Commit', 'Closed Won', 'Closed Lost',
                'Cancelled', 'Closed Cancelled', 'Closed-No Bid'
                };
                    public static final List<String> CREATE_STAGES = new List<String>{
                        'Evaluation', 'Proposal', 'Commit', 'Closed Won', 'Closed Lost',
                            'Cancelled', 'Closed Cancelled', 'Closed-No Bid'
                            };
                                
                                private static final Map<String, String> SORT_FIELDS = new Map<String, String>{
                                    'Name' => 'Name',
                                        'EndCustomerName__c' => 'EndCustomerName__c',
                                        'Account.Name' => 'Account.Name',
                                        'StageName' => 'StageName',
                                        'CloseDate' => 'CloseDate',
                                        'Amount' => 'Amount',
                                        'CreatedDate' => 'CreatedDate'
                                        };
                                            private static final String FIELD_LIST =
                                            'Id, Name, EndCustomerName__c, Account.Name, StageName, Amount, CurrencyIsoCode, ' +
                                            'CloseDate, CreatedDate, Expected_Ship_Date__c, InstallationDate__c, Country__c, IsClosed';
    private static final String RECORD_TYPE_FILTER = 'RecordType.DeveloperName = :recordTypeName';
    private static final String OPEN_STAGE_FILTER =
        RECORD_TYPE_FILTER + ' AND IsClosed = false AND StageName IN :openStages';
    
    /** @description GC-3603 Dealer Portal R1 - Filter accepted by the My Opportunities workspace. */
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
    
    /** @description GC-3603 Dealer Portal R1 - Returns the ten newest Dealer opportunities the user can access. */
    public static List<Opportunity> selectRecent() {
        return Database.queryWithBinds(
            'SELECT ' + FIELD_LIST + ' FROM Opportunity WHERE ' + RECORD_TYPE_FILTER +
            ' ORDER BY CreatedDate DESC LIMIT ' + RECENT_LIMIT,
            new Map<String, Object>{ 'recordTypeName' => RECORD_TYPE_NAME },
            AccessLevel.USER_MODE
        );
    }
    
    /** @description GC-3603 Dealer Portal R1 - Returns open Dealer opportunities whose Expected Ship Date is before today. */
    public static List<Opportunity> selectPastDue(Integer rowLimit) {
        Integer appliedLimit = rowLimit == null || rowLimit < 1 ? PAST_DUE_LIMIT : Math.min(rowLimit, MAX_PAGE_SIZE);
        return Database.queryWithBinds(
            'SELECT ' + FIELD_LIST + ' FROM Opportunity WHERE ' + RECORD_TYPE_FILTER +
            ' AND IsClosed = false AND Expected_Ship_Date__c != null AND Expected_Ship_Date__c < TODAY' +
            ' ORDER BY Expected_Ship_Date__c ASC LIMIT ' + appliedLimit,
            new Map<String, Object>{ 'recordTypeName' => RECORD_TYPE_NAME },
            AccessLevel.USER_MODE
        );
    }
    
    /** @description GC-3603 Dealer Portal R1 - Returns one page of Dealer opportunities for the workspace filters. */
    public static List<Opportunity> selectByFilter(OpportunityFilter filter) {
        Map<String, Object> binds = new Map<String, Object>();
        return Database.queryWithBinds(buildFilterQuery(filter, false, binds), binds, AccessLevel.USER_MODE);
    }
    
    /** @description GC-3603 Dealer Portal R1 - Counts Dealer opportunities matching the workspace filters. */
    public static Integer countByFilter(OpportunityFilter filter) {
        Map<String, Object> binds = new Map<String, Object>();
        return Database.countQueryWithBinds(buildFilterQuery(filter, true, binds), binds, AccessLevel.USER_MODE);
    }
    
    /** @description GC-3603 Dealer Portal R1 - Stage counts and converted USD amounts for every accessible Dealer opportunity. */
    public static List<AggregateResult> selectStageSummaries() {
        return Database.queryWithBinds(
            'SELECT StageName stageName, COUNT(Id) recordCount, SUM(convertCurrency(Amount)) amountTotal' +
            ' FROM Opportunity WHERE ' + RECORD_TYPE_FILTER + ' GROUP BY StageName',
            new Map<String, Object>{ 'recordTypeName' => RECORD_TYPE_NAME },
            AccessLevel.USER_MODE
        );
    }
    
    /** @description GC-3603 Dealer Portal R1 - Open pipeline value by fiscal quarter of Close Date. */
    public static List<AggregateResult> selectQuarterSummaries() {
        return Database.queryWithBinds(
            'SELECT FISCAL_YEAR(CloseDate) fiscalYear, FISCAL_QUARTER(CloseDate) fiscalQuarter,' +
            ' SUM(convertCurrency(Amount)) amountTotal FROM Opportunity WHERE ' + OPEN_STAGE_FILTER +
            ' AND CloseDate != null GROUP BY FISCAL_YEAR(CloseDate), FISCAL_QUARTER(CloseDate)' +
            ' ORDER BY FISCAL_YEAR(CloseDate), FISCAL_QUARTER(CloseDate)',
            new Map<String, Object>{ 'recordTypeName' => RECORD_TYPE_NAME, 'openStages' => OPEN_STAGES },
            AccessLevel.USER_MODE
        );
    }
    
    /** @description GC-3603 Dealer Portal R1 - Open dealer opportunities used to total pipeline by Business Unit. */
    public static List<Opportunity> selectOpenPipeline() {
        return Database.queryWithBinds(
            'SELECT HCBusinessUnit__c, convertCurrency(Amount) FROM Opportunity WHERE ' + OPEN_STAGE_FILTER,
            new Map<String, Object>{ 'recordTypeName' => RECORD_TYPE_NAME, 'openStages' => OPEN_STAGES },
            AccessLevel.USER_MODE
        );
    }
    
    private static String buildFilterQuery(OpportunityFilter filter, Boolean countOnly, Map<String, Object> binds) {
        if (filter == null) {
            filter = new OpportunityFilter();
        }
        binds.put('recordTypeName', RECORD_TYPE_NAME);
        List<String> conditions = new List<String>{ RECORD_TYPE_FILTER };
            if (filter.pastDueOnly == true) {
                conditions.add('IsClosed = false AND Expected_Ship_Date__c != null AND Expected_Ship_Date__c < TODAY');
            }
        if (String.isNotBlank(filter.stageName)) {
            conditions.add('StageName = :stageName');
            binds.put('stageName', filter.stageName);
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
                'Name LIKE :searchTerm', 'EndCustomerName__c LIKE :searchTerm', 'Country__c LIKE :searchTerm'
                    };
                        binds.put('searchTerm', '%' + filter.search.trim() + '%');
            String cleanedAmount = filter.search.trim().replace('$', '').replace(',', '').replace(' ', '');
            if (Pattern.matches('\\d+(\\.\\d+)?', cleanedAmount)) {
                searchConditions.add('Amount = :searchAmount');
                binds.put('searchAmount', Decimal.valueOf(cleanedAmount));
            }
            Date searchDate;
            String searchValue = filter.search.trim();
            try {
                searchDate = Date.valueOf(searchValue);
            } catch (Exception ignored) {
                // The search may use a locale date instead of yyyy-MM-dd.
            }
            if (searchDate == null) {
                Matcher slashDate = Pattern.compile('^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{4})$').matcher(searchValue);
                if (slashDate.matches()) {
                    try {
                        searchDate = Date.newInstance(
                            Integer.valueOf(slashDate.group(3)),
                            Integer.valueOf(slashDate.group(1)),
                            Integer.valueOf(slashDate.group(2))
                        );
                    } catch (Exception ignored) {
                        searchDate = null;
                    }
                } else {
                    try {
                        searchDate = Date.parse(searchValue);
                    } catch (Exception ignored) {
                        searchDate = null;
                    }
                }
            }
            if (searchDate != null) {
                searchConditions.add('CloseDate = :searchDate');
                searchConditions.add('Expected_Ship_Date__c = :searchDate');
                binds.put('searchDate', searchDate);
            }
            conditions.add('(' + String.join(searchConditions, ' OR ') + ')');
        }
        
        Integer rowLimit = filter.pageSize == null || filter.pageSize < 1
            ? DEFAULT_PAGE_SIZE
            : Math.min(filter.pageSize, MAX_PAGE_SIZE);
        Integer pageNumber = filter.pageNumber == null || filter.pageNumber < 1 ? 1 : filter.pageNumber;
        String sortField = SORT_FIELDS.containsKey(filter.sortField) ? SORT_FIELDS.get(filter.sortField) : 'Name';
        String sortDirection = filter.sortDirection == 'DESC' ? 'DESC' : 'ASC';
        return countOnly
            ? 'SELECT COUNT() FROM Opportunity WHERE ' + String.join(conditions, ' AND ')
            : 'SELECT ' + FIELD_LIST + ' FROM Opportunity WHERE ' + String.join(conditions, ' AND ') +
                ' ORDER BY ' + sortField + ' ' + sortDirection + ' NULLS LAST LIMIT ' + rowLimit +
                ' OFFSET ' + Math.min((pageNumber - 1) * rowLimit, 2000);
    }
}