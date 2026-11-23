/**
* @author PWC Developer
* @date 2026/11/02
*
* @group Dealer Portal
*
* @description
* GC-3603 Dealer Portal R1 - Builds the home page, My Opportunities workspace, and dealer opportunity
* creation. Record access stays in user mode. Owner assignment is delegated to the share service.
*/
public with sharing class DealerOpportunityService {

    private static final String DEFAULT_CURRENCY = 'USD';
    private static final String DEFAULT_CONFIDENCE = 'Pipeline';

    /** @description GC-3603 Dealer Portal R1 - Home page metrics, charts, recent opportunities, and past-due opportunities. */
    public static DealerOpportunityController.HomeResponse getHome() {
        DealerOpportunityController.HomeResponse response = new DealerOpportunityController.HomeResponse();
        response.summary = summary();
        response.stageChart = new List<DealerOpportunityController.StageMetric>();
        for (DealerOpportunityController.StageMetric metric : response.summary.stages) {
            if (DealerOpportunitySelector.OPEN_STAGES.contains(metric.stageName)) {
                response.stageChart.add(metric);
            }
        }
        response.recentOpportunities = rows(DealerOpportunitySelector.selectRecent());
        response.pastDueOpportunities = rows(
            DealerOpportunitySelector.selectPastDue(DealerOpportunitySelector.PAST_DUE_LIMIT)
        );
        response.quarterChart = new List<DealerOpportunityController.ChartPoint>();
        for (AggregateResult result : DealerOpportunitySelector.selectQuarterSummaries()) {
            Integer fiscalYear = Integer.valueOf(String.valueOf(result.get('fiscalYear')));
            Integer fiscalQuarter = Integer.valueOf(String.valueOf(result.get('fiscalQuarter')));
            Decimal amountTotal = (Decimal) result.get('amountTotal');
            DealerOpportunityController.ChartPoint point = new DealerOpportunityController.ChartPoint();
            point.label = 'FY' + fiscalYear + ' Q' + fiscalQuarter;
            point.value = amountTotal == null ? 0 : amountTotal;
            point.sortKey = (fiscalYear * 10) + fiscalQuarter;
            response.quarterChart.add(point);
        }
        Map<String, Decimal> amountByUnit = new Map<String, Decimal>();
        for (Opportunity opportunityRecord : DealerOpportunitySelector.selectOpenPipeline()) {
            Decimal amount = opportunityRecord.Amount == null ? 0 : opportunityRecord.Amount;
            List<String> unitNames = String.isBlank(opportunityRecord.HCBusinessUnit__c)
                ? new List<String>{ 'Unspecified' }
                : opportunityRecord.HCBusinessUnit__c.split(';');
            for (String unitName : unitNames) {
                String label = String.isBlank(unitName) ? 'Unspecified' : unitName.trim();
                amountByUnit.put(label, (amountByUnit.containsKey(label) ? amountByUnit.get(label) : 0) + amount);
            }
        }
        List<DealerOpportunityController.ChartPoint> unitPoints = new List<DealerOpportunityController.ChartPoint>();
        for (String label : amountByUnit.keySet()) {
            Decimal amount = amountByUnit.get(label);
            DealerOpportunityController.ChartPoint point = new DealerOpportunityController.ChartPoint();
            point.label = label;
            point.value = amount;
            point.sortKey = amount.intValue();
            Integer insertAt = unitPoints.size();
            while (insertAt > 0 && unitPoints[insertAt - 1].sortKey > point.sortKey) {
                insertAt--;
            }
            if (insertAt == unitPoints.size()) {
                unitPoints.add(point);
            } else {
                unitPoints.add(insertAt, point);
            }
        }
        response.businessUnitChart = new List<DealerOpportunityController.ChartPoint>();
        for (Integer index = unitPoints.size() - 1; index >= 0 && response.businessUnitChart.size() < 6; index--) {
            response.businessUnitChart.add(unitPoints[index]);
        }
        return response;
    }

    /** @description GC-3603 Dealer Portal R1 - Workspace summary and one filtered page of opportunities. */
    public static DealerOpportunityController.WorkspaceResponse getWorkspace(String filterJson) {
        DealerOpportunitySelector.OpportunityFilter filter = new DealerOpportunitySelector.OpportunityFilter();
        if (String.isBlank(filterJson)) {
            filter.pageNumber = 1;
            filter.pageSize = DealerOpportunitySelector.DEFAULT_PAGE_SIZE;
        } else {
            FilterRequest request = (FilterRequest) JSON.deserialize(filterJson, FilterRequest.class);
            filter.search = request.search;
            filter.stageName = request.stageName;
            filter.pastDueOnly = request.pastDueOnly;
            filter.country = request.country;
            filter.amountMin = request.amountMin;
            filter.amountMax = request.amountMax;
            filter.closeDateFrom = String.isBlank(request.closeDateFrom) ? null : Date.valueOf(request.closeDateFrom);
            filter.closeDateTo = String.isBlank(request.closeDateTo) ? null : Date.valueOf(request.closeDateTo);
            filter.shipDateFrom = String.isBlank(request.shipDateFrom) ? null : Date.valueOf(request.shipDateFrom);
            filter.shipDateTo = String.isBlank(request.shipDateTo) ? null : Date.valueOf(request.shipDateTo);
            filter.sortField = request.sortField;
            filter.sortDirection = request.sortDirection;
            filter.pageNumber = request.pageNumber;
            filter.pageSize = request.pageSize;
        }
        DealerOpportunityController.WorkspaceResponse response = new DealerOpportunityController.WorkspaceResponse();
        response.summary = summary();
        response.totalCount = DealerOpportunitySelector.countByFilter(filter);
        response.opportunities = rows(DealerOpportunitySelector.selectByFilter(filter));
        response.pageNumber = filter.pageNumber == null || filter.pageNumber < 1 ? 1 : filter.pageNumber;
        response.pageSize = filter.pageSize == null
            ? DealerOpportunitySelector.DEFAULT_PAGE_SIZE
            : Math.min(filter.pageSize, DealerOpportunitySelector.MAX_PAGE_SIZE);
        return response;
    }

    /** @description GC-3603 Dealer Portal R1 - Defaults shown on the create form. */
    public static DealerOpportunityController.CreateContext getCreateContext() {
        DealerOpportunityController.CreateContext context = new DealerOpportunityController.CreateContext();
        context.defaultCurrency = DEFAULT_CURRENCY;
        context.currencies = new List<DealerOpportunityController.CurrencyOption>();
        try {
            for (CurrencyType currencyType : [
                SELECT IsoCode FROM CurrencyType WHERE IsActive = true ORDER BY IsoCode
            ]) {
                DealerOpportunityController.CurrencyOption option = new DealerOpportunityController.CurrencyOption();
                option.label = currencyType.IsoCode;
                option.value = currencyType.IsoCode;
                context.currencies.add(option);
            }
        } catch (Exception exceptionValue) {
            context.currencies.clear();
        }
        if (context.currencies.isEmpty()) {
            DealerOpportunityController.CurrencyOption option = new DealerOpportunityController.CurrencyOption();
            option.label = DEFAULT_CURRENCY;
            option.value = DEFAULT_CURRENCY;
            context.currencies.add(option);
        }
        context.businessUnits = new List<DealerOpportunityController.CurrencyOption>();
        for (Schema.PicklistEntry entry : Opportunity.HCBusinessUnit__c.getDescribe().getPicklistValues()) {
            if (entry.isActive()) {
                DealerOpportunityController.CurrencyOption option = new DealerOpportunityController.CurrencyOption();
                option.label = entry.getLabel();
                option.value = entry.getValue();
                context.businessUnits.add(option);
            }
        }
        context.stages = new List<String>(DealerOpportunitySelector.CREATE_STAGES);
        Schema.RecordTypeInfo recordTypeInfo = Schema.SObjectType.Opportunity
            .getRecordTypeInfosByDeveloperName()
            .get(DealerOpportunitySelector.RECORD_TYPE_NAME);
        if (recordTypeInfo == null) {
            throw new DealerOpportunityException('The Dealer opportunity record type is not available.');
        }
        context.recordTypeId = recordTypeInfo.getRecordTypeId();
        User currentUser = portalUser();
        context.partnerUser = currentUser.UserType == 'PowerPartner';
        if (context.partnerUser && currentUser.Contact != null) {
            context.dealerAccountId = currentUser.Contact.AccountId;
            context.dealerAccountName = DealerOpportunityShareService.selectAccountName(currentUser.Contact.AccountId);
        }
        return context;
    }

    /** @description GC-3603 Dealer Portal R1 - Creates a Dealer opportunity in Evaluation and USD, then assigns the STERIS Dealer Manager as owner. */
    public static Id createOpportunity(String requestJson) {
        if (String.isBlank(requestJson)) {
            throw new DealerOpportunityException('Enter the opportunity details.');
        }
        CreateRequest request = (CreateRequest) JSON.deserialize(requestJson, CreateRequest.class);
        List<String> labels = new List<String>{
            'Opportunity Name', 'End Customer Name', 'Stage', 'Description', 'Country'
        };
        List<String> values = new List<String>{
            request.name, request.endCustomerName, request.stageName, request.description, request.country
        };
        for (Integer index = 0; index < labels.size(); index++) {
            if (String.isBlank(values[index])) {
                throw new DealerOpportunityException(labels[index] + ' is required.');
            }
        }
        if (!DealerOpportunitySelector.CREATE_STAGES.contains(request.stageName)) {
            throw new DealerOpportunityException('Select a stage available on the Dealer opportunity.');
        }
        if (request.amount == null || request.amount < 0) {
            throw new DealerOpportunityException('Amount is required.');
        }
        List<String> dateLabels = new List<String>{
            'Close Date', 'Expected Ship Date', 'Expected Installation Date'
        };
        List<String> dateValues = new List<String>{
            request.closeDate, request.expectedShipDate, request.installationDate
        };
        List<Date> parsedDates = new List<Date>();
        for (Integer index = 0; index < dateLabels.size(); index++) {
            if (String.isBlank(dateValues[index])) {
                throw new DealerOpportunityException(dateLabels[index] + ' is required.');
            }
            try {
                parsedDates.add(Date.valueOf(dateValues[index]));
            } catch (Exception exceptionValue) {
                throw new DealerOpportunityException(dateLabels[index] + ' must be a valid date.');
            }
        }
        User currentUser = portalUser();
        Id dealerAccountId;
        if (currentUser.UserType == 'PowerPartner') {
            if (currentUser.Contact == null || currentUser.Contact.AccountId == null) {
                throw new DealerOpportunityException('Your user is not linked to a dealer account.');
            }
            dealerAccountId = currentUser.Contact.AccountId;
        } else if (String.isBlank(request.accountId)) {
            throw new DealerOpportunityException('Select a dealer account.');
        } else {
            try {
                dealerAccountId = Id.valueOf(request.accountId);
            } catch (Exception exceptionValue) {
                throw new DealerOpportunityException('Select a valid dealer account.');
            }
        }
        String dealerAccountName = DealerOpportunityShareService.selectAccountName(dealerAccountId);
        if (String.isBlank(dealerAccountName)) {
            throw new DealerOpportunityException('Select a valid dealer account.');
        }
        String businessUnits = null;
        if (String.isNotBlank(request.businessUnits)) {
            Set<String> allowedValues = new Set<String>();
            for (Schema.PicklistEntry entry : Opportunity.HCBusinessUnit__c.getDescribe().getPicklistValues()) {
                if (entry.isActive()) {
                    allowedValues.add(entry.getValue());
                }
            }
            List<String> selectedValues = new List<String>();
            for (String unitName : request.businessUnits.split(';')) {
                String value = unitName.trim();
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
            businessUnits = selectedValues.isEmpty() ? null : String.join(selectedValues, ';');
        }
        Opportunity opportunityRecord = new Opportunity(
            RecordTypeId = Schema.SObjectType.Opportunity.getRecordTypeInfosByDeveloperName()
                .get(DealerOpportunitySelector.RECORD_TYPE_NAME)
                .getRecordTypeId(),
            Name = request.name.trim(),
            AccountId = dealerAccountId,
            EndCustomerName__c = request.endCustomerName.trim(),
            Description = request.description.trim(),
            Country__c = request.country.trim(),
            HCBusinessUnit__c = businessUnits,
            Amount = request.amount,
            StageName = request.stageName,
            ForecastConfidenceLevel__c = DEFAULT_CONFIDENCE,
            CloseDate = parsedDates[0],
            Expected_Order_Date__c = parsedDates[0],
            Expected_Ship_Date__c = parsedDates[1],
            ExpectedInstallationDate__c = parsedDates[2],
            DealerSubmitter__c = UserInfo.getUserId(),
            CurrencyIsoCode = String.isBlank(request.currencyCode) ? DEFAULT_CURRENCY : request.currencyCode
        );
        insert opportunityRecord;
        DealerOpportunityShareService.assignOwnerAndShare(opportunityRecord.Id, UserInfo.getUserId());
        return opportunityRecord.Id;
    }

    /** @description GC-3603 Dealer Portal R1 - Completes a Dealer opportunity created from the standard layout form. */
    public static void finalizeCreatedOpportunity(Id opportunityId) {
        if (opportunityId == null) {
            throw new DealerOpportunityException('The opportunity was not created.');
        }
        List<Opportunity> opportunities = [
            SELECT Id, DealerSubmitter__c, ForecastConfidenceLevel__c
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
        if (changed) {
            update opportunityRecord;
        }
        DealerOpportunityShareService.assignOwnerAndShare(opportunityRecord.Id, UserInfo.getUserId());
    }

    private static DealerOpportunityController.Summary summary() {
        Map<String, AggregateResult> resultByStage = new Map<String, AggregateResult>();
        Integer totalCount = 0;
        for (AggregateResult stageResult : DealerOpportunitySelector.selectStageSummaries()) {
            resultByStage.put((String) stageResult.get('stageName'), stageResult);
            totalCount += Integer.valueOf(String.valueOf(stageResult.get('recordCount')));
        }
        DealerOpportunityController.Summary result = new DealerOpportunityController.Summary();
        result.openCount = 0;
        result.openPipelineValue = 0;
        result.closedWonCount = 0;
        result.closedWonValue = 0;
        result.totalCount = totalCount;
        result.stages = new List<DealerOpportunityController.StageMetric>();
        for (String stageName : DealerOpportunitySelector.WORKSPACE_STAGES) {
            AggregateResult stageResult = resultByStage.get(stageName);
            Integer stageCount = 0;
            Decimal stageAmount = 0;
            if (stageResult != null) {
                stageCount = Integer.valueOf(String.valueOf(stageResult.get('recordCount')));
                Decimal amountTotal = (Decimal) stageResult.get('amountTotal');
                stageAmount = amountTotal == null ? 0 : amountTotal;
            }
            DealerOpportunityController.StageMetric metric = new DealerOpportunityController.StageMetric();
            metric.stageName = stageName;
            metric.recordCount = stageCount;
            metric.amount = stageAmount;
            result.stages.add(metric);
            if (DealerOpportunitySelector.OPEN_STAGES.contains(stageName)) {
                result.openCount += stageCount;
                result.openPipelineValue += stageAmount;
            }
            if (stageName == DealerOpportunitySelector.CLOSED_WON_STAGE) {
                result.closedWonCount = stageCount;
                result.closedWonValue = stageAmount;
            }
        }
        return result;
    }

    private static List<DealerOpportunityController.OpportunityRow> rows(List<Opportunity> opportunities) {
        List<DealerOpportunityController.OpportunityRow> result = new List<DealerOpportunityController.OpportunityRow>();
        for (Opportunity opportunityRecord : opportunities) {
            DealerOpportunityController.OpportunityRow row = new DealerOpportunityController.OpportunityRow();
            row.opportunityId = opportunityRecord.Id;
            row.name = opportunityRecord.Name;
            row.endCustomerName = opportunityRecord.EndCustomerName__c;
            row.dealerAccountName = opportunityRecord.Account.Name;
            row.stageName = opportunityRecord.StageName;
            row.amount = opportunityRecord.Amount;
            row.currencyCode = opportunityRecord.CurrencyIsoCode;
            row.closeDate = opportunityRecord.CloseDate;
            row.createdDate = opportunityRecord.CreatedDate.date();
            row.expectedShipDate = opportunityRecord.Expected_Ship_Date__c;
            row.country = opportunityRecord.Country__c;
            result.add(row);
        }
        return result;
    }

    private static User portalUser() {
        return [
            SELECT UserType, Contact.AccountId
            FROM User
            WHERE Id = :UserInfo.getUserId()
            WITH USER_MODE
            LIMIT 1
        ];
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
}