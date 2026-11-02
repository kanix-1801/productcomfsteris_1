/**
 * @description Service-layer orchestration for Vendor FedEx shipping labels via ShoutOut.
 *              Creates the label, stores tracking on the Return Order, attaches the shipping-label
 *              PDF and packing-slip PDF (HTML template → Blob.toPdf), and copies tracking onto
 *              the grouped vendor Work Orders.
 * @author Uptima Development Team
 * @date 2026-08-13
 * @group Services
 */
public with sharing class VendorFedExShipmentService {
    private static final String PACKING_SLIP_TEMPLATE_TITLE =
        'Vendor Shipping Change Notification Template';
    private static final String ROLI_RECORD_TYPE_OUTBOUND = 'Outbound';

    @TestVisible
    private static TrackingResponseDTO testResponse;

    /** Test hook: fail this many callout attempts, then return the mock success response. */
    @TestVisible
    private static Integer testRemainingCalloutFailures = 0;

    private static final Integer CALLOUT_ATTEMPTS = 3;
    private static final Integer RETRY_PAUSE_MS = 2000;

    /**
     * @description ShoutOut tracking payload: tracking number plus shipping-label PDF bytes.
     */
    public class TrackingResponseDTO {
        public String trackingNumber;
        public Blob shippingLabel;
    }

    /**
     * @description Request body serialized to ShoutOut RESTBODY for GetReturnOrderShippingLabel.
     */
    public class FedExShipmentRequestDTO {
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

    private class ResolvedAddress {
        public String line1;
        public String line2;
        public String city;
        public String stateCode;
        public String postalCode;
        public String countryCode;
    }

    private class ShipmentWork {
        public ReturnOrder returnOrder;
        public List<WorkOrder> workOrders;
        public TrackingResponseDTO response;
        public String restBody;
    }

    /**
     * @description Pre-flight check used by Consolidate Vendor Shipment before Complete so
     *              FedEx queueable address failures are caught in the UI instead of Apex Jobs.
     * @param vendorAccountId Vendor Account Id (ship-to)
     * @param vendorLabel Vendor display name for the error message
     * @param repairCenterLocationId Repair Center Location Id (return address)
     * @param repairCenterLabel Repair Center display name for the error message
     * @return Error message when addresses are incomplete; null when both are usable
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

        Map<Id, ResolvedAddress> vendorAddressByAccountId = resolveAccountAddresses(
            new Set<Id>{ vendorAccountId }
        );
        Map<Id, ResolvedAddress> repairCenterAddressByLocationId = resolveLocationAddresses(
            new Set<Id>{ repairCenterLocationId }
        );

        ResolvedAddress vendorAddress = vendorAddressByAccountId.get(vendorAccountId);
        if (!hasUsableFedExAddress(vendorAddress)) {
            String vendorName = String.isNotBlank(vendorLabel)
                ? vendorLabel
                : 'the selected Vendor';
            return (
                'Vendor "' +
                vendorName +
                '" ship-to address is incomplete' +
                formatMissingFedExAddressSuffix(vendorAddress) +
                '. Add Street, City, State, and Postal Code on Billing/Shipping or a related Address before completing.'
            );
        }

        ResolvedAddress repairCenterAddress = repairCenterAddressByLocationId.get(
            repairCenterLocationId
        );
        if (!hasUsableFedExAddress(repairCenterAddress)) {
            String repairCenterName = String.isNotBlank(repairCenterLabel)
                ? repairCenterLabel
                : 'the Repair Center';
            return (
                'Repair Center "' +
                repairCenterName +
                '" address is incomplete' +
                formatMissingFedExAddressSuffix(repairCenterAddress) +
                '. Add Street, City, State, and Postal Code on the Location before completing.'
            );
        }
        return null;
    }

    /**
     * @description True when FedEx can use this account as a ship-to address.
     */
    public static Boolean hasVendorShipToAddress(Id vendorAccountId) {
        if (vendorAccountId == null) {
            return false;
        }
        ResolvedAddress vendorAddress = resolveAccountAddresses(new Set<Id>{ vendorAccountId })
            .get(vendorAccountId);
        return hasUsableFedExAddress(vendorAddress);
    }

    /**
     * @description True when FedEx can use this Location as the Repair Center return address.
     */
    public static Boolean hasRepairCenterAddress(Id repairCenterLocationId) {
        if (repairCenterLocationId == null) {
            return false;
        }
        ResolvedAddress repairCenterAddress = resolveLocationAddresses(
                new Set<Id>{ repairCenterLocationId }
            )
            .get(repairCenterLocationId);
        return hasUsableFedExAddress(repairCenterAddress);
    }

    /**
     * @description FedEx requires street, city, state, and postal code (HTTP 400 otherwise).
     */
    private static Boolean hasUsableFedExAddress(ResolvedAddress addressValue) {
        return addressValue != null &&
            String.isNotBlank(addressValue.line1) &&
            String.isNotBlank(addressValue.city) &&
            String.isNotBlank(addressValue.stateCode) &&
            String.isNotBlank(addressValue.postalCode);
    }

    private static String formatMissingFedExAddressSuffix(ResolvedAddress addressValue) {
        List<String> missing = missingFedExAddressFields(addressValue);
        if (missing.isEmpty()) {
            return '';
        }
        return ' (missing: ' + String.join(missing, ', ') + ')';
    }

    private static List<String> missingFedExAddressFields(ResolvedAddress addressValue) {
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

    /**
     * @description Creates FedEx labels for each Vendor Return Order. Callouts run
     *              first, then tracking, labels, packing slips, and Work Order updates.
     * @param returnOrderIdToWorkOrderIdsMap Vendor Return Order Id to grouped Work Order Ids
     */
    public static void createShipments(Map<Id, List<Id>> returnOrderIdToWorkOrderIdsMap) {
        if (returnOrderIdToWorkOrderIdsMap == null || returnOrderIdToWorkOrderIdsMap.isEmpty()) {
            return;
        }

        try {
            Set<Id> returnOrderIdSet = returnOrderIdToWorkOrderIdsMap.keySet();
            Set<Id> workOrderIdSet = new Set<Id>();
            for (List<Id> workOrderIdList : returnOrderIdToWorkOrderIdsMap.values()) {
                if (workOrderIdList != null) {
                    workOrderIdSet.addAll(workOrderIdList);
                }
            }

            Map<Id, ReturnOrder> returnOrderByIdMap = queryReturnOrders(returnOrderIdSet);
            Map<Id, WorkOrder> workOrderByIdMap = queryWorkOrders(workOrderIdSet);
            Map<Id, List<ReturnOrderLineItem>> outboundLineListByRoIdMap = queryOutboundLines(
                returnOrderIdSet
            );

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

            Map<Id, ResolvedAddress> vendorAddressByAccountIdMap = resolveAccountAddresses(
                accountIdSet
            );
            Map<Id, ResolvedAddress> repairCenterAddressByLocationIdMap =
                resolveLocationAddresses(locationIdSet);
            Map<Id, String> contactNameByReturnOrderIdMap = resolveContactNameByReturnOrderIdMap(
                returnOrderByIdMap.values()
            );

            List<ShipmentWork> shipmentWorkList = new List<ShipmentWork>();
            for (Id returnOrderId : returnOrderIdToWorkOrderIdsMap.keySet()) {
                ReturnOrder returnOrderRecord = returnOrderByIdMap.get(returnOrderId);
                if (returnOrderRecord == null) {
                    throw new VendorFedExShipmentException(
                        'Vendor Return Order was not found for FedEx shipment.'
                    );
                }

                ShipmentWork shipmentWork = new ShipmentWork();
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
                validateAddresses(returnOrderRecord, vendorAddress, repairCenterAddress);

                FedExShipmentRequestDTO request = buildRequest(
                    returnOrderRecord,
                    vendorAddress,
                    repairCenterAddress,
                    contactNameByReturnOrderIdMap.get(returnOrderRecord.Id)
                );
                shipmentWork.restBody = JSON.serialize(request);
                shipmentWorkList.add(shipmentWork);
            }

            for (ShipmentWork shipmentWork : shipmentWorkList) {
                shipmentWork.response = requestShipment(shipmentWork.restBody);
            }

            persistShipmentResults(shipmentWorkList, outboundLineListByRoIdMap);
        } catch (VendorFedExShipmentException e) {
            Logger.error(
                new LogMessage(
                    'VendorFedExShipmentService.createShipments failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw e;
        } catch (Exception e) {
            Logger.error(
                new LogMessage(
                    'VendorFedExShipmentService.createShipments failed: {0}',
                    e.getMessage()
                ),
                e
            );
            throw new VendorFedExShipmentException(
                'FedEx shipment failed: ' + e.getMessage(),
                e
            );
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Calls ShoutOut FEDEX shipping-label operation and returns tracking plus PDF bytes.
     *              Retries when Boomi returns no tracking number or a transient callout failure.
     * @param restBody JSON request body for ShoutOut RESTBODY
     * @return Tracking number and shipping-label blob
     */
    @TestVisible
    static TrackingResponseDTO requestShipment(String restBody) {
        VendorFedExShipmentException lastException;
        for (Integer attempt = 1; attempt <= CALLOUT_ATTEMPTS; attempt++) {
            try {
                return performShipmentCallout(restBody);
            } catch (VendorFedExShipmentException e) {
                lastException = e;
                Logger.warn(
                    new LogMessage(
                        'FedEx shipment call attempt {0} of {1} failed: {2}',
                        attempt,
                        CALLOUT_ATTEMPTS,
                        e.getMessage()
                    )
                );
                if (attempt < CALLOUT_ATTEMPTS) {
                    pauseBetweenRetries();
                }
            }
        }
        throw lastException;
    }

    private static TrackingResponseDTO performShipmentCallout(String restBody) {
        if (Test.isRunningTest()) {
            if (testRemainingCalloutFailures > 0) {
                testRemainingCalloutFailures--;
                throw new VendorFedExShipmentException(
                    'FedEx shipment call did not return a tracking number. ' +
                    'An unexpected error has occurred.'
                );
            }
            if (testResponse != null) {
                if (String.isBlank(testResponse.trackingNumber)) {
                    throw new VendorFedExShipmentException(
                        'FedEx shipment call did not return a tracking number.'
                    );
                }
                return testResponse;
            }
            TrackingResponseDTO mockResponse = new TrackingResponseDTO();
            mockResponse.trackingNumber = '794900000000';
            mockResponse.shippingLabel = Blob.valueOf('MOCK-SHIPPING-LABEL');
            return mockResponse;
        }

        SO_Callout callout = new SO_Callout();
        callout
            .addToRequestMap(SO_Constants.CALLOUTOPERATION, VendorFedExConfig.getCalloutOperation())
            .addToRequestMap(SO_Constants.RESTBODY, restBody);
        callout.callWebService();

        Boolean success = (Boolean) callout.serviceResponseMap.get('SO_SUCCESS');
        Object serviceData = callout.serviceResponseMap.get('SERVICE_DATA');
        String jsonPayload = serviceDataToJson(serviceData);

        if (success == false) {
            throw new VendorFedExShipmentException(
                'FedEx shipment call failed: ' +
                formatCalloutFailure(callout.serviceResponseMap, jsonPayload)
            );
        }

        if (serviceData == null) {
            throw new VendorFedExShipmentException('FedEx shipment call returned no SERVICE_DATA.');
        }

        TrackingResponseDTO response = (TrackingResponseDTO) JSON.deserialize(
            jsonPayload,
            TrackingResponseDTO.class
        );
        if (response == null || String.isBlank(response.trackingNumber)) {
            String serviceErrors = extractErrorMessages(jsonPayload);
            throw new VendorFedExShipmentException(
                'FedEx shipment call did not return a tracking number.' +
                (String.isBlank(serviceErrors) ? '' : ' ' + serviceErrors)
            );
        }
        return response;
    }

    private static void pauseBetweenRetries() {
        if (Test.isRunningTest()) {
            return;
        }
        Long startTime = Datetime.now().getTime();
        while (Datetime.now().getTime() - startTime < RETRY_PAUSE_MS) {
            // Short pause so a transient Boomi miss can recover in the same job.
        }
    }

    @TestVisible
    static String serviceDataToJson(Object serviceData) {
        if (serviceData == null) {
            return null;
        }
        return serviceData instanceof String
            ? (String) serviceData
            : JSON.serialize(serviceData);
    }

    @TestVisible
    static String formatCalloutFailure(
        Map<String, Object> responseMap,
        String jsonPayload
    ) {
        List<String> parts = new List<String>();
        Object status = responseMap.get('SERVICE_STATUS');
        if (status != null && String.isNotBlank(String.valueOf(status))) {
            parts.add('HTTP ' + String.valueOf(status));
        }
        Object soReturn = responseMap.get('SO_RETURN');
        if (soReturn != null) {
            String returnText = String.valueOf(soReturn);
            if (String.isNotBlank(returnText) && returnText != 'null') {
                parts.add(returnText);
            }
        }
        String serviceErrors = extractErrorMessages(jsonPayload);
        if (String.isNotBlank(serviceErrors)) {
            parts.add(serviceErrors);
        }
        return parts.isEmpty() ? 'unknown error' : String.join(parts, ' — ');
    }

    @TestVisible
    static String extractErrorMessages(String jsonPayload) {
        if (String.isBlank(jsonPayload)) {
            return null;
        }
        try {
            Object parsed = JSON.deserializeUntyped(jsonPayload);
            if (!(parsed instanceof Map<String, Object>)) {
                return null;
            }
            Object errorsObj = ((Map<String, Object>) parsed).get('errors');
            if (!(errorsObj instanceof List<Object>)) {
                return null;
            }
            List<String> messages = new List<String>();
            for (Object errorObj : (List<Object>) errorsObj) {
                if (!(errorObj instanceof Map<String, Object>)) {
                    continue;
                }
                Object message = ((Map<String, Object>) errorObj).get('errorMessage');
                if (message != null && String.isNotBlank(String.valueOf(message))) {
                    messages.add(String.valueOf(message).trim().removeEnd(',').trim());
                }
            }
            return messages.isEmpty() ? null : String.join(messages, '; ');
        } catch (Exception e) {
            return null;
        }
    }

    private static void persistShipmentResults(
        List<ShipmentWork> jobs,
        Map<Id, List<ReturnOrderLineItem>> outboundLinesByRoId
    ) {
        List<ReturnOrder> returnOrdersToUpdate = new List<ReturnOrder>();
        List<WorkOrder> workOrdersToUpdate = new List<WorkOrder>();
        List<ContentVersion> filesToInsert = new List<ContentVersion>();

        for (ShipmentWork job : jobs) {
            String trackingNumber = job.response.trackingNumber;
            ReturnOrder roUpdate = new ReturnOrder(
                Id = job.returnOrder.Id,
                InboundTrackingNumber__c = trackingNumber
            );
            returnOrdersToUpdate.add(roUpdate);

            String fileBaseName = shippingFileBaseName(job.returnOrder.ReturnOrderNumber);
            if (job.response.shippingLabel != null) {
                ContentVersion label = new ContentVersion();
                label.Title = fileBaseName;
                label.PathOnClient = fileBaseName + '.pdf';
                label.VersionData = job.response.shippingLabel;
                label.FirstPublishLocationId = job.returnOrder.Id;
                filesToInsert.add(label);
            }

            Blob packingSlipBody = buildPackingSlip(
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

        // Copy tracking onto every Work Order linked to these Vendor ROs via ReturnOrder__c.
        Set<Id> returnOrderIds = new Set<Id>();
        Map<Id, String> trackingByReturnOrderId = new Map<Id, String>();
        for (ShipmentWork job : jobs) {
            returnOrderIds.add(job.returnOrder.Id);
            trackingByReturnOrderId.put(job.returnOrder.Id, job.response.trackingNumber);
        }
        if (!returnOrderIds.isEmpty()) {
            for (WorkOrder wo : [
                SELECT Id, ReturnOrder__c
                FROM WorkOrder
                WHERE ReturnOrder__c IN :returnOrderIds
                WITH USER_MODE
            ]) {
                String trackingNumber = trackingByReturnOrderId.get(
                    (Id) wo.get('ReturnOrder__c')
                );
                if (String.isNotBlank(trackingNumber)) {
                    workOrdersToUpdate.add(
                        new WorkOrder(Id = wo.Id, TrackingNumber__c = trackingNumber)
                    );
                }
            }
        }

        if (!returnOrdersToUpdate.isEmpty()) {
            update returnOrdersToUpdate;
        }
        if (!workOrdersToUpdate.isEmpty()) {
            update workOrdersToUpdate;
        }
        if (!filesToInsert.isEmpty()) {
            insert filesToInsert;
        }
    }

    private static FedExShipmentRequestDTO buildRequest(
        ReturnOrder returnOrderRecord,
        ResolvedAddress vendorAddress,
        ResolvedAddress repairCenterAddress,
        String contactName
    ) {
        FedExShipmentRequestDTO request = new FedExShipmentRequestDTO();
        request.FedExAccount = VendorFedExConfig.getFedExAccount();
        request.CustomerDisplay = returnOrderRecord.Account == null
            ? null
            : returnOrderRecord.Account.Name;
        // Same Carrier Service level resolution as inbound FedEx (Customer Preference).
        request.ShippingMethod = FedExService.getShippingMethod(returnOrderRecord.AccountId);
        request.ContactName = contactName;
        request.CustomerReference = String.valueOf(returnOrderRecord.Id);
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

    private static Map<Id, String> resolveContactNameByReturnOrderIdMap(
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

    private static void validateAddresses(
        ReturnOrder ro,
        ResolvedAddress vendorAddress,
        ResolvedAddress repairCenterAddress
    ) {
        if (!hasUsableFedExAddress(vendorAddress)) {
            throw new VendorFedExShipmentException(
                'Vendor account on Return Order ' +
                    returnOrderDisplayNumber(ro.ReturnOrderNumber) +
                    ' ship-to address is incomplete' +
                    formatMissingFedExAddressSuffix(vendorAddress) +
                    '.'
            );
        }
        if (!hasUsableFedExAddress(repairCenterAddress)) {
            throw new VendorFedExShipmentException(
                'Repair Center on Return Order ' +
                    returnOrderDisplayNumber(ro.ReturnOrderNumber) +
                    ' address is incomplete' +
                    formatMissingFedExAddressSuffix(repairCenterAddress) +
                    '.'
            );
        }
    }

    private static Map<Id, ReturnOrder> queryReturnOrders(Set<Id> returnOrderIds) {
        return new Map<Id, ReturnOrder>(
            [
                SELECT
                    Id,
                    ReturnOrderNumber,
                    AccountId,
                    Account.Name,
                    Account.AccountNumber,
                    ContactId,
                    Contact.Name,
                    CustomerPO__c,
                    SourceLocationId,
                    SalesRep__c,
                    SalesRep__r.Name
                FROM ReturnOrder
                WHERE Id IN :returnOrderIds
                WITH USER_MODE
            ]
        );
    }

    private static Map<Id, WorkOrder> queryWorkOrders(Set<Id> workOrderIds) {
        if (workOrderIds.isEmpty()) {
            return new Map<Id, WorkOrder>();
        }
        return new Map<Id, WorkOrder>(
            [
                SELECT Id, WorkOrderNumber, Vendor__c
                FROM WorkOrder
                WHERE Id IN :workOrderIds
                WITH USER_MODE
            ]
        );
    }

    private static Map<Id, List<ReturnOrderLineItem>> queryOutboundLines(Set<Id> returnOrderIds) {
        Map<Id, List<ReturnOrderLineItem>> byReturnOrder = new Map<Id, List<ReturnOrderLineItem>>();
        Id outboundRtId = Schema.SObjectType.ReturnOrderLineItem.getRecordTypeInfosByDeveloperName()
            .get(ROLI_RECORD_TYPE_OUTBOUND)
            ?.getRecordTypeId();
        if (outboundRtId == null) {
            return byReturnOrder;
        }

        for (ReturnOrderLineItem line : [
            SELECT
                Id,
                ReturnOrderId,
                QuantityReturned,
                SerialNumber__c,
                Model__c,
                Product2Id,
                Product2.Description
            FROM ReturnOrderLineItem
            WHERE ReturnOrderId IN :returnOrderIds AND RecordTypeId = :outboundRtId
            WITH USER_MODE
            ORDER BY CreatedDate
        ]) {
            if (!byReturnOrder.containsKey(line.ReturnOrderId)) {
                byReturnOrder.put(line.ReturnOrderId, new List<ReturnOrderLineItem>());
            }
            byReturnOrder.get(line.ReturnOrderId).add(line);
        }
        return byReturnOrder;
    }

    private static Map<Id, ResolvedAddress> resolveAccountAddresses(Set<Id> accountIds) {
        Map<Id, ResolvedAddress> byAccountId = new Map<Id, ResolvedAddress>();
        if (accountIds.isEmpty()) {
            return byAccountId;
        }

        for (SObject addressRecord : queryAddressesByParent(accountIds)) {
            Id parentId = (Id) addressRecord.get('ParentId');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (parentId != null && hasUsableFedExAddress(resolved) && !byAccountId.containsKey(parentId)) {
                byAccountId.put(parentId, resolved);
            }
        }

        Set<Id> missingIds = new Set<Id>(accountIds);
        missingIds.removeAll(byAccountId.keySet());
        if (!missingIds.isEmpty()) {
            for (Account account : new VendorAddressAccess().getAccountsById(missingIds)) {
                ResolvedAddress billing = toResolvedAddressFromAccountFields(
                    account.BillingStreet,
                    account.BillingCity,
                    account.BillingState,
                    account.BillingStateCode,
                    account.BillingPostalCode,
                    account.BillingCountry,
                    account.BillingCountryCode
                );
                if (hasUsableFedExAddress(billing)) {
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
                if (hasUsableFedExAddress(shipping)) {
                    byAccountId.put(account.Id, shipping);
                }
            }
        }

        missingIds = new Set<Id>(accountIds);
        missingIds.removeAll(byAccountId.keySet());
        if (missingIds.isEmpty()) {
            return byAccountId;
        }

        // Address.ParentId is Location; vendor Account addresses often use Customer__c.
        for (SObject addressRecord : new VendorAddressAccess().queryAddressesByCustomer(missingIds)) {
            Id accountId = (Id) addressRecord.get('Customer__c');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                accountId != null &&
                hasUsableFedExAddress(resolved) &&
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

    private static Map<Id, ResolvedAddress> resolveLocationAddresses(Set<Id> locationIds) {
        Map<Id, ResolvedAddress> byLocationId = new Map<Id, ResolvedAddress>();
        if (locationIds.isEmpty()) {
            return byLocationId;
        }

        for (SObject addressRecord : queryAddressesByParent(locationIds)) {
            Id parentId = (Id) addressRecord.get('ParentId');
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                parentId != null &&
                hasUsableFedExAddress(resolved) &&
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

        List<Schema.Location> locations = [
            SELECT Id, VisitorAddressId
            FROM Location
            WHERE Id IN :missingIds
            WITH USER_MODE
        ];
        Map<Id, Id> locationIdByVisitorAddressId = new Map<Id, Id>();
        for (Schema.Location location : locations) {
            if (location.VisitorAddressId != null) {
                locationIdByVisitorAddressId.put(location.VisitorAddressId, location.Id);
            }
        }
        if (locationIdByVisitorAddressId.isEmpty()) {
            return byLocationId;
        }

        for (SObject addressRecord : queryAddressesById(locationIdByVisitorAddressId.keySet())) {
            Id locationId = locationIdByVisitorAddressId.get(addressRecord.Id);
            ResolvedAddress resolved = toResolvedAddress(addressRecord);
            if (
                locationId != null &&
                hasUsableFedExAddress(resolved) &&
                !byLocationId.containsKey(locationId)
            ) {
                byLocationId.put(locationId, resolved);
            }
        }
        return byLocationId;
    }

    private static List<SObject> queryAddressesByParent(Set<Id> parentIds) {
        return Database.query(
            'SELECT Id, ParentId, Street, City, State, StateCode, Country, CountryCode, PostalCode ' +
                'FROM Address ' +
                'WHERE ParentId IN :parentIds ' +
                'WITH USER_MODE ' +
                'ORDER BY CreatedDate ASC'
        );
    }

    private static List<SObject> queryAddressesById(Set<Id> addressIds) {
        return Database.query(
            'SELECT Id, ParentId, Street, City, State, StateCode, Country, CountryCode, PostalCode ' +
                'FROM Address ' +
                'WHERE Id IN :addressIds ' +
                'WITH USER_MODE'
        );
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

    private static String returnOrderDisplayNumber(String returnOrderNumber) {
        if (String.isBlank(returnOrderNumber)) {
            return 'RO';
        }
        return returnOrderNumber.startsWith('RO-')
            ? returnOrderNumber
            : 'RO-' + returnOrderNumber;
    }

    /**
     * @description Builds packing-slip HTML for the Vendor Return Order Files related list.
     * @param ro Vendor Return Order
     * @param workOrders Grouped vendor Work Orders
     * @param outboundLines Outbound Return Order Line Items
     * @param trackingNumber FedEx tracking number
     * @return Packing slip PDF as a Blob (HTML template rendered via Blob.toPdf)
     */
    @TestVisible
    static Blob buildPackingSlip(
        ReturnOrder ro,
        List<WorkOrder> workOrders,
        List<ReturnOrderLineItem> outboundLines,
        String trackingNumber
    ) {
        return Blob.toPdf(
            buildPackingSlipHtml(ro, workOrders, outboundLines, trackingNumber)
        );
    }

    /**
     * @description Builds packing-slip HTML from the ContentVersion template (or default),
     *              matching the RO Form pattern before Blob.toPdf conversion.
     */
    @TestVisible
    static String buildPackingSlipHtml(
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
        String serviceRequestNumbers = joinWorkOrderNumbers(workOrders);
        String lineItemsHtml = buildLineItemsHtml(outboundLines, workOrders);

        String template = loadPackingSlipTemplate();
        if (String.isBlank(template)) {
            template = defaultPackingSlipTemplate();
        }

        return template
            .replace('{{TODAY}}', escapeHtml(todayText))
            .replace('{{CCS_NAME}}', escapeHtml(ccsName))
            .replace('{{ACCOUNT_MANAGER}}', escapeHtml(accountManager))
            .replace('{{ACCOUNT_NUMBER}}', escapeHtml(accountNumber))
            .replace('{{VENDOR_NAME}}', escapeHtml(vendorName))
            .replace('{{RO_NUMBER}}', escapeHtml(returnOrderDisplayNumber(ro.ReturnOrderNumber)))
            .replace('{{SERVICE_REQUEST_NUMBERS}}', escapeHtml(serviceRequestNumbers))
            .replace('{{TRACKING_NUMBER}}', escapeHtml(trackingNumber))
            .replace('{{FEDEX_CHECKED}}', 'Yes')
            .replace('{{LINE_ITEMS}}', lineItemsHtml);
    }

    private static String loadPackingSlipTemplate() {
        try {
            List<ContentVersion> templates = [
                SELECT VersionData
                FROM ContentVersion
                WHERE Title = :PACKING_SLIP_TEMPLATE_TITLE AND IsLatest = TRUE
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

    private static String defaultPackingSlipTemplate() {
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

    private static String buildLineItemsHtml(
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
                    escapeHtml(itemDescription) +
                    '</td><td>' +
                    escapeHtml((String) line.get('Model__c')) +
                    '</td><td>' +
                    escapeHtml((String) line.get('SerialNumber__c')) +
                    '</td><td>' +
                    String.valueOf(line.QuantityReturned == null ? 1 : line.QuantityReturned) +
                    '</td></tr>';
            }
        }
        if (String.isBlank(rows) && workOrders != null) {
            for (WorkOrder wo : workOrders) {
                rows +=
                    '<tr><td>' +
                    escapeHtml(wo.WorkOrderNumber) +
                    '</td><td></td><td></td><td>1</td></tr>';
            }
        }
        return '<table><thead><tr><th>Item</th><th>Model</th><th>Serial Number</th>' +
            '<th>Qty</th></tr></thead><tbody>' +
            rows +
            '</tbody></table>';
    }

    private static String joinWorkOrderNumbers(List<WorkOrder> workOrders) {
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

    private static String escapeHtml(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.escapeHtml4();
    }

    /**
     * @description Elevates vendor Account / related Address reads for FedEx ship-to resolution.
     *              Repair techs often lack Account sharing even when they can process the WO.
     */
    private without sharing class VendorAddressAccess {
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
}