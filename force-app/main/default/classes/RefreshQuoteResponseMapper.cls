/**
 * @author PWC Developer
 * @date 2026/07/08
 *
 * @group Generate Quote
 *
 * @description Maps Refresh Quote integration JSON to Generate Quote UI wrappers.
 */
public with sharing class RefreshQuoteResponseMapper {
    /**
     * @description Parses integration JSON into QuoteWrapper rows for the LWC datatable.
     * @param responseBody JSON array of quote rows.
     * @return Quote wrapper rows for UI rendering.
     */
    public static List<GenerateQuoteController.QuoteWrapper> parse(String responseBody) {
        if (String.isBlank(responseBody)) {
            return new List<GenerateQuoteController.QuoteWrapper>();
        }

        List<ApiQuoteWrapper> apiQuotes = (List<ApiQuoteWrapper>) JSON.deserialize(
            responseBody,
            List<ApiQuoteWrapper>.class
        );

        List<GenerateQuoteController.QuoteWrapper> quoteWrappers =
            new List<GenerateQuoteController.QuoteWrapper>();

        if (apiQuotes == null) {
            return quoteWrappers;
        }

        for (ApiQuoteWrapper apiQuote : apiQuotes) {
            quoteWrappers.add(mapQuote(apiQuote));
        }

        return quoteWrappers;
    }

    private static GenerateQuoteController.QuoteWrapper mapQuote(ApiQuoteWrapper apiQuote) {
        GenerateQuoteController.QuoteWrapper quoteWrapper = new GenerateQuoteController.QuoteWrapper();
        quoteWrapper.id = parseId(apiQuote.id);
        quoteWrapper.quoteNumber = apiQuote.quoteNumber;
        quoteWrapper.salesConnectionViewQuoteNumber = apiQuote.quoteNumber;
        quoteWrapper.salesConnectionQuoteId = apiQuote.salesConnectionQuoteId;
        quoteWrapper.quoteName = apiQuote.quoteName;
        quoteWrapper.expirationDate = parseDate(apiQuote.expirationDate);
        quoteWrapper.salesConnectionUrl = apiQuote.salesConnectionUrl;
        quoteWrapper.description = apiQuote.description;
        quoteWrapper.status = apiQuote.status;
        quoteWrapper.approvalStatus = apiQuote.approvalStatus;
        quoteWrapper.quoteTotalWithoutFreight = apiQuote.quoteTotalWithoutFreight;
        quoteWrapper.lastModifiedDate = parseDatetime(apiQuote.lastModifiedDate);
        quoteWrapper.productSubgroupSummary = mapSubgroups(apiQuote.productSubgroupSummary);
        return quoteWrapper;
    }

    private static List<GenerateQuoteController.ProductSubgroupSummaryWrapper> mapSubgroups(
        List<ApiSubgroupWrapper> apiSubgroups
    ) {
        List<GenerateQuoteController.ProductSubgroupSummaryWrapper> subgroups =
            new List<GenerateQuoteController.ProductSubgroupSummaryWrapper>();

        if (apiSubgroups == null) {
            return subgroups;
        }

        for (ApiSubgroupWrapper apiSubgroup : apiSubgroups) {
            GenerateQuoteController.ProductSubgroupSummaryWrapper subgroupWrapper =
                new GenerateQuoteController.ProductSubgroupSummaryWrapper();
            subgroupWrapper.productSubgroupDetailName = apiSubgroup.productSubgroupDetailName;
            subgroupWrapper.totalUnitPrice = apiSubgroup.totalUnitPrice;
            subgroupWrapper.quoteLines = mapQuoteLines(apiSubgroup.quoteLines);
            subgroups.add(subgroupWrapper);
        }

        return subgroups;
    }

    private static List<GenerateQuoteController.QuoteLineDetailWrapper> mapQuoteLines(
        List<ApiLineDetailWrapper> apiQuoteLines
    ) {
        List<GenerateQuoteController.QuoteLineDetailWrapper> quoteLines =
            new List<GenerateQuoteController.QuoteLineDetailWrapper>();

        if (apiQuoteLines == null) {
            return quoteLines;
        }

        for (ApiLineDetailWrapper apiQuoteLine : apiQuoteLines) {
            GenerateQuoteController.QuoteLineDetailWrapper lineWrapper =
                new GenerateQuoteController.QuoteLineDetailWrapper();
            lineWrapper.quoteLineId = apiQuoteLine.quoteLineId;
            lineWrapper.productName = apiQuoteLine.productName;
            lineWrapper.uom = apiQuoteLine.uom;
            lineWrapper.productFAMCode = apiQuoteLine.productFAMCode;
        lineWrapper.productSubgroupDetailName = apiQuoteLine.productSubgroupDetailName;
        lineWrapper.territoryId = apiQuoteLine.territoryId;
        lineWrapper.tasSalesCategory = apiQuoteLine.tasSalesCategory;
        lineWrapper.salesCategoryDescription = apiQuoteLine.salesCategoryDescription;
        lineWrapper.quantity = apiQuoteLine.quantity;
            lineWrapper.unitPrice = apiQuoteLine.unitPrice;
            lineWrapper.lineTotal = apiQuoteLine.lineTotal;
            quoteLines.add(lineWrapper);
        }

        return quoteLines;
    }

    private static Id parseId(String recordId) {
        if (String.isBlank(recordId) || recordId.startsWith('0Q0x') || recordId.startsWith('0QLx')) {
            return null;
        }

        try {
            return (Id) recordId;
        } catch (Exception exceptionValue) {
            return null;
        }
    }

    private static Date parseDate(String dateValue) {
        if (String.isBlank(dateValue)) {
            return null;
        }

        try {
            return Date.valueOf(dateValue);
        } catch (Exception exceptionValue) {
            return null;
        }
    }

    private static Datetime parseDatetime(String datetimeValue) {
        if (String.isBlank(datetimeValue) || datetimeValue.contains('...')) {
            return null;
        }

        try {
            return (Datetime) JSON.deserialize('"' + datetimeValue + '"', Datetime.class);
        } catch (Exception exceptionValue) {
            return null;
        }
    }

    public class ApiQuoteWrapper {
        public String id;
        public String quoteNumber;
        public String salesConnectionQuoteId;
        public String quoteName;
        public String expirationDate;
        public String salesConnectionUrl;
        public String description;
        public String status;
        public String approvalStatus;
        public Decimal quoteTotalWithoutFreight;
        public String lastModifiedDate;
        public List<ApiSubgroupWrapper> productSubgroupSummary;
    }

    public class ApiSubgroupWrapper {
        public String productSubgroupDetailName;
        public Decimal totalUnitPrice;
        public List<ApiLineDetailWrapper> quoteLines;
    }

    public class ApiLineDetailWrapper {
        public String quoteLineId;
        public String productName;
        public String uom;
        public String productFAMCode;
        public String productSubgroupDetailName;
        public String territoryId;
        public String tasSalesCategory;
        public String salesCategoryDescription;
        public Decimal quantity;
        public Decimal unitPrice;
        public Decimal lineTotal;
    }
}