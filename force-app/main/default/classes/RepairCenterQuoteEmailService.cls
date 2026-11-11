/**
 * @description GW-5102 - Repair Center quote customer emails and inbound Approve / Reject / Help processing.
 */
public with sharing class RepairCenterQuoteEmailService {
    public static final String INTENT_APPROVE = 'Approved';
    public static final String INTENT_REJECT = 'Reject';
    public static final String INTENT_HELP = 'Help';

    private static final String QLI_STATUS_APPROVED = 'Approved';
    private static final String QLI_STATUS_REJECTED = 'Rejected';
    private static final String QUOTE_STATUS_APPROVED = 'Approved';
    private static final String QUOTE_STATUS_REJECTED = 'Rejected';
    private static final String WO_SUBSTATUS_CUSTOMER_CARE = 'Customer Care';
    private static final String LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
    private static final String SERVICE_CODE_TYPE_DISINFECTION = 'Disinfection';
    private static final String LINE_TYPE_SERVICE_CODE = 'Service Code';
    private static final String WOLI_STATUS_APPROVED = 'Approved';

    @TestVisible
    private static Map<Id, String> serviceCodeTypeByProductIdOverride;
    @TestVisible
    private static Map<Id, Id> inspectionServiceProductByQliProductIdOverride;
    @TestVisible
    private static Boolean sendEmailInvoked;

    /**
     * @description Applies Approve / Reject / Help updates after the inbound handler resolves the Work Order.
     * @param parsedWorkOrder Work Order from the original outbound email Related To
     * @param intent Approved, Reject, or Help
     */
    public static void applyReply(WorkOrder parsedWorkOrder, String intent) {
        if (parsedWorkOrder == null) {
            return;
        }

        String resolvedIntent = String.isBlank(intent)
            ? INTENT_HELP
            : intent;
        List<WorkOrder> quoteWorkOrders = resolveQuoteWorkOrders(parsedWorkOrder);
        if (quoteWorkOrders.isEmpty()) {
            if (INTENT_HELP.equals(resolvedIntent)) {
                applyHelp(parsedWorkOrder);
            } else {
                Logger.info(
                    'RepairCenterQuoteEmailService.applyReply: no Active Quote for ' + parsedWorkOrder.Id
                );
            }
            return;
        }

        for (WorkOrder quoteWorkOrder : quoteWorkOrders) {
            if (INTENT_APPROVE.equals(resolvedIntent)) {
                applyApproved(quoteWorkOrder);
            } else if (INTENT_REJECT.equals(resolvedIntent)) {
                applyRejected(quoteWorkOrder);
            } else {
                applyHelp(quoteWorkOrder);
            }
        }
    }

    /**
     * @description Flow / Admin entry point to send Repair Center quote emails for Work Orders.
     * @param workOrderIds Work Order Ids (parent or child)
     * @return Related parent Work Order Ids that were emailed
     */
    @InvocableMethod(
        label='Send Repair Center Quote Email'
        description='Sends the Repair Center estimate email to the customer Contact, related to the Parent Work Order.'
    )
    public static List<Id> sendQuoteEmails(List<Id> workOrderIds) {
        List<Id> emailedParentIds = new List<Id>();
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            return emailedParentIds;
        }

        Logger.setScenario('Repair Center Quote Email');
        try {
            for (Id workOrderId : workOrderIds) {
                Id parentId = sendQuoteEmail(workOrderId);
                if (parentId != null) {
                    emailedParentIds.add(parentId);
                }
            }
        } catch (Exception e) {
            Logger.error('RepairCenterQuoteEmailService.sendQuoteEmails', e);
            throw e;
        } finally {
            Logger.saveLog();
        }
        return emailedParentIds;
    }

    /**
     * @description Sends one Repair Center quote email related to the Parent Work Order.
     * @param workOrderId Work Order Id
     * @return Parent Work Order Id used as the email Related To
     */
    public static Id sendQuoteEmail(Id workOrderId) {
        if (workOrderId == null) {
            return null;
        }

        WorkOrder workOrder = WorkOrdersSelector.selectForQuoteEmailReply(String.valueOf(workOrderId));
        if (workOrder == null) {
            throw new RepairCenterQuoteEmailException('Work Order was not found.');
        }

        List<WorkOrder> quoteWorkOrders = resolveQuoteWorkOrders(workOrder);
        WorkOrder quoteWorkOrder = quoteWorkOrders.isEmpty() ? workOrder : quoteWorkOrders[0];
        Id parentWorkOrderId = workOrder.ParentWorkOrderId != null
            ? workOrder.ParentWorkOrderId
            : workOrder.Id;

        Id contactId = quoteWorkOrder.EstimateContact__c != null
            ? quoteWorkOrder.EstimateContact__c
            : quoteWorkOrder.ContactId;
        String contactEmail = quoteWorkOrder.EstimateContact__c != null
            ? quoteWorkOrder.EstimateContact__r.Email
            : quoteWorkOrder.Contact != null ? quoteWorkOrder.Contact.Email : null;
        if (contactId == null || String.isBlank(contactEmail)) {
            throw new RepairCenterQuoteEmailException(
                'An Estimate Contact or Work Order Contact with an email address is required.'
            );
        }

        Boolean poRequired = quoteWorkOrder.CustomerPORequired__c == true;
        String accountName = quoteWorkOrder.Account != null ? quoteWorkOrder.Account.Name : '';
        String htmlBody = buildCustomerHtml(poRequired);
        String textBody = buildCustomerText(poRequired);

        Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();
        mail.setTargetObjectId(contactId);
        mail.setTreatTargetObjectAsRecipient(true);
        mail.setWhatId(parentWorkOrderId);
        mail.setSaveAsActivity(true);
        mail.setUseSignature(false);
        mail.setReplyTo(ExternalSystemEndpointSelector.repairCenterQuoteInboundEmail());
        mail.setSubject(buildQuoteEmailSubject(quoteWorkOrder, accountName));
        mail.setHtmlBody(htmlBody);
        mail.setPlainTextBody(textBody);

        QuoteDocument quoteDocument = QuoteDocumentsService.getLatestByQuoteId(
            quoteWorkOrder.ActiveQuote__c
        );
        if (quoteDocument != null && quoteDocument.Document != null) {
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(
                String.isBlank(quoteDocument.Name) ? 'Quote.pdf' : quoteDocument.Name + '.pdf'
            );
            attachment.setBody(quoteDocument.Document);
            mail.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });
        }

        if (Test.isRunningTest()) {
            sendEmailInvoked = true;
            return parentWorkOrderId;
        }
        Messaging.sendEmail(new List<Messaging.SingleEmailMessage>{ mail }, false);
        return parentWorkOrderId;
    }

    /**
     * @description Builds the Repair Center estimate subject: SRN is Return Order, Order is Work Order Number.
     * @param workOrder Work Order used for Return Order and Work Order Number
     * @param accountName Account name for the subject suffix
     * @return Subject line matching the Repair Center estimate template
     */
    @TestVisible
    private static String buildQuoteEmailSubject(WorkOrder workOrder, String accountName) {
        String srn = resolveReturnOrderNumber(workOrder);
        String orderNumber = workOrder == null || String.isBlank(workOrder.WorkOrderNumber)
            ? ''
            : workOrder.WorkOrderNumber;
        String account = String.isBlank(accountName) ? '' : accountName;
        return 'Estimate for SRN #' + srn + ', Order #' + orderNumber + ' - ' + account;
    }

    private static String resolveReturnOrderNumber(WorkOrder workOrder) {
        if (workOrder == null) {
            return '';
        }
        if (workOrder.Id != null) {
            List<WorkOrder> rows = [
                SELECT ReturnOrder.ReturnOrderNumber, ReturnOrder__r.ReturnOrderNumber
                FROM WorkOrder
                WHERE Id = :workOrder.Id
                WITH SYSTEM_MODE
                LIMIT 1
            ];
            if (!rows.isEmpty()) {
                return firstReturnOrderNumber(rows[0]);
            }
        }
        return firstReturnOrderNumber(workOrder);
    }

    private static String firstReturnOrderNumber(WorkOrder workOrder) {
        if (workOrder.ReturnOrder__r != null && String.isNotBlank(workOrder.ReturnOrder__r.ReturnOrderNumber)) {
            return workOrder.ReturnOrder__r.ReturnOrderNumber;
        }
        if (workOrder.ReturnOrder != null && String.isNotBlank(workOrder.ReturnOrder.ReturnOrderNumber)) {
            return workOrder.ReturnOrder.ReturnOrderNumber;
        }
        return '';
    }

    /**
     * @description Builds the customer HTML body with first-line Approve/Reject instructions.
     * @param poRequired True when Account Profile requires a PO
     * @return HTML body
     */
    @TestVisible
    private static String buildCustomerHtml(Boolean poRequired) {
        String connectCareUrl = ExternalSystemEndpointSelector.connectCareQuoteApprovalUrl();
        String html =
            '<p>Attached is a repair estimate for your review.</p>';
        if (poRequired != true) {
            html +=
                '<p>Please reply to this email. Put <b>Approved</b> or <b>Reject</b> on the first line ' +
                'to approve or reject the entire estimate.</p>';
        }
        html +=
            '<p>If you want to enter a combination of Reject / Approve, please do so through ' +
            '<a href="' +
            connectCareUrl +
            '">ConnectCare</a>.</p>';
        if (poRequired == true) {
            html +=
                '<p>A purchase order is required. Enter a PO# and/or upload a digital PO document through ' +
                '<a href="' +
                connectCareUrl +
                '">ConnectCare</a>.</p>';
        }
        html += '<p>Thank you for choosing STERIS.</p>';
        return html;
    }

    /**
     * @description Builds the customer plain-text body with first-line Approve/Reject instructions.
     * @param poRequired True when Account Profile requires a PO
     * @return Plain text body
     */
    @TestVisible
    private static String buildCustomerText(Boolean poRequired) {
        String text = 'Attached is a repair estimate for your review.\n\n';
        if (poRequired != true) {
            text +=
                'Please reply to this email. Put Approved or Reject on the first line ' +
                'to approve or reject the entire estimate.\n\n';
        }
        text +=
            'If you want to enter a combination of Reject / Approve, please do so through ConnectCare (' +
            ExternalSystemEndpointSelector.connectCareQuoteApprovalUrl() +
            ').\n';
        if (poRequired == true) {
            text +=
                'A purchase order is required. Enter a PO# and/or upload a digital PO document through ConnectCare.\n';
        }
        text += '\nThank you for choosing STERIS.';
        return text;
    }

    @TestVisible
    private static List<WorkOrder> resolveQuoteWorkOrders(WorkOrder parsedWorkOrder) {
        List<WorkOrder> results = new List<WorkOrder>();
        if (parsedWorkOrder == null) {
            return results;
        }
        if (parsedWorkOrder.ActiveQuote__c != null) {
            results.add(parsedWorkOrder);
            return results;
        }
        List<WorkOrder> children =
            WorkOrdersSelector.selectChildrenWithActiveQuoteByParentIds(
                new Set<Id>{ parsedWorkOrder.Id }
            );
        if (!children.isEmpty()) {
            return children;
        }
        if (parsedWorkOrder.ParentWorkOrderId != null) {
            WorkOrder parentWorkOrder = WorkOrdersSelector.selectForQuoteEmailReply(
                String.valueOf(parsedWorkOrder.ParentWorkOrderId)
            );
            if (parentWorkOrder != null && parentWorkOrder.ActiveQuote__c != null) {
                results.add(parentWorkOrder);
            }
        }
        return results;
    }

    private static void applyApproved(WorkOrder quoteWorkOrder) {
        List<QuoteLineItem> lineItems =
            QuoteLineItemService.getForQuoteEmailReplyByQuoteId(quoteWorkOrder.ActiveQuote__c);
        List<QuoteLineItem> lineUpdates = new List<QuoteLineItem>();
        for (QuoteLineItem lineItem : lineItems) {
            lineUpdates.add(new QuoteLineItem(Id = lineItem.Id, Status__c = QLI_STATUS_APPROVED));
        }
        if (!lineUpdates.isEmpty()) {
            update lineUpdates;
        }
        updateQuotes(
            new List<Quote>{
                new Quote(Id = quoteWorkOrder.ActiveQuote__c, Status = QUOTE_STATUS_APPROVED)
            }
        );
    }

    private static void applyRejected(WorkOrder quoteWorkOrder) {
        List<QuoteLineItem> lineItems =
            QuoteLineItemService.getForQuoteEmailReplyByQuoteId(quoteWorkOrder.ActiveQuote__c);
        Map<Id, Product2> productsById = loadProducts(lineItems);
        List<QuoteLineItem> lineUpdates = new List<QuoteLineItem>();
        List<QuoteLineItem> productServicedRejected = new List<QuoteLineItem>();

        for (QuoteLineItem lineItem : lineItems) {
            Boolean disinfection = isDisinfection(lineItem, productsById);
            String statusValue = disinfection ? QLI_STATUS_APPROVED : QLI_STATUS_REJECTED;
            lineUpdates.add(new QuoteLineItem(Id = lineItem.Id, Status__c = statusValue));
            if (!disinfection && LINE_TYPE_PRODUCT_SERVICED.equals(lineItem.LineType__c)) {
                productServicedRejected.add(lineItem);
            }
        }

        if (!lineUpdates.isEmpty()) {
            update lineUpdates;
        }
        updateQuotes(
            new List<Quote>{
                new Quote(Id = quoteWorkOrder.ActiveQuote__c, Status = QUOTE_STATUS_REJECTED)
            }
        );
        createInspectionFeeLines(quoteWorkOrder, productServicedRejected, productsById);
    }

    private static void applyHelp(WorkOrder quoteWorkOrder) {
        WorkOrdersService.updateWorkOrders(
            new List<WorkOrder>{
                new WorkOrder(
                    Id = quoteWorkOrder.Id,
                    SubStatus__c = WO_SUBSTATUS_CUSTOMER_CARE
                )
            }
        );
    }

    private static Map<Id, Product2> loadProducts(List<QuoteLineItem> lineItems) {
        Set<Id> productIds = new Set<Id>();
        for (QuoteLineItem lineItem : lineItems) {
            if (lineItem.Product2Id != null) {
                productIds.add(lineItem.Product2Id);
            }
            if (lineItem.Item__c != null) {
                productIds.add(lineItem.Item__c);
            }
        }
        Map<Id, Product2> productsById = new Map<Id, Product2>();
        if (productIds.isEmpty()) {
            return productsById;
        }
        for (Product2 product : ProductsSelector.selectForQuoteEmailReplyByIds(productIds)) {
            productsById.put(product.Id, product);
        }
        return productsById;
    }

    private static Boolean isDisinfection(QuoteLineItem lineItem, Map<Id, Product2> productsById) {
        Id productId = lineItem.Product2Id;
        if (serviceCodeTypeByProductIdOverride != null &&
            productId != null &&
            serviceCodeTypeByProductIdOverride.containsKey(productId)) {
            return SERVICE_CODE_TYPE_DISINFECTION.equalsIgnoreCase(
                serviceCodeTypeByProductIdOverride.get(productId)
            );
        }
        Product2 product = productId == null ? null : productsById.get(productId);
        return product != null &&
            SERVICE_CODE_TYPE_DISINFECTION.equalsIgnoreCase(product.ServiceCodeType__c);
    }

    /**
     * @description GW-5102 / GW-5398 - Inspection fee WOLI from QLI.Product.Inspection Service Code.
     *              Skips when Inspection Fee Applicable is false or Inspection Service Code is blank.
     */
    private static void createInspectionFeeLines(
        WorkOrder quoteWorkOrder,
        List<QuoteLineItem> productServicedLines,
        Map<Id, Product2> productsById
    ) {
        if (productServicedLines == null || productServicedLines.isEmpty()) {
            return;
        }

        Map<Id, Product2> products = productsById == null
            ? new Map<Id, Product2>()
            : productsById;
        Map<Id, Id> inspectionProductByQliProduct = resolveInspectionServiceProducts(
            productServicedLines,
            products
        );
        if (inspectionProductByQliProduct.isEmpty()) {
            return;
        }

        Set<Id> inspectionProductIds = new Set<Id>(inspectionProductByQliProduct.values());
        for (Product2 inspectionProduct : ProductsSelector.selectForQuoteEmailReplyByIds(inspectionProductIds)) {
            products.put(inspectionProduct.Id, inspectionProduct);
        }

        Quote quoteRecord = selectQuoteForReply(quoteWorkOrder.ActiveQuote__c);
        Id pricebookId = quoteRecord != null && quoteRecord.Pricebook2Id != null
            ? quoteRecord.Pricebook2Id
            : quoteWorkOrder.Pricebook2Id;
        if (pricebookId == null || String.isBlank(quoteWorkOrder.CurrencyIsoCode)) {
            return;
        }

        Map<Id, PricebookEntry> pbeByProductId = new Map<Id, PricebookEntry>();
        for (
            PricebookEntry entry :
            PricebookEntriesSelector.selectActiveWithProductByPricebookProductAndCurrency(
                pricebookId,
                new Set<Id>(inspectionProductByQliProduct.values()),
                quoteWorkOrder.CurrencyIsoCode
            )
        ) {
            pbeByProductId.put(entry.Product2Id, entry);
        }

        Id repairCodeRtId = WorkOrderLineItemsService.getRepairCodeRecordTypeId();
        if (repairCodeRtId == null) {
            return;
        }

        List<WorkOrderLineItem> linesToInsert = new List<WorkOrderLineItem>();
        for (QuoteLineItem lineItem : productServicedLines) {
            Id qliProductId = lineItem.Product2Id != null ? lineItem.Product2Id : lineItem.Item__c;
            Id inspectionProductId = inspectionProductByQliProduct.get(qliProductId);
            if (inspectionProductId == null) {
                continue;
            }
            PricebookEntry entry = pbeByProductId.get(inspectionProductId);
            if (entry == null) {
                continue;
            }
            Product2 qliProduct = products.get(lineItem.Product2Id);
            Product2 inspectionProduct = products.get(inspectionProductId);
            Id workOrderId = lineItem.WorkOrder__c != null
                ? lineItem.WorkOrder__c
                : quoteWorkOrder.Id;

            WorkOrderLineItem inspectionLine = new WorkOrderLineItem();
            inspectionLine.RecordTypeId = repairCodeRtId;
            inspectionLine.LineType__c = resolveInspectionLineType(inspectionProduct);
            inspectionLine.AssetId = lineItem.Asset__c;
            inspectionLine.SerialNumber__c = lineItem.SerialNumber__c;
            inspectionLine.Model__c = qliProduct == null ? null : qliProduct.Model__c;
            inspectionLine.Item__c = qliProductId;
            inspectionLine.ItemCode__c = lineItem.ItemCode__c;
            inspectionLine.ItemDescription__c = String.isNotBlank(lineItem.ItemDescription__c)
                ? lineItem.ItemDescription__c
                : lineItem.Description;
            inspectionLine.PricebookEntryId = entry.Id;
            inspectionLine.ProductCodeWoli__c = firstNonBlank(
                inspectionProduct == null ? null : inspectionProduct.ProductCode,
                entry.Product2 == null ? null : entry.Product2.ProductCode
            );
            inspectionLine.ProductDescription__c = firstNonBlank(
                inspectionProduct == null ? null : inspectionProduct.Description,
                entry.Product2 == null ? null : entry.Product2.Description
            );
            inspectionLine.WorkOrderId = workOrderId;
            inspectionLine.TopLevelWorkOrder__c = lineItem.TopLevelWorkOrder__c;
            inspectionLine.ParentWorkOrderLineItemId = lineItem.ParentWorkOrderLineItem__c;
            inspectionLine.Quantity = lineItem.Quantity == null ? 1 : lineItem.Quantity;
            inspectionLine.Status = WOLI_STATUS_APPROVED;
            linesToInsert.add(inspectionLine);
        }
        WorkOrderLineItemsService.createLineItems(linesToInsert);
    }

    private static Map<Id, Id> resolveInspectionServiceProducts(
        List<QuoteLineItem> productServicedLines,
        Map<Id, Product2> productsById
    ) {
        Map<Id, Id> inspectionProductByQliProduct = new Map<Id, Id>();
        if (inspectionServiceProductByQliProductIdOverride != null) {
            inspectionProductByQliProduct.putAll(inspectionServiceProductByQliProductIdOverride);
            return inspectionProductByQliProduct;
        }

        for (QuoteLineItem lineItem : productServicedLines) {
            Id qliProductId = lineItem.Product2Id != null ? lineItem.Product2Id : lineItem.Item__c;
            Id inspectionProductId = inspectionProductFromProduct(
                qliProductId == null || productsById == null
                    ? null
                    : productsById.get(qliProductId)
            );
            if (qliProductId != null && inspectionProductId != null) {
                inspectionProductByQliProduct.put(qliProductId, inspectionProductId);
            }
        }
        return inspectionProductByQliProduct;
    }

    private static Id inspectionProductFromProduct(Product2 product) {
        if (product == null || product.InspectionFeeApplicable__c != true) {
            return null;
        }
        return product.InspectionServiceCode__c;
    }

    private static String resolveInspectionLineType(Product2 inspectionProduct) {
        if (inspectionProduct != null &&
            String.isNotBlank(inspectionProduct.ProductType__c) &&
            (inspectionProduct.ProductType__c == LINE_TYPE_SERVICE_CODE ||
                inspectionProduct.ProductType__c == 'Category Code')) {
            return inspectionProduct.ProductType__c;
        }
        return LINE_TYPE_SERVICE_CODE;
    }

    private static String firstNonBlank(String left, String right) {
        return String.isNotBlank(left) ? left : right;
    }

    /**
     * @description Loads the Quote header used when creating inspection-fee lines from a reply.
     * @param quoteId Quote Id
     * @return Matching Quote, or null
     */
    @TestVisible
    private static Quote selectQuoteForReply(Id quoteId) {
        if (quoteId == null) {
            return null;
        }

        List<Quote> quotes = [
            SELECT
                Id,
                Name,
                QuoteNumber,
                Status,
                Pricebook2Id,
                WorkOrder__c
            FROM Quote
            WHERE Id = :quoteId
            WITH SYSTEM_MODE
            LIMIT 1
        ];
        return quotes.isEmpty() ? null : quotes[0];
    }

    /**
     * @description Updates Quote header status from inbound Approve / Reject replies.
     * @param quotes Quote rows to update
     */
    @TestVisible
    private static void updateQuotes(List<Quote> quotes) {
        if (quotes == null || quotes.isEmpty()) {
            return;
        }

        Logger.setScenario('Repair Center Quote Email');
        TriggerHandler.bypass('QuoteTriggerHandler');
        try {
            update quotes;
        } catch (Exception exceptionValue) {
            Logger.error(
                'RepairCenterQuoteEmailService.updateQuotes: ' + exceptionValue.getMessage()
            );
            throw exceptionValue;
        } finally {
            TriggerHandler.clearBypass('QuoteTriggerHandler');
            Logger.saveLog();
        }
    }

    /**
     * @description Thrown when Repair Center quote email send validation fails.
     */
    public class RepairCenterQuoteEmailException extends Exception {
    }
}