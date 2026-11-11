/**
 * @description Test class for Repair Center Quote document generation.
 */
@isTest
private class RepairCenterDocGenServiceTest {
    @isTest
    static void buildDocumentTokenDataFromQuote_buildsDevicesQuoteTokens() {
        QuoteTestData quoteTestData = buildDevicesQuoteGraph();

        Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );

        Assert.areEqual('Estimate', tokenData.get('DocumentTitle'));
        Assert.areEqual(true, tokenData.get('IF_IsSterisUS'));
        Assert.areEqual(false, tokenData.get('IF_IsSterisUK'));
        Assert.areEqual(true, tokenData.get('IF_IsDevicesWorkOrder'));
        Assert.areEqual(true, tokenData.get('IF_IsEstimate'));
        Assert.areEqual(false, tokenData.get('IF_IsPoRequired'));
        Assert.areEqual('ACME HOSPITAL (1234)', tokenData.get('AccountName'));
        Assert.areEqual('USD', tokenData.get('CurrencyCode'));
        Assert.areEqual('111 Mert Street', tokenData.get('BillToStreet'));
        Assert.areEqual('Kansas City, Missouri 21412', tokenData.get('BillToCityLine'));
        Assert.areEqual(
            '1320 Mercy Drive Northwest',
            tokenData.get('ShipToStreet')
        );
        Assert.areEqual('Canton, Ohio 44708', tokenData.get('ShipToCityLine'));

        List<Object> productServicedItems = (List<Object>) tokenData.get('ProductServicedItems');
        Assert.areEqual(1, productServicedItems.size());

        Map<String, Object> firstItem = (Map<String, Object>) productServicedItems[0];
        Assert.areEqual('SERIAL123', firstItem.get('ItemNumber'));
        Assert.areEqual('Waiting for Approval', firstItem.get('Status'));
        Assert.areEqual('Evaluation note', firstItem.get('EvaluationNotes'));
        Assert.areEqual(Date.today().format(), tokenData.get('PrintDate'));
        Assert.areEqual('$150.00', firstItem.get('ItemTotal'));

        List<Object> recommendedServices = (List<Object>) firstItem.get('RecommendedServices');
        Assert.areEqual(3, recommendedServices.size());

        // Return Order Line Items are Instruments-only.
        List<Object> returnOrderLineItems = (List<Object>) firstItem.get('ReturnOrderLineItems');
        Assert.areEqual(0, returnOrderLineItems.size());

