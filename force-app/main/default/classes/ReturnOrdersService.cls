/**
 * @description Service class for ReturnOrder business operations.
 *              Entry point for all ReturnOrder-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ReturnOrdersService {
    /** Temporary hardcoded STERIS FedEx account for inbound labels (GW-2793). */
    @TestVisible
    private static final String FEDEX_ACCOUNT_NUMBER = '166134293';

    /** Test-only: force catch paths for coverage. */
    @TestVisible
    private static Boolean simulateGenericException = false;
    @TestVisible
    private static Boolean simulateFedExException = false;

    @TestVisible
    private static void throwIfSimulated() {
        if (Test.isRunningTest() && simulateFedExException) {
            throw new FedExService.FedExServiceException('Simulated FedEx exception for coverage');
        }
        if (Test.isRunningTest() && simulateGenericException) {
            throw new CalloutException('Simulated exception for coverage');
        }
    }


    /**
     * @description Creates new ReturnOrder records with validation.
     * @param returnOrders List of ReturnOrder records to create.
     * @throws ReturnOrdersServiceException when the operation fails.
     */
    public static void createReturnOrders(List<ReturnOrder> returnOrders) {
        if (returnOrders == null || returnOrders.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Management');
        try {
            throwIfSimulated();
            ReturnOrders domain = new ReturnOrders(returnOrders);
            // domain.applyDefaults();
            // domain.validate();
            insert returnOrders;
        } catch (ReturnOrders.ReturnOrdersException e) {
            Logger.error(new LogMessage('ReturnOrdersService.createReturnOrders: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ReturnOrdersService.createReturnOrders: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException('An unexpected error occurred while creating ReturnOrder records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing ReturnOrder records with validation.
     * @param returnOrders List of ReturnOrder records to update.
     * @throws ReturnOrdersServiceException when the operation fails.
     */
    public static void updateReturnOrders(List<ReturnOrder> returnOrders) {
        if (returnOrders == null || returnOrders.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Management');
        try {
            throwIfSimulated();
            ReturnOrders domain = new ReturnOrders(returnOrders);
            // domain.validate();
            update returnOrders;
        } catch (ReturnOrders.ReturnOrdersException e) {
            Logger.error(new LogMessage('ReturnOrdersService.updateReturnOrders: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ReturnOrdersService.updateReturnOrders: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException('An unexpected error occurred while updating ReturnOrder records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes ReturnOrder records by their Ids.
     * @param returnOrderIds Set of ReturnOrder Ids to delete.
     * @throws ReturnOrdersServiceException when the operation fails.
     */
    public static void deleteReturnOrders(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Return Order Management');
        try {
            throwIfSimulated();
            List<ReturnOrder> returnOrderList = ReturnOrdersSelector.selectById(returnOrderIds);
            if (returnOrderList.isEmpty()) {
                return;
            }
            delete returnOrderList;
        } catch (Exception e) {
            Logger.error('ReturnOrdersService.deleteReturnOrders: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException('An unexpected error occurred while deleting ReturnOrder records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves ReturnOrder records by their Ids.
     * @param returnOrderIds Set of ReturnOrder Ids to retrieve.
     * @return List of ReturnOrder records.
     * @throws ReturnOrdersServiceException when the operation fails.
     */
    public static List<ReturnOrder> getReturnOrdersById(Set<Id> returnOrderIds) {
        if (returnOrderIds == null || returnOrderIds.isEmpty()) {
            return new List<ReturnOrder>();
        }
        try {
            throwIfSimulated();
            return ReturnOrdersSelector.selectById(returnOrderIds);
        } catch (Exception e) {
            Logger.error('ReturnOrdersService.getReturnOrdersById: Unexpected error.', e);
            Logger.saveLog();
            throw new ReturnOrdersServiceException('An unexpected error occurred while retrieving ReturnOrder records.', e);
        }
    }

    /**
     * @description GW-2793 - Requests an inbound FedEx shipping label for one Return Order via
     *              FedExService, writes InboundTrackingNumber__c, and attaches the label PDF.
     * @param returnOrderId Return Order Id
     * @throws ReturnOrdersServiceException when validation, callout, or persistence fails
     */
    public static void requestInboundShippingLabel(Id returnOrderId) {
        if (returnOrderId == null) {
            throw new ReturnOrdersServiceException('Return Order Id is required.');
        }

        Logger.setScenario('FedEx Inbound Label');
        try {
            throwIfSimulated();
            List<ReturnOrder> returnOrders =
                ReturnOrdersSelector.selectForInboundShippingLabel(returnOrderId);
            if (returnOrders.isEmpty()) {
                throw new ReturnOrdersServiceException('Return Order was not found.');
            }
            ReturnOrder returnOrderRecord = returnOrders[0];

            ResolvedAddress customerAddress = resolveSelectedShippingAddress(returnOrderRecord);
            ResolvedAddress labAddress = resolveRepairCenterAddress(
                returnOrderRecord.DestinationLocationId
            );
            validateInboundAddresses(returnOrderRecord, customerAddress, labAddress);

            String restBody = JSON.serialize(
                buildInboundShippingRequest(returnOrderRecord, customerAddress, labAddress)
            );
            FedExService.TrackingResponseDTO response = FedExService.requestShippingLabel(restBody);
            if (response == null || String.isBlank(response.trackingNumber)) {
                throw new ReturnOrdersServiceException(
                    'FedEx did not return a tracking number for Return Order ' +
                    returnOrderDisplayNumber(returnOrderRecord.ReturnOrderNumber) +
                    '.'
                );
            }

            updateReturnOrders(
                new List<ReturnOrder>{
                    new ReturnOrder(
                        Id = returnOrderRecord.Id,
                        InboundTrackingNumber__c = response.trackingNumber
                    )
                }
            );

            if (response.shippingLabel != null) {
                String fileBaseName = shippingFileBaseName(returnOrderRecord.ReturnOrderNumber);
                ContentVersion labelFile = new ContentVersion();
                labelFile.Title = fileBaseName;
                labelFile.PathOnClient = fileBaseName + '.pdf';
                labelFile.VersionData = response.shippingLabel;
                labelFile.FirstPublishLocationId = returnOrderRecord.Id;
                ContentVersionsService.createContentVersions(new List<ContentVersion>{ labelFile });
            }
        } catch (ReturnOrdersServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.requestInboundShippingLabel failed for {0}: {1}',
                    returnOrderId,
                    e.getMessage()
                ),
                e
            );
            throw e;
        } catch (FedExService.FedExServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.requestInboundShippingLabel FedEx error for {0}: {1}',
                    returnOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new ReturnOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.requestInboundShippingLabel unexpected error for {0}: {1}',
                    returnOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new ReturnOrdersServiceException(
                'An unexpected error occurred while requesting an inbound FedEx shipping label. ' +
                    e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Request body for Shout Out FEDEX_LABEL (GW-2793 / same shape as vendor).
     */
    @TestVisible
    private class InboundShippingRequestDTO {
        public String FedExAccount;
        public String CustomerDisplay;
        public String ShippingMethod;
        public String ContactName;
        public String CustomerReference;
        public String CustomerPo;
        public String AddressLine1;
        public String AddressLine2;
        public String City;
        public String State;
        public String PostalCode;
        public String Country;
        public String ReturnAddressLine1;
        public String ReturnAddressLine2;
        public String ReturnCity;
        public String ReturnState;
        public String ReturnPostalCode;
        public String ReturnCountryCode;
    }

    @TestVisible
    private class ResolvedAddress {
        public String line1;
        public String line2;
        public String city;
        public String stateCode;
        public String postalCode;
        public String countryCode;
    }

    @TestVisible
    private static InboundShippingRequestDTO buildInboundShippingRequest(
        ReturnOrder returnOrderRecord,
        ResolvedAddress customerAddress,
        ResolvedAddress labAddress
    ) {
        InboundShippingRequestDTO request = new InboundShippingRequestDTO();
        request.FedExAccount = FEDEX_ACCOUNT_NUMBER;
        request.CustomerDisplay = returnOrderRecord.Account == null
            ? null
            : returnOrderRecord.Account.Name;
        request.ShippingMethod = FedExService.getShippingMethod(returnOrderRecord.AccountId);
        request.ContactName = resolveContactName(returnOrderRecord);
        request.CustomerReference = returnOrderDisplayNumber(returnOrderRecord.ReturnOrderNumber);
        request.CustomerPo = String.isNotBlank(returnOrderRecord.CustomerPO__c)
            ? returnOrderRecord.CustomerPO__c
            : '-';
        // Destination = STERIS lab
        request.AddressLine1 = labAddress.line1;
        request.AddressLine2 = labAddress.line2;
        request.City = labAddress.city;
        request.State = labAddress.stateCode;
        request.PostalCode = labAddress.postalCode;
        request.Country = labAddress.countryCode;
        // Origin / return = customer ship-to
        request.ReturnAddressLine1 = customerAddress.line1;
        request.ReturnAddressLine2 = customerAddress.line2;
        request.ReturnCity = customerAddress.city;
        request.ReturnState = customerAddress.stateCode;
        request.ReturnPostalCode = customerAddress.postalCode;
        request.ReturnCountryCode = customerAddress.countryCode;
        return request;
    }

    private static String resolveContactName(ReturnOrder returnOrderRecord) {
        if (returnOrderRecord.Contact != null &&
            String.isNotBlank(returnOrderRecord.Contact.Name)) {
            return returnOrderRecord.Contact.Name;
        }
        return UserInfo.getName();
    }

    private static void validateInboundAddresses(
        ReturnOrder returnOrderRecord,
        ResolvedAddress customerAddress,
        ResolvedAddress labAddress
    ) {
        if (customerAddress == null || String.isBlank(customerAddress.line1)) {
            throw new ReturnOrdersServiceException(
                'Return Order ' +
                    returnOrderDisplayNumber(returnOrderRecord.ReturnOrderNumber) +
                    ' does not have a selected shipping address.'
            );
        }
        if (labAddress == null || String.isBlank(labAddress.line1)) {
            throw new ReturnOrdersServiceException(
                'Repair Center on Return Order ' +
                    returnOrderDisplayNumber(returnOrderRecord.ReturnOrderNumber) +
                    ' does not have a visitor address.'
            );
        }
    }

    /**
     * @description FedEx return/origin address is the Ship-To the user selected on the Return Order.
     *              Create Return Order copies that Address account onto ShipToAddress__*.
     * @param returnOrderRecord Return Order already loaded with ShipToAddress compound fields
     * @return Resolved street, city, state, postal code, and country. Line 1 is blank when no street.
     */
    private static ResolvedAddress resolveSelectedShippingAddress(ReturnOrder returnOrderRecord) {
        if (returnOrderRecord == null) {
            return null;
        }

        ResolvedAddress resolved = new ResolvedAddress();
        List<String> streetLines = splitStreet(returnOrderRecord.ShipToAddress__Street__s);
        resolved.line1 = streetLines[0];
        resolved.line2 = streetLines[1];
        resolved.city = returnOrderRecord.ShipToAddress__City__s;
        resolved.stateCode = returnOrderRecord.ShipToAddress__StateCode__s;
        resolved.postalCode = returnOrderRecord.ShipToAddress__PostalCode__s;
        resolved.countryCode = returnOrderRecord.ShipToAddress__CountryCode__s;
        return resolved;
    }

    /**
     * @description Temporary sprint rule: lab / destination address comes from
     *              Location.VisitorAddressId (Repair Center on the Return Order).
     */
    private static ResolvedAddress resolveRepairCenterAddress(Id locationId) {
        if (locationId == null) {
            return null;
        }

        List<Schema.Location> locations = [
            SELECT Id, VisitorAddressId
            FROM Location
            WHERE Id = :locationId
            LIMIT 1
        ];
        if (locations.isEmpty() || locations[0].VisitorAddressId == null) {
            return null;
        }

        Id visitorAddressId = locations[0].VisitorAddressId;
        List<SObject> visitorAddresses = [
            SELECT Id, ParentId, Street, City, State, StateCode, Country, CountryCode, PostalCode
            FROM Address
            WHERE Id = :visitorAddressId
            LIMIT 1
        ];
        return visitorAddresses.isEmpty() ? null : toResolvedAddress(visitorAddresses[0]);
    }

    private static ResolvedAddress toResolvedAddress(SObject addressRecord) {
        ResolvedAddress resolved = new ResolvedAddress();
        List<String> streetLines = splitStreet((String) addressRecord.get('Street'));
        resolved.line1 = streetLines[0];
        resolved.line2 = streetLines[1];
        resolved.city = (String) addressRecord.get('City');
        String stateCode = (String) addressRecord.get('StateCode');
        resolved.stateCode = String.isNotBlank(stateCode)
            ? stateCode
            : toCode((String) addressRecord.get('State'));
        resolved.postalCode = (String) addressRecord.get('PostalCode');
        String countryCode = (String) addressRecord.get('CountryCode');
        resolved.countryCode = String.isNotBlank(countryCode)
            ? countryCode
            : toCountryCode((String) addressRecord.get('Country'));
        return resolved;
    }

    private static List<String> splitStreet(String street) {
        if (String.isBlank(street)) {
            return new List<String>{ null, null };
        }
        List<String> lines = street.split('\\r?\\n', 2);
        String line1 = lines[0].trim();
        String line2 = lines.size() > 1 ? lines[1].replace('\n', ' ').trim() : null;
        if (String.isBlank(line2)) {
            line2 = null;
        }
        return new List<String>{ line1, line2 };
    }

    private static String toCode(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.length() <= 3 ? trimmed.toUpperCase() : trimmed;
    }

    @TestVisible
    private static String toCountryCode(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        String trimmed = value.trim();
        if (trimmed.length() == 2) {
            return trimmed.toUpperCase();
        }
        if (trimmed.equalsIgnoreCase('United States') || trimmed.equalsIgnoreCase('USA')) {
            return 'US';
        }
        return trimmed;
    }

    private static String shippingFileBaseName(String returnOrderNumber) {
        return 'Shipping Label ' + returnOrderDisplayNumber(returnOrderNumber);
    }

    @TestVisible
    private static String returnOrderDisplayNumber(String returnOrderNumber) {
        if (String.isBlank(returnOrderNumber)) {
            return 'RO';
        }
        return returnOrderNumber.startsWith('RO-')
            ? returnOrderNumber
            : 'RO-' + returnOrderNumber;
    }

    // ── GW-1347 RO Form PDF ───────────────────────────────────────────────────

    private static final String RO_FORM_TEMPLATE_TITLE = 'Return Order North America Template';
    private static final String COMBINED_FILE_PREFIX = 'RO Form and Shipping Label ';
    private static final String RO_FORM_STATIC_RESOURCE_LOGO = 'company_logo';
    private static final String RO_FORM_STATIC_RESOURCE_CHECKBOX = 'checkbox_checked';
    private static final String RO_FORM_DISINFECTED_NO = 'No, Item is not Disinfected';
    private static final String RO_FORM_DISINFECTED_NO_LEGACY =
        'No, items has not been cleaned and disinfected or Sterilized';
    private static final Set<String> RO_FORM_DISINFECTED_NO_VALUES = new Set<String>{
        RO_FORM_DISINFECTED_NO,
        RO_FORM_DISINFECTED_NO_LEGACY
    };
    private static final String RO_FORM_CHECKED_IMG_HTML =
        '<img src="{!checkboxCheckedUrl}" alt="Checked" width="26" height="26" '
        + 'style="border:0;display:block;"/>';
    private static final List<String> CODE128_PATTERNS = new List<String>{
        '212222','222122','222221','121223','121322','131222','122213','122312','132212','221213',
        '221312','231212','112232','122132','122231','113222','123122','123221','223211','221132',
        '221231','213212','223112','312131','311222','321122','321221','312212','322112','322211',
        '212123','212321','232121','111323','131123','131321','112313','132113','132311','211313',
        '231113','231311','112133','112331','132131','113123','113321','133121','313121','211331',
        '231131','213113','213311','213131','311123','311321','331121','312113','312311','332111',
        '314111','221411','431111','111224','111422','121124','121421','141122','141221','112214',
        '112412','122114','122411','142112','142211','241211','221114','413111','241112','134111',
        '111242','121142','121241','114212','124112','124211','411212','421112','421211','212141',
        '214121','412121','111143','111341','131141','114113','114311','411113','411311','113141',
        '114131','311141','411131','211412','211214','211232','233111'
    };
    private static final Integer CODE128_START_B = 104;
    private static final Integer CODE128_STOP = 106;

    /**
     * @description GW-1347 - Builds the RO Form PDF and attaches it to the Return Order.
     *              File name: "RO Form RO-<number>.pdf".
     * @param returnOrderId Return Order Id
     * @return Id of the created ContentVersion
     * @throws ReturnOrdersServiceException when validation or persistence fails
     */
    public static Id saveRoFormPdf(Id returnOrderId) {
        Logger.setScenario('RO Form Attach');
        try {
            throwIfSimulated();
            if (returnOrderId == null) {
                throw new ReturnOrdersServiceException('Return Order Id is required.');
            }

            ReturnOrder returnOrder = selectReturnOrderForPaperwork(returnOrderId);
            if (returnOrder == null) {
                throw new ReturnOrdersServiceException('Return Order was not found.');
            }

            String mergedHtml = buildMergedPaperworkHtml(returnOrderId);
            Blob pdfBlob = Blob.toPdf(mergedHtml);

            String fileBaseName = roFormFileBaseName(returnOrder.ReturnOrderNumber);
            ContentVersion formFile = new ContentVersion();
            formFile.Title = fileBaseName;
            formFile.PathOnClient = fileBaseName + '.pdf';
            formFile.VersionData = pdfBlob;
            formFile.FirstPublishLocationId = returnOrder.Id;

            List<ContentVersion> created =
                ContentVersionsService.createContentVersions(new List<ContentVersion>{ formFile });
            if (created == null || created.isEmpty() || created[0].Id == null) {
                throw new ReturnOrdersServiceException(
                    'Unable to save RO Form PDF to the Return Order.'
                );
            }
            return created[0].Id;
        } catch (ReturnOrdersServiceException e) {
            Logger.warn(
                new LogMessage(
                    'ReturnOrdersService.saveRoFormPdf validation: {0}',
                    e.getMessage()
                )
            );
            throw e;
        } catch (ContentVersionsService.ContentVersionsServiceException e) {
            Logger.error('ReturnOrdersService.saveRoFormPdf ContentVersion failed', e);
            throw new ReturnOrdersServiceException(
                'Unable to save RO Form PDF: ' + e.getMessage(),
                e
            );
        } catch (Exception e) {
            Logger.error('ReturnOrdersService.saveRoFormPdf failed', e);
            throw new ReturnOrdersServiceException(
                'Unable to save RO Form PDF: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-1347 - Builds merged HTML for the RO Form PDF (Blob.toPdf in saveRoFormPdf).
     * @param returnOrderId Return Order Id
     * @return Merged HTML string ready for PDF rendering
     */
    @TestVisible
    private static String buildMergedPaperworkHtml(Id returnOrderId) {
        if (returnOrderId == null) {
            throw new ReturnOrdersServiceException('Return Order Id is required.');
        }
        ReturnOrder returnOrder = selectReturnOrderForPaperwork(returnOrderId);
        if (returnOrder == null) {
            throw new ReturnOrdersServiceException('Return Order was not found.');
        }
        List<ReturnOrderLineItem> lineItems = selectLineItemsForPaperwork(returnOrderId);
        ContentVersion templateVersion = selectRoFormTemplateVersion();
        if (templateVersion == null || templateVersion.VersionData == null) {
            throw new ReturnOrdersServiceException(
                'RO form template was not found. Upload a File titled "'
                + RO_FORM_TEMPLATE_TITLE
                + '".'
            );
        }
        return buildMergedRoFormHtml(
            templateVersion.VersionData.toString(),
            returnOrder,
            lineItems,
            buildCode128BarcodeHtml(String.valueOf(returnOrder.Id))
        );
    }

    @TestVisible
    private static String roFormFileBaseName(String returnOrderNumber) {
        return 'RO Form ' + returnOrderDisplayNumber(returnOrderNumber);
    }

    private static String buildMergedRoFormHtml(
        String templateHtml,
        ReturnOrder returnOrder,
        List<ReturnOrderLineItem> lineItems,
        String barcodeMarkup
    ) {
        String logoUrl = buildStaticResourceUrl(RO_FORM_STATIC_RESOURCE_LOGO);
        String checkboxUrl = buildStaticResourceUrl(RO_FORM_STATIC_RESOURCE_CHECKBOX);
        Boolean anyNotDisinfected = hasAnyNotDisinfected(lineItems);
        String checkedImg = RO_FORM_CHECKED_IMG_HTML.replace(
            '{!checkboxCheckedUrl}',
            escapeHtml(checkboxUrl)
        );

        Map<String, String> tokens = new Map<String, String>();
        tokens.put('logoUrl', logoUrl);
        tokens.put('checkboxCheckedUrl', checkboxUrl);
        tokens.put('barcodeMarkup', barcodeMarkup);
        tokens.put('barcodeUrl', '');
        tokens.put('srnNumber', nullToEmpty(returnOrder.ReturnOrderNumber));
        tokens.put('accountManager', buildPaperworkAccountManager(returnOrder));
        tokens.put('estimateRequiredLabel', nullToEmpty(returnOrder.EstimateRequired__c));
        tokens.put('dateGenerated', Date.today().format());
        tokens.put('vendorLab', nullToEmpty(returnOrder.DestinationLocation?.Name));
        tokens.put(
            'vendorAddress',
            nullToEmpty(resolvePaperworkLocationAddress(returnOrder.DestinationLocationId))
        );
        tokens.put('returnAddressLine1', nullToEmpty(returnOrder.Account?.Name));
        tokens.put('returnAddressLine2', buildSelectedShippingAddressHtml(returnOrder));
        tokens.put('customerDisplay', buildPaperworkCustomerDisplay(returnOrder));
        tokens.put('poNumber', nullToEmpty(returnOrder.CustomerPO__c));
        // TODO GW-1347: no clear Customer Care / division field on Return Order
        tokens.put('customerCare', '');
        tokens.put('orderType', nullToEmpty(returnOrder.ReturnOrderType__c));
        tokens.put('department', resolvePaperworkDepartment(lineItems));
        tokens.put('contactName', resolvePaperworkContactName(returnOrder, lineItems));
        tokens.put('customerReference', nullToEmpty(returnOrder.CustomerReference__c));
        tokens.put('reprocessHasBeenContent', anyNotDisinfected ? '&nbsp;' : checkedImg);
        tokens.put('reprocessHasNotBeenContent', anyNotDisinfected ? checkedImg : '&nbsp;');
        tokens.put('repairItemRows', buildRepairItemRowsHtml(lineItems));
        tokens.put('createdByName', resolvePaperworkCreatedByName(returnOrder));
        tokens.put('creationSource', nullToEmpty(returnOrder.CreationSource__c));
        tokens.put(
            'createdDateTime',
            returnOrder.CreatedDate == null ? '' : returnOrder.CreatedDate.format()
        );
        tokens.put('copyrightYear', String.valueOf(Date.today().year()));

        String merged = templateHtml;
        for (String tokenName : tokens.keySet()) {
            merged = merged.replace('{!' + tokenName + '}', nullToEmpty(tokens.get(tokenName)));
        }
        return merged;
    }

    private static Boolean hasAnyNotDisinfected(List<ReturnOrderLineItem> lineItems) {
        if (lineItems == null) {
            return false;
        }
        for (ReturnOrderLineItem lineItem : lineItems) {
            if (RO_FORM_DISINFECTED_NO_VALUES.contains(lineItem.Disinfected__c)) {
                return true;
            }
        }
        return false;
    }

    private static String buildRepairItemRowsHtml(List<ReturnOrderLineItem> lineItems) {
        if (lineItems == null || lineItems.isEmpty()) {
            return '';
        }
        List<String> rows = new List<String>();
        Integer lineNumber = 1;
        for (ReturnOrderLineItem lineItem : lineItems) {
            String serialNumber = nullToEmpty(lineItem.SerialNumber__c);
            String typeManufacturer = buildTypeManufacturer(lineItem);
            String model = firstNonBlank(lineItem.Model__c, lineItem.Product2?.Model__c);
            Decimal quantity = lineItem.QuantityReturned != null
                ? lineItem.QuantityReturned
                : lineItem.QuantityExpected;
            String qtyText = quantity == null ? '' : String.valueOf(quantity.intValue());
            String problem = nullToEmpty(lineItem.ReportedProblem__c);

            rows.add(
                '<tr>'
                + '<td align="center" style="font-size:10px;vertical-align:top;">'
                + escapeHtml(String.valueOf(lineNumber))
                + '</td>'
                + '<td style="font-size:10px;vertical-align:top;">'
                + escapeHtml(nullToEmpty(serialNumber))
                + '</td>'
                + '<td style="font-size:10px;vertical-align:top;">'
                + escapeHtml(typeManufacturer)
                + '</td>'
                + '<td style="font-size:10px;vertical-align:top;">'
                + escapeHtml(nullToEmpty(model))
                + '</td>'
                + '<td align="center" style="font-size:10px;vertical-align:top;">'
                + escapeHtml(qtyText)
                + '</td>'
                + '<td style="font-size:10px;vertical-align:top;">'
                + escapeHtml(problem)
                + '</td>'
                + '</tr>'
            );
            lineNumber++;
        }
        return String.join(rows, '');
    }

    private static String buildTypeManufacturer(ReturnOrderLineItem lineItem) {
        String productName = lineItem.Product2?.Name;
        String manufacturer = lineItem.Product2?.Manufacturer__c;
        if (String.isNotBlank(productName) && String.isNotBlank(manufacturer)) {
            return productName + ' / ' + manufacturer;
        }
        if (String.isNotBlank(productName)) {
            return productName;
        }
        if (String.isNotBlank(manufacturer)) {
            return manufacturer;
        }
        return nullToEmpty(lineItem.ItemDescription__c);
    }

    private static String buildPaperworkAccountManager(ReturnOrder returnOrder) {
        if (returnOrder.SalesRep__r == null) {
            return '';
        }
        List<String> parts = new List<String>();
        if (String.isNotBlank(returnOrder.SalesRep__r.EmployeeNumber)) {
            parts.add(returnOrder.SalesRep__r.EmployeeNumber);
        }
        if (String.isNotBlank(returnOrder.SalesRep__r.Name)) {
            parts.add(returnOrder.SalesRep__r.Name);
        }
        return String.join(parts, ' ');
    }

    private static String buildPaperworkCustomerDisplay(ReturnOrder returnOrder) {
        if (returnOrder.Account == null) {
            return '';
        }
        String accountNumber = returnOrder.Account.AccountNumber;
        String name = returnOrder.Account.Name;
        if (String.isNotBlank(accountNumber) && String.isNotBlank(name)) {
            return '#' + accountNumber + ' ' + name;
        }
        if (String.isNotBlank(name)) {
            return name;
        }
        return String.isBlank(accountNumber) ? '' : '#' + accountNumber;
    }

    /**
     * @description Return Address on the RO form. Uses the Ship-To the user selected.
     * @param returnOrder Return Order loaded with ShipToAddress compound fields
     * @return HTML address lines, or blank when no selected shipping address is stored
     */
    private static String buildSelectedShippingAddressHtml(ReturnOrder returnOrder) {
        List<String> lines = new List<String>();
        if (String.isNotBlank(returnOrder.ShipToAddress__Street__s)) {
            lines.add(escapeHtml(returnOrder.ShipToAddress__Street__s).replace('\n', '<br/>'));
        }
        List<String> cityStateZip = new List<String>();
        if (String.isNotBlank(returnOrder.ShipToAddress__City__s)) {
            cityStateZip.add(returnOrder.ShipToAddress__City__s);
        }
        if (String.isNotBlank(returnOrder.ShipToAddress__StateCode__s)) {
            cityStateZip.add(returnOrder.ShipToAddress__StateCode__s);
        }
        if (String.isNotBlank(returnOrder.ShipToAddress__PostalCode__s)) {
            cityStateZip.add(returnOrder.ShipToAddress__PostalCode__s);
        }
        if (!cityStateZip.isEmpty()) {
            lines.add(escapeHtml(String.join(cityStateZip, ' ')));
        }
        if (String.isNotBlank(returnOrder.ShipToAddress__CountryCode__s)) {
            lines.add(escapeHtml(returnOrder.ShipToAddress__CountryCode__s));
        }
        return String.join(lines, '<br/>');
    }

    private static String resolvePaperworkDepartment(List<ReturnOrderLineItem> lineItems) {
        if (lineItems == null) {
            return '';
        }
        for (ReturnOrderLineItem lineItem : lineItems) {
            if (lineItem.Department__r != null && String.isNotBlank(lineItem.Department__r.Name)) {
                return lineItem.Department__r.Name;
            }
        }
        return '';
    }

    private static String resolvePaperworkContactName(
        ReturnOrder returnOrder,
        List<ReturnOrderLineItem> lineItems
    ) {
        if (returnOrder.Contact != null && String.isNotBlank(returnOrder.Contact.Name)) {
            return returnOrder.Contact.Name;
        }
        if (lineItems != null) {
            for (ReturnOrderLineItem lineItem : lineItems) {
                if (lineItem.Contact__r != null && String.isNotBlank(lineItem.Contact__r.Name)) {
                    return lineItem.Contact__r.Name;
                }
            }
        }
        return '';
    }

    private static String resolvePaperworkCreatedByName(ReturnOrder returnOrder) {
        if (
            returnOrder.CreatedByContact__r != null
            && String.isNotBlank(returnOrder.CreatedByContact__r.Name)
        ) {
            return returnOrder.CreatedByContact__r.Name;
        }
        return nullToEmpty(returnOrder.CreatedBy?.Name);
    }

    private static String resolvePaperworkLocationAddress(Id locationId) {
        if (locationId == null) {
            return '';
        }
        List<Schema.Location> locations = [
            SELECT VisitorAddressId
            FROM Location
            WHERE Id = :locationId
            WITH USER_MODE
            LIMIT 1
        ];
        if (locations.isEmpty() || locations[0].VisitorAddressId == null) {
            return '';
        }

        Id visitorAddressId = locations[0].VisitorAddressId;
        List<SObject> visitorAddresses = Database.query(
            'SELECT AddressShipTo__c, Street, City, State, PostalCode, Country '
            + 'FROM Address '
            + 'WHERE Id = :visitorAddressId '
            + 'WITH USER_MODE '
            + 'LIMIT 1'
        );
        if (visitorAddresses.isEmpty()) {
            return '';
        }

        SObject visitorAddress = visitorAddresses[0];
        String formattedShipTo = (String) visitorAddress.get('AddressShipTo__c');
        if (String.isNotBlank(formattedShipTo)) {
            return escapeHtml(formattedShipTo).replace('\n', '<br/>');
        }
        return formatAddressHtml(
            (String) visitorAddress.get('Street'),
            (String) visitorAddress.get('City'),
            (String) visitorAddress.get('State'),
            (String) visitorAddress.get('PostalCode'),
            (String) visitorAddress.get('Country')
        );
    }

    private static String formatAddressHtml(
        String street,
        String city,
        String state,
        String postalCode,
        String country
    ) {
        List<String> lines = new List<String>();
        if (String.isNotBlank(street)) {
            lines.add(escapeHtml(street).replace('\n', '<br/>'));
        }
        List<String> cityLine = new List<String>();
        if (String.isNotBlank(city)) {
            cityLine.add(city);
        }
        if (String.isNotBlank(state)) {
            cityLine.add(state);
        }
        if (String.isNotBlank(postalCode)) {
            cityLine.add(postalCode);
        }
        if (!cityLine.isEmpty()) {
            lines.add(escapeHtml(String.join(cityLine, ' ')));
        }
        if (String.isNotBlank(country)) {
            lines.add(escapeHtml(country));
        }
        return String.join(lines, '<br/>');
    }

    private static String buildStaticResourceUrl(String resourceName) {
        return '/resource/' + resourceName;
    }

    /**
     * @description Builds a scannable CODE128 barcode as nested HTML tables for Blob.toPdf.
     * @param value Text to encode (Return Order Id for GW-1347)
     * @return HTML markup replacing the template barcode image
     */
    @TestVisible
    private static String buildCode128BarcodeHtml(String value) {
        if (String.isBlank(value)) {
            return '&nbsp;';
        }
        List<Integer> codes = new List<Integer>();
        codes.add(CODE128_START_B);
        Integer checksum = CODE128_START_B;
        Integer position = 1;
        for (Integer i = 0; i < value.length(); i++) {
            Integer codePoint = value.charAt(i) - 32;
            if (codePoint < 0 || codePoint > 94) {
                codePoint = '?'.charAt(0) - 32;
            }
            codes.add(codePoint);
            checksum += codePoint * position;
            position++;
        }
        codes.add(Math.mod(checksum, 103));
        codes.add(CODE128_STOP);

        List<String> cells = new List<String>();
        Boolean isBar = true;
        for (Integer codeValue : codes) {
            String pattern = CODE128_PATTERNS[codeValue];
            for (Integer p = 0; p < pattern.length(); p++) {
                Integer width = Integer.valueOf(pattern.substring(p, p + 1));
                String bg = isBar ? '#000000' : '#ffffff';
                cells.add(
                    '<td width="'
                    + String.valueOf(width)
                    + '" height="48" bgcolor="'
                    + bg
                    + '" style="font-size:1px;line-height:1px;">&nbsp;</td>'
                );
                isBar = !isBar;
            }
        }
        cells.add(
            '<td width="2" height="48" bgcolor="#000000" style="font-size:1px;line-height:1px;">&nbsp;</td>'
        );

        return '<table cellpadding="0" cellspacing="0" border="0" style="border-collapse:collapse;margin:0 0 0 -12px;">'
            + '<tr>'
            + String.join(cells, '')
            + '</tr></table>';
    }

    private static String nullToEmpty(String value) {
        return value == null ? '' : value;
    }

    private static String firstNonBlank(String first, String second) {
        if (String.isNotBlank(first)) {
            return first;
        }
        return second;
    }

    private static String escapeHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value
            .replace('&', '&amp;')
            .replace('<', '&lt;')
            .replace('>', '&gt;')
            .replace('"', '&quot;')
            .replace('\'', '&#39;');
    }

    private static ReturnOrder selectReturnOrderForPaperwork(Id returnOrderId) {
        List<ReturnOrder> rows = [
            SELECT
                Id,
                ReturnOrderNumber,
                EstimateRequired__c,
                CustomerPO__c,
                CustomerReference__c,
                ReturnOrderType__c,
                CreationSource__c,
                CreatedDate,
                ShipToAddress__Street__s,
                ShipToAddress__City__s,
                ShipToAddress__StateCode__s,
                ShipToAddress__PostalCode__s,
                ShipToAddress__CountryCode__s,
                DestinationLocationId,
                DestinationLocation.Name,
                AccountId,
                Account.Name,
                Account.AccountNumber,
                ContactId,
                Contact.Name,
                SalesRep__c,
                SalesRep__r.Name,
                SalesRep__r.EmployeeNumber,
                CreatedById,
                CreatedBy.Name,
                CreatedByContact__c,
                CreatedByContact__r.Name
            FROM ReturnOrder
            WHERE Id = :returnOrderId
            WITH USER_MODE
            LIMIT 1
        ];
        return rows.isEmpty() ? null : rows[0];
    }

    private static List<ReturnOrderLineItem> selectLineItemsForPaperwork(Id returnOrderId) {
        return [
            SELECT
                Id,
                ReturnOrderLineItemNumber,
                SerialNumber__c,
                Model__c,
                ItemDescription__c,
                QuantityReturned,
                QuantityExpected,
                ReportedProblem__c,
                Disinfected__c,
                Product2Id,
                Product2.Name,
                Product2.Manufacturer__c,
                Product2.Model__c,
                Department__c,
                Department__r.Name,
                Contact__c,
                Contact__r.Name
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId = :returnOrderId
            WITH USER_MODE
            ORDER BY CreatedDate ASC, ReturnOrderLineItemNumber ASC
        ];
    }

    private static ContentVersion selectRoFormTemplateVersion() {
        List<ContentVersion> versions = [
            SELECT Id, Title, VersionData
            FROM ContentVersion
            WHERE Title = :RO_FORM_TEMPLATE_TITLE AND IsLatest = TRUE
            WITH USER_MODE
            ORDER BY LastModifiedDate DESC
            LIMIT 1
        ];
        return versions.isEmpty() ? null : versions[0];
    }

    // ── GW-1347 Create RO paperwork orchestration ─────────────────────────────

    /**
     * @description Per-Return-Order paperwork outcome for the Create RO wizard.
     */
    public class PaperworkResult {
        @AuraEnabled public Id returnOrderId;
        @AuraEnabled public String returnOrderNumber;
        @AuraEnabled public Boolean shippingLabelCreated;
        @AuraEnabled public String shippingLabelError;
        @AuraEnabled public Boolean roFormCreated;
        @AuraEnabled public String roFormError;
        @AuraEnabled public String roFormBase64;
        @AuraEnabled public String shippingLabelBase64;
        @AuraEnabled public String combinedFileTitle;
    }

    /**
     * @description GW-1347 - Generates shipping label (best effort) and RO Form for one Return Order.
     *              Call once per RO from LWC so each transaction can perform a FedEx callout.
     * @param returnOrderId Return Order Id
     * @return PaperworkResult with success flags, errors, and PDF base64 when files exist
     */
    @AuraEnabled
    public static PaperworkResult generatePaperworkForReturnOrder(Id returnOrderId) {
        if (returnOrderId == null) {
            throw new AuraHandledException('Return Order Id is required.');
        }

        Logger.setScenario('RO Creation Paperwork');
        PaperworkResult result = new PaperworkResult();
        result.returnOrderId = returnOrderId;
        result.shippingLabelCreated = false;
        result.roFormCreated = false;

        try {
            throwIfSimulated();
            List<ReturnOrder> returnOrders = [
                SELECT Id, ReturnOrderNumber
                FROM ReturnOrder
                WHERE Id = :returnOrderId
                WITH USER_MODE
                LIMIT 1
            ];
            if (returnOrders.isEmpty()) {
                throw new AuraHandledException('Return Order was not found.');
            }
            result.returnOrderNumber = returnOrders[0].ReturnOrderNumber;
            result.combinedFileTitle = combinedPaperworkFileBaseName(result.returnOrderNumber);

            try {
                throwIfSimulated();
                requestInboundShippingLabel(returnOrderId);
                result.shippingLabelCreated = true;
            } catch (ReturnOrdersServiceException e) {
                result.shippingLabelError = e.getMessage();
                Logger.warn(
                    new LogMessage(
                        'ReturnOrdersService.generatePaperworkForReturnOrder shipping label failed for {0}: {1}',
                        returnOrderId,
                        e.getMessage()
                    )
                );
            } catch (Exception e) {
                result.shippingLabelError = e.getMessage();
                Logger.error(
                    new LogMessage(
                        'ReturnOrdersService.generatePaperworkForReturnOrder shipping label unexpected for {0}: {1}',
                        returnOrderId,
                        e.getMessage()
                    ),
                    e
                );
            }

            try {
                throwIfSimulated();
                saveRoFormPdf(returnOrderId);
                result.roFormCreated = true;
            } catch (ReturnOrdersServiceException e) {
                result.roFormError = e.getMessage();
                Logger.warn(
                    new LogMessage(
                        'ReturnOrdersService.generatePaperworkForReturnOrder RO Form failed for {0}: {1}',
                        returnOrderId,
                        e.getMessage()
                    )
                );
            } catch (Exception e) {
                result.roFormError = e.getMessage();
                Logger.error(
                    new LogMessage(
                        'ReturnOrdersService.generatePaperworkForReturnOrder RO Form unexpected for {0}: {1}',
                        returnOrderId,
                        e.getMessage()
                    ),
                    e
                );
            }

            if (result.roFormCreated == true) {
                result.roFormBase64 = encodeLatestPaperworkFileBase64(returnOrderId, 'RO Form');
            }
            if (result.shippingLabelCreated == true) {
                result.shippingLabelBase64 = encodeLatestPaperworkFileBase64(returnOrderId, 'Shipping Label');
            }
            return result;
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description GW-1347 - Attaches a client-merged PDF (RO Form + shipping label) to the Return Order.
     * @param returnOrderId Return Order Id
     * @param base64Pdf Base64-encoded combined PDF bytes
     * @param returnOrderNumber Return Order Number for file title (optional)
     * @return Created ContentVersion Id
     */
    @AuraEnabled
    public static Id attachCombinedPdf(Id returnOrderId, String base64Pdf, String returnOrderNumber) {
        if (returnOrderId == null) {
            throw new AuraHandledException('Return Order Id is required.');
        }
        if (String.isBlank(base64Pdf)) {
            throw new AuraHandledException('Combined PDF payload is required.');
        }

        Logger.setScenario('RO Creation Combined PDF');
        try {
            throwIfSimulated();
            String fileBaseName = combinedPaperworkFileBaseName(returnOrderNumber);
            ContentVersion combinedFile = new ContentVersion();
            combinedFile.Title = fileBaseName;
            combinedFile.PathOnClient = fileBaseName + '.pdf';
            combinedFile.VersionData = EncodingUtil.base64Decode(base64Pdf);
            combinedFile.FirstPublishLocationId = returnOrderId;

            List<ContentVersion> created =
                ContentVersionsService.createContentVersions(
                    new List<ContentVersion>{ combinedFile }
                );
            if (created == null || created.isEmpty() || created[0].Id == null) {
                throw new AuraHandledException('Unable to save combined paperwork PDF.');
            }
            return created[0].Id;
        } catch (AuraHandledException e) {
            throw e;
        } catch (ContentVersionsService.ContentVersionsServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.attachCombinedPdf failed for {0}: {1}',
                    returnOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new AuraHandledException('Unable to save combined paperwork PDF: ' + e.getMessage());
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.attachCombinedPdf unexpected for {0}: {1}',
                    returnOrderId,
                    e.getMessage()
                ),
                e
            );
            throw new AuraHandledException('Unable to save combined paperwork PDF: ' + e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    private static String combinedPaperworkFileBaseName(String returnOrderNumber) {
        String displayNumber = 'RO';
        if (String.isNotBlank(returnOrderNumber)) {
            displayNumber = returnOrderNumber.startsWith('RO-')
                ? returnOrderNumber
                : 'RO-' + returnOrderNumber;
        }
        return COMBINED_FILE_PREFIX + displayNumber;
    }

    private static String encodeLatestPaperworkFileBase64(Id returnOrderId, String titleContains) {
        Id contentVersionId = findLatestPaperworkContentVersionId(returnOrderId, titleContains);
        if (contentVersionId == null) {
            return null;
        }
        ContentVersion version = [
            SELECT VersionData
            FROM ContentVersion
            WHERE Id = :contentVersionId
            WITH USER_MODE
            LIMIT 1
        ];
        return EncodingUtil.base64Encode(version.VersionData);
    }

    private static Id findLatestPaperworkContentVersionId(Id returnOrderId, String titleContains) {
        List<ContentDocumentLink> links = [
            SELECT ContentDocumentId
            FROM ContentDocumentLink
            WHERE LinkedEntityId = :returnOrderId
            WITH USER_MODE
        ];
        if (links.isEmpty()) {
            return null;
        }
        Set<Id> documentIds = new Set<Id>();
        for (ContentDocumentLink link : links) {
            documentIds.add(link.ContentDocumentId);
        }
        List<ContentVersion> files = [
            SELECT Id
            FROM ContentVersion
            WHERE ContentDocumentId IN :documentIds
                AND Title LIKE :('%' + titleContains + '%')
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 1
        ];
        return files.isEmpty() ? null : files[0].Id;
    }

    // ── GW-3880 Consolidate Vendor Shipment ────────────────────────────────────

    private static final String VCS_PACKING_SLIP_TEMPLATE_TITLE =
        'Vendor Shipping Change Notification Template';
    private static final String VCS_ROLI_RECORD_TYPE_OUTBOUND = 'Outbound';
    private static final String VCS_RO_STATUS_CREATED = 'Created';
    private static final String VCS_ROLI_STATUS_CREATED = 'Created';
    private static final String VCS_CREATION_SOURCE_SALESFORCE = 'Salesforce';
    private static final String VCS_RO_RECORD_TYPE_VENDOR_RETURN = 'VendorReturn';
    private static final String VCS_ROLI_RECORD_TYPE_INBOUND = 'Inbound';
    private static final String VCS_RO_TYPE_VENDOR = 'Vendor';
    private static final String VCS_ROLI_LINE_TYPE_OUTBOUND = 'Outbound';
    private static final String VCS_ROLI_LINE_TYPE_INBOUND = 'Inbound';
    private static final Integer VCS_CALLOUT_ATTEMPTS = 3;
    private static final Integer VCS_RETRY_PAUSE_MS = 2000;

    @TestVisible
    private static Integer testRemainingVendorCalloutFailures = 0;

    /** Parent RO header fields copied onto the new Vendor Return Order when present. */
    private static final List<String> VCS_PARENT_RO_COPY_FIELDS = new List<String>{
        'HospitalReferencedTrayName__c',
        'EstimateRequired__c',
        'EstimateContact__c',
        'CustomerReference__c',
        'RepairWarranty__c',
        'PreviousReturnOrder__c',
        'WarrantyNotes__c'
    };

    /**
     * @description GW-3880 - Result of vendor consolidation Complete.
     */
    public class VendorConsolidationCompleteResult {
        public List<Id> returnOrderIds;
        public List<String> returnOrderNumbers;
        public Integer workOrderCount;
        public String message;
        public Map<Id, List<Id>> returnOrderIdToWorkOrderIds;
    }

    /**
     * @description Request body serialized to ShoutOut RESTBODY for vendor outbound labels.
     */
    @TestVisible
    private class VendorFedExShipmentRequestDTO {
        public String FedExAccount;
        public String CustomerDisplay;
        public String ShippingMethod;
        public String ContactName;
        public String CustomerReference;
        public String CustomerPo;
        public String AddressLine1;
        public String AddressLine2;
        public String City;
        public String State;
        public String PostalCode;
        public String Country;
        public String ReturnAddressLine1;
        public String ReturnAddressLine2;
        public String ReturnCity;
        public String ReturnState;
        public String ReturnPostalCode;
        public String ReturnCountryCode;
    }

    private class VendorShipmentWork {
        public ReturnOrder returnOrder;
        public List<WorkOrder> workOrders;
        public FedExService.TrackingResponseDTO response;
        public String restBody;
    }

    /**
     * @description GW-3880 - Creates Vendor Return Order(s) for selected work orders and enqueues FedEx.
     * @param workOrderIds Selected Work Order Ids
     * @return Created Return Order context
     */
    public static VendorConsolidationCompleteResult completeVendorShipment(List<Id> workOrderIds) {
        if (workOrderIds == null || workOrderIds.isEmpty()) {
            throw new ReturnOrdersServiceException(
                'Select at least one work order before completing.'
            );
        }

        Logger.setScenario('Consolidate Vendor Shipment');
        try {
            throwIfSimulated();
            Id userRepairCenterId = ServiceResourcesService.getRepairCenterIdForCurrentUser();
            if (userRepairCenterId == null) {
                throw new ReturnOrdersServiceException(
                    'No active Service Resource with a Repair Center was found for your user.'
                );
            }

            List<WorkOrder> workOrders =
                WorkOrdersService.getWorkOrdersForVendorConsolidationComplete(workOrderIds);
            WorkOrdersService.validateWorkOrdersForVendorConsolidation(
                workOrders,
                userRepairCenterId
            );

            Map<Id, ReturnOrder> parentReturnOrdersById = loadParentReturnOrdersForVendorConsolidation(
                workOrders
            );
            Map<Id, List<WorkOrderLineItem>> wolisByWorkOrderId =
                WorkOrdersService.getWorkOrderLineItemsForVendorConsolidation(workOrders);
            Id defaultProductId = resolveDefaultProductIdForVendorConsolidation();

            Id vendorReturnRtId = getRecordTypeId(
                ReturnOrder.SObjectType,
                VCS_RO_RECORD_TYPE_VENDOR_RETURN
            );
            Id outboundRtId = getRecordTypeId(
                ReturnOrderLineItem.SObjectType,
                VCS_ROLI_RECORD_TYPE_OUTBOUND
            );
            Id inboundRtId = getRecordTypeId(
                ReturnOrderLineItem.SObjectType,
                VCS_ROLI_RECORD_TYPE_INBOUND
            );

            Map<Id, List<WorkOrder>> workOrdersByVendor = groupWorkOrdersByVendor(workOrders);
            List<ReturnOrder> returnOrdersToInsert = new List<ReturnOrder>();
            List<Id> vendorKeysInOrder = new List<Id>();

            for (Id vendorId : workOrdersByVendor.keySet()) {
                List<WorkOrder> vendorWos = workOrdersByVendor.get(vendorId);
                returnOrdersToInsert.add(
                    buildVendorReturnOrder(
                        vendorId,
                        vendorWos,
                        userRepairCenterId,
                        vendorReturnRtId,
                        parentReturnOrdersById
                    )
                );
                vendorKeysInOrder.add(vendorId);
            }

            insertViaElevatedAccess(returnOrdersToInsert);

            List<ReturnOrderLineItem> outboundLines = new List<ReturnOrderLineItem>();
            List<WorkOrderLineItem> outboundSourceWolis = new List<WorkOrderLineItem>();

            for (Integer i = 0; i < returnOrdersToInsert.size(); i++) {
                ReturnOrder ro = returnOrdersToInsert[i];
                List<WorkOrder> vendorWos = workOrdersByVendor.get(vendorKeysInOrder[i]);
                for (WorkOrder wo : vendorWos) {
                    List<WorkOrderLineItem> wolis = wolisByWorkOrderId.get(wo.Id);
                    if (wolis == null || wolis.isEmpty()) {
                        throw new ReturnOrdersServiceException(
                            'Work Order ' +
                                wo.WorkOrderNumber +
                                ' has no Work Order Line Items to create Vendor ROLIs.'
                        );
                    }
                    for (WorkOrderLineItem woli : wolis) {
                        outboundLines.add(
                            buildVendorRoliFromWorkOrderLineItem(
                                ro.Id,
                                outboundRtId,
                                VCS_ROLI_LINE_TYPE_OUTBOUND,
                                woli,
                                userRepairCenterId,
                                true,
                                defaultProductId
                            )
                        );
                        outboundSourceWolis.add(woli);
                    }
                }
            }

            ReturnOrderLineItemsService.createReturnOrderLineItems(outboundLines);
            WorkOrdersService.linkSourceRecordsToVendorShipment(
                outboundLines,
                outboundSourceWolis
            );

            List<ReturnOrderLineItem> inboundLines = new List<ReturnOrderLineItem>();
            for (Integer i = 0; i < outboundLines.size(); i++) {
                ReturnOrderLineItem outbound = outboundLines[i];
                WorkOrderLineItem woli = outboundSourceWolis[i];
                ReturnOrderLineItem inbound = buildVendorRoliFromWorkOrderLineItem(
                    outbound.ReturnOrderId,
                    inboundRtId,
                    VCS_ROLI_LINE_TYPE_INBOUND,
                    woli,
                    userRepairCenterId,
                    false,
                    defaultProductId
                );
                inbound.put('ParentROLI__c', outbound.Id);
                inboundLines.add(inbound);
            }

            ReturnOrderLineItemsService.createReturnOrderLineItems(inboundLines);
            WorkOrdersService.updateWorkOrderStatusToShipToVendor(workOrders);

            VendorConsolidationCompleteResult result = new VendorConsolidationCompleteResult();
            result.returnOrderIds = new List<Id>();
            result.returnOrderNumbers = new List<String>();
            result.returnOrderIdToWorkOrderIds = new Map<Id, List<Id>>();
            for (Integer i = 0; i < returnOrdersToInsert.size(); i++) {
                ReturnOrder ro = returnOrdersToInsert[i];
                result.returnOrderIds.add(ro.Id);
                result.returnOrderNumbers.add(ro.ReturnOrderNumber);
                List<Id> groupedWorkOrderIds = new List<Id>();
                for (WorkOrder wo : workOrdersByVendor.get(vendorKeysInOrder[i])) {
                    groupedWorkOrderIds.add(wo.Id);
                }
                result.returnOrderIdToWorkOrderIds.put(ro.Id, groupedWorkOrderIds);
            }
            result.workOrderCount = workOrders.size();
            result.message =
                'Created ' +
                result.returnOrderNumbers.size() +
                ' Vendor Return Order(s) for ' +
                result.workOrderCount +
                ' work order(s). FedEx labels and packing slips are being generated.';
            enqueueVendorFedExShipments(result.returnOrderIdToWorkOrderIds);
            return result;
        } catch (ReturnOrdersServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.completeVendorShipment failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw e;
        } catch (WorkOrdersService.WorkOrdersServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.completeVendorShipment failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new ReturnOrdersServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.completeVendorShipment failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new ReturnOrdersServiceException(
                'Error creating vendor return order: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Pre-flight FedEx address validation for Consolidate Vendor Shipment Complete.
     */
    public static String getShipmentAddressValidationError(
        Id vendorAccountId,
        String vendorLabel,
        Id repairCenterLocationId,
        String repairCenterLabel
    ) {
        if (vendorAccountId == null) {
            return 'Vendor account is required for FedEx shipment.';
        }
        if (repairCenterLocationId == null) {
            return 'Repair Center is required for FedEx shipment.';
        }

        Map<Id, ResolvedAddress> vendorAddressByAccountId = resolveVendorAccountAddresses(
            new Set<Id>{ vendorAccountId }
        );
        Map<Id, ResolvedAddress> repairCenterAddressByLocationId = resolveVendorLocationAddresses(
            new Set<Id>{ repairCenterLocationId }
        );

        ResolvedAddress vendorAddress = vendorAddressByAccountId.get(vendorAccountId);
        if (!hasUsableVendorFedExAddress(vendorAddress)) {
            String vendorName = String.isNotBlank(vendorLabel)
                ? vendorLabel
                : 'the selected Vendor';
            return (
                'Vendor "' +
                vendorName +
                '" ship-to address is incomplete' +
                formatMissingVendorFedExAddressSuffix(vendorAddress) +
                '. Add Street, City, State, and Postal Code on Billing/Shipping or a related Address before completing.'
            );
        }

        ResolvedAddress repairCenterAddress = repairCenterAddressByLocationId.get(
            repairCenterLocationId
        );
        if (!hasUsableVendorFedExAddress(repairCenterAddress)) {
            String repairCenterName = String.isNotBlank(repairCenterLabel)
                ? repairCenterLabel
                : 'the Repair Center';
            return (
                'Repair Center "' +
                repairCenterName +
                '" address is incomplete' +
                formatMissingVendorFedExAddressSuffix(repairCenterAddress) +
                '. Add Street, City, State, and Postal Code on the Location before completing.'
            );
        }
        return null;
    }

    /**
     * @description True when FedEx can use this Location as the Repair Center return address.
     */
    public static Boolean hasRepairCenterAddress(Id repairCenterLocationId) {
        if (repairCenterLocationId == null) {
            return false;
        }
        ResolvedAddress repairCenterAddress = resolveVendorLocationAddresses(
                new Set<Id>{ repairCenterLocationId }
            )
            .get(repairCenterLocationId);
        return hasUsableVendorFedExAddress(repairCenterAddress);
    }

    /**
     * @description GW-3880 - Creates FedEx labels for each Vendor Return Order.
     * @param returnOrderIdToWorkOrderIdsMap Vendor Return Order Id to grouped Work Order Ids
     */
    public static void createVendorFedExShipments(
        Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap
    ) {
        if (returnOrderIdToWorkOrderIdsMap == null || returnOrderIdToWorkOrderIdsMap.isEmpty()) {
            return;
        }

        Logger.setScenario('Vendor FedEx Shipment');
        try {
            throwIfSimulated();
            Set<Id> returnOrderIdSet = returnOrderIdToWorkOrderIdsMap.keySet();
            Set<Id> workOrderIdSet = new Set<Id>();
            for (List<Id> workOrderIdList : returnOrderIdToWorkOrderIdsMap.values()) {
                if (workOrderIdList != null) {
                    workOrderIdSet.addAll(workOrderIdList);
                }
            }

            Map<Id, ReturnOrder> returnOrderByIdMap = new Map<Id, ReturnOrder>(
                ReturnOrdersSelector.selectForVendorFedExShipment(returnOrderIdSet)
            );
            Map<Id, WorkOrder> workOrderByIdMap =
                WorkOrdersService.getWorkOrdersByIdForVendorFedExShipment(workOrderIdSet);
            Map<Id, List<ReturnOrderLineItem>> outboundLineListByRoIdMap =
                queryOutboundLinesForVendorFedEx(returnOrderIdSet);

            Set<Id> accountIdSet = new Set<Id>();
            Set<Id> locationIdSet = new Set<Id>();
            for (ReturnOrder returnOrderRecord : returnOrderByIdMap.values()) {
                if (returnOrderRecord.AccountId != null) {
                    accountIdSet.add(returnOrderRecord.AccountId);
                }
                if (returnOrderRecord.SourceLocationId != null) {
                    locationIdSet.add(returnOrderRecord.SourceLocationId);
                }
            }

            Map<Id, ResolvedAddress> vendorAddressByAccountIdMap = resolveVendorAccountAddresses(
                accountIdSet
            );
            Map<Id, ResolvedAddress> repairCenterAddressByLocationIdMap =
                resolveVendorLocationAddresses(locationIdSet);
            Map<Id, String> contactNameByReturnOrderIdMap =
                resolveVendorContactNameByReturnOrderIdMap(returnOrderByIdMap.values());

            List<VendorShipmentWork> shipmentWorkList = new List<VendorShipmentWork>();
            for (Id returnOrderId : returnOrderIdToWorkOrderIdsMap.keySet()) {
                ReturnOrder returnOrderRecord = returnOrderByIdMap.get(returnOrderId);
                if (returnOrderRecord == null) {
                    throw new ReturnOrdersServiceException(
                        'Vendor Return Order was not found for FedEx shipment.'
                    );
                }

                VendorShipmentWork shipmentWork = new VendorShipmentWork();
                shipmentWork.returnOrder = returnOrderRecord;
                shipmentWork.workOrders = new List<WorkOrder>();
                List<Id> workOrderIdList = returnOrderIdToWorkOrderIdsMap.get(returnOrderId);
                if (workOrderIdList != null) {
                    for (Id workOrderId : workOrderIdList) {
                        WorkOrder workOrderRecord = workOrderByIdMap.get(workOrderId);
                        if (workOrderRecord != null) {
                            shipmentWork.workOrders.add(workOrderRecord);
                        }
                    }
                }

                ResolvedAddress vendorAddress = vendorAddressByAccountIdMap.get(
                    returnOrderRecord.AccountId
                );
                ResolvedAddress repairCenterAddress = repairCenterAddressByLocationIdMap.get(
                    returnOrderRecord.SourceLocationId
                );
                validateVendorFedExAddresses(
                    returnOrderRecord,
                    vendorAddress,
                    repairCenterAddress
                );

                VendorFedExShipmentRequestDTO request = buildVendorFedExRequest(
                    returnOrderRecord,
                    vendorAddress,
                    repairCenterAddress,
                    contactNameByReturnOrderIdMap.get(returnOrderRecord.Id)
                );
                shipmentWork.restBody = JSON.serialize(request);
                shipmentWorkList.add(shipmentWork);
            }

            for (VendorShipmentWork shipmentWork : shipmentWorkList) {
                shipmentWork.response = requestVendorFedExShipment(shipmentWork.restBody);
            }

            persistVendorFedExShipmentResults(shipmentWorkList, outboundLineListByRoIdMap);
        } catch (ReturnOrdersServiceException e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.createVendorFedExShipments failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'ReturnOrdersService.createVendorFedExShipments failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new ReturnOrdersServiceException(
                'FedEx shipment failed: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    @TestVisible
    static FedExService.TrackingResponseDTO requestVendorFedExShipment(String restBody) {
        ReturnOrdersServiceException lastException;
        for (Integer attempt = 1; attempt <= VCS_CALLOUT_ATTEMPTS; attempt++) {
            try {
                throwIfSimulated();
                if (Test.isRunningTest() && testRemainingVendorCalloutFailures > 0) {
                    testRemainingVendorCalloutFailures--;
                    throw new FedExService.FedExServiceException(
                        'FedEx shipping-label call did not return a tracking number.'
                    );
                }
                FedExService.TrackingResponseDTO response = FedExService.requestShippingLabel(restBody);
                if (response == null || String.isBlank(response.trackingNumber)) {
                    throw new FedExService.FedExServiceException(
                        'FedEx shipping-label call did not return a tracking number.'
                    );
                }
                return response;
            } catch (FedExService.FedExServiceException e) {
                lastException = new ReturnOrdersServiceException(e.getMessage(), e);
                Logger.warn(
                    new LogMessage(
                        'Vendor FedEx call attempt {0} of {1} failed: {2}',
                        attempt,
                        VCS_CALLOUT_ATTEMPTS,
                        e.getMessage()
                    )
                );
                if (attempt < VCS_CALLOUT_ATTEMPTS) {
                    pauseBetweenVendorFedExRetries();
                }
            }
        }
        throw lastException;
    }

    @TestVisible
    static Blob buildVendorPackingSlip(
        ReturnOrder ro,
        List<WorkOrder> workOrders,
        List<ReturnOrderLineItem> outboundLines,
        String trackingNumber
    ) {
        return Blob.toPdf(
            buildVendorPackingSlipHtml(ro, workOrders, outboundLines, trackingNumber)
        );
    }

    @TestVisible
    static String buildVendorPackingSlipHtml(
        ReturnOrder ro,
        List<WorkOrder> workOrders,
        List<ReturnOrderLineItem> outboundLines,
        String trackingNumber
    ) {
        String todayText = Date.today().format();
        String ccsName = UserInfo.getName();
        String accountManager = ro.SalesRep__r == null ? '' : ro.SalesRep__r.Name;
        String accountNumber = ro.Account == null ? '' : ro.Account.AccountNumber;
        String vendorName = ro.Account == null ? '' : ro.Account.Name;
        String serviceRequestNumbers = joinVendorWorkOrderNumbers(workOrders);
        String lineItemsHtml = buildVendorLineItemsHtml(outboundLines, workOrders);

        String template = loadVendorPackingSlipTemplate();
        if (String.isBlank(template)) {
            template = defaultVendorPackingSlipTemplate();
        }

        return template
            .replace('{{TODAY}}', escapeVendorHtml(todayText))
            .replace('{{CCS_NAME}}', escapeVendorHtml(ccsName))
            .replace('{{ACCOUNT_MANAGER}}', escapeVendorHtml(accountManager))
            .replace('{{ACCOUNT_NUMBER}}', escapeVendorHtml(accountNumber))
            .replace('{{VENDOR_NAME}}', escapeVendorHtml(vendorName))
            .replace('{{RO_NUMBER}}', escapeVendorHtml(returnOrderDisplayNumber(ro.ReturnOrderNumber)))
            .replace('{{SERVICE_REQUEST_NUMBERS}}', escapeVendorHtml(serviceRequestNumbers))
            .replace('{{TRACKING_NUMBER}}', escapeVendorHtml(trackingNumber))
            .replace('{{FEDEX_CHECKED}}', 'Yes')
            .replace('{{LINE_ITEMS}}', lineItemsHtml);
    }

    private static void enqueueVendorFedExShipments(Map<Id, List<Id>> returnOrderIdToWorkOrderIds) {
        if (returnOrderIdToWorkOrderIds == null || returnOrderIdToWorkOrderIds.isEmpty()) {
            return;
        }
        System.enqueueJob(new ReturnOrdersVendorShipmentQueueable(returnOrderIdToWorkOrderIds));
    }

    private static void pauseBetweenVendorFedExRetries() {
        if (Test.isRunningTest()) {
            return;
        }
        Long startTime = Datetime.now().getTime();
        while (Datetime.now().getTime() - startTime < VCS_RETRY_PAUSE_MS) {
            // Short pause so a transient Boomi miss can recover in the same job.
        }
    }

    private static void persistVendorFedExShipmentResults(
        List<VendorShipmentWork> jobs,
        Map<Id, List<ReturnOrderLineItem>> outboundLinesByRoId
    ) {
        List<ReturnOrder> returnOrdersToUpdate = new List<ReturnOrder>();
        List<ContentVersion> filesToInsert = new List<ContentVersion>();
        Map<Id, String> trackingByReturnOrderId = new Map<Id, String>();

        for (VendorShipmentWork job : jobs) {
            String trackingNumber = job.response.trackingNumber;
            trackingByReturnOrderId.put(job.returnOrder.Id, trackingNumber);
            returnOrdersToUpdate.add(
                new ReturnOrder(
                    Id = job.returnOrder.Id,
                    InboundTrackingNumber__c = trackingNumber
                )
            );

            String fileBaseName = shippingFileBaseName(job.returnOrder.ReturnOrderNumber);
            if (job.response.shippingLabel != null) {
                ContentVersion label = new ContentVersion();
                label.Title = fileBaseName;
                label.PathOnClient = fileBaseName + '.pdf';
                label.VersionData = job.response.shippingLabel;
                label.FirstPublishLocationId = job.returnOrder.Id;
                filesToInsert.add(label);
            }

            Blob packingSlipBody = buildVendorPackingSlip(
                job.returnOrder,
                job.workOrders,
                outboundLinesByRoId.get(job.returnOrder.Id),
                trackingNumber
            );
            ContentVersion packingSlip = new ContentVersion();
            packingSlip.Title = 'Packing Slip ' + returnOrderDisplayNumber(
                job.returnOrder.ReturnOrderNumber
            );
            packingSlip.PathOnClient =
                'Packing Slip ' +
                returnOrderDisplayNumber(job.returnOrder.ReturnOrderNumber) +
                '.pdf';
            packingSlip.VersionData = packingSlipBody;
            packingSlip.FirstPublishLocationId = job.returnOrder.Id;
            filesToInsert.add(packingSlip);
        }

        if (!returnOrdersToUpdate.isEmpty()) {
            updateReturnOrders(returnOrdersToUpdate);
        }
        WorkOrdersService.updateWorkOrdersWithVendorFedExTracking(trackingByReturnOrderId);
        if (!filesToInsert.isEmpty()) {
            insert filesToInsert;
        }
    }

    @TestVisible
    private static VendorFedExShipmentRequestDTO buildVendorFedExRequest(
        ReturnOrder returnOrderRecord,
        ResolvedAddress vendorAddress,
        ResolvedAddress repairCenterAddress,
        String contactName
    ) {
        VendorFedExShipmentRequestDTO request = new VendorFedExShipmentRequestDTO();
        request.FedExAccount = FEDEX_ACCOUNT_NUMBER;
        request.CustomerDisplay = returnOrderRecord.Account == null
            ? null
            : returnOrderRecord.Account.Name;
        request.ShippingMethod = FedExService.getShippingMethod(returnOrderRecord.AccountId);
        request.ContactName = contactName;
        request.CustomerReference = returnOrderDisplayNumber(returnOrderRecord.ReturnOrderNumber);
        String customerPo = (String) returnOrderRecord.get('CustomerPO__c');
        request.CustomerPo = String.isNotBlank(customerPo) ? customerPo.trim() : '-';
        request.AddressLine1 = vendorAddress.line1;
        request.AddressLine2 = vendorAddress.line2;
        request.City = vendorAddress.city;
        request.State = vendorAddress.stateCode;
        request.PostalCode = vendorAddress.postalCode;
        request.Country = vendorAddress.countryCode;
        request.ReturnAddressLine1 = repairCenterAddress.line1;
        request.ReturnAddressLine2 = repairCenterAddress.line2;
        request.ReturnCity = repairCenterAddress.city;
        request.ReturnState = repairCenterAddress.stateCode;
        request.ReturnPostalCode = repairCenterAddress.postalCode;
        request.ReturnCountryCode = repairCenterAddress.countryCode;
        return request;
    }

    private static Map<Id, String> resolveVendorContactNameByReturnOrderIdMap(
        List<ReturnOrder> returnOrderList
    ) {
        Map<Id, String> contactNameByReturnOrderIdMap = new Map<Id, String>();
        if (returnOrderList == null || returnOrderList.isEmpty()) {
            return contactNameByReturnOrderIdMap;
        }

        Set<Id> accountIdSet = new Set<Id>();
        for (ReturnOrder returnOrderRecord : returnOrderList) {
            if (returnOrderRecord.Contact != null &&
                String.isNotBlank(returnOrderRecord.Contact.Name)) {
                contactNameByReturnOrderIdMap.put(
                    returnOrderRecord.Id,
                    returnOrderRecord.Contact.Name
                );
            } else if (returnOrderRecord.AccountId != null) {
                accountIdSet.add(returnOrderRecord.AccountId);
            }
        }

        Map<Id, String> contactNameByAccountIdMap = new Map<Id, String>();
        if (!accountIdSet.isEmpty()) {
            for (Contact contactRecord : [
                SELECT Name, AccountId
                FROM Contact
                WHERE AccountId IN :accountIdSet
                WITH USER_MODE
                ORDER BY CreatedDate ASC
            ]) {
                if (!contactNameByAccountIdMap.containsKey(contactRecord.AccountId) &&
                    String.isNotBlank(contactRecord.Name)) {
                    contactNameByAccountIdMap.put(contactRecord.AccountId, contactRecord.Name);
                }
            }
        }

        for (ReturnOrder returnOrderRecord : returnOrderList) {
            if (contactNameByReturnOrderIdMap.containsKey(returnOrderRecord.Id)) {
                continue;
            }
            if (returnOrderRecord.AccountId != null &&
                contactNameByAccountIdMap.containsKey(returnOrderRecord.AccountId)) {
                contactNameByReturnOrderIdMap.put(
                    returnOrderRecord.Id,
                    contactNameByAccountIdMap.get(returnOrderRecord.AccountId)
                );
            } else {
                contactNameByReturnOrderIdMap.put(returnOrderRecord.Id, UserInfo.getName());
            }
        }
        return contactNameByReturnOrderIdMap;
    }

    private static void validateVendorFedExAddresses(
        ReturnOrder ro,
        ResolvedAddress vendorAddress,
        ResolvedAddress repairCenterAddress
    ) {
        if (!hasUsableVendorFedExAddress(vendorAddress)) {
            throw new ReturnOrdersServiceException(
                'Vendor account on Return Order ' +
                    returnOrderDisplayNumber(ro.ReturnOrderNumber) +
                    ' ship-to address is incomplete' +
                    formatMissingVendorFedExAddressSuffix(vendorAddress) +
                    '.'
            );
        }
        if (!hasUsableVendorFedExAddress(repairCenterAddress)) {
            throw new ReturnOrdersServiceException(
                'Repair Center on Return Order ' +
                    returnOrderDisplayNumber(ro.ReturnOrderNumber) +
                    ' address is incomplete' +
                    formatMissingVendorFedExAddressSuffix(repairCenterAddress) +
                    '.'
            );
        }
    }

    private static Map<Id, List<ReturnOrderLineItem>> queryOutboundLinesForVendorFedEx(
        Set<Id> returnOrderIds
    ) {
        Map<Id, List<ReturnOrderLineItem>> byReturnOrder = new Map<Id, List<ReturnOrderLineItem>>();
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get(VCS_ROLI_RECORD_TYPE_OUTBOUND)
            ?.getRecordTypeId();
        if (outboundRtId == null) {
            return byReturnOrder;
        }
        for (ReturnOrderLineItem line : ReturnOrderLineItemsSelector.selectOutboundByReturnOrderIds(
            returnOrderIds,
            outboundRtId
        )) {
            if (!byReturnOrder.containsKey(line.ReturnOrderId)) {
                byReturnOrder.put(line.ReturnOrderId, new List<ReturnOrderLineItem>());
            }
            byReturnOrder.get(line.ReturnOrderId).add(line);
        }
        return byReturnOrder;
    }

    private static Boolean hasUsableVendorFedExAddress(ResolvedAddress addressValue) {
        return addressValue != null &&
            String.isNotBlank(addressValue.line1) &&
            String.isNotBlank(addressValue.city) &&
            String.isNotBlank(addressValue.stateCode) &&
            String.isNotBlank(addressValue.postalCode);
    }

    private static String formatMissingVendorFedExAddressSuffix(ResolvedAddress addressValue) {
        List<String> missing = missingVendorFedExAddressFields(addressValue);
        if (missing.isEmpty()) {
            return '';
        }
        return ' (missing: ' + String.join(missing, ', ') + ')';
    }

    private static List<String> missingVendorFedExAddressFields(ResolvedAddress addressValue) {
        List<String> missing = new List<String>();
        if (addressValue == null || String.isBlank(addressValue.line1)) {
            missing.add('Street');
        }
        if (addressValue == null || String.isBlank(addressValue.city)) {
            missing.add('City');
        }
        if (addressValue == null || String.isBlank(addressValue.stateCode)) {
            missing.add('State');
        }
        if (addressValue == null || String.isBlank(addressValue.postalCode)) {
            missing.add('Postal Code');
        }
        return missing;
    }

    private static Map<Id, ResolvedAddress> resolveVendorAccountAddresses(Set<Id> accountIds) {
        Map<Id, ResolvedAddress> byAccountId = new Map<Id, ResolvedAddress>();
        if (accountIds == null || accountIds.isEmpty()) {
            return byAccountId;
        }

        for (SObject addressRecord : queryVendorAddressesByParent(accountIds)) {
            Id parentId = (Id) addressRecord.get('ParentId');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (parentId != null && hasUsableVendorFedExAddress(resolved) && !byAccountId.containsKey(parentId)) {
                byAccountId.put(parentId, resolved);
            }
        }

        Set<Id> missingIds = new Set<Id>(accountIds);
        missingIds.removeAll(byAccountId.keySet());
        if (!missingIds.isEmpty()) {
            for (Account account : new VendorFedExAddressAccess().getAccountsById(missingIds)) {
                ResolvedAddress billing = toResolvedAddressFromAccountFields(
                    account.BillingStreet,
                    account.BillingCity,
                    account.BillingState,
                    account.BillingStateCode,
                    account.BillingPostalCode,
                    account.BillingCountry,
                    account.BillingCountryCode
                );
                if (hasUsableVendorFedExAddress(billing)) {
                    byAccountId.put(account.Id, billing);
                    continue;
                }
                ResolvedAddress shipping = toResolvedAddressFromAccountFields(
                    account.ShippingStreet,
                    account.ShippingCity,
                    account.ShippingState,
                    account.ShippingStateCode,
                    account.ShippingPostalCode,
                    account.ShippingCountry,
                    account.ShippingCountryCode
                );
                if (hasUsableVendorFedExAddress(shipping)) {
                    byAccountId.put(account.Id, shipping);
                }
            }
        }

        missingIds = new Set<Id>(accountIds);
        missingIds.removeAll(byAccountId.keySet());
        if (missingIds.isEmpty()) {
            return byAccountId;
        }

        for (SObject addressRecord : new VendorFedExAddressAccess().queryAddressesByCustomer(missingIds)) {
            Id accountId = (Id) addressRecord.get('Customer__c');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                accountId != null &&
                hasUsableVendorFedExAddress(resolved) &&
                !byAccountId.containsKey(accountId)
            ) {
                byAccountId.put(accountId, resolved);
            }
        }
        return byAccountId;
    }

    private static ResolvedAddress toResolvedAddressFromAccountFields(
        String street,
        String city,
        String state,
        String stateCode,
        String postalCode,
        String country,
        String countryCode
    ) {
        ResolvedAddress resolved = new ResolvedAddress();
        List<String> streetLines = splitStreet(street);
        resolved.line1 = streetLines[0];
        resolved.line2 = streetLines[1];
        resolved.city = city;
        resolved.stateCode = String.isNotBlank(stateCode) ? stateCode : toCode(state);
        resolved.postalCode = postalCode;
        resolved.countryCode = String.isNotBlank(countryCode)
            ? countryCode
            : toCountryCode(country);
        return resolved;
    }

    private static Map<Id, ResolvedAddress> resolveVendorLocationAddresses(Set<Id> locationIds) {
        Map<Id, ResolvedAddress> byLocationId = new Map<Id, ResolvedAddress>();
        if (locationIds == null || locationIds.isEmpty()) {
            return byLocationId;
        }

        for (SObject addressRecord : queryVendorAddressesByParent(locationIds)) {
            Id parentId = (Id) addressRecord.get('ParentId');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                parentId != null &&
                hasUsableVendorFedExAddress(resolved) &&
                !byLocationId.containsKey(parentId)
            ) {
                byLocationId.put(parentId, resolved);
            }
        }

        Set<Id> missingIds = new Set<Id>(locationIds);
        missingIds.removeAll(byLocationId.keySet());
        if (missingIds.isEmpty()) {
            return byLocationId;
        }

        List<Schema.Location> locations = LocationsSelector.selectById(missingIds);
        Map<Id, Id> locationIdByVisitorAddressId = new Map<Id, Id>();
        for (Schema.Location location : locations) {
            if (location.VisitorAddressId != null) {
                locationIdByVisitorAddressId.put(location.VisitorAddressId, location.Id);
            }
        }
        if (locationIdByVisitorAddressId.isEmpty()) {
            return byLocationId;
        }

        for (SObject addressRecord : queryVendorAddressesById(locationIdByVisitorAddressId.keySet())) {
            Id locationId = locationIdByVisitorAddressId.get(addressRecord.Id);
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                locationId != null &&
                hasUsableVendorFedExAddress(resolved) &&
                !byLocationId.containsKey(locationId)
            ) {
                byLocationId.put(locationId, resolved);
            }
        }
        return byLocationId;
    }

    private static List<SObject> queryVendorAddressesByParent(Set<Id> parentIds) {
        return Database.query(
            'SELECT Id, ParentId, Street, City, State, StateCode, Country, CountryCode, PostalCode ' +
                'FROM Address ' +
                'WHERE ParentId IN :parentIds ' +
                'WITH USER_MODE ' +
                'ORDER BY CreatedDate ASC'
        );
    }

    private static List<SObject> queryVendorAddressesById(Set<Id> addressIds) {
        return Database.query(
            'SELECT Id, ParentId, Street, City, State, StateCode, Country, CountryCode, PostalCode ' +
                'FROM Address ' +
                'WHERE Id IN :addressIds ' +
                'WITH USER_MODE'
        );
    }

    private static Map<Id, ReturnOrder> loadParentReturnOrdersForVendorConsolidation(
        List<WorkOrder> workOrders
    ) {
        Set<Id> parentRoIds = new Set<Id>();
        for (WorkOrder wo : workOrders) {
            Id parentRoId = resolveParentReturnOrderIdFromWorkOrder(wo);
            if (parentRoId != null) {
                parentRoIds.add(parentRoId);
            }
        }
        Map<Id, ReturnOrder> byId = new Map<Id, ReturnOrder>();
        if (parentRoIds.isEmpty()) {
            return byId;
        }
        for (ReturnOrder ro : ReturnOrdersSelector.selectParentReturnOrdersForVendorConsolidation(
            parentRoIds,
            VCS_PARENT_RO_COPY_FIELDS
        )) {
            byId.put(ro.Id, ro);
        }
        return byId;
    }

    private static Id resolveParentReturnOrderIdFromWorkOrder(WorkOrder wo) {
        if (wo == null) {
            return null;
        }
        if (wo.ReturnOrder__c != null) {
            return wo.ReturnOrder__c;
        }
        return wo.ReturnOrderId;
    }

    private static Map<Id, List<WorkOrder>> groupWorkOrdersByVendor(List<WorkOrder> workOrders) {
        Map<Id, List<WorkOrder>> byVendor = new Map<Id, List<WorkOrder>>();
        for (WorkOrder wo : workOrders) {
            if (!byVendor.containsKey(wo.Vendor__c)) {
                byVendor.put(wo.Vendor__c, new List<WorkOrder>());
            }
            byVendor.get(wo.Vendor__c).add(wo);
        }
        return byVendor;
    }

    private static ReturnOrder buildVendorReturnOrder(
        Id vendorId,
        List<WorkOrder> vendorWos,
        Id repairCenterId,
        Id vendorReturnRtId,
        Map<Id, ReturnOrder> parentReturnOrdersById
    ) {
        WorkOrder first = vendorWos[0];
        ReturnOrder parentRo = findParentReturnOrderForVendorConsolidation(
            vendorWos,
            parentReturnOrdersById
        );
        Id woRepairCenterId = first.RepairCenter__c != null
            ? first.RepairCenter__c
            : repairCenterId;

        ReturnOrder ro = new ReturnOrder();
        ro.RecordTypeId = vendorReturnRtId;
        ro.AccountId = vendorId;
        ro.Status = VCS_RO_STATUS_CREATED;
        ro.DestinationLocationId = woRepairCenterId;
        ro.SourceLocationId = woRepairCenterId;
        ro.CreationSource__c = VCS_CREATION_SOURCE_SALESFORCE;
        ro.put('WorkOrder__c', first.Id);
        ro.put('OperatingUnit__c', resolveVendorOperatingUnit(first));
        ro.put('ReturnOrderType__c', VCS_RO_TYPE_VENDOR);
        ro.Description =
            'Consolidate Vendor Shipment — Work Orders: ' +
            joinVendorWorkOrderNumbers(vendorWos);

        if (parentRo != null) {
            ro.put('ParentReturnOrder__c', parentRo.Id);
            copyPopulatedVendorFields(ro, parentRo, VCS_PARENT_RO_COPY_FIELDS);
        }

        String customerPoFromWo = resolveCustomerPoFromVendorWorkOrders(vendorWos);
        if (String.isNotBlank(customerPoFromWo)) {
            ro.put('CustomerPO__c', customerPoFromWo);
        }
        return ro;
    }

    private static ReturnOrder findParentReturnOrderForVendorConsolidation(
        List<WorkOrder> vendorWos,
        Map<Id, ReturnOrder> parentReturnOrdersById
    ) {
        for (WorkOrder wo : vendorWos) {
            Id parentRoId = resolveParentReturnOrderIdFromWorkOrder(wo);
            if (parentRoId != null && parentReturnOrdersById.containsKey(parentRoId)) {
                return parentReturnOrdersById.get(parentRoId);
            }
        }
        return null;
    }

    private static String resolveCustomerPoFromVendorWorkOrders(List<WorkOrder> vendorWos) {
        if (vendorWos == null) {
            return null;
        }
        for (WorkOrder wo : vendorWos) {
            String customerPo = (String) wo.get('CustomerPO__c');
            if (String.isNotBlank(customerPo)) {
                return customerPo.trim();
            }
        }
        return null;
    }

    private static ReturnOrderLineItem buildVendorRoliFromWorkOrderLineItem(
        Id returnOrderId,
        Id recordTypeId,
        String lineType,
        WorkOrderLineItem woli,
        Id repairCenterId,
        Boolean isOutbound,
        Id defaultProductId
    ) {
        ReturnOrderLineItem line = new ReturnOrderLineItem();
        line.ReturnOrderId = returnOrderId;
        line.RecordTypeId = recordTypeId;
        line.put('Status__c', VCS_ROLI_STATUS_CREATED);
        line.put('LineType__c', lineType);
        line.QuantityReturned = woli.Quantity != null && woli.Quantity > 0
            ? woli.Quantity
            : 1;

        if (isOutbound) {
            line.SourceLocationId = repairCenterId;
        } else {
            line.DestinationLocationId = repairCenterId;
        }

        Id productId = woli.Product2Id != null
            ? woli.Product2Id
            : (Id) woli.get('Product__c');
        if (productId != null) {
            line.Product2Id = productId;
        }
        if (woli.AssetId != null) {
            line.AssetId = woli.AssetId;
        }
        if (String.isNotBlank(woli.SerialNumber__c)) {
            line.SerialNumber__c = woli.SerialNumber__c;
        }
        if (String.isNotBlank(woli.Model__c)) {
            line.put('Model__c', woli.Model__c);
        }

        String productLine = null;
        if (woli.Product2Id != null && woli.Product2 != null) {
            productLine = (String) woli.Product2.get('ProductLine__c');
        }
        if (String.isBlank(productLine) && woli.getSObject('Product__r') != null) {
            productLine = (String) woli.getSObject('Product__r').get('ProductLine__c');
        }
        if (String.isNotBlank(productLine)) {
            line.put('ProductLine__c', productLine);
        }

        SObject parentWorkOrder = woli.getSObject('WorkOrder');
        if (parentWorkOrder != null) {
            if (parentWorkOrder.get('InstructionsToVendor__c') != null) {
                line.put(
                    'InstructionsToVendor__c',
                    parentWorkOrder.get('InstructionsToVendor__c')
                );
            }
            if (parentWorkOrder.get('VendorNotes__c') != null) {
                line.put('VendorNotes__c', parentWorkOrder.get('VendorNotes__c'));
            }
            if (parentWorkOrder.get('VendorReferenceNumber__c') != null) {
                line.put(
                    'VendorReferenceNumber__c',
                    parentWorkOrder.get('VendorReferenceNumber__c')
                );
            }
            if (parentWorkOrder.get('VendorCost__c') != null) {
                line.put('VendorCost__c', parentWorkOrder.get('VendorCost__c'));
            }
        }

        if (line.Product2Id == null && line.AssetId == null && defaultProductId != null) {
            line.Product2Id = defaultProductId;
        }
        if (line.Product2Id == null && line.AssetId == null) {
            throw new ReturnOrdersServiceException(
                'Work Order Line Item ' +
                    woli.Id +
                    ' has no Product/Asset to create a Return Order Line Item. ' +
                    'Set Product/Asset on the line item or create an active Product named "Default Product".'
            );
        }
        return line;
    }

    private static void copyPopulatedVendorFields(
        SObject target,
        SObject source,
        List<String> fieldNames
    ) {
        if (target == null || source == null || fieldNames == null) {
            return;
        }
        for (String fieldName : fieldNames) {
            Object value = source.get(fieldName);
            if (value != null && value != '') {
                target.put(fieldName, value);
            }
        }
    }

    private static String resolveVendorOperatingUnit(WorkOrder wo) {
        if (wo.Vendor__r != null && String.isNotBlank(wo.Vendor__r.OrgIDs__c)) {
            return wo.Vendor__r.OrgIDs__c.trim().split('[;,]')[0].trim();
        }
        return null;
    }

    private static Id resolveDefaultProductIdForVendorConsolidation() {
        Product2 defaultProduct = Product2QueryUtil.queryDefaultProduct();
        return defaultProduct == null ? null : defaultProduct.Id;
    }

    private static Id getRecordTypeId(Schema.SObjectType sobjectType, String developerName) {
        Map<String, Schema.RecordTypeInfo> infos = sobjectType.getDescribe()
            .getRecordTypeInfosByDeveloperName();
        Schema.RecordTypeInfo info = infos.get(developerName);
        if (info == null || !info.isAvailable()) {
            throw new ReturnOrdersServiceException(
                'Record Type "' +
                    developerName +
                    '" is not available for ' +
                    sobjectType.getDescribe().getName() +
                    '.'
            );
        }
        return info.getRecordTypeId();
    }

    private static void insertViaElevatedAccess(List<SObject> records) {
        if (records == null || records.isEmpty()) {
            return;
        }
        new VendorConsolidationDml().insertRecords(records);
    }

    private static String loadVendorPackingSlipTemplate() {
        try {
            throwIfSimulated();
            List<ContentVersion> templates = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Title = :VCS_PACKING_SLIP_TEMPLATE_TITLE AND IsLatest = TRUE
                WITH USER_MODE
                LIMIT 1
            ];
            if (templates.isEmpty() || templates[0].VersionData == null) {
                return null;
            }
            return templates[0].VersionData.toString();
        } catch (Exception e) {
            return null;
        }
    }

    private static String defaultVendorPackingSlipTemplate() {
        return '<!DOCTYPE html><html><head><meta charset="UTF-8"/>' +
            '<title>Vendor Packing Slip {{RO_NUMBER}}</title>' +
            '<style>body{font-family:Arial,sans-serif;font-size:12px;color:#222}' +
            'h1{font-size:18px;margin-bottom:8px}table{border-collapse:collapse;width:100%}' +
            'th,td{border:1px solid #999;padding:6px;text-align:left}' +
            '.meta{margin:12px 0}label{font-weight:bold}</style></head><body>' +
            '<h1>Vendor Shipping Packing Slip</h1>' +
            '<div class="meta"><div><label>Date: </label>{{TODAY}}</div>' +
            '<div><label>C.C.S Name: </label>{{CCS_NAME}}</div>' +
            '<div><label>Account Manager: </label>{{ACCOUNT_MANAGER}}</div>' +
            '<div><label>Acct #: </label>{{ACCOUNT_NUMBER}}</div>' +
            '<div><label>Vendor: </label>{{VENDOR_NAME}}</div>' +
            '<div><label>Return Order: </label>{{RO_NUMBER}}</div>' +
            '<div><label>Service Request Number: </label>{{SERVICE_REQUEST_NUMBERS}}</div>' +
            '<div><label>FedEx: </label>{{FEDEX_CHECKED}}</div>' +
            '<div><label>Tracking Number: </label>{{TRACKING_NUMBER}}</div></div>' +
            '<h2>Box Contents</h2>{{LINE_ITEMS}}</body></html>';
    }

    private static String buildVendorLineItemsHtml(
        List<ReturnOrderLineItem> outboundLines,
        List<WorkOrder> workOrders
    ) {
        String rows = '';
        if (outboundLines != null) {
            for (ReturnOrderLineItem line : outboundLines) {
                String itemDescription = line.Product2 == null
                    ? null
                    : line.Product2.Description;
                rows +=
                    '<tr><td>' +
                    escapeVendorHtml(itemDescription) +
                    '</td><td>' +
                    escapeVendorHtml((String) line.get('Model__c')) +
                    '</td><td>' +
                    escapeVendorHtml((String) line.get('SerialNumber__c')) +
                    '</td><td>' +
                    String.valueOf(line.QuantityReturned == null ? 1 : line.QuantityReturned) +
                    '</td></tr>';
            }
        }
        if (String.isBlank(rows) && workOrders != null) {
            for (WorkOrder wo : workOrders) {
                rows +=
                    '<tr><td>' +
                    escapeVendorHtml(wo.WorkOrderNumber) +
                    '</td><td></td><td></td><td>1</td></tr>';
            }
        }
        return '<table><thead><tr><th>Item</th><th>Model</th><th>Serial Number</th>' +
            '<th>Qty</th></tr></thead><tbody>' +
            rows +
            '</tbody></table>';
    }

    private static String joinVendorWorkOrderNumbers(List<WorkOrder> workOrders) {
        List<String> numbers = new List<String>();
        if (workOrders == null) {
            return '';
        }
        for (WorkOrder wo : workOrders) {
            if (String.isNotBlank(wo.WorkOrderNumber)) {
                String workOrderNumber = wo.WorkOrderNumber;
                numbers.add(
                    workOrderNumber.startsWith('WO-')
                        ? workOrderNumber
                        : 'WO-' + workOrderNumber
                );
            }
        }
        return String.join(numbers, ', ');
    }

    private static String escapeVendorHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.escapeHtml4();
    }

    /**
     * @description Elevates vendor Account / related Address reads for FedEx ship-to resolution.
     */
    private without sharing class VendorFedExAddressAccess {
        private List<Account> getAccountsById(Set<Id> accountIds) {
            if (accountIds == null || accountIds.isEmpty()) {
                return new List<Account>();
            }
            return [
                SELECT
                    Id,
                    BillingStreet,
                    BillingCity,
                    BillingState,
                    BillingStateCode,
                    BillingPostalCode,
                    BillingCountry,
                    BillingCountryCode,
                    ShippingStreet,
                    ShippingCity,
                    ShippingState,
                    ShippingStateCode,
                    ShippingPostalCode,
                    ShippingCountry,
                    ShippingCountryCode
                FROM Account
                WHERE Id IN :accountIds
            ];
        }

        private List<SObject> queryAddressesByCustomer(Set<Id> accountIds) {
            if (accountIds == null || accountIds.isEmpty()) {
                return new List<SObject>();
            }
            return Database.query(
                'SELECT Customer__c, Street, City, State, StateCode, Country, CountryCode, PostalCode ' +
                    'FROM Address ' +
                    'WHERE Customer__c IN :accountIds ' +
                    'ORDER BY CreatedDate ASC'
            );
        }
    }

    /**
     * @description Elevates vendor consolidation DML when Repair Center techs lack Account sharing.
     */
    private without sharing class VendorConsolidationDml {
        private void insertRecords(List<SObject> records) {
            insert records;
        }
    }

    /**
     * @description GW-5492 - Redirect result for Finish Receiving.
     */
    public class ReceivingRedirectResult {
        public Id returnOrderId;
        public String returnOrderNumber;
        public Boolean sourceReturnOrderFullyRedirected;
    }

    /**
     * @description GW-5492 - Links RO.WorkOrder__c to the parent/primary Work Order.
     * @param returnOrderId Return Order Id
     * @param workOrderId Work Order Id
     */
    public static void linkWorkOrderForReceiving(Id returnOrderId, Id workOrderId) {
        if (returnOrderId == null || workOrderId == null) {
            return;
        }
        Database.update(
            new List<ReturnOrder>{
                new ReturnOrder(Id = returnOrderId, WorkOrder__c = workOrderId)
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description GW-5492 - Updates WOCount__c from related Work Orders.
     * @param returnOrderId Return Order Id
     */
    public static void syncReceivingWorkOrderCount(Id returnOrderId) {
        if (returnOrderId == null) {
            return;
        }
        Integer workOrderCount = WorkOrdersService.countByReturnOrderId(returnOrderId);
        Database.update(
            new List<ReturnOrder>{
                new ReturnOrder(Id = returnOrderId, WOCount__c = workOrderCount)
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description GW-5492 - Stores the quantity confirmed on an Instruments receive.
     * @param returnOrderId Return Order Id
     * @param quantityReceived Quantity entered for the instrument item
     */
    public static void setQuantityReceivedForReceiving(Id returnOrderId, Decimal quantityReceived) {
        if (returnOrderId == null || quantityReceived == null) {
            return;
        }
        Database.update(
            new List<ReturnOrder>{
                new ReturnOrder(Id = returnOrderId, QuantityReceived__c = quantityReceived)
            },
            AccessLevel.USER_MODE
        );
    }

    /**
     * @description GW-5492 - Sets RO Status Received when no Created lines remain.
     * @param returnOrderId Return Order Id
     * @return True when RO is fully received
     */
    public static Boolean markReturnOrderReceivedIfComplete(Id returnOrderId) {
        if (returnOrderId == null) {
            return false;
        }
        Integer openCount = ReturnOrderLineItemsService.countCreatedByReturnOrderId(returnOrderId);
        if (openCount > 0) {
            return false;
        }
        Database.update(
            new List<ReturnOrder>{
                new ReturnOrder(Id = returnOrderId, Status = 'Received')
            },
            AccessLevel.USER_MODE
        );
        return true;
    }

    /**
     * @description GW-5492 - Clones RO/ROLI for Redirect and marks source ROLI Redirected.
     * @param sourceReturnOrderId Source Return Order Id
     * @param sourceLineItemId Source line item Id
     * @param repairCenterId Destination Repair Center Location Id
     * @param redirectionNotes Optional notes
     * @return Redirect result
     */
    public static ReceivingRedirectResult redirectLineItemForReceiving(
        Id sourceReturnOrderId,
        Id sourceLineItemId,
        Id repairCenterId,
        String redirectionNotes
    ) {
        return redirectLinesForReceiving(
            sourceReturnOrderId,
            new Set<Id>{ sourceLineItemId },
            repairCenterId,
            redirectionNotes
        );
    }

    /**
     * @description GW-5492 - Clones one Return Order and the given lines for Redirect.
     *              Instruments pass every Created line so the source item is fully redirected.
     * @param sourceReturnOrderId Source Return Order Id
     * @param sourceLineItemIds Source line item Ids
     * @param repairCenterId Destination Repair Center Location Id
     * @param redirectionNotes Optional notes
     * @return Redirect result
     */
    public static ReceivingRedirectResult redirectLinesForReceiving(
        Id sourceReturnOrderId,
        Set<Id> sourceLineItemIds,
        Id repairCenterId,
        String redirectionNotes
    ) {
        List<ReturnOrder> sourceRows = ReturnOrdersSelector.selectForReceivingFinish(
            sourceReturnOrderId
        );
        if (sourceRows.isEmpty()) {
            throw new ReturnOrdersServiceException('Return Order was not found.');
        }
        ReturnOrder source = sourceRows[0];
        List<ReturnOrderLineItem> sourceLines =
            ReturnOrderLineItemsService.getLinesForReceivingFinish(sourceLineItemIds);
        if (sourceLines.isEmpty()) {
            throw new ReturnOrdersServiceException('Return Order Line Item was not found.');
        }

        Schema.RecordTypeInfo customerReturnRtInfo = Schema.SObjectType.ReturnOrder
            .getRecordTypeInfosByDeveloperName()
            .get('CustomerReturn');
        Id customerReturnRtId = customerReturnRtInfo == null
            ? null
            : customerReturnRtInfo.getRecordTypeId();

        ReturnOrder clonedReturnOrder = new ReturnOrder();
        if (customerReturnRtId != null) {
            clonedReturnOrder.RecordTypeId = customerReturnRtId;
        }
        clonedReturnOrder.AccountId = source.AccountId;
        clonedReturnOrder.CaseId = source.CaseId;
        clonedReturnOrder.ContactId = source.ContactId;
        clonedReturnOrder.OrderId = source.OrderId;
        clonedReturnOrder.OperatingUnit__c = source.OperatingUnit__c;
        clonedReturnOrder.CreationSource__c = source.CreationSource__c;
        clonedReturnOrder.SalesRep__c = source.SalesRep__c;
        clonedReturnOrder.ShipToAddressAccount__c = source.ShipToAddressAccount__c;
        clonedReturnOrder.ShipToAddress__Street__s = source.ShipToAddress__Street__s;
        clonedReturnOrder.ShipToAddress__City__s = source.ShipToAddress__City__s;
        clonedReturnOrder.ShipToAddress__StateCode__s = source.ShipToAddress__StateCode__s;
        clonedReturnOrder.ShipToAddress__PostalCode__s = source.ShipToAddress__PostalCode__s;
        clonedReturnOrder.ShipToAddress__CountryCode__s = source.ShipToAddress__CountryCode__s;
        clonedReturnOrder.ReturnOrderType__c = source.ReturnOrderType__c;
        clonedReturnOrder.SourceLocationId = source.SourceLocationId;
        clonedReturnOrder.Description = appendRedirectionNotes(
            source.Description,
            redirectionNotes
        );
        clonedReturnOrder.ShipmentType = source.ShipmentType;
        clonedReturnOrder.ExpectedArrivalDate = source.ExpectedArrivalDate;
        clonedReturnOrder.ExpirationDate = source.ExpirationDate;
        clonedReturnOrder.ProductRequestId = source.ProductRequestId;
        clonedReturnOrder.ReturnedById = source.ReturnedById;
        clonedReturnOrder.CreatedByContact__c = source.CreatedByContact__c;
        clonedReturnOrder.DestinationLocationId = repairCenterId;
        clonedReturnOrder.ParentReturnOrder__c = source.Id;
        clonedReturnOrder.Status = 'Created';
        Database.insert(
            new List<ReturnOrder>{ clonedReturnOrder },
            AccessLevel.USER_MODE
        );

        List<ReturnOrderLineItem> clonedLines = new List<ReturnOrderLineItem>();
        Set<Id> sourceLineIds = new Set<Id>();
        for (ReturnOrderLineItem sourceLine : sourceLines) {
            clonedLines.add(cloneLineForReceivingRedirect(
                sourceLine,
                clonedReturnOrder.Id,
                repairCenterId
            ));
            sourceLineIds.add(sourceLine.Id);
        }
        Database.insert(clonedLines, AccessLevel.USER_MODE);
        ReturnOrderLineItemsService.markLinesRedirectedForReceiving(sourceLineIds);

        Boolean fullyRedirected =
            ReturnOrderLineItemsService.countCreatedByReturnOrderId(source.Id) == 0;
        if (fullyRedirected) {
            Database.update(
                new List<ReturnOrder>{
                    new ReturnOrder(Id = source.Id, Status = 'Redirected')
                },
                AccessLevel.USER_MODE
            );
        }

        List<ReturnOrder> inserted = ReturnOrdersSelector.selectForReceivingFinish(
            clonedReturnOrder.Id
        );
        ReceivingRedirectResult result = new ReceivingRedirectResult();
        result.returnOrderId = clonedReturnOrder.Id;
        result.returnOrderNumber = inserted.isEmpty() ? null : inserted[0].ReturnOrderNumber;
        result.sourceReturnOrderFullyRedirected = fullyRedirected;
        return result;
    }

    private static String appendRedirectionNotes(
        String existingDescription,
        String redirectionNotes
    ) {
        if (String.isBlank(redirectionNotes)) {
            return existingDescription;
        }
        String notesLine = 'Redirection Notes: ' + redirectionNotes.trim();
        if (String.isBlank(existingDescription)) {
            return notesLine;
        }
        return existingDescription + '\n\n' + notesLine;
    }

    private static ReturnOrderLineItem cloneLineForReceivingRedirect(
        ReturnOrderLineItem sourceLine,
        Id clonedReturnOrderId,
        Id repairCenterId
    ) {
        ReturnOrderLineItem clonedLine = new ReturnOrderLineItem();
        clonedLine.ReturnOrderId = clonedReturnOrderId;
        clonedLine.Status__c = 'Created';
        clonedLine.ParentROLI__c = sourceLine.Id;
        clonedLine.AssetId = sourceLine.AssetId;
        clonedLine.Product2Id = sourceLine.Product2Id;
        clonedLine.ProductLine__c = sourceLine.ProductLine__c;
        clonedLine.LineType__c = sourceLine.LineType__c;
        clonedLine.QuantityReturned = sourceLine.QuantityReturned;
        clonedLine.CustomerPO__c = sourceLine.CustomerPO__c;
        clonedLine.CustomerReference__c = sourceLine.CustomerReference__c;
        clonedLine.Contact__c = sourceLine.Contact__c;
        clonedLine.Department__c = sourceLine.Department__c;
        clonedLine.Description = sourceLine.Description;
        clonedLine.Model__c = sourceLine.Model__c;
        clonedLine.SerialNumber__c = sourceLine.SerialNumber__c;
        clonedLine.ReportedProblem__c = sourceLine.ReportedProblem__c;
        clonedLine.IsLoanerAsset__c = sourceLine.IsLoanerAsset__c;
        clonedLine.LoanerRequested__c = sourceLine.LoanerRequested__c;
        clonedLine.EstimateRequired__c = sourceLine.EstimateRequired__c;
        clonedLine.Disinfected__c = sourceLine.Disinfected__c;
        clonedLine.DestinationLocationId = repairCenterId;
        clonedLine.SourceLocationId = sourceLine.SourceLocationId;
        clonedLine.QuantityExpected = sourceLine.QuantityExpected;
        clonedLine.QuantityUnitOfMeasure = sourceLine.QuantityUnitOfMeasure;
        clonedLine.ReasonForReturn = sourceLine.ReasonForReturn;
        clonedLine.RepaymentMethod = sourceLine.RepaymentMethod;
        clonedLine.ProcessingPlan = sourceLine.ProcessingPlan;
        clonedLine.HospitalReferencedTrayName__c = sourceLine.HospitalReferencedTrayName__c;
        return clonedLine;
    }

    /**
     * @description One Customer Return Order created from a grouped payload.
     */
    public class GroupedReturnOrderResult {
        public Id returnOrderId;
        public String returnOrderNumber;
        public String returnOrderType;
        public String repairCenterName;
        public Integer lineCount;
    }

    private static final String STATUS_CREATED = 'Created';
    private static final String FLEXIBLE_SCOPE_PRODUCT_LINE = 'FLEXIBLE SCOPE';
    private static final String INSTRUMENT_PRODUCT_LINE = 'INSTRUMENT';
    private static final String DEFAULT_PRODUCT_NAME = 'Default Product';
    private static final Decimal QUANTITY_RETURNED_DEFAULT = 1;
    private static final String ROLI_LINE_TYPE_SERIALIZED = 'Serialized';
    private static final String ROLI_LINE_TYPE_INSTRUMENT = 'Instrument';
    private static final String ROLI_LINE_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
    private static final String ROLI_LINE_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
    private static final String RETURN_ORDER_TYPE_SERIALIZED = 'Serialized';
    private static final String RETURN_ORDER_TYPE_INSTRUMENTS = 'Instruments';
    private static final String RETURN_ORDER_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
    private static final String RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
    private static final String ESTIMATE_REQUIRED_QUOTE_VALUE = 'Estimate Required';
    private static final String RETURN_ORDER_TYPE_FIELD = 'ReturnOrderType__c';
    private static Map<String, String> itemTypeToProductLineCache;

    /**
     * @description Creates one Customer Return Order per group.
     * @param headerJson Account header JSON
     * @param groupsJson Grouped line JSON
     * @return Created Return Orders
     */
    public static List<GroupedReturnOrderResult> createGroupedReturnOrders(
        String headerJson,
        String groupsJson
    ) {
        try {
            Map<String, Object> header = (Map<String, Object>) JSON.deserializeUntyped(headerJson);
            List<Object> groupObjects = groupsJson != null
                ? (List<Object>) JSON.deserializeUntyped(groupsJson)
                : new List<Object>();
            if (groupObjects.isEmpty()) {
                throw new ReturnOrdersServiceException('No return orders to create.');
            }
            List<GroupedReturnOrderResult> createdOrders = new List<GroupedReturnOrderResult>();
            for (Object groupObj : groupObjects) {
                Map<String, Object> groupPayload = (Map<String, Object>) groupObj;
                Boolean requiresSelection = toBoolean(
                    groupPayload.get('requiresRepairCenterSelection')
                );
                Id repairCenterId = parseId(String.valueOf(groupPayload.get('repairCenterId')));
                if (requiresSelection == true && repairCenterId == null) {
                    throw new ReturnOrdersServiceException(
                        'Select a repair center for lines without a routing rule match.'
                    );
                }
                if (!requiresSelection && repairCenterId == null) {
                    throw new ReturnOrdersServiceException(
                        'Repair center is required for each return order group.'
                    );
                }
                String lineItemsJson = (String) groupPayload.get('lineItemsJson');
                List<Object> lineObjects = String.isNotBlank(lineItemsJson)
                    ? (List<Object>) JSON.deserializeUntyped(lineItemsJson)
                    : new List<Object>();
                createdOrders.add(
                    insertReturnOrder(
                        header,
                        repairCenterId,
                        lineObjects,
                        (Map<String, Object>) groupPayload.get('orderHeader')
                    )
                );
            }
            return createdOrders;
        } catch (ReturnOrdersServiceException e) {
            throw e;
        } catch (DmlException e) {
            throw new ReturnOrdersServiceException(
                'Error creating return orders: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            throw new ReturnOrdersServiceException(
                'Error creating return orders: ' + e.getMessage(),
                e
            );
        }
    }

    /**
     * @description Creates one Customer Return Order from a header and line payload.
     * @param headerJson Account header JSON
     * @param lineItemsJson Line JSON
     * @return Created Return Order
     */
    public static GroupedReturnOrderResult createSingleReturnOrder(
        String headerJson,
        String lineItemsJson
    ) {
        try {
            Map<String, Object> header = (Map<String, Object>) JSON.deserializeUntyped(headerJson);
            List<Object> lineObjects = lineItemsJson != null
                ? (List<Object>) JSON.deserializeUntyped(lineItemsJson)
                : new List<Object>();
            Id repairCenterId = parseId((String) header.get('repairCenterId'));
            return insertReturnOrder(header, repairCenterId, lineObjects, null);
        } catch (ReturnOrdersServiceException e) {
            throw e;
        } catch (DmlException e) {
            throw new ReturnOrdersServiceException(
                'Error creating return order: ' + e.getDmlMessage(0),
                e
            );
        } catch (Exception e) {
            throw new ReturnOrdersServiceException(
                'Error creating return order: ' + e.getMessage(),
                e
            );
        }
    }

    private static void applyInstrumentReturnOrderHeader(
        ReturnOrder returnOrder,
        Map<String, Object> orderHeader
    ) {
        if (returnOrder == null || orderHeader == null) {
            return;
        }

        Id contactId = parseId((String) orderHeader.get('contactId'));
        if (contactId != null) {
            returnOrder.ContactId = contactId;
        }

        String estimateRequired = (String) orderHeader.get('estimateRequired');
        if (String.isBlank(estimateRequired)) {
            estimateRequired = (String) orderHeader.get('estReq');
        }
        populateReturnOrderEstimateRequired(returnOrder, estimateRequired);
        populateReturnOrderEstimateContact(returnOrder, orderHeader, estimateRequired);
        populateReturnOrderModRequestContact(returnOrder, orderHeader);

        String hospitalTrayName = (String) orderHeader.get('hospitalReferencedTrayName');
        setReturnOrderCustomFieldValue(
            returnOrder,
            'HospitalReferencedTrayName__c',
            String.isNotBlank(hospitalTrayName) ? hospitalTrayName.trim() : null
        );

        String customerReference = (String) orderHeader.get('customerReference');
        setReturnOrderCustomFieldValue(
            returnOrder,
            'CustomerReference__c',
            String.isNotBlank(customerReference) ? customerReference.trim() : null
        );

        String repairWarranty = (String) orderHeader.get('repairWarranty');
        if (String.isNotBlank(repairWarranty)) {
            setReturnOrderCustomFieldValue(
                returnOrder,
                'RepairWarranty__c',
                repairWarranty.trim()
            );
        }

        String previousReturnOrder = (String) orderHeader.get('previousReturnOrder');
        String warrantyNotes = (String) orderHeader.get('warrantyNotes');
        setReturnOrderCustomFieldValue(
            returnOrder,
            'PreviousReturnOrder__c',
            String.isNotBlank(previousReturnOrder) ? previousReturnOrder.trim() : null
        );
        setReturnOrderCustomFieldValue(
            returnOrder,
            'WarrantyNotes__c',
            String.isNotBlank(warrantyNotes) ? warrantyNotes.trim() : null
        );

        String customerPo = (String) orderHeader.get('customerPo');
        setReturnOrderCustomFieldValue(
            returnOrder,
            'CustomerPO__c',
            String.isNotBlank(customerPo) ? customerPo.trim() : null
        );
    }

    private static void applyReturnOrderType(
        ReturnOrder returnOrder,
        List<Object> lineObjects
    ) {
        if (lineObjects == null || lineObjects.isEmpty()) {
            return;
        }

        try {
            returnOrder.put(
                RETURN_ORDER_TYPE_FIELD,
                resolveReturnOrderTypeForLines(lineObjects)
            );
        } catch (SObjectException e) {
            if (!isInvalidCustomFieldException(e)) {
                throw e;
            }
        }
    }

    private static void applyShipToAddress(
        ReturnOrder returnOrder,
        Id customerAccountId,
        Map<String, Object> header,
        List<Object> lineObjects,
        Map<String, Object> orderHeader
    ) {
        if (returnOrder == null || customerAccountId == null) {
            return;
        }

        Map<Id, Account> shipToById = new Map<Id, Account>();
        Account primaryShipTo;
        for (Account shipTo : AccountService.getShipToAddressAccounts(customerAccountId)) {
            shipToById.put(shipTo.Id, shipTo);
            if (primaryShipTo == null && shipTo.ShiptoAddressStatus__c == 'Primary') {
                primaryShipTo = shipTo;
            }
        }

        Id selectedShipToId = resolveShipToAccountId(header, lineObjects, orderHeader);
        Account selectedShipTo = selectedShipToId == null
            ? null
            : shipToById.get(selectedShipToId);
        if (selectedShipToId != null && selectedShipTo == null) {
            throw new ReturnOrdersServiceException(
                'The selected Ship-To is not a valid Address account for this customer.'
            );
        }
        if (selectedShipTo == null) {
            selectedShipTo = primaryShipTo;
        }
        if (selectedShipTo == null) {
            return;
        }

        returnOrder.ShipToAddressAccount__c = selectedShipTo.Id;
        returnOrder.ShipToAddress__Street__s = selectedShipTo.BillingStreet;
        returnOrder.ShipToAddress__City__s = selectedShipTo.BillingCity;
        returnOrder.ShipToAddress__PostalCode__s = selectedShipTo.BillingPostalCode;
        String stateCode = String.isNotBlank(selectedShipTo.BillingStateCode)
            ? selectedShipTo.BillingStateCode
            : selectedShipTo.BillingState;
        String countryCode = String.isNotBlank(selectedShipTo.BillingCountryCode)
            ? selectedShipTo.BillingCountryCode
            : selectedShipTo.BillingCountry;
        if (String.isNotBlank(stateCode) && stateCode.length() <= 3) {
            returnOrder.ShipToAddress__StateCode__s = stateCode;
        }
        if (String.isNotBlank(countryCode) && countryCode.length() <= 3) {
            returnOrder.ShipToAddress__CountryCode__s = countryCode;
        }
    }

    private static List<ReturnOrderLineItem> buildLineItems(
        Id returnOrderId,
        List<Object> lineObjects,
        Map<String, Object> instrumentOrderHeader
    ) {
        List<ReturnOrderLineItem> lineItems = new List<ReturnOrderLineItem>();
        Boolean useInstrumentOrderHeader = instrumentOrderHeader != null;
        Id instrumentContactId = useInstrumentOrderHeader
            ? parseId((String) instrumentOrderHeader.get('contactId'))
            : null;

        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Boolean isSerialized = isSerializedLine(line) || isOtherSerializedLine(line);
            Boolean isOther = isOtherLine(line);
            ReturnOrderLineItem item = new ReturnOrderLineItem();
            item.ReturnOrderId = returnOrderId;
            Id inboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
                .get('Inbound')
                ?.getRecordTypeId();
            if (inboundRtId != null) {
                item.RecordTypeId = inboundRtId;
            }
            item.LineType__c = resolveRoliLineType(line);
            item.Serialized__c = isSerialized;
            item.QuantityReturned = isSerialized ||
                isOtherSerializedLine(line) ||
                isFlexibleScopeProductLine(line)
                ? QUANTITY_RETURNED_DEFAULT
                : parseQuantityReturned(line.get('quantityReturned'));
            item.AssetId = isSerialized ? parseId((String) line.get('assetId')) : null;

            Id product2Id = parseId(String.valueOf(line.get('product2Id')));
            if (product2Id == null) {
                throw new ReturnOrdersServiceException('Product is required on all line items.');
            }
            if (isInstrumentsLine(line)) {
                String serialNumber = (String) line.get('serialNumber');
                if (String.isNotBlank(serialNumber)) {
                    Id defaultProductId = resolveDefaultProductId();
                    if (defaultProductId != null && product2Id == defaultProductId) {
                        throw new ReturnOrdersServiceException(
                            'Default Product cannot be used when Serial Number is provided on instrument lines.'
                        );
                    }
                }
            }
            item.Product2Id = product2Id;

            String model = (String) line.get('model');
            if (isSerialized) {
                if (String.isBlank(model)) {
                    throw new ReturnOrdersServiceException('Model is required on serialized line items.');
                }
                item.Model__c = normalizeUppercaseValue(model);
            } else if (String.isNotBlank(model)) {
                item.Model__c = normalizeUppercaseValue(model);
            }

            Id departmentId = parseId((String) line.get('departmentId'));
            if (departmentId == null) {
                throw new ReturnOrdersServiceException('Department is required on all line items.');
            }
            item.Department__c = departmentId;

            Boolean instrumentsLine = isInstrumentsLine(line);
            Id lineContactId;
            if (instrumentsLine && useInstrumentOrderHeader) {
                lineContactId = instrumentContactId;
            } else {
                lineContactId = parseId((String) line.get('contactId'));
            }
            if (lineContactId == null) {
                throw new ReturnOrdersServiceException('Contact is required on all line items.');
            }
            item.Contact__c = lineContactId;

            String productLine;
            if (instrumentsLine) {
                productLine = INSTRUMENT_PRODUCT_LINE;
            } else if (isOther) {
                String itemType = (String) line.get('itemType');
                if (String.isBlank(itemType)) {
                    throw new ReturnOrdersServiceException('Item Type is required on Other line items.');
                }
                productLine = resolveProductLineForItemType(itemType.trim());
                if (String.isBlank(productLine)) {
                    throw new ReturnOrdersServiceException(
                        'No Product Line mapping found for Item Type ' + itemType.trim() + '.'
                    );
                }
            } else {
                productLine = (String) line.get('productLine');
            }
            if (String.isBlank(productLine)) {
                throw new ReturnOrdersServiceException('Product Line is required on all line items.');
            }
            item.ProductLine__c = productLine;

            if (isSerialized) {
                String serialNumber = (String) line.get('serialNumber');
                if (String.isNotBlank(serialNumber)) {
                    item.SerialNumber__c = normalizeUppercaseValue(serialNumber);
                }

                populateDisinfected(
                    item,
                    line,
                    'Disinfected is required on serialized line items.'
                );

                String reportedProblem = (String) line.get('reportedProblem');
                if (String.isBlank(reportedProblem)) {
                    throw new ReturnOrdersServiceException(
                        'Reported Problem is required on serialized line items.'
                    );
                }
                item.ReportedProblem__c = reportedProblem.trim();
                item.CustomerReference__c = (String) line.get('customerReference');
                item.CustomerPO__c = (String) line.get('customerPo');
                item.IsLoanerAsset__c = toBoolean(line.get('isLoanerAsset'));
                item.LoanerRequested__c = toBoolean(line.get('loanerRequested'));
            } else {
                if (!(instrumentsLine && useInstrumentOrderHeader)) {
                    item.CustomerPO__c = (String) line.get('customerPo');
                }
                if (!(instrumentsLine && useInstrumentOrderHeader)) {
                    String hospitalTrayName = (String) line.get('hospitalReferencedTrayName');
                    if (String.isNotBlank(hospitalTrayName)) {
                        item.HospitalReferencedTrayName__c = hospitalTrayName.trim();
                    }
                }
                if (!instrumentsLine) {
                    String customerReference = (String) line.get('customerReference');
                    if (String.isNotBlank(customerReference)) {
                        item.CustomerReference__c = customerReference.trim();
                    }
                }

                String reportedProblem = (String) line.get('reportedProblem');
                if (String.isBlank(reportedProblem)) {
                    throw new ReturnOrdersServiceException(
                        'Reported Problem is required on non-serialized line items.'
                    );
                }
                item.ReportedProblem__c = reportedProblem.trim();

                if (instrumentsLine) {
                    String itemDescription = (String) line.get('itemDescription');
                    if (String.isNotBlank(itemDescription)) {
                        item.ItemDescription__c = itemDescription.trim();
                    }

                    populateDisinfected(
                        item,
                        line,
                        'Disinfected is required on instrument line items.'
                    );

                    String serialNumber = (String) line.get('serialNumber');
                    if (String.isNotBlank(serialNumber)) {
                        item.SerialNumber__c = normalizeUppercaseValue(serialNumber);
                    }

                    item.ModRequest__c = toBoolean(line.get('modRequest'));
                    populateInstrumentAdditionalServiceFields(item, line);
                } else {
                    String itemType = (String) line.get('itemType');
                    if (String.isBlank(itemType)) {
                        throw new ReturnOrdersServiceException('Item Type is required on Other line items.');
                    }
                    item.ItemType__c = itemType.trim();

                    String itemDescription = (String) line.get('itemDescription');
                    if (String.isNotBlank(itemDescription)) {
                        item.ItemDescription__c = itemDescription.trim();
                    }

                    populateDisinfected(
                        item,
                        line,
                        'Disinfected is required on Other line items.'
                    );

                    if (isOtherSerializedLine(line)) {
                        String serialNumber = (String) line.get('serialNumber');
                        if (String.isBlank(serialNumber)) {
                            throw new ReturnOrdersServiceException(
                                'Serial Number is required on Other (Serialized) line items.'
                            );
                        }
                        item.SerialNumber__c = normalizeUppercaseValue(serialNumber);
                    }
                }
            }

            if (!(instrumentsLine && useInstrumentOrderHeader)) {
                String estimateRequired = (String) line.get('estimateRequired');
                if (String.isBlank(estimateRequired)) {
                    estimateRequired = (String) line.get('estReq');
                }
                populateEstimateRequiredFields(item, line);
                validateLineEstimateContactWhenRequired(line, estimateRequired);
                populateLineEstimateContact(item, line, estimateRequired);
                populateRepairWarrantyFields(item, line);
            }

            item.Status__c = String.isNotBlank((String) line.get('status'))
                ? (String) line.get('status')
                : STATUS_CREATED;
            lineItems.add(item);
        }

        return lineItems;
    }

    private static Account getAccountDetails(Id accountId) {
        try {
            if (accountId == null) {
                return null;
            }

            List<Account> accounts = [
                SELECT
                    Id,
                    Name,
                    SystemID__c,
                    OrgIDs__c,
                    BillingState
                FROM Account
                WHERE Id = :accountId
                WITH USER_MODE
                LIMIT 1
            ];
            return accounts.isEmpty() ? null : accounts[0];
        } catch (Exception e) {
            throw new ReturnOrdersServiceException('Error retrieving account: ' + e.getMessage());
        }
    }

    private static Map<String, String> getItemTypeToProductLineMappings() {
        if (itemTypeToProductLineCache != null) {
            return itemTypeToProductLineCache;
        }

        itemTypeToProductLineCache = new Map<String, String>();
        for (ROLIItemTypeandProductLine__mdt mapping : [
            SELECT ItemType__c, ProductLine__c
            FROM ROLIItemTypeandProductLine__mdt
            WHERE ItemType__c != NULL AND ProductLine__c != NULL AND IsActive__c = TRUE
        ]) {
            itemTypeToProductLineCache.put(mapping.ItemType__c, mapping.ProductLine__c);
        }
        return itemTypeToProductLineCache;
    }

    private static Boolean hasInstrumentOrderHeader(Map<String, Object> orderHeader) {
        return orderHeader != null && !orderHeader.isEmpty();
    }

    private static GroupedReturnOrderResult insertReturnOrder(
        Map<String, Object> header,
        Id repairCenterId,
        List<Object> lineObjects,
        Map<String, Object> orderHeader
    ) {
        Id accountId = parseId((String) header.get('accountId'));
        if (accountId == null) {
            throw new ReturnOrdersServiceException('Account is required.');
        }

        String operatingUnit = resolveOperatingUnit(header);
        if (String.isBlank(operatingUnit)) {
            throw new ReturnOrdersServiceException('Operating Unit is required.');
        }

        ReturnOrder returnOrder = new ReturnOrder();
        Id customerReturnRtId = Schema.SObjectType.ReturnOrder.getRecordTypeInfosByDeveloperName()
            .get('CustomerReturn')
            ?.getRecordTypeId();
        if (customerReturnRtId != null) {
            returnOrder.RecordTypeId = customerReturnRtId;
        }
        returnOrder.AccountId = accountId;
        returnOrder.Status = STATUS_CREATED;
        returnOrder.put('OperatingUnit__c', operatingUnit);
        returnOrder.CreationSource__c = (String) header.get('creationSource');
        returnOrder.SalesRep__c = parseId((String) header.get('salesRepId'));
        returnOrder.CaseId = parseId((String) header.get('caseId'));
        returnOrder.put('WorkOrder__c', parseId(String.valueOf(header.get('workOrderId'))));
        returnOrder.DestinationLocationId = repairCenterId;
        applyReturnOrderType(returnOrder, lineObjects);

        Boolean instrumentOrder = isInstrumentOrder(lineObjects);
        Boolean useInstrumentOrderHeader = instrumentOrder && hasInstrumentOrderHeader(orderHeader);
        if (instrumentOrder && useInstrumentOrderHeader) {
            validateInstrumentOrderHeader(orderHeader);
            applyInstrumentReturnOrderHeader(returnOrder, orderHeader);
        }

        applyShipToAddress(returnOrder, accountId, header, lineObjects, orderHeader);

        insert returnOrder;

        List<ReturnOrderLineItem> lineItems = buildLineItems(
            returnOrder.Id,
            lineObjects,
            useInstrumentOrderHeader ? orderHeader : null
        );
        if (!lineItems.isEmpty()) {
            insert lineItems;
            linkContentDocumentsToLineItems(lineItems, lineObjects);
        }

        List<ReturnOrder> createdRows = ReturnOrdersSelector.selectForReceivingFinish(
            returnOrder.Id
        );
        if (createdRows.isEmpty()) {
            throw new ReturnOrdersServiceException('Return Order was not found after create.');
        }
        ReturnOrder created = createdRows[0];

        GroupedReturnOrderResult result = new GroupedReturnOrderResult();
        result.returnOrderId = created.Id;
        result.returnOrderNumber = created.ReturnOrderNumber;
        result.returnOrderType = lineObjects == null || lineObjects.isEmpty()
            ? null
            : resolveReturnOrderTypeForLines(lineObjects);
        result.repairCenterName = resolveRepairCenterName(
            String.valueOf(repairCenterId),
            new List<RepairCenterRoutingRule__c>()
        );
        result.lineCount = lineObjects == null ? 0 : lineObjects.size();
        return result;
    }

    private static Boolean isFlexibleScopeProductLine(Map<String, Object> line) {
        if (line == null) {
            return false;
        }

        String productLine = (String) line.get('productLine');
        return String.isNotBlank(productLine) &&
            FLEXIBLE_SCOPE_PRODUCT_LINE.equalsIgnoreCase(productLine.trim());
    }

    private static Boolean isInstrumentOrder(List<Object> lineObjects) {
        if (lineObjects == null || lineObjects.isEmpty()) {
            return false;
        }

        for (Object lineObj : lineObjects) {
            if (!isInstrumentsLine((Map<String, Object>) lineObj)) {
                return false;
            }
        }
        return true;
    }

    private static Boolean isInstrumentsLine(Map<String, Object> line) {
        if (isOtherLine(line)) {
            return false;
        }
        if (line != null && line.containsKey('lineType')) {
            return 'instruments'.equalsIgnoreCase((String) line.get('lineType'));
        }
        return !isSerializedLine(line);
    }

    private static Boolean isInvalidCustomFieldException(SObjectException e) {
        String message = e == null ? null : e.getMessage();
        return message != null && message.contains('Invalid field');
    }

    private static Boolean isOtherLine(Map<String, Object> line) {
        if (line == null) {
            return false;
        }
        if (line.containsKey('lineType')) {
            String lineType = ((String) line.get('lineType')).toLowerCase();
            return lineType == 'other' ||
                lineType == 'other-serialized' ||
                lineType == 'other-non-serialized';
        }
        return false;
    }

    private static Boolean isOtherNonSerializedLine(Map<String, Object> line) {
        if (line == null || !line.containsKey('lineType')) {
            return false;
        }
        String lineType = ((String) line.get('lineType')).toLowerCase();
        if (lineType == 'other-non-serialized') {
            return true;
        }
        return lineType == 'other' && !toBoolean(line.get('serialized'));
    }

    private static Boolean isOtherSerializedLine(Map<String, Object> line) {
        if (line == null || !line.containsKey('lineType')) {
            return false;
        }
        String lineType = ((String) line.get('lineType')).toLowerCase();
        if (lineType == 'other-serialized') {
            return true;
        }
        return lineType == 'other' && toBoolean(line.get('serialized'));
    }

    private static Boolean isSerializedLine(Map<String, Object> line) {
        if (line == null) {
            return true;
        }
        if (line.containsKey('lineType')) {
            return 'serialized'.equalsIgnoreCase((String) line.get('lineType'));
        }
        if (line.containsKey('serialized')) {
            return toBoolean(line.get('serialized'));
        }
        return true;
    }

    private static void linkContentDocumentsToLineItems(
        List<ReturnOrderLineItem> lineItems,
        List<Object> lineObjects
    ) {
        if (lineItems == null || lineItems.isEmpty() || lineObjects == null || lineObjects.isEmpty()) {
            return;
        }

        Integer pairCount = Math.min(lineItems.size(), lineObjects.size());
        List<ContentDocumentLink> links = new List<ContentDocumentLink>();

        for (Integer index = 0; index < pairCount; index++) {
            ReturnOrderLineItem lineItem = lineItems[index];
            Map<String, Object> line = (Map<String, Object>) lineObjects[index];
            List<Id> contentDocumentIds = parseContentDocumentIds(line.get('contentDocumentIds'));
            // GW-3893: also link dedicated Mod Request form uploads from the instrument line.
            contentDocumentIds.addAll(
                parseContentDocumentIds(line.get('modFormContentDocumentIds'))
            );

            for (Id contentDocumentId : contentDocumentIds) {
                ContentDocumentLink link = new ContentDocumentLink();
                link.ContentDocumentId = contentDocumentId;
                link.LinkedEntityId = lineItem.Id;
                link.ShareType = 'V';
                link.Visibility = 'AllUsers';
                links.add(link);
            }
        }

        if (!links.isEmpty()) {
            Database.insert(links, false, AccessLevel.USER_MODE);
        }
    }

    private static String normalizeUppercaseValue(String value) {
        return String.isBlank(value) ? null : value.trim().toUpperCase();
    }

    private static List<Id> parseContentDocumentIds(Object value) {
        List<Id> contentDocumentIds = new List<Id>();
        if (value == null) {
            return contentDocumentIds;
        }

        if (value instanceof List<Object>) {
            for (Object documentIdValue : (List<Object>) value) {
                Id contentDocumentId = parseId(String.valueOf(documentIdValue));
                if (contentDocumentId != null) {
                    contentDocumentIds.add(contentDocumentId);
                }
            }
        }

        return contentDocumentIds;
    }

    private static Id parseId(String value) {
        if (String.isBlank(value)) {
            return null;
        }
        try {
            return (Id) value;
        } catch (Exception e) {
            return null;
        }
    }

    private static Decimal parseQuantityReturned(Object value) {
        if (value == null) {
            return QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Decimal) {
            return ((Decimal) value) > 0 ? (Decimal) value : QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Integer) {
            Integer intValue = (Integer) value;
            return intValue > 0 ? Decimal.valueOf(intValue) : QUANTITY_RETURNED_DEFAULT;
        }
        if (value instanceof Long) {
            Long longValue = (Long) value;
            return longValue > 0 ? Decimal.valueOf(longValue) : QUANTITY_RETURNED_DEFAULT;
        }

        String text = String.valueOf(value);
        if (String.isBlank(text)) {
            return QUANTITY_RETURNED_DEFAULT;
        }

        Decimal parsed = Decimal.valueOf(text);
        return parsed > 0 ? parsed : QUANTITY_RETURNED_DEFAULT;
    }

    private static void populateDisinfected(
        ReturnOrderLineItem item,
        Map<String, Object> line,
        String requiredMessage
    ) {
        String disinfected = (String) line.get('disinfected');
        if (String.isBlank(disinfected)) {
            throw new ReturnOrdersServiceException(requiredMessage);
        }
        item.Disinfected__c = disinfected;
    }

    private static void populateEstimateRequiredFields(
        ReturnOrderLineItem item,
        Map<String, Object> line
    ) {
        String estimateRequired = (String) line.get('estimateRequired');
        if (String.isBlank(estimateRequired)) {
            estimateRequired = (String) line.get('estReq');
        }
        if (String.isBlank(estimateRequired)) {
            throw new ReturnOrdersServiceException('Estimate Required is required on all line items.');
        }

        if (
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap()
                .containsKey('estimaterequired__c')
        ) {
            item.EstimateRequired__c = estimateRequired;
            return;
        }

        setLineItemCustomFieldValue(item, 'EstReq__c', estimateRequired);
    }

    private static void populateInstrumentAdditionalServiceFields(
        ReturnOrderLineItem item,
        Map<String, Object> line
    ) {
        Boolean additionalServices = toBoolean(line.get('additionalServices'));
        Boolean modRequest = toBoolean(line.get('modRequest'));
        String serialNumber = (String) line.get('serialNumber');
        Boolean hasSerialNumber = String.isNotBlank(serialNumber);

        if (additionalServices && modRequest) {
            setLineItemCustomFieldValue(
                item,
                'InsulationPowderCoating__c',
                (String) line.get('insulationPowderCoating')
            );
            return;
        }

        if (additionalServices && !modRequest && hasSerialNumber) {
            setLineItemCustomFieldValue(
                item,
                'LegPositionersStirrup__c',
                (String) line.get('legPositionersStirrup')
            );
            return;
        }

        if (additionalServices && !modRequest && !hasSerialNumber) {
            setLineItemCustomBooleanFieldValue(
                item,
                'AdditionalServiceRepair__c',
                toBoolean(line.get('additionalServiceRepair'))
            );
            setLineItemCustomFieldValue(
                item,
                'LaserMarking__c',
                (String) line.get('laserMarking')
            );
            setLineItemCustomFieldValue(
                item,
                'ColorDipping__c',
                (String) line.get('colorDipping')
            );
            setLineItemCustomFieldValue(
                item,
                'NumberOfRings__c',
                (String) line.get('numberOfRings')
            );
        }
    }

    private static void populateLineEstimateContact(
        ReturnOrderLineItem item,
        Map<String, Object> line,
        String estimateRequired
    ) {
        if (item == null || line == null) {
            return;
        }

        Map<String, Schema.SObjectField> lineFields =
            Schema.SObjectType.ReturnOrderLineItem.fields.getMap();
        if (!lineFields.containsKey('estimatecontact__c')) {
            return;
        }

        if (!ESTIMATE_REQUIRED_QUOTE_VALUE.equalsIgnoreCase(estimateRequired)) {
            item.put('EstimateContact__c', null);
            return;
        }

        item.put('EstimateContact__c', resolveLineEstimateContactId(line));
    }

    private static void populateRepairWarrantyFields(
        ReturnOrderLineItem item,
        Map<String, Object> line
    ) {
        String repairWarranty = (String) line.get('repairWarranty');
        if (String.isBlank(repairWarranty)) {
            return;
        }

        item.RepairWarranty__c = repairWarranty.trim();
        String previousReturnOrder = (String) line.get('previousReturnOrder');
        String warrantyNotes = (String) line.get('warrantyNotes');
        String trimmedPreviousReturnOrder = String.isNotBlank(previousReturnOrder)
            ? previousReturnOrder.trim()
            : null;
        String trimmedWarrantyNotes = String.isNotBlank(warrantyNotes)
            ? warrantyNotes.trim()
            : null;
        if (
            'Yes'.equalsIgnoreCase(item.RepairWarranty__c) &&
            String.isBlank(trimmedPreviousReturnOrder) &&
            String.isBlank(trimmedWarrantyNotes)
        ) {
            throw new ReturnOrdersServiceException(
                'Warranty Notes is required when Repair Warranty is Yes and Previous Return Order is not provided.'
            );
        }
        item.PreviousReturnOrder__c = trimmedPreviousReturnOrder;
        item.WarrantyNotes__c = trimmedWarrantyNotes;
    }

    private static void populateReturnOrderEstimateContact(
        ReturnOrder returnOrder,
        Map<String, Object> orderHeader,
        String estimateRequired
    ) {
        if (returnOrder == null) {
            return;
        }

        Map<String, Schema.SObjectField> returnOrderFields =
            Schema.SObjectType.ReturnOrder.fields.getMap();
        if (!returnOrderFields.containsKey('EstimateContact__c')) {
            return;
        }

        if (!ESTIMATE_REQUIRED_QUOTE_VALUE.equalsIgnoreCase(estimateRequired)) {
            returnOrder.put('EstimateContact__c', null);
            return;
        }

        returnOrder.put('EstimateContact__c', resolveEstimateContactId(orderHeader));
    }

    private static void populateReturnOrderEstimateRequired(
        ReturnOrder returnOrder,
        String estimateRequired
    ) {
        if (returnOrder == null || String.isBlank(estimateRequired)) {
            return;
        }

        Map<String, Schema.SObjectField> returnOrderFields =
            Schema.SObjectType.ReturnOrder.fields.getMap();
        if (returnOrderFields.containsKey('EstimateRequired__c')) {
            returnOrder.EstimateRequired__c = estimateRequired;
            return;
        }

        setReturnOrderCustomFieldValue(returnOrder, 'EstReq__c', estimateRequired);
    }

    private static void populateReturnOrderModRequestContact(
        ReturnOrder returnOrder,
        Map<String, Object> orderHeader
    ) {
        if (returnOrder == null) {
            return;
        }

        Map<String, Schema.SObjectField> returnOrderFields =
            Schema.SObjectType.ReturnOrder.fields.getMap();
        if (!returnOrderFields.containsKey('ModRequestContact__c')) {
            return;
        }

        Id modRequestContactId = resolveModRequestContactId(orderHeader);
        returnOrder.put('ModRequestContact__c', modRequestContactId);
    }

    private static Product2 queryDefaultProduct() {
        List<Product2> products = [
            SELECT Id, Name, Description, ProductLine__c, ProductCode, Model__c
            FROM Product2
            WHERE Name = :DEFAULT_PRODUCT_NAME AND IsActive = TRUE
            WITH USER_MODE
            ORDER BY CreatedDate ASC
            LIMIT 1
        ];
        return products.isEmpty() ? null : products[0];
    }

    private static String readAccountOperatingUnit(Account account) {
        if (account == null) {
            return null;
        }

        if (String.isNotBlank(account.OrgIDs__c)) {
            return account.OrgIDs__c.trim();
        }

        return null;
    }

    private static String resolveDefaultProductId() {
        Product2 defaultProduct = queryDefaultProduct();
        return defaultProduct == null ? null : String.valueOf(defaultProduct.Id);
    }

    private static Id resolveEstimateContactId(Map<String, Object> orderHeader) {
        if (orderHeader == null) {
            return null;
        }

        Id estimateContactId = parseId((String) orderHeader.get('estimateContactId'));
        return estimateContactId;
    }

    private static Id resolveLineEstimateContactId(Map<String, Object> line) {
        if (line == null) {
            return null;
        }

        return parseId((String) line.get('estimateContactId'));
    }

    private static Id resolveModRequestContactId(Map<String, Object> orderHeader) {
        if (orderHeader == null) {
            return null;
        }

        Id contactId = parseId((String) orderHeader.get('modRequestContactId'));
        if (contactId == null) {
            contactId = parseId((String) orderHeader.get('modRequestContact'));
        }
        return contactId;
    }

    private static String resolveOperatingUnit(Map<String, Object> header) {
        if (header == null) {
            return null;
        }

        String operatingUnit = (String) header.get('operatingUnit');
        if (String.isNotBlank(operatingUnit)) {
            return operatingUnit.trim();
        }

        Id accountId = parseId((String) header.get('accountId'));
        if (accountId == null) {
            return null;
        }

        return readAccountOperatingUnit(getAccountDetails(accountId));
    }

    private static String resolveProductLineForItemType(String itemType) {
        if (String.isBlank(itemType)) {
            return null;
        }
        return getItemTypeToProductLineMappings().get(itemType);
    }

    private static String resolveRepairCenterName(
        String repairCenterId,
        List<RepairCenterRoutingRule__c> routingRules
    ) {
        Id locationId = parseId(repairCenterId);
        if (locationId == null) {
            return 'Repair Center';
        }

        for (RepairCenterRoutingRule__c rule : routingRules) {
            if (rule.RepairCenter__c == locationId && rule.RepairCenter__r != null) {
                return rule.RepairCenter__r.Name;
            }
        }

        List<Schema.Location> locations = [
            SELECT Name
            FROM Location
            WHERE Id = :locationId
            WITH USER_MODE
            LIMIT 1
        ];
        return locations.isEmpty() ? 'Repair Center' : locations[0].Name;
    }

    private static String resolveReturnOrderTypeForLines(List<Object> lineObjects) {
        if (lineObjects == null || lineObjects.isEmpty()) {
            throw new ReturnOrdersServiceException('Add at least one line item.');
        }

        String returnOrderType = null;
        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            String lineType = resolveReturnOrderTypeFromLine(line);
            if (returnOrderType == null) {
                returnOrderType = lineType;
            } else if (!returnOrderType.equalsIgnoreCase(lineType)) {
                throw new ReturnOrdersServiceException(
                    'A return order cannot include line items with different types.'
                );
            }
        }
        return returnOrderType;
    }

    private static String resolveReturnOrderTypeFromLine(Map<String, Object> line) {
        if (isOtherSerializedLine(line)) {
            return RETURN_ORDER_TYPE_OTHER_SERIALIZED;
        }
        if (isOtherNonSerializedLine(line)) {
            return RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED;
        }
        if (isOtherLine(line)) {
            return toBoolean(line.get('serialized'))
                ? RETURN_ORDER_TYPE_OTHER_SERIALIZED
                : RETURN_ORDER_TYPE_OTHER_NON_SERIALIZED;
        }
        if (isInstrumentsLine(line)) {
            return RETURN_ORDER_TYPE_INSTRUMENTS;
        }
        return RETURN_ORDER_TYPE_SERIALIZED;
    }

    private static String resolveRoliLineType(Map<String, Object> line) {
        String payloadLineType = line == null ? null : (String) line.get('roliLineType');
        if (String.isNotBlank(payloadLineType)) {
            return payloadLineType.trim();
        }
        if (isSerializedLine(line)) {
            return ROLI_LINE_TYPE_SERIALIZED;
        }
        if (isOtherSerializedLine(line)) {
            return ROLI_LINE_TYPE_OTHER_SERIALIZED;
        }
        if (isOtherNonSerializedLine(line) || isOtherLine(line)) {
            return ROLI_LINE_TYPE_OTHER_NON_SERIALIZED;
        }
        return ROLI_LINE_TYPE_INSTRUMENT;
    }

    private static Id resolveShipToAccountId(
        Map<String, Object> header,
        List<Object> lineObjects,
        Map<String, Object> orderHeader
    ) {
        Id fromOrderHeader = orderHeader == null
            ? null
            : parseId((String) orderHeader.get('shipToAccountId'));
        if (fromOrderHeader != null) {
            return fromOrderHeader;
        }

        Id fromHeader = header == null ? null : parseId((String) header.get('shipToAccountId'));
        if (fromHeader != null) {
            return fromHeader;
        }

        if (lineObjects == null) {
            return null;
        }
        for (Object lineObj : lineObjects) {
            Map<String, Object> line = (Map<String, Object>) lineObj;
            Id fromLine = parseId((String) line.get('shipToAccountId'));
            if (fromLine != null) {
                return fromLine;
            }
        }
        return null;
    }

    private static void setLineItemCustomBooleanFieldValue(
        ReturnOrderLineItem item,
        String fieldApiName,
        Boolean value
    ) {
        if (value != true) {
            return;
        }

        try {
            item.put(fieldApiName, true);
        } catch (SObjectException e) {
            if (!isInvalidCustomFieldException(e)) {
                throw e;
            }
        }
    }

    private static void setLineItemCustomFieldValue(
        ReturnOrderLineItem item,
        String fieldApiName,
        String value
    ) {
        if (String.isBlank(value)) {
            return;
        }

        try {
            item.put(fieldApiName, value.trim());
        } catch (SObjectException e) {
            if (!isInvalidCustomFieldException(e)) {
                throw e;
            }
        }
    }

    private static void setReturnOrderCustomFieldValue(
        ReturnOrder returnOrder,
        String fieldApiName,
        String value
    ) {
        if (returnOrder == null || String.isBlank(fieldApiName) || String.isBlank(value)) {
            return;
        }

        try {
            returnOrder.put(fieldApiName, value.trim());
        } catch (SObjectException e) {
            if (!isInvalidCustomFieldException(e)) {
                throw e;
            }
        }
    }

    private static Boolean toBoolean(Object value) {
        if (value == null) {
            return false;
        }
        if (value instanceof Boolean) {
            return (Boolean) value;
        }
        String text = String.valueOf(value);
        return 'true'.equalsIgnoreCase(text) || '1'.equals(text) || 'yes'.equalsIgnoreCase(text);
    }

    private static void validateContactHasEmail(Id contactId, String message) {
        if (contactId == null) {
            return;
        }

        List<Contact> contacts = [
            SELECT Email
            FROM Contact
            WHERE Id = :contactId
            WITH USER_MODE
            LIMIT 1
        ];
        if (contacts.isEmpty() || String.isBlank(contacts[0].Email)) {
            throw new ReturnOrdersServiceException(message);
        }
    }

    private static void validateEstimateContactWhenRequired(
        Map<String, Object> orderHeader,
        String estimateRequired
    ) {
        if (!ESTIMATE_REQUIRED_QUOTE_VALUE.equalsIgnoreCase(estimateRequired)) {
            return;
        }

        Id estimateContactId = resolveEstimateContactId(orderHeader);
        if (estimateContactId == null) {
            throw new ReturnOrdersServiceException(
                'Estimate Contact is required when Estimate Required is Estimate Required.'
            );
        }

        validateContactHasEmail(
            estimateContactId,
            'Estimate Contact must have an email address.'
        );
    }

    private static void validateInstrumentOrderHeader(Map<String, Object> orderHeader) {
        if (orderHeader == null) {
            throw new ReturnOrdersServiceException(
                'Return order header details are required for instrument return orders.'
            );
        }

        Id contactId = parseId((String) orderHeader.get('contactId'));
        if (contactId == null) {
            throw new ReturnOrdersServiceException('Contact is required on instrument return orders.');
        }

        String estimateRequired = (String) orderHeader.get('estimateRequired');
        if (String.isBlank(estimateRequired)) {
            estimateRequired = (String) orderHeader.get('estReq');
        }
        if (String.isBlank(estimateRequired)) {
            throw new ReturnOrdersServiceException(
                'Estimate Required is required on instrument return orders.'
            );
        }

        validateEstimateContactWhenRequired(orderHeader, estimateRequired);
        validateModRequestContactWhenProvided(orderHeader);

        String repairWarranty = (String) orderHeader.get('repairWarranty');
        if (!'Yes'.equalsIgnoreCase(repairWarranty)) {
            return;
        }

        String previousReturnOrder = (String) orderHeader.get('previousReturnOrder');
        String warrantyNotes = (String) orderHeader.get('warrantyNotes');
        if (
            String.isBlank(previousReturnOrder) &&
            String.isBlank(warrantyNotes)
        ) {
            throw new ReturnOrdersServiceException(
                'Warranty Notes is required when Repair Warranty is Yes and Previous Return Order is not provided.'
            );
        }
    }

    private static void validateLineEstimateContactWhenRequired(
        Map<String, Object> line,
        String estimateRequired
    ) {
        if (!ESTIMATE_REQUIRED_QUOTE_VALUE.equalsIgnoreCase(estimateRequired)) {
            return;
        }

        Id estimateContactId = resolveLineEstimateContactId(line);
        if (estimateContactId == null) {
            throw new ReturnOrdersServiceException(
                'Estimate Contact is required when Estimate Required is Estimate Required.'
            );
        }

        validateContactHasEmail(
            estimateContactId,
            'Estimate Contact must have an email address.'
        );
    }

    private static void validateModRequestContactWhenProvided(Map<String, Object> orderHeader) {
        Boolean hasModRequest = toBoolean(orderHeader == null ? null : orderHeader.get('hasModRequest'));
        Id modRequestContactId = resolveModRequestContactId(orderHeader);

        if (hasModRequest && modRequestContactId == null) {
            throw new ReturnOrdersServiceException(
                'Mod Request Contact is required when Mod Request is selected.'
            );
        }

        if (modRequestContactId == null) {
            return;
        }

        validateContactHasEmail(
            modRequestContactId,
            'Mod Request Contact must have an Email address.'
        );
    }

    /**
     * @description Thrown when a ReturnOrder service operation fails.
     */
    public class ReturnOrdersServiceException extends Exception {}
}