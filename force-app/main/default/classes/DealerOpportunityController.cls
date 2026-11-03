/**
 * @author PWC Developer
 * @date 2026/11/02
 *
 * @group Dealer Portal
 *
 * @description
 * Dealer Portal R1 - LWC controller for the dealer home page, My Opportunities workspace,
 * and opportunity creation.
 */
public with sharing class DealerOpportunityController {

    public static final String SCENARIO = 'Dealer Portal';
    public static final String LOGGER_TAG = 'DealerOpportunity';

    /**
     * @description
     * Dealer Portal R1 - Pipeline totals shown on Home and My Opportunities.
     */
    public class Summary {
        @AuraEnabled public Integer openCount;
        @AuraEnabled public Decimal openPipelineValue;
        @AuraEnabled public Integer closedWonCount;
        @AuraEnabled public Decimal closedWonValue;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public List<StageMetric> stages;
    }

    /**
     * @description
     * Dealer Portal R1 - One stage tab or stage chart column.
     */
    public class StageMetric {
        @AuraEnabled public String stageName;
        @AuraEnabled public Integer recordCount;
        @AuraEnabled public Decimal amount;
    }

    /**
     * @description
     * Dealer Portal R1 - One chart bar.
     */
    public class ChartPoint {
        @AuraEnabled public String label;
        @AuraEnabled public Decimal value;
        @AuraEnabled public Integer sortKey;
    }

    /**
     * @description
     * Dealer Portal R1 - One opportunity row in a list or table.
     */
    public class OpportunityRow {
        @AuraEnabled public Id opportunityId;
        @AuraEnabled public String name;
        @AuraEnabled public String endCustomerName;
        @AuraEnabled public String dealerAccountName;
        @AuraEnabled public String stageName;
        @AuraEnabled public Decimal amount;
        @AuraEnabled public String currencyCode;
        @AuraEnabled public Date closeDate;
        @AuraEnabled public Date createdDate;
        @AuraEnabled public Date expectedShipDate;
        @AuraEnabled public String country;
    }

    /**
     * @description
     * Dealer Portal R1 - Home page payload.
     */
    public class HomeResponse {
        @AuraEnabled public Summary summary;
        @AuraEnabled public List<OpportunityRow> recentOpportunities;
        @AuraEnabled public List<OpportunityRow> pastDueOpportunities;
        @AuraEnabled public List<StageMetric> stageChart;
        @AuraEnabled public List<ChartPoint> quarterChart;
        @AuraEnabled public List<ChartPoint> businessUnitChart;
    }

    /**
     * @description
     * Dealer Portal R1 - My Opportunities payload.
     */
    public class WorkspaceResponse {
        @AuraEnabled public Summary summary;
        @AuraEnabled public List<OpportunityRow> opportunities;
        @AuraEnabled public Integer totalCount;
        @AuraEnabled public Integer pageNumber;
        @AuraEnabled public Integer pageSize;
    }

    /**
     * @description
     * Dealer Portal R1 - Create form defaults.
     */
    public class CreateContext {
        @AuraEnabled public Boolean partnerUser;
        @AuraEnabled public Id dealerAccountId;
        @AuraEnabled public String dealerAccountName;
        @AuraEnabled public String defaultCurrency;
        @AuraEnabled public List<CurrencyOption> currencies;
        @AuraEnabled public List<CurrencyOption> businessUnits;
        @AuraEnabled public List<String> stages;
        @AuraEnabled public Id recordTypeId;
    }

    /**
     * @description
     * Dealer Portal R1 - One active currency.
     */
    public class CurrencyOption {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
    }

    /**
     * @description
     * Dealer Portal R1 - Loads the dealer home page.
     *
     * @return Metrics, charts, recent opportunities, and past-due opportunities.
     */
    @AuraEnabled
    public static HomeResponse getHome() {
        try {
            return DealerOpportunityService.getHome();
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to load the dealer home page.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Dealer Portal R1 - Loads one filtered page of My Opportunities.
     *
     * @param filterJson Search, stage, date, amount, and paging values.
     * @return Summary tiles and the current page.
     */
    @AuraEnabled
    public static WorkspaceResponse getWorkspace(String filterJson) {
        try {
            return DealerOpportunityService.getWorkspace(filterJson);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to load opportunities.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Dealer Portal R1 - Loads create-form defaults for the signed-in user.
     *
     * @return Currency choices and the dealer account for a partner user.
     */
    @AuraEnabled
    public static CreateContext getCreateContext() {
        try {
            return DealerOpportunityService.getCreateContext();
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to open opportunity creation.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Dealer Portal R1 - Creates a Dealer opportunity from the portal form.
     *
     * @param requestJson Required opportunity fields.
     * @return New opportunity Id.
     */
    @AuraEnabled
    public static Id createOpportunity(String requestJson) {
        try {
            return DealerOpportunityService.createOpportunity(requestJson);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to create the opportunity.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description
     * Dealer Portal R1 - Stamps dealer fields and assigns the Dealer Manager after the
     * standard Opportunity form creates the record.
     *
     * @param opportunityId Opportunity created by the standard form.
     */
    @AuraEnabled
    public static void finalizeCreatedOpportunity(Id opportunityId) {
        try {
            DealerOpportunityService.finalizeCreatedOpportunity(opportunityId);
        } catch (Exception exceptionValue) {
            throw buildHandledException('Unable to finish the opportunity.', exceptionValue);
        } finally {
            Logger.saveLog();
        }
    }

    private static AuraHandledException buildHandledException(String message, Exception exceptionValue) {
        Logger.setScenario(SCENARIO);
        Logger.error(message + ' ' + exceptionValue.getMessage()).addTag(LOGGER_TAG);

        if (exceptionValue instanceof AuraHandledException) {
            return (AuraHandledException) exceptionValue;
        }

        String detail = String.isBlank(exceptionValue.getMessage()) ? message : exceptionValue.getMessage();
        if (exceptionValue instanceof DealerOpportunityException || exceptionValue instanceof DmlException) {
            AuraHandledException validationException = new AuraHandledException(detail);
            validationException.setMessage(detail);
            return validationException;
        }

        AuraHandledException handledException = new AuraHandledException(detail);
        handledException.setMessage(detail);
        return handledException;
    }
}