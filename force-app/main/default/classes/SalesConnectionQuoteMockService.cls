/**
 * @author PWC Developer
 * @date 2026/07/07
 *
 * @group Generate Quote
 *
 * @description
 * Mock Sales Connection quote payloads used until Boomi integration is available.
 */
public with sharing class SalesConnectionQuoteMockService {
    private static final Set<String> HC_SALES_QUOTE_STATUSES = new Set<String>{
        'Open',
        'Closed',
        'Budget',
        'Draft'
    };
    public static final Integer TEMPLATE_COUNT = 6;

    public class MockQuoteLine {
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
    }

    public class PricebookEntryResolution {
        public Id pricebookEntryId;
        public Boolean exactMatch;
    }

    public class MockQuoteTemplate {
        public String salesConnectionQuoteId;
        public String quoteNumber;
        public String quoteStatus;
        public String approvalStatus;
        public String description;
        public Decimal quoteTotalWithoutFreight;
        public Datetime lastModifiedDate;
        public List<MockQuoteLine> quoteLines = new List<MockQuoteLine>();
    }

    /**
     * @description Returns a mock Sales Connection quote template.
     * @param templateIndex Rotating template index.
     * @return Mock quote template.
     */
    public static MockQuoteTemplate getTemplate(Integer templateIndex) {
        Integer normalizedIndex = templateIndex == null
            ? 0
            : Math.mod(Math.abs(templateIndex), TEMPLATE_COUNT);

        MockQuoteTemplate template;
        if (normalizedIndex == 1) {
            template = buildTemplateTwo();
        } else if (normalizedIndex == 2) {
            template = buildTemplateThree();
        } else if (normalizedIndex == 3) {
            template = buildTemplateFour();
        } else if (normalizedIndex == 4) {
            template = buildTemplateFive();
        } else if (normalizedIndex == 5) {
            template = buildTemplateSix();
        } else {
            template = buildTemplateOne();
        }

        applyMockQuoteStatus(template);
        return template;
    }

    /**
     * @description Sets mock quote status to Open for all generated quotes.
     * @param template Mock quote template being returned.
     */
    private static void applyMockQuoteStatus(MockQuoteTemplate template) {
        if (template == null) {
            return;
        }

        template.quoteStatus = 'Open';
    }

    /**
     * @description Applies mock header values to a Quote record before insert.
     * @param quoteRecord Quote being created.
     * @param template Mock Sales Connection template.
     */
    public static void applyTemplateToQuote(
        Quote quoteRecord,
        MockQuoteTemplate template
    ) {
        applyTemplateToQuote(quoteRecord, template, (Integer) null);
    }

    /**
     * @description Applies mock header values to a Quote record before insert.
     * @param quoteRecord Quote being created.
     * @param template Mock Sales Connection template.
     * @param quoteSequence Zero-based quote count on the Opportunity used to keep external ids unique.
     */
    public static void applyTemplateToQuote(
        Quote quoteRecord,
        MockQuoteTemplate template,
        Integer quoteSequence
    ) {
        if (quoteRecord == null || template == null) {
            return;
        }

        quoteRecord.Description = template.description;
        quoteRecord.Status = resolveQuoteStatus(template.quoteStatus);
        quoteRecord.Approval_Status__c = resolveApprovalStatus(template.approvalStatus);
        quoteRecord.LastModifiedDate__c = template.lastModifiedDate;
    }

    /**
     * @description Applies mock header values to a Quote record before insert.
     * @param quoteRecord Quote being created.
     * @param template Mock Sales Connection template.
     * @param opportunityId Deprecated. Retained for backward compatibility.
     * @param quoteSequence Zero-based quote count on the Opportunity used to keep external ids unique.
     */
    public static void applyTemplateToQuote(
        Quote quoteRecord,
        MockQuoteTemplate template,
        Id opportunityId,
        Integer quoteSequence
    ) {
        applyTemplateToQuote(quoteRecord, template, quoteSequence);
    }

    /**
     * @description Builds a unique Quote Number value from a mock template.
     * @param template Mock Sales Connection template.
     * @param quoteSequence Zero-based quote count on the Opportunity.
     * @return Quote Number value for QuoteNumber__c.
     */
    public static String resolveTemplateQuoteNumber(MockQuoteTemplate template, Integer quoteSequence) {
        if (template == null || String.isBlank(template.quoteNumber)) {
            return null;
        }

        return buildUniqueExternalId(template.quoteNumber, quoteSequence, 18);
    }

    /**
     * @description Builds a unique Sales Connection quote id from a mock template.
     * @param template Mock Sales Connection template.
     * @param quoteSequence Zero-based quote count on the Opportunity.
     * @return Sales Connection quote id for SalesConnectionQuoteID__c.
     */
    public static String resolveTemplateSalesConnectionQuoteId(
        MockQuoteTemplate template,
        Integer quoteSequence
    ) {
        if (template == null || String.isBlank(template.salesConnectionQuoteId)) {
            return null;
        }

        return buildUniqueExternalId(template.salesConnectionQuoteId, quoteSequence, 50);
    }

    /**
     * @description Resolves refresh payload quote number from the Quote or mock template.
     * @param quoteRecord Salesforce Quote being refreshed.
     * @param template Mock template used for fallback values.
     * @param quoteSequence Zero-based quote position in the refresh payload.
     * @return Quote number for the integration payload.
     */
    public static String resolveRefreshQuoteNumber(
        Quote quoteRecord,
        MockQuoteTemplate template,
        Integer quoteSequence
    ) {
        if (quoteRecord != null && String.isNotBlank(quoteRecord.QuoteNumber__c)) {
            return quoteRecord.QuoteNumber__c;
        }

        if (template != null && String.isNotBlank(template.quoteNumber)) {
            return buildUniqueExternalIdForQuote(template.quoteNumber, quoteRecord, quoteSequence, 18);
        }

        return GenerateQuoteService.resolveQuoteNumber(quoteRecord);
    }

    /**
     * @description Resolves refresh payload Sales Connection quote id from the Quote or mock template.
     * @param quoteRecord Salesforce Quote being refreshed.
     * @param template Mock template used for fallback values.
     * @param quoteSequence Zero-based quote position in the refresh payload.
     * @return Sales Connection quote id for the integration payload.
     */
    public static String resolveRefreshSalesConnectionQuoteId(
        Quote quoteRecord,
        MockQuoteTemplate template,
        Integer quoteSequence
    ) {
        if (quoteRecord != null && String.isNotBlank(quoteRecord.SalesConnectionQuoteID__c)) {
            return quoteRecord.SalesConnectionQuoteID__c;
        }

        if (template != null && String.isNotBlank(template.salesConnectionQuoteId)) {
            return buildUniqueExternalIdForQuote(
                template.salesConnectionQuoteId,
                quoteRecord,
                quoteSequence,
                50
            );
        }

        return GenerateQuoteService.normalizeSalesConnectionQuoteIdForStorage(
            GenerateQuoteService.resolveSalesConnectionQuoteId(quoteRecord)
        );
    }

    private static String buildUniqueExternalId(String baseValue, Integer quoteSequence, Integer maxLength) {
        if (String.isBlank(baseValue)) {
            return null;
        }

        if (quoteSequence == null || quoteSequence <= 0) {
            return baseValue.left(maxLength);
        }

        String suffix = String.valueOf(quoteSequence);
        String delimiter = baseValue.contains('-') ? '' : '-';
        return (baseValue + delimiter + suffix).left(maxLength);
    }

    private static String buildUniqueExternalIdForQuote(
        String baseValue,
        Quote quoteRecord,
        Integer quoteSequence,
        Integer maxLength
    ) {
        if (String.isBlank(baseValue)) {
            return null;
        }

        if (quoteRecord != null && quoteRecord.Id != null) {
            String suffix = quoteRecord.Id.toString().right(6);
            return (baseValue + '-' + suffix).left(maxLength);
        }

        return buildUniqueExternalId(baseValue, quoteSequence, maxLength);
    }

    /**
     * @description Builds Quote Line Items from a mock Sales Connection template.
     * @param quoteId Quote Id.
     * @param pricebookEntryId Pricebook entry used for all mock lines.
     * @param template Mock Sales Connection template.
     * @return Quote line items ready for insert.
     */
    public static List<QuoteLineItem> buildQuoteLineItems(
        Id quoteId,
        Id pricebookEntryId,
        MockQuoteTemplate template
    ) {
        return buildQuoteLineItems(quoteId, pricebookEntryId, template, null);
    }

    /**
     * @description Builds Quote Line Items from a mock Sales Connection template.
     * @param quoteId Quote Id.
     * @param pricebookEntryId Deprecated single entry; wraps one-entry list when provided.
     * @param template Mock Sales Connection template.
     * @param sourceSystemId Prefix used to build unique line external ids.
     * @return Quote line items ready for insert.
     */
    public static List<QuoteLineItem> buildQuoteLineItems(
        Id quoteId,
        Id pricebookEntryId,
        MockQuoteTemplate template,
        String sourceSystemId
    ) {
        List<PricebookEntry> pricebookEntries = new List<PricebookEntry>();
        if (pricebookEntryId != null) {
            pricebookEntries.add(new PricebookEntry(Id = pricebookEntryId));
        }

        return buildQuoteLineItems(quoteId, pricebookEntries, template, sourceSystemId);
    }

    /**
     * @description Builds Quote Line Items from a mock Sales Connection template.
     * @param quoteId Quote Id.
     * @param pricebookEntries Active price book entries used to assign products to lines.
     * @param template Mock Sales Connection template.
     * @param sourceSystemId Prefix used to build unique line external ids.
     * @return Quote line items ready for insert.
     */
    public static List<QuoteLineItem> buildQuoteLineItems(
        Id quoteId,
        List<PricebookEntry> pricebookEntries,
        MockQuoteTemplate template,
        String sourceSystemId
    ) {
        List<QuoteLineItem> quoteLineItems = new List<QuoteLineItem>();

        if (quoteId == null || template == null || pricebookEntries == null || pricebookEntries.isEmpty()) {
            return quoteLineItems;
        }

        Integer lineIndex = 0;
        for (MockQuoteLine mockLine : template.quoteLines) {
            PricebookEntryResolution pricebookEntryResolution = resolvePricebookEntryResolution(
                mockLine.productFAMCode,
                mockLine.productName,
                lineIndex,
                pricebookEntries
            );

            if (pricebookEntryResolution.pricebookEntryId == null) {
                lineIndex++;
                continue;
            }

            Decimal quantity = normalizeQuantity(mockLine.quantity);
            Decimal unitPrice = mockLine.unitPrice == null ? 0 : mockLine.unitPrice;
            Decimal lineTotal = quantity * unitPrice;

            QuoteLineItem quoteLineItem = new QuoteLineItem();
            quoteLineItem.QuoteId = quoteId;
            quoteLineItem.PricebookEntryId = pricebookEntryResolution.pricebookEntryId;
            quoteLineItem.Description = resolveQuoteLineDescription(
                mockLine.productName,
                pricebookEntryResolution,
                pricebookEntries
            );
            quoteLineItem.Product_FAM_Code__c = mockLine.productFAMCode;
            quoteLineItem.Quantity = quantity;
            quoteLineItem.UnitPrice = unitPrice;
            quoteLineItem.Product_Subgroup_Detail_Name__c = mockLine.productSubgroupDetailName;
            quoteLineItem.TerritoryID__c = mockLine.territoryId;
            quoteLineItem.SalesCategory__c = mockLine.tasSalesCategory;
            quoteLineItem.UOM__c = mockLine.uom;
            quoteLineItem.SalesConnectionQuoteLineID__c = buildUniqueQuoteLineId(
                mockLine.quoteLineId,
                sourceSystemId
            );
            quoteLineItem.Total_Unit_Price__c = lineTotal;
            quoteLineItems.add(quoteLineItem);
            lineIndex++;
        }

        return quoteLineItems;
    }

    /**
     * @description Resolves a Pricebook Entry for a mock/integration quote line.
     * @param productFamCode Product FAM code from integration payload.
     * @param productName Product name from integration payload.
     * @param lineIndex Zero-based line index used for rotation across available entries.
     * @param pricebookEntries Active price book entries for the quote price book.
     * @return Matching or rotated Pricebook Entry Id.
     */
    public static Id resolvePricebookEntryId(
        String productFamCode,
        String productName,
        Integer lineIndex,
        List<PricebookEntry> pricebookEntries
    ) {
        return resolvePricebookEntryResolution(
            productFamCode,
            productName,
            lineIndex,
            pricebookEntries
        ).pricebookEntryId;
    }

    /**
     * @description Resolves a Pricebook Entry and whether the match was exact.
     * @param productFamCode Product FAM code from integration payload.
     * @param productName Product name from integration payload.
     * @param lineIndex Zero-based line index used for rotation across available entries.
     * @param pricebookEntries Active price book entries for the quote price book.
     * @return Matching or rotated Pricebook Entry resolution.
     */
    public static PricebookEntryResolution resolvePricebookEntryResolution(
        String productFamCode,
        String productName,
        Integer lineIndex,
        List<PricebookEntry> pricebookEntries
    ) {
        PricebookEntryResolution resolution = new PricebookEntryResolution();

        if (pricebookEntries == null || pricebookEntries.isEmpty()) {
            return resolution;
        }

        String normalizedFamCode = normalizeLookupValue(productFamCode);

        if (String.isNotBlank(normalizedFamCode)) {
            for (PricebookEntry pricebookEntry : pricebookEntries) {
                if (pricebookEntry == null || pricebookEntry.Id == null) {
                    continue;
                }

                if (
                    pricebookEntry.Product2 != null &&
                    normalizedFamCode.equalsIgnoreCase(normalizeLookupValue(pricebookEntry.Product2.ProductCode))
                ) {
                    resolution.pricebookEntryId = pricebookEntry.Id;
                    resolution.exactMatch = true;
                    return resolution;
                }
            }
        }

        String normalizedProductName = normalizeLookupValue(productName);
        if (String.isNotBlank(normalizedProductName)) {
            for (PricebookEntry pricebookEntry : pricebookEntries) {
                if (
                    pricebookEntry != null &&
                    pricebookEntry.Id != null &&
                    pricebookEntry.Product2 != null &&
                    normalizedProductName.equalsIgnoreCase(normalizeLookupValue(pricebookEntry.Product2.Name))
                ) {
                    resolution.pricebookEntryId = pricebookEntry.Id;
                    resolution.exactMatch = true;
                    return resolution;
                }
            }
        }

        List<PricebookEntry> usableEntries = new List<PricebookEntry>();
        for (PricebookEntry pricebookEntry : pricebookEntries) {
            if (pricebookEntry != null && pricebookEntry.Id != null) {
                usableEntries.add(pricebookEntry);
            }
        }

        if (usableEntries.isEmpty()) {
            return resolution;
        }

        Integer normalizedIndex = lineIndex == null || lineIndex < 0 ? 0 : lineIndex;
        Integer selectedIndex = Math.mod(normalizedIndex, usableEntries.size());
        resolution.pricebookEntryId = usableEntries[selectedIndex].Id;
        resolution.exactMatch = false;
        return resolution;
    }

    /**
     * @description Sets quote line description from integration/mock data or catalog product name.
     * @param integrationProductName Integration or mock product name.
     * @param pricebookEntryResolution Resolved price book entry match.
     * @param pricebookEntries Active price book entries for the quote price book.
     * @return Line description for display and downstream grouping.
     */
    public static String resolveQuoteLineDescription(
        String integrationProductName,
        PricebookEntryResolution pricebookEntryResolution,
        List<PricebookEntry> pricebookEntries
    ) {
        if (pricebookEntryResolution != null && pricebookEntryResolution.exactMatch == true) {
            return resolveLineDescription(
                integrationProductName,
                pricebookEntryResolution.pricebookEntryId,
                pricebookEntries
            );
        }

        return integrationProductName;
    }

    /**
     * @description Uses the linked Product2 name for quote line description when available.
     * @param fallbackDescription Integration or mock description.
     * @param pricebookEntryId Assigned price book entry Id.
     * @param pricebookEntries Active price book entries for the quote price book.
     * @return Product2 name when present, otherwise the fallback description.
     */
    public static String resolveLineDescription(
        String fallbackDescription,
        Id pricebookEntryId,
        List<PricebookEntry> pricebookEntries
    ) {
        if (pricebookEntries != null) {
            for (PricebookEntry pricebookEntry : pricebookEntries) {
                if (
                    pricebookEntry != null &&
                    pricebookEntry.Id == pricebookEntryId &&
                    pricebookEntry.Product2 != null &&
                    isUsableCatalogProductName(pricebookEntry.Product2.Name)
                ) {
                    return pricebookEntry.Product2.Name;
                }
            }
        }

        return fallbackDescription;
    }

    private static Boolean isUsableCatalogProductName(String productName) {
        if (String.isBlank(productName)) {
            return false;
        }

        return productName.trim().length() > 1;
    }

    private static String normalizeLookupValue(String value) {
        return String.isBlank(value) ? null : value.trim();
    }

    private static MockQuoteTemplate buildTemplateOne() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283624';
        template.quoteNumber = '00003956';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Approved';
        template.description = 'Endoscopy equipment upgrade';
        template.quoteTotalWithoutFreight = 97000;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 15, 14, 30, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-001',
                'AER Pomezia - Innova E4CMS',
                '027',
                'AER',
                'TERR-001',
                'SURG SPT',
                'Surgical Support',
                'EA',
                1,
                30000
            ),
            buildLine(
                'QL-002',
                'VerifEYE Borescope',
                '045',
                'AER',
                'TERR-001',
                'SURG SPT',
                'Surgical Support',
                'EA',
                2,
                20000
            ),
            buildLine(
                'QL-003',
                'VHP - VHP 100i',
                '054',
                'AER',
                'TERR-002',
                'STERL PROC',
                'Sterilization Processing',
                'EA',
                3,
                5000
            ),
            buildLine(
                'QL-004',
                'Barrier Product 700',
                '700',
                'Barrier Products',
                'TERR-003',
                'PM',
                'Preventive Maintenance',
                'BX',
                2,
                2500
            ),
            buildLine(
                'QL-005',
                'Barrier Product 703',
                '703',
                'Barrier Products',
                'TERR-003',
                'PM',
                'Preventive Maintenance',
                'CS',
                1,
                7000
            )
        };
        return template;
    }

    private static MockQuoteTemplate buildTemplateTwo() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283625';
        template.quoteNumber = '00003957';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Approved';
        template.description = 'Sterilization suite refresh';
        template.quoteTotalWithoutFreight = 107000;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 10, 9, 15, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-101',
                'Washer Disinfector',
                'WASH1',
                'Washer-Disinfectors',
                'TERR-001',
                'SURG SPT',
                'Surgical Support',
                'EA',
                1,
                45000
            ),
            buildLine(
                'QL-102',
                'Steam Sterilizer',
                'STER1',
                'Sterilizers',
                'TERR-002',
                'ORI',
                'Orthopedic Instruments',
                'EA',
                1,
                62000
            )
        };
        return template;
    }

    private static MockQuoteTemplate buildTemplateThree() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283626';
        template.quoteNumber = '00003958';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Approved';
        template.description = 'Flexible endoscopy replacement';
        template.quoteTotalWithoutFreight = 84500;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 20, 16, 45, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-201',
                'Chemical Indicator',
                'CHEM1',
                'Chemical Indicators',
                'TERR-003',
                'PMI',
                'Patient Monitoring Instruments',
                'BX',
                5,
                16900
            )
        };
        return template;
    }

    private static MockQuoteTemplate buildTemplateFour() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283627';
        template.quoteNumber = '00003959';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Approved';
        template.description = 'Service contract renewal';
        template.quoteTotalWithoutFreight = 18000;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 25, 11, 0, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-301',
                'Annual Maintenance',
                'SRVC1',
                'Service Contracts',
                '123',
                'SURG SPT',
                'Surgical Support',
                'EA',
                1,
                12000
            ),
            buildLine(
                'QL-302',
                'Extended Warranty',
                'SRVC2',
                'Service Contracts',
                '123',
                'SURG SPT',
                'Surgical Support',
                'EA',
                2,
                3000
            )
        };
        return template;
    }

    private static MockQuoteTemplate buildTemplateFive() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283628';
        template.quoteNumber = '00003960';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Approved';
        template.description = 'CSSD capital equipment package';
        template.quoteTotalWithoutFreight = 125000;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 8, 11, 30, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-401',
                'Cart Washer',
                'WASH2',
                'Washer-Disinfectors',
                'TERR-001',
                'SURG SPT',
                'Surgical Support',
                'EA',
                1,
                75000
            ),
            buildLine(
                'QL-402',
                'Instrument Tracking System',
                'TRK1',
                'Tracking Systems',
                'TERR-002',
                'ORI',
                'Orthopedic Instruments',
                'EA',
                1,
                50000
            )
        };
        return template;
    }

    private static MockQuoteTemplate buildTemplateSix() {
        MockQuoteTemplate template = new MockQuoteTemplate();
        template.salesConnectionQuoteId = '2283629';
        template.quoteNumber = '00003961';
        template.quoteStatus = 'Open';
        template.approvalStatus = 'Unapproved';
        template.description = 'SPD workflow optimization';
        template.quoteTotalWithoutFreight = 56000;
        template.lastModifiedDate = Datetime.newInstanceGmt(2026, 7, 28, 13, 0, 0);
        template.quoteLines = new List<MockQuoteLine>{
            buildLine(
                'QL-501',
                'Ultrasonic Cleaner',
                'ULTR1',
                'Ultrasonic Cleaners',
                'TERR-003',
                'STERL PROC',
                'Sterilization Processing',
                'EA',
                2,
                18000
            ),
            buildLine(
                'QL-502',
                'Scope Storage Cabinet',
                'STOR1',
                'Storage Systems',
                'TERR-003',
                'PM',
                'Preventive Maintenance',
                'EA',
                1,
                20000
            )
        };
        return template;
    }

    private static MockQuoteLine buildLine(
        String quoteLineId,
        String productName,
        String productFAMCode,
        String productSubgroupDetailName,
        String territoryId,
        String tasSalesCategory,
        String salesCategoryDescription,
        String uom,
        Decimal quantity,
        Decimal unitPrice
    ) {
        MockQuoteLine mockLine = new MockQuoteLine();
        mockLine.quoteLineId = quoteLineId;
        mockLine.productName = productName;
        mockLine.productFAMCode = productFAMCode;
        mockLine.productSubgroupDetailName = productSubgroupDetailName;
        mockLine.territoryId = territoryId;
        mockLine.tasSalesCategory = tasSalesCategory;
        mockLine.salesCategoryDescription = salesCategoryDescription;
        mockLine.uom = uom;
        mockLine.quantity = quantity;
        mockLine.unitPrice = unitPrice;
        return mockLine;
    }

    public static String buildUniqueQuoteLineId(String templateLineId, String lineIdPrefix) {
        if (String.isBlank(templateLineId)) {
            return null;
        }

        if (String.isBlank(lineIdPrefix)) {
            return templateLineId + '-' + String.valueOf(Math.abs(Crypto.getRandomInteger()));
        }

        return lineIdPrefix + '-' + templateLineId;
    }

    public static String resolveQuoteStatus(String mockStatus) {
        if (String.isBlank(mockStatus)) {
            return getDefaultQuoteStatus();
        }

        String normalizedStatus = normalizeToHcSalesStatus(mockStatus);
        String resolvedStatus = findActiveQuoteStatus(normalizedStatus);
        return resolvedStatus != null ? resolvedStatus : getDefaultQuoteStatus();
    }

    private static String normalizeToHcSalesStatus(String mockStatus) {
        for (String allowedStatus : HC_SALES_QUOTE_STATUSES) {
            if (allowedStatus.equalsIgnoreCase(mockStatus)) {
                return allowedStatus;
            }
        }

        return 'Draft';
    }

    private static String findActiveQuoteStatus(String statusValue) {
        if (String.isBlank(statusValue) || !isAllowedHcSalesStatus(statusValue)) {
            return null;
        }

        for (Schema.PicklistEntry picklistEntry : Quote.Status.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(statusValue)) {
                return picklistEntry.getValue();
            }
        }

        for (String allowedStatus : HC_SALES_QUOTE_STATUSES) {
            if (allowedStatus.equalsIgnoreCase(statusValue)) {
                return allowedStatus;
            }
        }

        return null;
    }

    private static Boolean isAllowedHcSalesStatus(String statusValue) {
        for (String allowedStatus : HC_SALES_QUOTE_STATUSES) {
            if (allowedStatus.equalsIgnoreCase(statusValue)) {
                return true;
            }
        }

        return false;
    }

    public static String resolveApprovalStatus(String mockApprovalStatus) {
        if (String.isBlank(mockApprovalStatus)) {
            return null;
        }

        for (Schema.PicklistEntry picklistEntry :
            Quote.Approval_Status__c.getDescribe().getPicklistValues()) {
            if (picklistEntry.isActive() && picklistEntry.getValue().equalsIgnoreCase(mockApprovalStatus)) {
                return picklistEntry.getValue();
            }
        }

        return null;
    }

    private static String getDefaultQuoteStatus() {
        String draftStatus = findActiveQuoteStatus('Draft');
        return draftStatus != null ? draftStatus : 'Draft';
    }

    private static Decimal normalizeQuantity(Decimal quantity) {
        if (quantity == null || quantity <= 0) {
            return 1;
        }

        return quantity;
    }

    /**
     * @description Builds a Refresh Quote integration JSON payload from existing Opportunity quotes.
     *              Used while the Boomi / mocki.io endpoint is unavailable.
     * @param opportunityId Opportunity Id.
     * @return JSON array of quote rows for RefreshQuoteResponseMapper.
     */
    public static String buildRefreshQuoteResponseBody(Id opportunityId) {
        if (opportunityId == null) {
            return '[]';
        }

        List<Quote> quoteRecords = QuoteSelector.selectByOpportunityIdWithLineItems(opportunityId);
        if (quoteRecords.isEmpty()) {
            return '[]';
        }

        List<Object> apiQuotes = new List<Object>();
        Integer quoteCount = quoteRecords.size();

        for (Integer quoteIndex = 0; quoteIndex < quoteCount; quoteIndex++) {
            Quote quoteRecord = quoteRecords[quoteIndex];
            Integer templateIndex = quoteCount - 1 - quoteIndex;
            MockQuoteTemplate template = getTemplate(templateIndex);
            apiQuotes.add(buildRefreshQuotePayload(quoteRecord, template, quoteIndex));
        }

        return JSON.serialize(apiQuotes);
    }

    private static Map<String, Object> buildRefreshQuotePayload(
        Quote quoteRecord,
        MockQuoteTemplate template,
        Integer quoteSequence
    ) {
        Map<String, Object> payload = new Map<String, Object>{
            'id' => quoteRecord.Id,
            'quoteNumber' => resolveRefreshQuoteNumber(quoteRecord, template, quoteSequence),
            'salesConnectionQuoteId' => resolveRefreshSalesConnectionQuoteId(
                quoteRecord,
                template,
                quoteSequence
            ),
            'quoteName' => quoteRecord.Name,
            'expirationDate' => quoteRecord.ExpirationDate == null
                ? null
                : String.valueOf(quoteRecord.ExpirationDate),
            'description' => template.description,
            'status' => template.quoteStatus,
            'approvalStatus' => template.approvalStatus,
            'quoteTotalWithoutFreight' => template.quoteTotalWithoutFreight,
            'lastModifiedDate' => formatRefreshLastModifiedDate(template.lastModifiedDate),
            'productSubgroupSummary' => buildRefreshProductSubgroupSummary(quoteRecord, template)
        };
        return payload;
    }

    private static String formatRefreshLastModifiedDate(Datetime lastModifiedDate) {
        if (lastModifiedDate == null) {
            return null;
        }

        return lastModifiedDate.formatGmt('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\'');
    }

    private static List<Object> buildRefreshProductSubgroupSummary(
        Quote quoteRecord,
        MockQuoteTemplate template
    ) {
        if (quoteRecord != null && quoteRecord.QuoteLineItems != null && !quoteRecord.QuoteLineItems.isEmpty()) {
            return buildRefreshProductSubgroupSummaryFromQuoteLines(quoteRecord);
        }

        return buildRefreshProductSubgroupSummaryFromTemplate(template);
    }

    private static List<Object> buildRefreshProductSubgroupSummaryFromQuoteLines(Quote quoteRecord) {
        List<Object> subgroups = new List<Object>();
        Map<String, List<QuoteLineItem>> linesBySubgroup = new Map<String, List<QuoteLineItem>>();

        for (QuoteLineItem lineRecord : quoteRecord.QuoteLineItems) {
            if (lineRecord == null) {
                continue;
            }

            String subgroupName = String.isBlank(lineRecord.Product_Subgroup_Detail_Name__c)
                ? 'Other'
                : lineRecord.Product_Subgroup_Detail_Name__c;

            if (!linesBySubgroup.containsKey(subgroupName)) {
                linesBySubgroup.put(subgroupName, new List<QuoteLineItem>());
            }

            linesBySubgroup.get(subgroupName).add(lineRecord);
        }

        for (String subgroupName : linesBySubgroup.keySet()) {
            List<QuoteLineItem> subgroupLines = linesBySubgroup.get(subgroupName);
            Decimal totalUnitPrice = 0;
            List<Object> apiLines = new List<Object>();

            for (QuoteLineItem lineRecord : subgroupLines) {
                Decimal quantity = normalizeQuantity(lineRecord.Quantity);
                Decimal unitPrice = lineRecord.UnitPrice == null ? 0 : lineRecord.UnitPrice;
                Decimal lineTotal = lineRecord.Total_Unit_Price__c == null
                    ? quantity * unitPrice
                    : lineRecord.Total_Unit_Price__c;
                totalUnitPrice += lineTotal;
                apiLines.add(buildRefreshQuoteLinePayload(lineRecord, quoteRecord.Id, quantity, lineTotal));
            }

            subgroups.add(
                new Map<String, Object>{
                    'productSubgroupDetailName' => subgroupName,
                    'totalUnitPrice' => totalUnitPrice,
                    'quoteLines' => apiLines
                }
            );
        }

        return subgroups;
    }

    private static List<Object> buildRefreshProductSubgroupSummaryFromTemplate(MockQuoteTemplate template) {
        List<Object> subgroups = new List<Object>();

        if (template == null || template.quoteLines == null || template.quoteLines.isEmpty()) {
            return subgroups;
        }

        Map<String, List<MockQuoteLine>> linesBySubgroup = new Map<String, List<MockQuoteLine>>();
        for (MockQuoteLine mockLine : template.quoteLines) {
            if (mockLine == null) {
                continue;
            }

            String subgroupName = String.isBlank(mockLine.productSubgroupDetailName)
                ? 'Other'
                : mockLine.productSubgroupDetailName;

            if (!linesBySubgroup.containsKey(subgroupName)) {
                linesBySubgroup.put(subgroupName, new List<MockQuoteLine>());
            }

            linesBySubgroup.get(subgroupName).add(mockLine);
        }

        for (String subgroupName : linesBySubgroup.keySet()) {
            List<MockQuoteLine> subgroupLines = linesBySubgroup.get(subgroupName);
            Decimal totalUnitPrice = 0;
            List<Object> apiLines = new List<Object>();

            for (MockQuoteLine mockLine : subgroupLines) {
                Decimal quantity = normalizeQuantity(mockLine.quantity);
                Decimal unitPrice = mockLine.unitPrice == null ? 0 : mockLine.unitPrice;
                Decimal lineTotal = quantity * unitPrice;
                totalUnitPrice += lineTotal;
                apiLines.add(buildRefreshQuoteLinePayload(mockLine, quantity, lineTotal));
            }

            subgroups.add(
                new Map<String, Object>{
                    'productSubgroupDetailName' => subgroupName,
                    'totalUnitPrice' => totalUnitPrice,
                    'quoteLines' => apiLines
                }
            );
        }

        return subgroups;
    }

    private static Map<String, Object> buildRefreshQuoteLinePayload(
        QuoteLineItem lineRecord,
        Id quoteId,
        Decimal quantity,
        Decimal lineTotal
    ) {
        return new Map<String, Object>{
            'quoteLineId' => extractTemplateLineId(lineRecord.SalesConnectionQuoteLineID__c, quoteId),
            'productName' => lineRecord.Description,
            'uom' => lineRecord.UOM__c,
            'productFAMCode' => lineRecord.Product_FAM_Code__c,
            'productSubgroupDetailName' => lineRecord.Product_Subgroup_Detail_Name__c,
            'territoryId' => lineRecord.TerritoryID__c,
            'tasSalesCategory' => lineRecord.SalesCategory__c,
            'salesCategoryDescription' => lineRecord.SalesCategory__c,
            'quantity' => quantity,
            'unitPrice' => lineRecord.UnitPrice,
            'lineTotal' => lineTotal
        };
    }

    private static String extractTemplateLineId(String externalLineId, Id quoteId) {
        if (String.isBlank(externalLineId)) {
            return null;
        }

        if (quoteId != null) {
            String prefix = String.valueOf(quoteId) + '-';
            if (externalLineId.startsWith(prefix)) {
                return externalLineId.substring(prefix.length());
            }
        }

        Integer dashIndex = externalLineId.lastIndexOf('-');
        return dashIndex >= 0 ? externalLineId.substring(dashIndex + 1) : externalLineId;
    }

    private static Map<String, Object> buildRefreshQuoteLinePayload(
        MockQuoteLine mockLine,
        Decimal quantity,
        Decimal lineTotal
    ) {
        return new Map<String, Object>{
            'quoteLineId' => mockLine.quoteLineId,
            'productName' => mockLine.productName,
            'uom' => mockLine.uom,
            'productFAMCode' => mockLine.productFAMCode,
            'productSubgroupDetailName' => mockLine.productSubgroupDetailName,
            'territoryId' => mockLine.territoryId,
            'tasSalesCategory' => mockLine.tasSalesCategory,
            'salesCategoryDescription' => mockLine.salesCategoryDescription,
            'quantity' => quantity,
            'unitPrice' => mockLine.unitPrice,
            'lineTotal' => lineTotal
        };
    }
}