        List<Object> repairEvaluationGroups = (List<Object>) tokenData.get('RepairEvaluationGroups');
        Assert.areEqual(1, repairEvaluationGroups.size());
        List<Object> repairEvaluationRows = (List<Object>) tokenData.get('RepairEvaluationRows');
        Assert.areEqual(1, repairEvaluationRows.size());
        Assert.areEqual(
            'SERIAL123',
            ((Map<String, Object>) repairEvaluationRows[0]).get('SerialNumber')
        );
        Assert.areEqual('$150.00', tokenData.get('GrandTotal'));
    }

    @isTest
    static void buildDocumentTokenDataFromQuote_buildsUkInstrumentQuoteTokens() {
        QuoteTestData quoteTestData = buildInstrumentsQuoteGraph();
        quoteTestData.quoteRecord.OperatingUnit__c = 'STERIS UK IMS';

        Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );

        Assert.areEqual('Quote', tokenData.get('DocumentTitle'));
        Assert.areEqual(false, tokenData.get('IF_IsSterisUS'));
        Assert.areEqual(true, tokenData.get('IF_IsSterisUK'));
        Assert.areEqual(false, tokenData.get('IF_IsDevicesWorkOrder'));
        Assert.areEqual(true, tokenData.get('IF_IsInstrumentsWorkOrder'));

        Map<String, Object> firstItem = (Map<String, Object>) ((List<Object>) tokenData.get(
            'ProductServicedItems'
        ))[0];
        Assert.areEqual('IN.10041', firstItem.get('ItemNumber'));
        Assert.areEqual('', firstItem.get('EvaluationNotes'));
        Assert.areEqual(
            1,
            ((List<Object>) firstItem.get('RecommendedServices')).size()
        );
        Assert.areEqual(
            1,
            ((List<Object>) firstItem.get('ReturnOrderLineItems')).size()
        );
        Assert.areEqual(
            'L4',
            ((Map<String, Object>) ((List<Object>) firstItem.get('ReturnOrderLineItems'))[0])
                .get('DisplayValue')
        );
        Assert.areEqual('$50.00', firstItem.get('ItemTotal'));
        Assert.areEqual(
            0,
            ((List<Object>) tokenData.get('RepairEvaluationGroups')).size()
        );
        Assert.areEqual(
            0,
            ((List<Object>) tokenData.get('RepairEvaluationRows')).size()
        );
    }

    @isTest
    static void buildDocumentTokenDataFromQuote_nestsOrphansByParentWorkOrderLineItem() {
        QuoteTestData quoteTestData = buildInstrumentsQuoteGraphWithWoliParents();

        Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );

        List<Object> productServicedItems = (List<Object>) tokenData.get('ProductServicedItems');
        Assert.areEqual(2, productServicedItems.size());

        Map<String, Object> firstItem = (Map<String, Object>) productServicedItems[0];
        Map<String, Object> secondItem = (Map<String, Object>) productServicedItems[1];
        List<Object> firstServices = (List<Object>) firstItem.get('RecommendedServices');
        List<Object> secondServices = (List<Object>) secondItem.get('RecommendedServices');

        Assert.areEqual(1, firstServices.size());
        Assert.areEqual(1, secondServices.size());
        Assert.areEqual(
            'SC.DAM009',
            ((Map<String, Object>) firstServices[0]).get('ProductCode')
        );
        Assert.areEqual(
            'SC.00285',
            ((Map<String, Object>) secondServices[0]).get('ProductCode')
        );
    }

    @isTest
    static void resolveDocumentTitle_coversUsUkAndPurchaseOrderRequired() {
        Assert.areEqual(
            'Estimate',
            RepairCenterDocGenService.resolveDocumentTitle(true, false, false)
        );
        Assert.areEqual(
            'Re-Estimate',
            RepairCenterDocGenService.resolveDocumentTitle(true, true, false)
        );
        Assert.areEqual(
            'Quote',
            RepairCenterDocGenService.resolveDocumentTitle(false, false, false)
        );
        Assert.areEqual(
            'Requote',
            RepairCenterDocGenService.resolveDocumentTitle(false, true, false)
        );
        Assert.areEqual(
            'Purchase Order Required',
            RepairCenterDocGenService.resolveDocumentTitle(true, false, true)
        );
        Assert.areEqual(
            'Purchase Order Required',
            RepairCenterDocGenService.resolveDocumentTitle(false, true, true)
        );
    }

    @isTest
    static void resolveIsSterisUs_usesOrgIdsAndLabelFallback() {
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsSterisUs('82'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsSterisUs('84'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsSterisUs('4871'));
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsSterisUs('STERIS US'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsSterisUs('STERIS UK IMS'));
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsSterisUs('765'));
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsSterisUs(null));
    }

    @isTest
    static void resolveIsLetterSize_usesLetterOnlyForSterisUs() {
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsLetterSize('82'));
        Assert.areEqual(true, RepairCenterDocGenService.resolveIsLetterSize('STERIS US'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize('84'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize('4871'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize('STERIS UK IMS'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize('765'));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize(null));
        Assert.areEqual(false, RepairCenterDocGenService.resolveIsLetterSize('   '));
    }

    @isTest
    static void resolveDefaultTemplateName_picksLetterOrA4ByOperatingUnit() {
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_TEMPLATE_NAME,
            RepairCenterDocGenService.resolveDefaultTemplateName(false, '82')
        );
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_TEMPLATE_NAME_A4,
            RepairCenterDocGenService.resolveDefaultTemplateName(false, 'STERIS UK IMS')
        );
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_WORK_ORDER_TEMPLATE_NAME,
            RepairCenterDocGenService.resolveDefaultTemplateName(true, 'STERIS US')
        );
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_WORK_ORDER_TEMPLATE_NAME_A4,
            RepairCenterDocGenService.resolveDefaultTemplateName(true, null)
        );
    }

    @isTest
    static void selector_returnsNullForMissingInputs() {
        Assert.areEqual(null, QuoteService.selectForRepairCenterDocumentGeneration(null));
        Assert.areEqual(null, RepairCenterDocGenService.selectActiveTemplateIdByName(null));
        Assert.areEqual(null, RepairCenterDocGenService.selectActiveTemplateIdByName('   '));
    }

    @isTest
    static void selector_returnsNullWhenRecordsAreNotFound() {
        assignRepairCenterOperations();
        Assert.areEqual(
            null,
            QuoteService.selectForRepairCenterDocumentGeneration(createFakeQuoteId())
        );
        Assert.areEqual(
            null,
            RepairCenterDocGenService.selectActiveTemplateIdByName('Repair Center Quote Missing')
        );
    }

    @isTest
    static void transform_returnsFalseForUnknownMethod() {
        RepairCenterQuoteDocGenTransform transformPlugin = new RepairCenterQuoteDocGenTransform();
        Map<String, Object> inputMap = new Map<String, Object>();
        Map<String, Object> outputMap = new Map<String, Object>();

        Assert.areEqual(
            false,
            transformPlugin.invokeMethod('unknownMethod', inputMap, outputMap)
        );
    }

    @isTest
    static void transform_routesTransformTokenDataToService() {
        assignRepairCenterOperations();
        RepairCenterQuoteDocGenTransform transformPlugin = new RepairCenterQuoteDocGenTransform();
        Map<String, Object> inputMap = new Map<String, Object>{
            RepairCenterDocGenService.TOKEN_DATA_KEY => new Map<String, Object>{
                'Quote' => new Map<String, Object>{ 'Id' => createFakeQuoteId() }
            }
        };
        Map<String, Object> outputMap = new Map<String, Object>();

        try {
            transformPlugin.invokeMethod(
                RepairCenterDocGenService.TRANSFORM_METHOD_NAME,
                inputMap,
                outputMap
            );
            Assert.isTrue(false, 'Expected quote-not-found exception.');
        } catch (RepairCenterQuoteDocGenException ex) {
            Assert.isTrue(ex.getMessage().contains('Quote record was not found'));
        }
    }

    @isTest
    static void transform_parsesJsonStringTokenDataFromContextService() {
        assignRepairCenterOperations();
        RepairCenterQuoteDocGenTransform transformPlugin = new RepairCenterQuoteDocGenTransform();
        Id quoteId = createFakeQuoteId();
        Map<String, Object> inputMap = new Map<String, Object>{
            RepairCenterDocGenService.TOKEN_DATA_KEY => JSON.serialize(
                new Map<String, Object>{
                    'WorkOrderType__c' => 'Devices',
                    'Id' => quoteId
                }
            )
        };
        Map<String, Object> outputMap = new Map<String, Object>();

        try {
            transformPlugin.invokeMethod(
                RepairCenterDocGenService.TRANSFORM_METHOD_NAME,
                inputMap,
                outputMap
            );
            Assert.isTrue(false, 'Expected quote-not-found exception.');
        } catch (RepairCenterQuoteDocGenException ex) {
            Assert.isTrue(ex.getMessage().contains('Quote record was not found'));
        }
    }

    @isTest
    static void buildDocumentTokenDataFromQuote_setsReEstimateTitleForVersionTwo() {
        QuoteTestData quoteTestData = buildDevicesQuoteGraph();
        quoteTestData.quoteRecord.Version__c = 2;

        Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );

        Assert.areEqual('Re-Estimate', tokenData.get('DocumentTitle'));
        Assert.areEqual(true, tokenData.get('IF_IsReEstimate'));
    }

    @isTest
    static void buildDocumentTokenDataFromQuote_setsPurchaseOrderRequiredTitle() {
        QuoteTestData quoteTestData = buildDevicesQuoteGraph();
        Map<String, Object> quoteFields = (Map<String, Object>) JSON.deserializeUntyped(
            JSON.serialize(quoteTestData.quoteRecord)
        );
        quoteFields.put('EstimateType__c', 'PO Required');
        Quote poRequiredQuote = (Quote) JSON.deserialize(
            JSON.serialize(quoteFields),
            Quote.class
        );
        poRequiredQuote.QuoteAccount = quoteTestData.quoteRecord.QuoteAccount;
        poRequiredQuote.WorkOrder__r = quoteTestData.quoteRecord.WorkOrder__r;
        quoteTestData.quoteRecord = poRequiredQuote;

        Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );

        Assert.areEqual('Purchase Order Required', tokenData.get('DocumentTitle'));
        Assert.areEqual(false, tokenData.get('IF_IsEstimate'));
    }

    @isTest
    static void buildDocumentTokenDataFromQuote_formatsGbpAndClearsUnsupportedType() {
        QuoteTestData quoteTestData = buildDevicesQuoteGraph();
        quoteTestData.quoteRecord.CurrencyIsoCode = 'GBP';

        Map<String, Object> gbpTokenData = RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
            quoteTestData.quoteRecord,
            quoteTestData.lineItems
        );
        Map<String, Object> firstItem = (Map<String, Object>) ((List<Object>) gbpTokenData.get(
            'ProductServicedItems'
        ))[0];
        Assert.areEqual('£150.00', firstItem.get('ItemTotal'));
        Assert.areEqual('£150.00', gbpTokenData.get('GrandTotal'));

        quoteTestData.quoteRecord.WorkOrderType__c = 'Unsupported';
        Map<String, Object> unsupportedTokenData =
            RepairCenterDocGenService.buildDocumentTokenDataFromQuote(
                quoteTestData.quoteRecord,
                quoteTestData.lineItems
            );
        Assert.areEqual(false, unsupportedTokenData.get('IF_IsSupportedWorkOrderType'));
        Assert.areEqual(
            0,
            ((List<Object>) unsupportedTokenData.get('ProductServicedItems')).size()
        );
        Assert.areEqual('£0.00', unsupportedTokenData.get('GrandTotal'));
    }

    @isTest
    static void buildDocumentFileTitle_usesQuoteAccountAndVersion() {
        Quote quoteRecord = (Quote) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'QuoteNumber' => '00004824',
                    'Version__c' => 9
                }
            ),
            Quote.class
        );
        quoteRecord.QuoteAccount = new Account(AccountNumber = '1001');

        Assert.areEqual(
            '00004824-1001-V9',
            RepairCenterDocGenService.buildDocumentFileTitle(quoteRecord, createFakeQuoteId())
        );

        Id fakeQuoteId = createFakeQuoteId();
        Assert.areEqual(
            String.valueOf(fakeQuoteId) + '--V1',
            RepairCenterDocGenService.buildDocumentFileTitle(new Quote(), fakeQuoteId)
        );
    }

    @isTest
    static void generateDocuments_returnsErrorWhenRecordIdMissing() {
        RepairCenterDocGenService.DocumentGenerationRequest request =
            new RepairCenterDocGenService.DocumentGenerationRequest();

        List<RepairCenterDocGenService.DocumentGenerationResult> results =
            RepairCenterDocGenService.generateDocuments(
                new List<RepairCenterDocGenService.DocumentGenerationRequest>{ request }
            );

        Assert.areEqual(1, results.size());
        Assert.areEqual(false, results[0].isSuccess);
        Assert.isTrue(
            results[0].errorMessage.contains('Quote Id or Work Order Id is required')
        );
    }

    @isTest
    static void generateDocuments_returnsErrorWhenTemplateIsMissing() {
        RepairCenterDocGenService.DocumentGenerationRequest request =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        request.quoteId = createFakeQuoteId();
        request.documentTemplateName = 'Repair Center Quote Missing';

        List<RepairCenterDocGenService.DocumentGenerationResult> results =
            RepairCenterDocGenService.generateDocuments(
                new List<RepairCenterDocGenService.DocumentGenerationRequest>{ request }
            );

        Assert.areEqual(1, results.size());
        Assert.areEqual(false, results[0].isSuccess);
        Assert.isTrue(
            results[0].errorMessage.contains('No active document template')
        );
    }

    @isTest
    static void generateDocuments_looksUpOperatingUnitForDefaultTemplates() {
        assignRepairCenterOperations();
        RepairCenterDocGenService.DocumentGenerationRequest quoteRequest =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        quoteRequest.quoteId = createFakeQuoteId();
        RepairCenterDocGenService.DocumentGenerationRequest workOrderRequest =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        workOrderRequest.workOrderId = createFakeWorkOrderId();
        RepairCenterDocGenService.DocumentGenerationRequest secondWorkOrderRequest =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        secondWorkOrderRequest.workOrderId = createFakeWorkOrderId();

        Test.startTest();
        List<RepairCenterDocGenService.DocumentGenerationResult> results =
            RepairCenterDocGenService.generateDocuments(
                new List<RepairCenterDocGenService.DocumentGenerationRequest>{
                    quoteRequest,
                    workOrderRequest,
                    secondWorkOrderRequest
                }
            );
        Test.stopTest();

        // Covers the bulk Operating Unit lookup. Whether the A4 templates resolve depends on the org,
        // so only the shape of the results is asserted here.
        Assert.areEqual(3, results.size());
        for (RepairCenterDocGenService.DocumentGenerationResult result : results) {
            Assert.isNotNull(result.isSuccess);
        }
    }

    @isTest
    static void prepareDocumentGeneration_usesOperatingUnitUnlessTemplateIsGiven() {
        Id quoteId = createFakeQuoteId();
        Id workOrderId = createFakeWorkOrderId();
        Map<Id, String> operatingUnitByRecordId = new Map<Id, String>{
            quoteId => 'STERIS UK IMS',
            workOrderId => '82'
        };

        RepairCenterDocGenService.DocumentGenerationRequest quoteRequest =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        quoteRequest.quoteId = quoteId;
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_TEMPLATE_NAME_A4,
            RepairCenterDocGenService.prepareDocumentGeneration(
                quoteRequest,
                operatingUnitByRecordId
            ).templateName
        );

        RepairCenterDocGenService.DocumentGenerationRequest workOrderRequest =
            new RepairCenterDocGenService.DocumentGenerationRequest();
        workOrderRequest.workOrderId = workOrderId;
        Assert.areEqual(
            RepairCenterDocGenService.DEFAULT_WORK_ORDER_TEMPLATE_NAME,
            RepairCenterDocGenService.prepareDocumentGeneration(
                workOrderRequest,
                operatingUnitByRecordId
            ).templateName
        );

        quoteRequest.documentTemplateName = 'Custom Template';
        Assert.areEqual(
            'Custom Template',
            RepairCenterDocGenService.prepareDocumentGeneration(
                quoteRequest,
                operatingUnitByRecordId
            ).templateName
        );
    }

	@isTest
	static void generateVendorPaperwork_ignoresEmptyInput() {
		RepairCenterDocGenService.generateVendorPaperwork(null);
		RepairCenterDocGenService.generateVendorPaperwork(new List<WorkOrder>());

		Assert.areEqual(0, [SELECT COUNT() FROM DocumentGenerationProcess]);
	}

	@isTest
	static void generateVendorPaperwork_logsInsteadOfThrowingOnFailure() {
		// Missing template or a fake Work Order Id fails the request; it must be logged, not thrown, so Complete is never blocked.
		Exception thrown;
		Test.startTest();
		try {
			RepairCenterDocGenService.generateVendorPaperwork(new List<WorkOrder>{ buildVendorWorkOrder('00000123') });
		} catch (Exception ex) {
			thrown = ex;
		}
		Test.stopTest();

		Assert.isNull(thrown, 'generateVendorPaperwork must not throw');
	}

	@isTest
	static void buildVendorPaperworkProcesses_buildsOneRequestPerWorkOrder() {
		WorkOrder firstWorkOrder = buildVendorWorkOrder('00000123');
		WorkOrder secondWorkOrder = buildVendorWorkOrder('00000124');
		Id templateId = (Id) (DocumentTemplate.SObjectType.getDescribe().getKeyPrefix() + '000000000001');

		List<DocumentGenerationProcess> processes = RepairCenterDocGenService.buildVendorPaperworkProcesses(new List<WorkOrder>{ firstWorkOrder, secondWorkOrder }, templateId);

		Assert.areEqual(2, processes.size());
		Assert.areEqual(firstWorkOrder.Id, processes[0].ReferenceObject);
		Assert.areEqual(String.valueOf(secondWorkOrder.Id), processes[1].DocGenAdditionalInput);
		Assert.areEqual(templateId, processes[0].DocumentTemplateId);
		Assert.areEqual(RepairCenterDocGenService.DGP_TYPE, processes[0].Type);
		Assert.areEqual(RepairCenterDocGenService.DGP_ADDITIONAL_INPUT_TYPE, processes[0].DocGenAdditionalInputType);
		Map<String, Object> requestText = (Map<String, Object>) JSON.deserializeUntyped(processes[1].RequestText);
		Assert.areEqual('Vendor Form WO-00000124', requestText.get('title'));
		Assert.areEqual(false, requestText.get('keepIntermediate'));
	}

	private static WorkOrder buildVendorWorkOrder(String workOrderNumber) {
		// WorkOrderNumber is an auto-number, so it is set through JSON instead of the constructor.
		return (WorkOrder) JSON.deserialize(JSON.serialize(new Map<String, Object>{ 'Id' => createFakeWorkOrderId(), 'WorkOrderNumber' => workOrderNumber }), WorkOrder.class);
	}

    @isTest
    static void buildDocumentTokenDataFromWorkOrder_buildsDevicesTokens() {
        WorkOrderTestData workOrderTestData = buildDevicesWorkOrderGraph();

        Map<String, Object> tokenData =
            RepairCenterDocGenService.buildDocumentTokenDataFromWorkOrder(
                workOrderTestData.workOrderRecord,
                workOrderTestData.lineItems,
                false
            );

        Assert.areEqual('Order Acknowledgement', tokenData.get('DocumentTitle'));
        Assert.areEqual(false, tokenData.get('IF_IsDeliveryDocument'));
        Assert.areEqual(true, tokenData.get('IF_IsOrderAcknowledgement'));
        Assert.areEqual(true, tokenData.get('IF_IsSterisUS'));
        Assert.areEqual(true, tokenData.get('IF_IsDevicesWorkOrder'));
        Assert.areEqual('ACME HOSPITAL (1234)', tokenData.get('AccountName'));
        Assert.areEqual('Robin Hart', tokenData.get('ContactName'));
        Assert.areEqual('111 Mert Street', tokenData.get('BillToStreet'));
        Assert.areEqual('Kansas City, MO 21412', tokenData.get('BillToCityLine'));
        Assert.areEqual(
            '1320 Mercy Drive Northwest',
            tokenData.get('ShipToStreet')
        );
        Assert.areEqual('Canton, Ohio 44708', tokenData.get('ShipToCityLine'));

        Map<String, Object> firstItem = (Map<String, Object>) ((List<Object>) tokenData.get(
            'ProductServicedItems'
        ))[0];
        Assert.areEqual('SERIAL123', firstItem.get('ItemNumber'));
        Assert.areEqual('Approval Required', firstItem.get('Status'));
        Assert.areEqual('Evaluation note', firstItem.get('EvaluationNotes'));
        Assert.areEqual(2, ((List<Object>) firstItem.get('RecommendedServices')).size());
        Assert.areEqual(0, ((List<Object>) firstItem.get('ReturnOrderLineItems')).size());

        Map<String, Object> secondItem = (Map<String, Object>) ((List<Object>) tokenData.get(
            'ProductServicedItems'
        ))[1];
        Assert.areEqual('SERIAL456', secondItem.get('ItemNumber'));
        Assert.areEqual('Second device note', secondItem.get('EvaluationNotes'));

        Assert.areEqual(1, ((List<Object>) tokenData.get('RepairEvaluationRows')).size());
        Assert.areEqual('$150.00', tokenData.get('GrandTotal'));
    }

    @isTest
    static void buildDocumentTokenDataFromWorkOrder_buildsInstrumentsTokens() {
        WorkOrderTestData workOrderTestData = buildInstrumentsWorkOrderGraph();

        Map<String, Object> tokenData =
            RepairCenterDocGenService.buildDocumentTokenDataFromWorkOrder(
                workOrderTestData.workOrderRecord,
                workOrderTestData.lineItems,
                false
            );

        Assert.areEqual('Order Acknowledgement', tokenData.get('DocumentTitle'));
        Assert.areEqual(false, tokenData.get('IF_IsSterisUS'));
        Assert.areEqual(true, tokenData.get('IF_IsInstrumentsWorkOrder'));

        Map<String, Object> firstItem = (Map<String, Object>) ((List<Object>) tokenData.get(
            'ProductServicedItems'
        ))[0];
        Assert.areEqual('IN.10041', firstItem.get('ItemNumber'));
        Assert.areEqual('', firstItem.get('EvaluationNotes'));
        Assert.areEqual(
            'L4',
            ((Map<String, Object>) ((List<Object>) firstItem.get('ReturnOrderLineItems'))[0])
                .get('DisplayValue')
        );
        Assert.areEqual(0, ((List<Object>) tokenData.get('RepairEvaluationRows')).size());
    }

	@isTest
	static void buildDocumentTokenDataFromWorkOrder_deliveryPricesOnlyShippedItems() {
		WorkOrderTestData workOrderTestData = buildDevicesWorkOrderGraph();
		workOrderTestData.workOrderRecord.ActualShipDate__c = Date.newInstance(2026, 11, 5);
		// First device has $150 of services and has shipped; the second is still in repair.
		workOrderTestData.lineItems[0].WorkOrder = new WorkOrder(EvaluationNotes__c = 'Evaluation note', Status = 'Ship', ActualShipDate__c = Date.newInstance(2026, 11, 4));
		workOrderTestData.lineItems[4].WorkOrder = new WorkOrder(EvaluationNotes__c = 'Second device note', Status = 'Repair');

		Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromWorkOrder(workOrderTestData.workOrderRecord, workOrderTestData.lineItems, true);

		Assert.areEqual(RepairCenterDocGenService.DOCUMENT_TITLE_SERVICE_DELIVERY_REPORT, tokenData.get('DocumentTitle'));
		Assert.areEqual(true, tokenData.get('IF_IsDeliveryDocument'));
		Assert.areEqual(false, tokenData.get('IF_IsOrderAcknowledgement'));
		Assert.areEqual(Date.newInstance(2026, 11, 5).format(), tokenData.get('ShipDate'));
		Assert.areEqual(true, tokenData.get('IF_HasShipDate'));
		Assert.areEqual('$150.00', tokenData.get('GrandTotal'));

		List<Object> items = (List<Object>) tokenData.get('ProductServicedItems');
		Map<String, Object> shippedItem = (Map<String, Object>) items[0];
		Assert.areEqual('Ship', shippedItem.get('Status'));
		Assert.areEqual(true, shippedItem.get('IF_ShowPricing'));
		Assert.areEqual(Date.newInstance(2026, 11, 4).format(), shippedItem.get('ShipDate'));
		Assert.areEqual('$150.00', shippedItem.get('ItemTotal'));

		Map<String, Object> inRepairItem = (Map<String, Object>) items[1];
		Assert.areEqual('Repair', inRepairItem.get('Status'));
		Assert.areEqual(false, inRepairItem.get('IF_ShowPricing'));
		Assert.areEqual(false, inRepairItem.get('IF_HasShipDate'));
		Assert.areEqual('', inRepairItem.get('ItemTotal'));
	}

	@isTest
	static void buildDocumentTokenDataFromWorkOrder_deliveryHidesServicePricesUntilShipped() {
		WorkOrderTestData workOrderTestData = buildDevicesWorkOrderGraph();
		workOrderTestData.lineItems[0].WorkOrder = new WorkOrder(Status = 'QC');

		Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromWorkOrder(workOrderTestData.workOrderRecord, workOrderTestData.lineItems, true);

		Map<String, Object> firstItem = (Map<String, Object>) ((List<Object>) tokenData.get('ProductServicedItems'))[0];
		for (Object service : (List<Object>) firstItem.get('RecommendedServices')) {
			Assert.areEqual('', ((Map<String, Object>) service).get('TotalPrice'));
		}
		Assert.areEqual('$0.00', tokenData.get('GrandTotal'));
		Assert.areEqual('', tokenData.get('ShipDate'));
		Assert.areEqual(false, tokenData.get('IF_HasShipDate'));
	}

	@isTest
	static void buildDocumentTokenDataFromWorkOrder_deliveryUsesDeliveryNoteOutsideUs() {
		WorkOrderTestData workOrderTestData = buildInstrumentsWorkOrderGraph();

		Map<String, Object> tokenData = RepairCenterDocGenService.buildDocumentTokenDataFromWorkOrder(workOrderTestData.workOrderRecord, workOrderTestData.lineItems, true);

		Assert.areEqual(RepairCenterDocGenService.DOCUMENT_TITLE_DELIVERY_NOTE, tokenData.get('DocumentTitle'));
	}

	@isTest
	static void prepareDocumentGeneration_deliveryRequiresExistingWorkOrder() {
		RepairCenterDocGenService.DocumentGenerationRequest quoteRequest = new RepairCenterDocGenService.DocumentGenerationRequest();
		quoteRequest.quoteId = createFakeQuoteId();
		quoteRequest.documentType = RepairCenterDocGenService.DOCUMENT_TYPE_DELIVERY;
		Assert.areEqual('Work Order Id is required for delivery documents.', RepairCenterDocGenService.prepareDocumentGeneration(quoteRequest, new Map<Id, String>()).errorMessage);

		RepairCenterDocGenService.DocumentGenerationRequest workOrderRequest = new RepairCenterDocGenService.DocumentGenerationRequest();
		workOrderRequest.workOrderId = createFakeWorkOrderId();
		workOrderRequest.documentType = RepairCenterDocGenService.DOCUMENT_TYPE_DELIVERY;
		Assert.areEqual('Work Order record was not found for document generation.', RepairCenterDocGenService.prepareDocumentGeneration(workOrderRequest, new Map<Id, String>()).errorMessage);
	}

	@isTest
	static void isDeliveryDocumentRequested_isFalseWithoutInProgressRequest() {
		Assert.isFalse(RepairCenterDocGenService.isDeliveryDocumentRequested(createFakeWorkOrderId()));
	}

    @isTest
    static void buildWorkOrderDocumentFileTitle_usesWorkOrderAndAccountNumber() {
        WorkOrder workOrderRecord = (WorkOrder) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'WorkOrderNumber' => '00001234' }),
            WorkOrder.class
        );
        workOrderRecord.Account = new Account(AccountNumber = '1001');

        Assert.areEqual(
            '00001234-1001',
            RepairCenterDocGenService.buildWorkOrderDocumentFileTitle(
                workOrderRecord,
                createFakeWorkOrderId()
            )
        );
    }

    @isTest
    static void transform_routesWorkOrderTokenDataToService() {
        RepairCenterQuoteDocGenTransform transformPlugin = new RepairCenterQuoteDocGenTransform();
        Map<String, Object> inputMap = new Map<String, Object>{
            RepairCenterDocGenService.TOKEN_DATA_KEY => new Map<String, Object>{
                'WorkOrder' => new Map<String, Object>{ 'Id' => createFakeWorkOrderId() }
            }
        };
        Map<String, Object> outputMap = new Map<String, Object>();

        try {
            transformPlugin.invokeMethod(
                RepairCenterDocGenService.TRANSFORM_METHOD_NAME,
                inputMap,
                outputMap
            );
            Assert.isTrue(false, 'Expected work-order-not-found exception.');
        } catch (RepairCenterQuoteDocGenException ex) {
            Assert.isTrue(ex.getMessage().contains('Work Order record was not found'));
        }
    }

    @isTest
    static void selector_returnsNullForMissingWorkOrderId() {
        assignRepairCenterOperations();
        Assert.areEqual(
            null,
            WorkOrdersService.selectForRepairCenterDocumentGeneration(null)
        );
        Assert.areEqual(
            null,
            WorkOrdersService.selectForRepairCenterDocumentGeneration(
                createFakeWorkOrderId()
            )
        );
        Assert.areEqual(
            null,
            WorkOrdersService.resolveDocumentFamilyRootId(null)
        );
        Assert.areEqual(
            0,
            WorkOrderLineItemsService.selectForRepairCenterDocumentGeneration(null)
                .size()
        );
        Assert.areEqual(
            0,
            WorkOrderLineItemsService.selectForRepairCenterDocumentGeneration(
                    createFakeWorkOrderId()
                )
                .size()
        );
    }

    @isTest
    static void resolveDocumentFamilyRootId_usesParentWhenPresent() {
        Id parentId = createFakeWorkOrderId();
        Id childId = createFakeWorkOrderId();
        WorkOrder childWorkOrder = (WorkOrder) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Id' => childId,
                    'ParentWorkOrderId' => parentId
                }
            ),
            WorkOrder.class
        );
        WorkOrder parentWorkOrder = (WorkOrder) JSON.deserialize(
            JSON.serialize(new Map<String, Object>{ 'Id' => parentId }),
            WorkOrder.class
        );

        Assert.areEqual(
            parentId,
            WorkOrdersService.resolveDocumentFamilyRootId(childWorkOrder)
        );
        Assert.areEqual(
            parentId,
            WorkOrdersService.resolveDocumentFamilyRootId(parentWorkOrder)
        );
    }

    private class QuoteTestData {
        Quote quoteRecord;
        List<QuoteLineItem> lineItems;
    }

    private class WorkOrderTestData {
        WorkOrder workOrderRecord;
        List<WorkOrderLineItem> lineItems;
    }

    private static QuoteLineItem buildQuoteLineItem(Map<String, Object> fieldValues) {
        return (QuoteLineItem) JSON.deserialize(
            JSON.serialize(withNetTotalPrice(fieldValues)),
            QuoteLineItem.class
        );
    }

    private static WorkOrderLineItem buildWorkOrderLineItem(Map<String, Object> fieldValues) {
        return (WorkOrderLineItem) JSON.deserialize(
            JSON.serialize(withNetTotalPrice(fieldValues)),
            WorkOrderLineItem.class
        );
    }

    // GW-5213: line totals are read from the NetTotalPrice__c formula, so mirror TotalPrice into it.
    private static Map<String, Object> withNetTotalPrice(Map<String, Object> fieldValues) {
        if (fieldValues.containsKey('TotalPrice') && !fieldValues.containsKey('NetTotalPrice__c')) {
            fieldValues.put('NetTotalPrice__c', fieldValues.get('TotalPrice'));
        }
        return fieldValues;
    }

    private static WorkOrderTestData buildDevicesWorkOrderGraph() {
        Id parentLineItemId = createFakeWorkOrderLineItemId();

        WorkOrderLineItem childLineOne = buildWorkOrderLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentWorkOrderLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01012P',
                'ProductDescription__c' => 'Bearings Replaced',
                'Quantity' => 1,
                'TotalPrice' => 100
            }
        );
        childLineOne.Product2 = new Product2(QuantityUnitOfMeasure = 'EA');

        WorkOrderLineItem childLineTwo = buildWorkOrderLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_CATEGORY_CODE,
                'ParentWorkOrderLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01100P',
                'ProductDescription__c' => 'O-rings Replaced',
                'Quantity' => 1,
                'TotalPrice' => 50
            }
        );

        WorkOrderLineItem observationLine = buildWorkOrderLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_OBSERVATION_CODE,
                'SerialNumber__c' => 'SERIAL123',
                'ProductDescription__c' => 'Output Drive is Dirty',
                'ObservationCodeCondition__c' => 'CRITICAL (CONTROLLABLE)'
            }
        );

        WorkOrderLineItem parentLine = buildWorkOrderLineItem(
            new Map<String, Object>{
                'Id' => parentLineItemId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'SerialNumber__c' => 'SERIAL123',
                'ProductDescription__c' => 'FLEXIBLE SCOPE',
                'Status' => 'Approval Required',
                'TurnTime__c' => 5
            }
        );
        parentLine.WorkOrder = new WorkOrder(EvaluationNotes__c = 'Evaluation note');

        Id secondParentLineItemId = createFakeWorkOrderLineItemId();
        WorkOrderLineItem secondParentLine = buildWorkOrderLineItem(
            new Map<String, Object>{
                'Id' => secondParentLineItemId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'SerialNumber__c' => 'SERIAL456',
                'ProductDescription__c' => 'SECOND SCOPE',
                'Status' => 'Approval Required',
                'TurnTime__c' => 2
            }
        );
        secondParentLine.WorkOrder = new WorkOrder(EvaluationNotes__c = 'Second device note');

        WorkOrder workOrderRecord = (WorkOrder) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'WorkOrderNumber' => '00009999',
                    'CurrencyIsoCode' => 'USD',
                    'CustomerPO__c' => 'PO-1',
                    'CustomerReference__c' => 'CR-1',
                    'AccountManager__c' => 'Manager',
                    'DepartmentName__c' => 'Surgery',
                    'ReturnOrderNumber__c' => 'RO-1',
                    'EvaluationNotes__c' => 'Header notes should not win',
                    'OperatingUnit__c' => '82',
                    'BillToAddress__Street__s' => '111 Mert Street',
                    'BillToAddress__City__s' => 'Kansas City',
                    'BillToAddress__StateCode__s' => 'MO',
                    'BillToAddress__PostalCode__s' => '21412',
                    'BillToAddress__CountryCode__s' => 'US',
                    'Street' => '1320 Mercy Drive Northwest',
                    'City' => 'Canton',
                    'State' => 'Ohio',
                    'PostalCode' => '44708',
                    'Country' => 'United States'
                }
            ),
            WorkOrder.class
        );
        workOrderRecord.Account = new Account(Name = 'ACME HOSPITAL', AccountNumber = '1234');
        workOrderRecord.Contact = (Contact) JSON.deserialize(
            '{"attributes":{"type":"Contact"},"Name":"Robin Hart"}',
            Contact.class
        );
        workOrderRecord.RecordType = new RecordType(
            DeveloperName = RepairCenterDocGenService.RECORD_TYPE_DEVICES
        );

        WorkOrderTestData workOrderTestData = new WorkOrderTestData();
        workOrderTestData.workOrderRecord = workOrderRecord;
        workOrderTestData.lineItems = new List<WorkOrderLineItem>{
            parentLine,
            childLineOne,
            childLineTwo,
            observationLine,
            secondParentLine
        };
        return workOrderTestData;
    }

    private static WorkOrderTestData buildInstrumentsWorkOrderGraph() {
        Id parentLineItemId = createFakeWorkOrderLineItemId();
        WorkOrderLineItem parentLine = buildWorkOrderLineItem(
            new Map<String, Object>{
                'Id' => parentLineItemId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'ProductCode__c' => 'IN.10041',
                'ProductDescription__c' => 'INSTRUMENT.SPECIALTY.LAP GRASPER',
                'Status' => 'Approval Required',
                'TurnTime__c' => 4,
                'ReturnOrderLineItems__c' => 'L4'
            }
        );
        WorkOrderLineItem childLine = buildWorkOrderLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentWorkOrderLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01012P',
                'ProductDescription__c' => 'Instrument Service',
                'Quantity' => 1,
                'TotalPrice' => 50
            }
        );
        childLine.Product2 = new Product2(QuantityUnitOfMeasure = 'EA');

        WorkOrder workOrderRecord = (WorkOrder) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'WorkOrderNumber' => '00008888',
                    'CurrencyIsoCode' => 'USD',
                    'OperatingUnit__c' => 'STERIS UK IMS',
                    'EvaluationNotes__c' => 'Should not appear on Instruments'
                }
            ),
            WorkOrder.class
        );
        workOrderRecord.Account = new Account(
            Name = 'SYNERGY HEALTH UK LIMITED',
            AccountNumber = '84765'
        );
        workOrderRecord.RecordType = new RecordType(
            DeveloperName = RepairCenterDocGenService.RECORD_TYPE_INSTRUMENTS
        );

        WorkOrderTestData workOrderTestData = new WorkOrderTestData();
        workOrderTestData.workOrderRecord = workOrderRecord;
        workOrderTestData.lineItems = new List<WorkOrderLineItem>{ parentLine, childLine };
        return workOrderTestData;
    }

    private static QuoteTestData buildDevicesQuoteGraph() {
        Id parentLineItemId = createFakeQuoteLineItemId();

        QuoteLineItem childLineOne = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentQuoteLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01012P',
                'ProductDescription__c' => 'Bearings Replaced',
                'Quantity' => 1,
                'TotalPrice' => 100,
                'UOM__c' => 'EA'
            }
        );
        QuoteLineItem childLineTwo = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_CATEGORY_CODE,
                'ParentQuoteLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01100P',
                'ProductDescription__c' => 'O-rings Replaced',
                'Quantity' => 1,
                'TotalPrice' => 50
            }
        );
        QuoteLineItem childLineThree = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SPECIAL_PRICING,
                'ParentQuoteLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SP.001',
                'ProductDescription__c' => 'Special Pricing Adjustment',
                'Quantity' => 1,
                'TotalPrice' => 0,
                'UOM__c' => 'EA'
            }
        );
        QuoteLineItem parentLine = buildQuoteLineItem(
            new Map<String, Object>{
                'Id' => parentLineItemId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'SerialNumber__c' => 'SERIAL123',
                'ProductDescription__c' => 'Device description',
                'Status__c' => 'Waiting for Approval',
                'TurnTime__c' => 5,
                'ReturnOrderLineItems__c' => 'L4'
            }
        );
        parentLine.WorkOrderLineItem__r = new WorkOrderLineItem();
        parentLine.WorkOrderLineItem__r.WorkOrder = new WorkOrder(
            EvaluationNotes__c = 'Evaluation note'
        );
        QuoteLineItem observationLine = new QuoteLineItem(
            LineType__c = RepairCenterDocGenService.LINE_TYPE_OBSERVATION_CODE,
            SerialNumber__c = 'SERIAL123',
            ProductDescription__c = 'Output Drive is Dirty',
            Condition__c = 'CRITICAL (CONTROLLABLE)'
        );

        Quote quoteRecord = (Quote) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Version__c' => 1,
                    'WorkOrderType__c' => RepairCenterDocGenService.WORK_ORDER_TYPE_DEVICES,
                    'PurchaseOrder__c' => 'PO-100',
                    'AccountManager__c' => 'Manager Name',
                    'CustomerReference__c' => 'REF-1',
                    'CurrencyIsoCode' => 'USD',
                    'EstimateType__c' => 'Estimate',
                    'WorkOrderNumber__c' => 'WO-100',
                    'ReturnOrderNumber__c' => 'RO-100',
                    'PrintDate__c' => Date.today(),
                    'AccountName__c' => 'ACME HOSPITAL',
                    'DepartmentName__c' => 'Operating Room',
                    'OperatingUnit__c' => 'STERIS US',
                    'BillingStreet' => '111 Mert Street',
                    'BillingCity' => 'Kansas City',
                    'BillingState' => 'Missouri',
                    'BillingPostalCode' => '21412',
                    'BillingCountry' => 'United States',
                    'ShippingStreet' => '1320 Mercy Drive Northwest',
                    'ShippingCity' => 'Canton',
                    'ShippingState' => 'Ohio',
                    'ShippingPostalCode' => '44708',
                    'ShippingCountry' => 'United States'
                }
            ),
            Quote.class
        );
        quoteRecord.QuoteAccount = new Account(AccountNumber = '1234');
        quoteRecord.WorkOrder__r = new WorkOrder(
            EvaluationNotes__c = 'Evaluation note',
            SubStatus__c = 'Resolved',
            EstimateContact__r = new Contact(FirstName = 'Robin', LastName = 'Hart')
        );

        QuoteTestData quoteTestData = new QuoteTestData();
        quoteTestData.quoteRecord = quoteRecord;
        quoteTestData.lineItems = new List<QuoteLineItem>{
            parentLine,
            childLineOne,
            childLineTwo,
            childLineThree,
            observationLine
        };
        return quoteTestData;
    }

    private static QuoteTestData buildInstrumentsQuoteGraph() {
        Id parentLineItemId = createFakeQuoteLineItemId();
        QuoteLineItem parentLine = buildQuoteLineItem(
            new Map<String, Object>{
                'Id' => parentLineItemId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'ProductCode__c' => 'IN.10041',
                'ProductDescription__c' => 'INSTRUMENT.SPECIALTY.LAP GRASPER',
                'Status__c' => 'Waiting for Approval',
                'TurnTime__c' => 4,
                'ReturnOrderLineItems__c' => 'L4'
            }
        );
        QuoteLineItem childLine = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentQuoteLineItemId' => parentLineItemId,
                'ProductCode__c' => 'SC.01012P',
                'ProductDescription__c' => 'Instrument Service',
                'Quantity' => 1,
                'TotalPrice' => 50,
                'UOM__c' => 'EA'
            }
        );

        Quote quoteRecord = (Quote) JSON.deserialize(
            JSON.serialize(
                new Map<String, Object>{
                    'Version__c' => 1,
                    'WorkOrderType__c' => RepairCenterDocGenService.WORK_ORDER_TYPE_INSTRUMENTS,
                    'CurrencyIsoCode' => 'USD',
                    'EstimateType__c' => 'Estimate',
                    'AccountName__c' => 'SYNERGY HEALTH UK LIMITED'
                }
            ),
            Quote.class
        );
        quoteRecord.QuoteAccount = new Account(AccountNumber = '84765');
        quoteRecord.WorkOrder__r = new WorkOrder(
            EvaluationNotes__c = 'Should not appear on Instruments'
        );

        QuoteTestData quoteTestData = new QuoteTestData();
        quoteTestData.quoteRecord = quoteRecord;
        quoteTestData.lineItems = new List<QuoteLineItem>{ parentLine, childLine };
        return quoteTestData;
    }

    private static QuoteTestData buildInstrumentsQuoteGraphWithWoliParents() {
        Id parentWoliOneId = createFakeWorkOrderLineItemId();
        Id parentWoliTwoId = createFakeWorkOrderLineItemId();
        Id parentQliOneId = createFakeQuoteLineItemId();
        Id parentQliTwoId = createFakeQuoteLineItemId();

        QuoteLineItem parentLineOne = buildQuoteLineItem(
            new Map<String, Object>{
                'Id' => parentQliOneId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'WorkOrderLineItem__c' => parentWoliOneId,
                'ProductCode__c' => 'IN.10041',
                'ProductDescription__c' => 'INSTRUMENT.SPECIALTY.LAP GRASPER',
                'Status__c' => 'Waiting for Approval',
                'TurnTime__c' => 4,
                'ReturnOrderLineItems__c' => 'L4'
            }
        );
        QuoteLineItem parentLineTwo = buildQuoteLineItem(
            new Map<String, Object>{
                'Id' => parentQliTwoId,
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_PRODUCT_SERVICED,
                'WorkOrderLineItem__c' => parentWoliTwoId,
                'ProductCode__c' => 'IN.10001',
                'ProductDescription__c' => 'INSTRUMENT.SPECIALTY.ARM BOARD',
                'Status__c' => 'Waiting for Approval',
                'TurnTime__c' => 4,
                'ReturnOrderLineItems__c' => 'L4'
            }
        );
        QuoteLineItem childLineOne = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentWorkOrderLineItem__c' => parentWoliOneId,
                'ProductCode__c' => 'SC.DAM009',
                'ProductDescription__c' => 'Instrument replacement',
                'Quantity' => 1,
                'TotalPrice' => 50,
                'UOM__c' => 'EA'
            }
        );
        QuoteLineItem childLineTwo = buildQuoteLineItem(
            new Map<String, Object>{
                'LineType__c' => RepairCenterDocGenService.LINE_TYPE_SERVICE_CODE,
                'ParentWorkOrderLineItem__c' => parentWoliTwoId,
                'ProductCode__c' => 'SC.00285',
                'ProductDescription__c' => 'Handle replacement',
                'Quantity' => 1,
                'TotalPrice' => 25,
                'UOM__c' => 'EA'
            }
        );

        QuoteTestData quoteTestData = buildInstrumentsQuoteGraph();
        quoteTestData.lineItems = new List<QuoteLineItem>{
            parentLineOne,
            parentLineTwo,
            childLineOne,
            childLineTwo
        };
        return quoteTestData;
    }

    private static Integer fakeQuoteLineItemSequence = 1;

    private static Id createFakeQuoteLineItemId() {
        String keyPrefix = QuoteLineItem.SObjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(fakeQuoteLineItemSequence++).leftPad(12, '0');
        return (Id) (keyPrefix + suffix);
    }

    private static void assignRepairCenterOperations() {
        List<PermissionSet> permissionSets = [
            SELECT Id
            FROM PermissionSet
            WHERE Name = 'RepairCenterOperations'
            LIMIT 1
        ];
        if (permissionSets.isEmpty()) {
            return;
        }
        Integer existingAssignmentCount = [
            SELECT COUNT()
            FROM PermissionSetAssignment
            WHERE AssigneeId = :UserInfo.getUserId()
            AND PermissionSetId = :permissionSets[0].Id
        ];
        if (existingAssignmentCount == 0) {
            insert new PermissionSetAssignment(
                AssigneeId = UserInfo.getUserId(),
                PermissionSetId = permissionSets[0].Id
            );
        }
    }

    private static Id createFakeQuoteId() {
        String keyPrefix = Quote.SObjectType.getDescribe().getKeyPrefix();
        return (Id) (keyPrefix + '000000000001');
    }

    private static Integer fakeWorkOrderLineItemSequence = 1;

    private static Id createFakeWorkOrderLineItemId() {
        String keyPrefix = WorkOrderLineItem.SObjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(fakeWorkOrderLineItemSequence++).leftPad(12, '0');
        return (Id) (keyPrefix + suffix);
    }

    private static Integer fakeWorkOrderSequence = 1;

    private static Id createFakeWorkOrderId() {
        String keyPrefix = WorkOrder.SObjectType.getDescribe().getKeyPrefix();
        String suffix = String.valueOf(fakeWorkOrderSequence++).leftPad(12, '0');
        return (Id) (keyPrefix + suffix);
    }
}