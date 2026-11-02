/**
 * @description GW-4117 - Evaluates Repair Center Quote Line Items against IMS Customer Preference
 *              Pre-Approval Limits by Product Line and auto-approves lines / Quote when within limit.
 */
public with sharing class RepairCenterQuotePreApprovalService {
    public static final String LOGGER_TAG = 'RepairCenterQuotePreApproval';
    public static final String SCENARIO = 'Repair Center Quote Pre-Approval';

    @TestVisible
    private static final String PREFERENCE_TYPE_PRE_APPROVAL_LIMIT = 'Pre-Approval Limit';
    @TestVisible
    private static final String PREFERENCE_RECORD_TYPE = 'IMSCustomerPreference';
@TestVisible
private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
@TestVisible
private static final String LINE_TYPE_SPECIAL_PRICING = 'Special Pricing';
@TestVisible
private static final String LINE_TYPE_CATEGORY_CODE = 'Category Code';
@TestVisible
private static final String LINE_TYPE_SERVICE_CODE = 'Service Code';
    @TestVisible
    private static final String STATUS_APPROVED = 'Approved';

    public class Request {
        @InvocableVariable(
            required=true
            label='Quote Id'
            description='Repair Center Quote to evaluate for pre-approval limits.'
        )
        public Id quoteId;
    }

    /**
     * @description Invocable entry for SubFlow_GenerateRepairCenterWOQuote after QLI create/pricing.
     * @param requests Quote Ids to evaluate.
     */
    @InvocableMethod(
        label='Evaluate Repair Center Quote Pre-Approval Limits'
        description='Compares Product Serviced QLI totals to Customer Preference Pre-Approval Limits and auto-approves when within limit.'
        category='Repair Center'
    )
    public static void evaluatePreApprovalLimits(List<Request> requests) {
        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> quoteIds = new Set<Id>();
        for (Request request : requests) {
            if (request != null && request.quoteId != null) {
                quoteIds.add(request.quoteId);
            }
        }

        if (quoteIds.isEmpty()) {
            return;
        }

        Logger.setScenario(SCENARIO);
        try {
            evaluateQuotes(quoteIds);
        } catch (Exception e) {
            // TEMP (GW-4471 Dev E2E): do not rethrow — SubFlow_GenerateRepairCenterWOQuote
            // fault path ends the interview (skips Update Parent WO / DocGen). Log and continue
            // so quote generation can finish. Pre-approval Status stamps are skipped for this run.
            // Remove once NetTotalPrice FLS is granted to the running user.
            Logger.error(
                    'RepairCenterQuotePreApprovalService.evaluatePreApprovalLimits failed: ' +
                    e.getMessage()
                )
                .addTag(LOGGER_TAG);
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static void evaluateQuotes(Set<Id> quoteIds) {
        List<Quote> quotes = QuoteService.selectForRepairCenterPreApproval(quoteIds);
        if (quotes.isEmpty()) {
            return;
        }

        Map<Id, Quote> quoteById = new Map<Id, Quote>(quotes);
        Set<Id> accountIds = new Set<Id>();
        for (Quote quoteRecord : quotes) {
            if (quoteRecord.AccountId != null) {
                accountIds.add(quoteRecord.AccountId);
            }
        }

        List<QuoteLineItem> quoteLineItems = QuoteLineItemService.selectForRepairCenterPreApproval(
            quoteIds
        );

        stampProductLinesFromPricebookProduct(quoteLineItems);

        Set<Id> parentWoliIds = new Set<Id>();
        for (QuoteLineItem qli : quoteLineItems) {
            if (qli.ParentWorkOrderLineItem__c != null) {
                parentWoliIds.add(qli.ParentWorkOrderLineItem__c);
            }
        }

        Map<Id, String> parentWoliProductLineById = new Map<Id, String>();
        if (!parentWoliIds.isEmpty()) {
            for (
                WorkOrderLineItem woli : WorkOrderLineItemsService.selectForRepairCenterPreApproval(
                    parentWoliIds
                )
            ) {
                parentWoliProductLineById.put(woli.Id, resolveProductLine(woli));
            }
        }

        Map<Id, List<QuoteLineItem>> qlisByQuoteId = new Map<Id, List<QuoteLineItem>>();
        Set<String> productLines = new Set<String>();
        for (QuoteLineItem qli : quoteLineItems) {
            if (!qlisByQuoteId.containsKey(qli.QuoteId)) {
                qlisByQuoteId.put(qli.QuoteId, new List<QuoteLineItem>());
            }
            qlisByQuoteId.get(qli.QuoteId).add(qli);

            if (
                qli.LineType__c == LINE_TYPE_PRODUCT_SERVICED &&
                String.isNotBlank(qli.ProductLine__c)
            ) {
                productLines.add(qli.ProductLine__c);
            }
        }

        Map<String, Decimal> preApprovalLimitByAccountAndProductLine = loadPreApprovalLimits(
            accountIds,
            productLines
        );

        List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();
        List<Quote> quotesToUpdate = new List<Quote>();

        for (Id quoteId : quoteById.keySet()) {
            Quote quoteRecord = quoteById.get(quoteId);
            List<QuoteLineItem> lines = qlisByQuoteId.containsKey(quoteId)
                ? qlisByQuoteId.get(quoteId)
                : new List<QuoteLineItem>();

            EvaluationResult result = evaluateQuoteLines(
                quoteRecord,
                lines,
                parentWoliProductLineById,
                preApprovalLimitByAccountAndProductLine
            );
            qlisToUpdate.addAll(result.qlisToUpdate);
            if (result.quoteToUpdate != null) {
                quotesToUpdate.add(result.quoteToUpdate);
            }
        }

        if (!qlisToUpdate.isEmpty()) {
            update qlisToUpdate;
        }
        if (!quotesToUpdate.isEmpty()) {
            update quotesToUpdate;
        }
    }

    @TestVisible
    private class EvaluationResult {
        public List<QuoteLineItem> qlisToUpdate = new List<QuoteLineItem>();
        public Quote quoteToUpdate;
    }

    @TestVisible
    private static EvaluationResult evaluateQuoteLines(
        Quote quoteRecord,
        List<QuoteLineItem> lines,
        Map<Id, String> parentWoliProductLineById,
        Map<String, Decimal> preApprovalLimitByAccountAndProductLine
    ) {
        EvaluationResult result = new EvaluationResult();
        if (lines.isEmpty()) {
            return result;
        }

        List<QuoteLineItem> productServicedLines = new List<QuoteLineItem>();
        List<QuoteLineItem> pricedChildLines = new List<QuoteLineItem>();
        for (QuoteLineItem qli : lines) {
            if (qli.LineType__c == LINE_TYPE_PRODUCT_SERVICED) {
                productServicedLines.add(qli);
            } else if (
                 qli.LineType__c == LINE_TYPE_SPECIAL_PRICING ||
    qli.LineType__c == LINE_TYPE_CATEGORY_CODE ||
    qli.LineType__c == LINE_TYPE_SERVICE_CODE
            ) {
                pricedChildLines.add(qli);
            }
        }

        if (productServicedLines.isEmpty()) {
            return result;
        }

        Set<String> processedProductLines = new Set<String>();
        Set<Id> approvedQliIds = new Set<Id>();

        for (QuoteLineItem productServiced : productServicedLines) {
            String productLine = productServiced.ProductLine__c;
            if (String.isBlank(productLine) || processedProductLines.contains(productLine)) {
                continue;
            }
            processedProductLines.add(productLine);

            Decimal preApprovalLimit = getPreApprovalLimit(
                quoteRecord.AccountId,
                productLine,
                preApprovalLimitByAccountAndProductLine
            );

            Decimal lineSum = 0;
            List<QuoteLineItem> matchingChildren = new List<QuoteLineItem>();
            for (QuoteLineItem child : pricedChildLines) {
                String parentProductLine = parentWoliProductLineById.get(
                    child.ParentWorkOrderLineItem__c
                );
                if (productLine.equals(parentProductLine)) {
                    matchingChildren.add(child);
                    lineSum += child.NetTotalPrice__c == null ? 0 : child.NetTotalPrice__c;
                }
            }

            // A missing preference stays unapproved, including a $0 service total.
            if (preApprovalLimit != null && preApprovalLimit >= lineSum) {
                for (QuoteLineItem productServicedLine : productServicedLines) {
                    if (productLine.equals(productServicedLine.ProductLine__c)) {
                        approvedQliIds.add(productServicedLine.Id);
                    }
                }
                for (QuoteLineItem child : matchingChildren) {
                    approvedQliIds.add(child.Id);
                }
            }
        }

        for (QuoteLineItem qli : lines) {
            if (approvedQliIds.contains(qli.Id) && qli.Status__c != STATUS_APPROVED) {
                result.qlisToUpdate.add(
                    new QuoteLineItem(Id = qli.Id, Status__c = STATUS_APPROVED)
                );
                qli.Status__c = STATUS_APPROVED;
            }
        }

        Boolean allProductServicedApproved = true;
        for (QuoteLineItem productServiced : productServicedLines) {
            if (productServiced.Status__c != STATUS_APPROVED) {
                allProductServicedApproved = false;
                break;
            }
        }

        if (allProductServicedApproved && quoteRecord.Status != STATUS_APPROVED) {
            result.quoteToUpdate = new Quote(Id = quoteRecord.Id, Status = STATUS_APPROVED);
        }

        return result;
    }

    @TestVisible
    private static Map<String, Decimal> loadPreApprovalLimits(
        Set<Id> accountIds,
        Set<String> productLines
    ) {
        Map<String, Decimal> limits = new Map<String, Decimal>();
        if (accountIds.isEmpty() || productLines.isEmpty()) {
            return limits;
        }

        for (
            CustomerPreference__c preference : CustomerPreferencesService.selectActivePreApprovalLimits(
                accountIds,
                productLines,
                Date.today(),
                PREFERENCE_TYPE_PRE_APPROVAL_LIMIT,
                PREFERENCE_RECORD_TYPE
            )
        ) {
            String key = buildLimitKey(preference.Account__c, preference.ProductLine__c);
            limits.put(key, toCurrency(preference));
        }
        return limits;
    }

    /**
     * @description Sets QLI.ProductLine__c from WOLI Pricebook Product.Product Line (fallback WOLI.ProductLine__c).
     *              Flow Transform cannot map related PricebookEntry fields, so this stamps after QLI create.
     */
    @TestVisible
    private static void stampProductLinesFromPricebookProduct(List<QuoteLineItem> quoteLineItems) {
        if (quoteLineItems == null || quoteLineItems.isEmpty()) {
            return;
        }

        Set<Id> woliIds = new Set<Id>();
        for (QuoteLineItem qli : quoteLineItems) {
            if (qli.WorkOrderLineItem__c != null) {
                woliIds.add(qli.WorkOrderLineItem__c);
            }
        }
        if (woliIds.isEmpty()) {
            return;
        }

        Map<Id, WorkOrderLineItem> woliById = new Map<Id, WorkOrderLineItem>(
            WorkOrderLineItemsService.selectForRepairCenterPreApproval(woliIds)
        );

        List<QuoteLineItem> qlisToStamp = new List<QuoteLineItem>();
        for (QuoteLineItem qli : quoteLineItems) {
            WorkOrderLineItem woli = woliById.get(qli.WorkOrderLineItem__c);
            String productLine = resolveProductLine(woli);
            if (String.isBlank(productLine)) {
                continue;
            }
            String existingProductLine = qli.ProductLine__c;
            qli.ProductLine__c = productLine;
            if (existingProductLine != productLine) {
                qlisToStamp.add(new QuoteLineItem(Id = qli.Id, ProductLine__c = productLine));
            }
        }

        if (!qlisToStamp.isEmpty()) {
            update qlisToStamp;
        }
    }

    private static Decimal getPreApprovalLimit(
        Id accountId,
        String productLine,
        Map<String, Decimal> preApprovalLimitByAccountAndProductLine
    ) {
        if (accountId == null || String.isBlank(productLine)) {
            return null;
        }
        String key = buildLimitKey(accountId, productLine);
        if (
            preApprovalLimitByAccountAndProductLine.containsKey(key) &&
            preApprovalLimitByAccountAndProductLine.get(key) != null
        ) {
            return preApprovalLimitByAccountAndProductLine.get(key);
        }
        return null;
    }

    private static String buildLimitKey(Id accountId, String productLine) {
        return String.valueOf(accountId) + '|' + productLine;
    }

    @TestVisible
    private static String resolveProductLine(WorkOrderLineItem woli) {
        if (woli == null) {
            return null;
        }
        if (String.isNotBlank(woli.ProductLine__c)) {
            return woli.ProductLine__c;
        }
        if (
            woli.PricebookEntry != null &&
            woli.PricebookEntry.Product2 != null &&
            String.isNotBlank(woli.PricebookEntry.Product2.ProductLine__c)
        ) {
            return woli.PricebookEntry.Product2.ProductLine__c;
        }
        return null;
    }

    @TestVisible
    private static Decimal toCurrency(CustomerPreference__c preference) {
        if (preference == null || String.isBlank(preference.PreferenceValue__c)) {
            return 0;
        }

        String rawValue = preference.PreferenceValue__c.trim();
        rawValue = rawValue.replace('$', '').replace(',', '');
        try {
            return Decimal.valueOf(rawValue);
        } catch (Exception e) {
            return 0;
        }
    }
}