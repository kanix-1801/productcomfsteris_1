/**
 * @author PWC Developer
 * @date 2026/11/02
 *
 * @group Dealer Portal
 *
 * @description
 * Dealer Portal R1 - Builds the home page, My Opportunities workspace, and dealer opportunity
 * creation. Record access stays in user mode. Owner assignment is delegated to the share service.
 */
public with sharing class DealerOpportunityService {

    private static final String DEFAULT_CURRENCY = 'USD';
    private static final String DEFAULT_CONFIDENCE = 'Pipeline';

    /**
     * @description
     * Dealer Portal R1 - Home page metrics, charts, recent opportunities, and past-due opportunities.
     *
     * @return Home payload for the portal landing page.
     */
    public static DealerOpportunityController.HomeResponse getHome() {
        DealerOpportunityController.HomeResponse response = new DealerOpportunityController.HomeResponse();
        response.summary = buildSummary(DealerOpportunitySelector.selectStageSummaries());
        response.recentOpportunities = toRows(DealerOpportunitySelector.selectRecent());
        response.pastDueOpportunities = toRows(
            DealerOpportunitySelector.selectPastDue(DealerOpportunitySelector.PAST_DUE_LIMIT)
        );
        response.stageChart = buildStageChart(response.summary);
        response.quarterChart = buildQuarterChart(DealerOpportunitySelector.selectQuarterSummaries());
        response.businessUnitChart = buildBusinessUnitChart(DealerOpportunitySelector.selectOpenPipeline());
        return response;
    }

    /**
     * @description
     * Dealer Portal R1 - Workspace summary and one filtered page of opportunities.
     *
     * @param filterJson Filter JSON from the My Opportunities page.
     * @return Summary tiles, stage tabs, and the current page.
     */
    public static DealerOpportunityController.WorkspaceResponse getWorkspace(String filterJson) {
        DealerOpportunitySelector.OpportunityFilter filter = parseFilter(filterJson);
        DealerOpportunityController.WorkspaceResponse response = new DealerOpportunityController.WorkspaceResponse();
        response.summary = buildSummary(DealerOpportunitySelector.selectStageSummaries());
        response.totalCount = DealerOpportunitySelector.countByFilter(filter);
        response.opportunities = toRows(DealerOpportunitySelector.selectByFilter(filter));
        response.pageNumber = filter.pageNumber == null || filter.pageNumber < 1 ? 1 : filter.pageNumber;
        response.pageSize = filter.pageSize == null
            ? DealerOpportunitySelector.DEFAULT_PAGE_SIZE
            : Math.min(filter.pageSize, DealerOpportunitySelector.MAX_PAGE_SIZE);
        return response;
    }

    /**
     * @description
     * Dealer Portal R1 - Defaults shown on the create form.
     *
     * @return Currency default and whether an internal user must choose the dealer account.
     */
    public static DealerOpportunityController.CreateContext getCreateContext() {
        DealerOpportunityController.CreateContext context = new DealerOpportunityController.CreateContext();
        context.defaultCurrency = DEFAULT_CURRENCY;
        context.currencies = activeCurrencies();
        context.businessUnits = businessUnitOptions();
        context.stages = new List<String>(DealerOpportunitySelector.CREATE_STAGES);
        context.recordTypeId = dealerRecordTypeId();

        User currentUser = [
            SELECT UserType, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        context.partnerUser = currentUser.UserType == 'PowerPartner';
        if (context.partnerUser && currentUser.Contact != null) {
            context.dealerAccountId = currentUser.Contact.AccountId;
            context.dealerAccountName = DealerOpportunityShareService.selectAccountName(
                currentUser.Contact.AccountId
            );
        }
        return context;
    }

    /**
     * @description
     * Dealer Portal R1 - Creates a Dealer opportunity in Evaluation and USD, then assigns the
     * STERIS Dealer Manager as owner.
     *
     * @param requestJson Create form JSON.
     * @return New opportunity Id.
     */
    public static Id createOpportunity(String requestJson) {
        CreateRequest request = parseCreateRequest(requestJson);
        validateCreateRequest(request);

        Id dealerAccountId = resolveDealerAccountId(request.accountId);
        String dealerAccountName = DealerOpportunityShareService.selectAccountName(dealerAccountId);
        if (String.isBlank(dealerAccountName)) {
            throw new DealerOpportunityException('Select a valid dealer account.');
        }

        Opportunity opportunityRecord = new Opportunity();
        opportunityRecord.RecordTypeId = dealerRecordTypeId();
        opportunityRecord.Name = request.name.trim();
        opportunityRecord.AccountId = dealerAccountId;
        opportunityRecord.DealerAccountName__c = dealerAccountName;
        opportunityRecord.EndCustomerName__c = request.endCustomerName.trim();
        opportunityRecord.Description = request.description.trim();
        opportunityRecord.Country__c = request.country.trim();
        opportunityRecord.HCBusinessUnit__c = normalizeBusinessUnits(request.businessUnits);
        opportunityRecord.Amount = request.amount;
        opportunityRecord.StageName = request.stageName;
        opportunityRecord.ForecastConfidenceLevel__c = DEFAULT_CONFIDENCE;
        opportunityRecord.CloseDate = Date.valueOf(request.closeDate);
        opportunityRecord.Expected_Ship_Date__c = Date.valueOf(request.expectedShipDate);
        opportunityRecord.InstallationDate__c = Date.valueOf(request.installationDate);
        opportunityRecord.DealerSubmitter__c = UserInfo.getUserId();
        opportunityRecord.CurrencyIsoCode = String.isBlank(request.currencyCode)
            ? DEFAULT_CURRENCY
            : request.currencyCode;

        insert opportunityRecord;

        DealerOpportunityShareService.assignOwnerAndShare(opportunityRecord.Id, UserInfo.getUserId());
        return opportunityRecord.Id;
    }

    /**
     * @description
     * Dealer Portal R1 - Completes a Dealer opportunity created from the standard layout form.
     *
     * @param opportunityId Opportunity created by the signed-in user.
     */
    public static void finalizeCreatedOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new DealerOpportunityException('The opportunity was not created.');
        }

        List<Opportunity> opportunities = [
            SELECT Id, AccountId, DealerAccountName__c, DealerSubmitter__c, ForecastConfidenceLevel__c
            FROM Opportunity
            WHERE Id = :opportunityId
            LIMIT 1
        ];
        if (opportunities.isEmpty()) {
            throw new DealerOpportunityException('The opportunity was not created.');
        }

        Opportunity opportunityRecord = opportunities[0];
        Boolean changed = false;
        if (opportunityRecord.DealerSubmitter__c == null) {
            opportunityRecord.DealerSubmitter__c = UserInfo.getUserId();
            changed = true;
        }
        if (String.isBlank(opportunityRecord.ForecastConfidenceLevel__c)) {
            opportunityRecord.ForecastConfidenceLevel__c = DEFAULT_CONFIDENCE;
            changed = true;
        }
        if (opportunityRecord.AccountId != null && String.isBlank(opportunityRecord.DealerAccountName__c)) {
            opportunityRecord.DealerAccountName__c = DealerOpportunityShareService.selectAccountName(
                opportunityRecord.AccountId
            );
            changed = true;
        }
        if (changed) {
            update opportunityRecord;
        }
        DealerOpportunityShareService.assignOwnerAndShare(opportunityRecord.Id, UserInfo.getUserId());
    }

    private static DealerOpportunityController.Summary buildSummary(List<AggregateResult> stageResults) {
        Map<String, AggregateResult> resultByStage = new Map<String, AggregateResult>();
        Integer totalCount = 0;
        for (AggregateResult stageResult : stageResults) {
            String stageName = (String) stageResult.get('stageName');
            resultByStage.put(stageName, stageResult);
            totalCount += integerValue(stageResult.get('recordCount'));
        }

        DealerOpportunityController.Summary summary = new DealerOpportunityController.Summary();
        summary.openCount = 0;
        summary.openPipelineValue = 0;
        summary.closedWonCount = 0;
        summary.closedWonValue = 0;
        summary.totalCount = totalCount;
        summary.stages = new List<DealerOpportunityController.StageMetric>();

        for (String stageName : DealerOpportunitySelector.WORKSPACE_STAGES) {
            AggregateResult stageResult = resultByStage.get(stageName);
            Integer stageCount = stageResult == null ? 0 : integerValue(stageResult.get('recordCount'));
            Decimal stageAmount = stageResult == null ? 0 : decimalValue(stageResult.get('amountTotal'));
            summary.stages.add(stageMetric(stageName, stageCount, stageAmount));

            if (DealerOpportunitySelector.OPEN_STAGES.contains(stageName)) {
                summary.openCount += stageCount;
                summary.openPipelineValue += stageAmount;
            }
            if (stageName == DealerOpportunitySelector.CLOSED_WON_STAGE) {
                summary.closedWonCount = stageCount;
                summary.closedWonValue = stageAmount;
            }
        }
        return summary;
    }

    private static List<DealerOpportunityController.StageMetric> buildStageChart(
        DealerOpportunityController.Summary summary
    ) {
        List<DealerOpportunityController.StageMetric> chart = new List<DealerOpportunityController.StageMetric>();
        for (DealerOpportunityController.StageMetric stageMetric : summary.stages) {
            if (DealerOpportunitySelector.OPEN_STAGES.contains(stageMetric.stageName)) {
                chart.add(stageMetric);
            }
        }
        return chart;
    }

    private static List<DealerOpportunityController.ChartPoint> buildQuarterChart(List<AggregateResult> results) {
        List<DealerOpportunityController.ChartPoint> points = new List<DealerOpportunityController.ChartPoint>();
        for (AggregateResult result : results) {
            Integer fiscalYear = integerValue(result.get('fiscalYear'));
            Integer fiscalQuarter = integerValue(result.get('fiscalQuarter'));
            DealerOpportunityController.ChartPoint point = new DealerOpportunityController.ChartPoint();
            point.label = 'FY' + fiscalYear + ' Q' + fiscalQuarter;
            point.sortKey = (fiscalYear * 10) + fiscalQuarter;
            point.value = decimalValue(result.get('amountTotal'));
            points.add(point);
        }
        points.sort(new ChartPointComparator());
        return points;
    }

    private static List<DealerOpportunityController.ChartPoint> buildBusinessUnitChart(List<Opportunity> opportunities) {
        Map<String, Decimal> amountByUnit = new Map<String, Decimal>();
        for (Opportunity opportunityRecord : opportunities) {
            Decimal amount = opportunityRecord.Amount == null ? 0 : opportunityRecord.Amount;
            String businessUnits = opportunityRecord.HCBusinessUnit__c;
            List<String> unitNames = String.isBlank(businessUnits)
                ? new List<String>{ 'Unspecified' }
                : businessUnits.split(';');
            for (String unitName : unitNames) {
                String label = String.isBlank(unitName) ? 'Unspecified' : unitName.trim();
                Decimal currentAmount = amountByUnit.containsKey(label) ? amountByUnit.get(label) : 0;
                amountByUnit.put(label, currentAmount + amount);
            }
        }

        List<DealerOpportunityController.ChartPoint> points = new List<DealerOpportunityController.ChartPoint>();
        for (String label : amountByUnit.keySet()) {
            DealerOpportunityController.ChartPoint point = new DealerOpportunityController.ChartPoint();
            point.label = label;
            point.value = amountByUnit.get(label);
            point.sortKey = point.value == null ? 0 : point.value.intValue();
            points.add(point);
        }
        points.sort(new ChartPointComparator());
        List<DealerOpportunityController.ChartPoint> topPoints = new List<DealerOpportunityController.ChartPoint>();
        for (Integer index = points.size() - 1; index >= 0 && topPoints.size() < 6; index--) {
            topPoints.add(points[index]);
        }
        return topPoints;
    }

    private static List<DealerOpportunityController.OpportunityRow> toRows(List<Opportunity> opportunities) {
        List<DealerOpportunityController.OpportunityRow> rows = new List<DealerOpportunityController.OpportunityRow>();
        for (Opportunity opportunityRecord : opportunities) {
            DealerOpportunityController.OpportunityRow row = new DealerOpportunityController.OpportunityRow();
            row.opportunityId = opportunityRecord.Id;
            row.name = opportunityRecord.Name;
            row.endCustomerName = opportunityRecord.EndCustomerName__c;
            row.dealerAccountName = opportunityRecord.DealerAccountName__c;
            row.stageName = opportunityRecord.StageName;
            row.amount = opportunityRecord.Amount;
            row.currencyCode = opportunityRecord.CurrencyIsoCode;
            row.closeDate = opportunityRecord.CloseDate;
            row.createdDate = opportunityRecord.CreatedDate == null
                ? null
                : opportunityRecord.CreatedDate.date();
            row.expectedShipDate = opportunityRecord.Expected_Ship_Date__c;
            row.country = opportunityRecord.Country__c;
            rows.add(row);
        }
        return rows;
    }

    private static DealerOpportunitySelector.OpportunityFilter parseFilter(String filterJson) {
        DealerOpportunitySelector.OpportunityFilter filter = new DealerOpportunitySelector.OpportunityFilter();
        if (String.isBlank(filterJson)) {
            filter.pageNumber = 1;
            filter.pageSize = DealerOpportunitySelector.DEFAULT_PAGE_SIZE;
            return filter;
        }

        FilterRequest request = (FilterRequest) JSON.deserialize(filterJson, FilterRequest.class);
        filter.search = request.search;
        filter.stageName = request.stageName;
        filter.pastDueOnly = request.pastDueOnly;
        filter.country = request.country;
        filter.amountMin = request.amountMin;
        filter.amountMax = request.amountMax;
        filter.closeDateFrom = parseOptionalDate(request.closeDateFrom);
        filter.closeDateTo = parseOptionalDate(request.closeDateTo);
        filter.shipDateFrom = parseOptionalDate(request.shipDateFrom);
        filter.shipDateTo = parseOptionalDate(request.shipDateTo);
        filter.sortField = request.sortField;
        filter.sortDirection = request.sortDirection;
        filter.pageNumber = request.pageNumber;
        filter.pageSize = request.pageSize;
        return filter;
    }

    private static CreateRequest parseCreateRequest(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new DealerOpportunityException('Enter the opportunity details.');
        }
        return (CreateRequest) JSON.deserialize(requestJson, CreateRequest.class);
    }

    private static void validateCreateRequest(CreateRequest request) {
        requireText(request.name, 'Opportunity Name');
        requireText(request.endCustomerName, 'End Customer Name');
        requireText(request.stageName, 'Stage');
        if (!DealerOpportunitySelector.CREATE_STAGES.contains(request.stageName)) {
            throw new DealerOpportunityException('Select a stage available on the Dealer opportunity.');
        }
        requireText(request.description, 'Description');
        requireText(request.country, 'Country');
        requireText(request.closeDate, 'Close Date');
        requireText(request.expectedShipDate, 'Expected Ship Date');
        requireText(request.installationDate, 'Expected Installation Date');
        if (request.amount == null || request.amount < 0) {
            throw new DealerOpportunityException('Amount is required.');
        }
        parseRequiredDate(request.closeDate, 'Close Date');
        parseRequiredDate(request.expectedShipDate, 'Expected Ship Date');
        parseRequiredDate(request.installationDate, 'Expected Installation Date');
    }

    private static Id resolveDealerAccountId(String requestedAccountId) {
        User currentUser = [
            SELECT UserType, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
        if (currentUser.UserType == 'PowerPartner') {
            if (currentUser.Contact == null || currentUser.Contact.AccountId == null) {
                throw new DealerOpportunityException('Your user is not linked to a dealer account.');
            }
            return currentUser.Contact.AccountId;
        }
        if (String.isBlank(requestedAccountId)) {
            throw new DealerOpportunityException('Select a dealer account.');
        }
        try {
            return Id.valueOf(requestedAccountId);
        } catch (Exception exceptionValue) {
            throw new DealerOpportunityException('Select a valid dealer account.');
        }
    }

    private static Id dealerRecordTypeId() {
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(DealerOpportunitySelector.RECORD_TYPE_NAME);
        if (recordTypeInfo == null) {
            throw new DealerOpportunityException('The Dealer opportunity record type is not available.');
        }
        return recordTypeInfo.getRecordTypeId();
    }

    private static String normalizeBusinessUnits(String rawValue) {
        if (String.isBlank(rawValue)) {
            return null;
        }

        Set<String> allowedValues = new Set<String>();
        for (Schema.PicklistEntry entry : Opportunity.HCBusinessUnit__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                allowedValues.add(entry.getValue());
            }
        }

        List<String> selectedValues = new List<String>();
        for (String unitName : rawValue.split(';')) {
            String value = unitName == null ? null : unitName.trim();
            if (String.isBlank(value)) {
                continue;
            }
            if (!allowedValues.contains(value)) {
                throw new DealerOpportunityException('Select a valid Business Unit.');
            }
            if (!selectedValues.contains(value)) {
                selectedValues.add(value);
            }
        }
        return selectedValues.isEmpty() ? null : String.join(selectedValues, ';');
    }

    private static List<DealerOpportunityController.CurrencyOption> businessUnitOptions() {
        List<DealerOpportunityController.CurrencyOption> options =
            new List<DealerOpportunityController.CurrencyOption>();
        for (Schema.PicklistEntry entry : Opportunity.HCBusinessUnit__c.getDescribe().getPicklistValues()) {
            if (!entry.isActive()) {
                continue;
            }
            DealerOpportunityController.CurrencyOption option = new DealerOpportunityController.CurrencyOption();
            option.label = entry.getLabel();
            option.value = entry.getValue();
            options.add(option);
        }
        return options;
    }

    private static List<DealerOpportunityController.CurrencyOption> activeCurrencies() {
        List<DealerOpportunityController.CurrencyOption> options =
            new List<DealerOpportunityController.CurrencyOption>();
        try {
            for (CurrencyType currencyType : [
                SELECT IsoCode
                FROM CurrencyType
                WHERE IsActive = true
                ORDER BY IsoCode
            ]) {
                DealerOpportunityController.CurrencyOption option = new DealerOpportunityController.CurrencyOption();
                option.value = currencyType.IsoCode;
                option.label = currencyType.IsoCode;
                options.add(option);
            }
        } catch (Exception exceptionValue) {
            options.clear();
        }
        if (options.isEmpty()) {
            DealerOpportunityController.CurrencyOption usd = new DealerOpportunityController.CurrencyOption();
            usd.value = DEFAULT_CURRENCY;
            usd.label = DEFAULT_CURRENCY;
            options.add(usd);
        }
        return options;
    }

    private static DealerOpportunityController.StageMetric stageMetric(
        String stageName,
        Integer stageCount,
        Decimal stageAmount
    ) {
        DealerOpportunityController.StageMetric metric = new DealerOpportunityController.StageMetric();
        metric.stageName = stageName;
        metric.recordCount = stageCount;
        metric.amount = stageAmount;
        return metric;
    }

    private static void requireText(String value, String label) {
        if (String.isBlank(value)) {
            throw new DealerOpportunityException(label + ' is required.');
        }
    }

    private static Date parseRequiredDate(String value, String label) {
        try {
            return Date.valueOf(value);
        } catch (Exception exceptionValue) {
            throw new DealerOpportunityException(label + ' must be a valid date.');
        }
    }

    private static Date parseOptionalDate(String value) {
        return String.isBlank(value) ? null : Date.valueOf(value);
    }

    private static Integer integerValue(Object value) {
        if (value == null) {
            return 0;
        }
        if (value instanceof Integer) {
            return (Integer) value;
        }
        if (value instanceof Long) {
            return ((Long) value).intValue();
        }
        if (value instanceof Decimal) {
            return ((Decimal) value).intValue();
        }
        return Integer.valueOf(String.valueOf(value));
    }

    private static Decimal decimalValue(Object value) {
        return value == null ? 0 : (Decimal) value;
    }

    private class FilterRequest {
        public String search;
        public String stageName;
        public Boolean pastDueOnly;
        public String country;
        public Decimal amountMin;
        public Decimal amountMax;
        public String closeDateFrom;
        public String closeDateTo;
        public String shipDateFrom;
        public String shipDateTo;
        public String sortField;
        public String sortDirection;
        public Integer pageNumber;
        public Integer pageSize;
    }

    private class CreateRequest {
        public String name;
        public String stageName;
        public String endCustomerName;
        public String description;
        public String country;
        public String businessUnits;
        public Decimal amount;
        public String currencyCode;
        public String closeDate;
        public String expectedShipDate;
        public String installationDate;
        public String accountId;
    }

    public class ChartPointComparator implements Comparator<DealerOpportunityController.ChartPoint> {
        public Integer compare(
            DealerOpportunityController.ChartPoint leftPoint,
            DealerOpportunityController.ChartPoint rightPoint
        ) {
            Integer leftKey = leftPoint.sortKey == null ? 0 : leftPoint.sortKey;
            Integer rightKey = rightPoint.sortKey == null ? 0 : rightPoint.sortKey;
            if (leftKey == rightKey) {
                return 0;
            }
            return leftKey < rightKey ? -1 : 1;
        }
    }
}