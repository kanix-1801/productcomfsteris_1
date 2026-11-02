/**
 * @description Tests for InstrumentEvaluationController (GW-3400).
 */
@IsTest
private class InstrumentEvaluationControllerTest {
    /**
     * @description GW-3400 - Stub service client that returns canned workspace context.
     */
    private class StubClient implements InstrumentEvaluationController.IInstrumentEvaluationClient {
        /**
         * @description GW-3400 - Returns a canned initialize context for the scanned Work Order.
         * @param workOrderInput Work Order Id or Number
         * @return Instrument Evaluation context
         */
        public WorkOrdersService.InstrumentEvaluationContext initializeInstrumentEvaluation(
            String workOrderInput
        ) {
            WorkOrder scanned = WorkOrdersSelector.selectByIdOrNumber(workOrderInput);
            return buildContext(scanned == null ? workOrderInput : scanned.Id);
        }

        /**
         * @description GW-3400 - Returns a canned save context with notes applied.
         * @param workOrderId Parent Work Order Id
         * @param subStatus Sub Status value
         * @param unableToTakePhoto Unable To Take Photo checkbox
         * @param turnTime Turn Time
         * @param evaluationNotes Customer-facing evaluation notes
         * @param internalEvaluationNotes Internal evaluation notes
         * @param internalSpecialistEvaluationNotes Internal specialist notes
         * @return Instrument Evaluation context
         */
        public WorkOrdersService.InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            Decimal quantityReceived,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        ) {
            WorkOrdersService.InstrumentEvaluationContext context = buildContext(workOrderId);
            context.workOrder.SubStatus__c = subStatus;
            context.workOrder.UnableToTakePhoto__c = unableToTakePhoto == true;
            context.workOrder.TurnTime__c = turnTime;
            context.workOrder.QuantityReceived__c = quantityReceived;
            context.workOrder.EvaluationNotes__c = evaluationNotes;
            context.workOrder.InternalEvaluationNotes__c = internalEvaluationNotes;
            context.workOrder.InternalSpecialistEvaluationNotes__c =
                internalSpecialistEvaluationNotes;
            return context;
        }

        private WorkOrdersService.InstrumentEvaluationContext buildContext(String workOrderInput) {
            WorkOrdersService.InstrumentEvaluationContext context =
                new WorkOrdersService.InstrumentEvaluationContext();
            Id workOrderId = (Id) workOrderInput;
            context.workOrder = new WorkOrder(
                Id = workOrderId,
                Status = 'Evaluate & Quote',
                SubStatus__c = null,
                UnableToTakePhoto__c = false,
                TurnTime__c = 3,
                EstimateRequired__c = 'Yes',
                RepairWarranty__c = 'No',
                ContinuousImprovementOpportunity__c = false,
                CustomerPORequired__c = true,
                CustomerPO__c = 'PO-100',
                ShipComplete__c = true,
                EvaluationNotes__c = 'Eval notes',
                InternalEvaluationNotes__c = 'Internal notes',
                InternalSpecialistEvaluationNotes__c = 'Specialist notes',
                QCInspectionNotes__c = 'QC notes',
                RepairCategory__c = 'Stainless',
                QuantityReceived__c = 1,
                Subject = 'IE Subject',
                Description = 'IE Description'
            );
            context.photosRequired = true;
            context.hasAsset = true;
            context.showItemSelection = true;
            context.canAddItems = true;
            context.productLine = 'Instruments';
            context.manufacturer = 'STERIS';
            context.model = 'Model-X';
            context.serialNumber = 'SN-1';
            context.assetIdentityLine = 'SN-1 - STERIS';
            context.repairHistoryHasMore = true;

            CustomerPreference__c preference = new CustomerPreference__c(
                Id = fakeId(CustomerPreference__c.SObjectType),
                Name = 'Photos Required',
                PreferenceType__c = 'Photos Required',
                ProductLine__c = 'Instrument',
                StartDate__c = Date.today().addDays(-1),
                EndDate__c = Date.today().addDays(30)
            );
            context.customerPreferences = new List<CustomerPreference__c>{ preference };

            WorkOrder historyRow = new WorkOrder(
                Id = workOrderId,
                Description = 'Angulation up/down is loose.',
                ActualShipDate__c = Date.today().addDays(-10),
                CompletedTimestamp__c = Datetime.now().addDays(-10),
                EvaluationNotes__c = 'Angulation wires stretched.'
            );
            historyRow.Evaluator__r = new User(
                Id = UserInfo.getUserId(),
                LastName = 'Evaluator'
            );
            context.repairHistory = new List<WorkOrder>{ historyRow };
            return context;
        }

        public List<WorkOrdersService.InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
            Id workOrderId
        ) {
            WorkOrdersService.InstrumentEvalCategoryCard card =
                new WorkOrdersService.InstrumentEvalCategoryCard();
            card.evalCategory = 'Forceps';
            card.evalRank = '10';
            return new List<WorkOrdersService.InstrumentEvalCategoryCard>{ card };
        }

        public List<WorkOrdersService.InstrumentProductCard> getInstrumentEvaluationProducts(
            Id workOrderId,
            String evalCategory
        ) {
            WorkOrdersService.InstrumentProductCard card =
                new WorkOrdersService.InstrumentProductCard();
            card.productId = workOrderId;
            card.productCode = 'INST-001';
            card.productName = 'Test Instrument';
            card.evalCategory = evalCategory;
            return new List<WorkOrdersService.InstrumentProductCard>{ card };
        }

        public ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
            getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId) {
            ProductRelatedMaterialsService.InstrumentEvaluationCodeCards cards =
                new ProductRelatedMaterialsService.InstrumentEvaluationCodeCards();
            ProductRelatedMaterialsService.RepairCodeCardData category =
                new ProductRelatedMaterialsService.RepairCodeCardData();
            category.productId = workOrderId;
            category.productCode = 'CAT-001';
            category.productName = 'Category Code';
            category.codeType = 'Category Code';
            category.selected = true;
            category.workOrderLineItemId = workOrderId;
            category.status = 'Approved';
            cards.categoryCodes.add(category);

            ProductRelatedMaterialsService.RepairCodeCardData service =
                new ProductRelatedMaterialsService.RepairCodeCardData();
            service.productId = fakeId(Product2.SObjectType);
            service.productCode = 'SC-001';
            service.productName = 'Service Code';
            service.codeType = 'Service Code';
            service.selected = false;
            cards.serviceCodes.add(service);
            return cards;
        }

        public Id persistInstrumentEvaluationItem(
            Id workOrderId,
            Id productId,
            Decimal quantity,
            List<Id> repairCodeProductIds
        ) {
            return workOrderId;
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            return new List<Id>{ workOrderId };
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems,
            Boolean reconcileRemovedLines
        ) {
            return saveInstrumentEvaluationDraft(workOrderId, draftItems);
        }

        public List<Id> completeInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            return new List<Id>{ workOrderId };
        }

        public List<WorkOrdersService.InstrumentEvaluationItem> getInstrumentEvaluationItems(
            Id workOrderId
        ) {
            WorkOrdersService.InstrumentEvaluationItem item =
                new WorkOrdersService.InstrumentEvaluationItem();
            item.productServicedId = workOrderId;
            item.status = 'Waiting for Approval';
            item.productId = workOrderId;
            item.productCode = 'INST-001';
            item.productName = 'Test Instrument';
            item.quantity = 2;

            ProductRelatedMaterialsService.RepairCodeCardData code =
                new ProductRelatedMaterialsService.RepairCodeCardData();
            code.productId = workOrderId;
            code.productCode = 'RC-001';
            code.productName = 'Repair Code Name';
            code.codeType = 'Category Code';
            code.workOrderLineItemId = workOrderId;
            code.status = 'Approved';
            code.selected = true;
            item.repairCodes = new List<ProductRelatedMaterialsService.RepairCodeCardData>{
                code
            };

            ContentDocumentLinksService.DeviceEvaluationFileData photo =
                new ContentDocumentLinksService.DeviceEvaluationFileData();
            photo.contentDocumentId = fakeId(ContentDocument.SObjectType);
            photo.title = 'IE Photo';
            photo.thumbnailUrl = '';
            photo.imageDownloadUrl = '/sfc/download';
            ContentDocumentLinksService.DeviceEvaluationFileData skipped =
                new ContentDocumentLinksService.DeviceEvaluationFileData();
            item.photos = new List<ContentDocumentLinksService.DeviceEvaluationFileData>{
                photo,
                skipped,
                null
            };
            return new List<WorkOrdersService.InstrumentEvaluationItem>{ item };
        }

        public void returnWorkOrderToEvaluation(Id workOrderId) {
        }
    }

    private static Id fakeId(Schema.SObjectType sobjectType) {
        return (Id) (sobjectType.getDescribe().getKeyPrefix() + '000000000001');
    }

    /**
     * @description GW-3400 - Stub that throws WorkOrdersServiceException.
     */
    private class ThrowingClient implements InstrumentEvaluationController.IInstrumentEvaluationClient {
        /**
         * @description GW-3400 - Throws not-found to exercise initialize error wrapping.
         * @param workOrderInput Work Order Id or Number
         * @return Never returns
         */
        public WorkOrdersService.InstrumentEvaluationContext initializeInstrumentEvaluation(
            String workOrderInput
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order was not found.');
        }

        /**
         * @description GW-3400 - Throws a save error to exercise save error wrapping.
         * @param workOrderId Parent Work Order Id
         * @param subStatus Sub Status value
         * @param unableToTakePhoto Unable To Take Photo checkbox
         * @param turnTime Turn Time
         * @param evaluationNotes Customer-facing evaluation notes
         * @param internalEvaluationNotes Internal evaluation notes
         * @param internalSpecialistEvaluationNotes Internal specialist notes
         * @return Never returns
         */
        public WorkOrdersService.InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            Decimal quantityReceived,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<WorkOrdersService.InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
            Id workOrderId
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<WorkOrdersService.InstrumentProductCard> getInstrumentEvaluationProducts(
            Id workOrderId,
            String evalCategory
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
            getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public Id persistInstrumentEvaluationItem(
            Id workOrderId,
            Id productId,
            Decimal quantity,
            List<Id> repairCodeProductIds
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems,
            Boolean reconcileRemovedLines
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<Id> completeInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public List<WorkOrdersService.InstrumentEvaluationItem> getInstrumentEvaluationItems(
            Id workOrderId
        ) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }

        public void returnWorkOrderToEvaluation(Id workOrderId) {
            throw new WorkOrdersService.WorkOrdersServiceException('Work Order is required.');
        }
    }

    /**
     * @description GW-3400 - Stub that throws an unexpected exception for error wrapping.
     */
    private class UnexpectedExceptionClient
        implements InstrumentEvaluationController.IInstrumentEvaluationClient {
        /**
         * @description GW-3400 - Throws a non-service exception on initialize.
         * @param workOrderInput Work Order Id or Number
         * @return Never returns
         */
        public WorkOrdersService.InstrumentEvaluationContext initializeInstrumentEvaluation(
            String workOrderInput
        ) {
            throw new IllegalArgumentException('Unexpected initialize failure');
        }

        /**
         * @description GW-3400 - Throws a non-service exception on save.
         * @param workOrderId Parent Work Order Id
         * @param subStatus Sub Status value
         * @param unableToTakePhoto Unable To Take Photo checkbox
         * @param turnTime Turn Time
         * @param evaluationNotes Customer-facing evaluation notes
         * @param internalEvaluationNotes Internal evaluation notes
         * @param internalSpecialistEvaluationNotes Internal specialist notes
         * @return Never returns
         */
        public WorkOrdersService.InstrumentEvaluationContext saveInstrumentEvaluationWorkOrderFields(
            Id workOrderId,
            String subStatus,
            Boolean unableToTakePhoto,
            Decimal turnTime,
            Decimal quantityReceived,
            String evaluationNotes,
            String internalEvaluationNotes,
            String internalSpecialistEvaluationNotes
        ) {
            throw new IllegalArgumentException('Unexpected save failure');
        }

        public List<WorkOrdersService.InstrumentEvalCategoryCard> getInstrumentEvaluationEvalCategories(
            Id workOrderId
        ) {
            throw new IllegalArgumentException('Unexpected catalog failure');
        }

        public List<WorkOrdersService.InstrumentProductCard> getInstrumentEvaluationProducts(
            Id workOrderId,
            String evalCategory
        ) {
            throw new IllegalArgumentException('Unexpected product failure');
        }

        public ProductRelatedMaterialsService.InstrumentEvaluationCodeCards
            getInstrumentEvaluationRepairCodes(Id workOrderId, Id productId) {
            throw new IllegalArgumentException('Unexpected repair code failure');
        }

        public Id persistInstrumentEvaluationItem(
            Id workOrderId,
            Id productId,
            Decimal quantity,
            List<Id> repairCodeProductIds
        ) {
            throw new IllegalArgumentException('Unexpected persist failure');
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            throw new IllegalArgumentException('Unexpected save draft failure');
        }

        public List<Id> saveInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems,
            Boolean reconcileRemovedLines
        ) {
            throw new IllegalArgumentException('Unexpected save draft failure');
        }

        public List<Id> completeInstrumentEvaluationDraft(
            Id workOrderId,
            List<WorkOrdersService.InstrumentEvaluationDraftItem> draftItems
        ) {
            throw new IllegalArgumentException('Unexpected complete failure');
        }

        public List<WorkOrdersService.InstrumentEvaluationItem> getInstrumentEvaluationItems(
            Id workOrderId
        ) {
            throw new IllegalArgumentException('Unexpected items failure');
        }

        public void returnWorkOrderToEvaluation(Id workOrderId) {
            throw new IllegalArgumentException('Unexpected return failure');
        }
    }

    /**
     * @description GW-3400 - Verifies blank scan input requires a Work Order.
     */
    @IsTest
    static void testInitializeEvaluation_WhenBlankInput_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.initializeEvaluation('  ');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('required'),
                'Blank input should require a Work Order'
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Blank Work Order input should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Verifies unknown Work Order Id/Number throws AuraHandledException.
     */
    @IsTest
    static void testInitializeEvaluation_WhenInvalidId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.initializeEvaluation('not-an-id');
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('was not found'),
                'Unknown Id/Number should use the shared not-found message'
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unknown Work Order input should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Verifies initialize by Id or Number and save return workspace DTOs.
     */
    @IsTest
    static void testInitializeAndSave_WhenStubClient_ReturnsWorkspace() {
        InstrumentEvaluationController.clientOverride = new StubClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = [
            SELECT Id, WorkOrderNumber
            FROM WorkOrder
            WHERE Id = :((WorkOrder) builder.record).Id
        ];

        Test.startTest();
        InstrumentEvaluationController.Workspace startedById =
            InstrumentEvaluationController.initializeEvaluation(created.Id);
        InstrumentEvaluationController.Workspace startedByNumber =
            InstrumentEvaluationController.initializeEvaluation(created.WorkOrderNumber);
        InstrumentEvaluationController.Workspace saved =
            InstrumentEvaluationController.saveWorkOrderFields(
                created.Id,
                'Eval',
                true,
                3,
                1,
                'Customer notes',
                'Internal notes',
                'Specialist notes',
                null);
        Test.stopTest();

        Assert.areEqual(created.Id, startedById.workOrderId);
        Assert.areEqual('QC notes', startedById.qcInspectionNotes);
        Assert.isTrue(startedById.shipComplete, 'Ship Complete should map from the Work Order.');
        Assert.areEqual(created.Id, startedByNumber.workOrderId);
        Assert.isTrue(startedById.showItemSelection);
        Assert.isTrue(startedById.hasAsset);
        Assert.areEqual(1, startedById.customerPreferences.size());
        Assert.areEqual('Customer notes', saved.evaluationNotes);
        Assert.areEqual(3, saved.turnTime);
        Assert.isTrue(saved.unableToTakePhoto);
    }

    /**
     * @description GW-3400 - Verifies save with a null Work Order Id throws.
     */
    @IsTest
    static void testSaveWorkOrderFields_WhenNullId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.saveWorkOrderFields(
                null,
                'Eval',
                false,
                1,
                1,
                null,
                null,
                null,
                null);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(
                e.getMessage().contains('required'),
                'Null Work Order Id should require a Work Order'
            );
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null Work Order Id should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Verifies the default client calls WorkOrdersService.
     */
    @IsTest
    static void testInitializeAndSave_WhenDefaultClient_UsesService() {
        InstrumentEvaluationController.clientOverride = null;
        WorkOrder created = createInstrumentEvaluationParentWorkOrder();

        Test.startTest();
        InstrumentEvaluationController.Workspace started =
            InstrumentEvaluationController.initializeEvaluation(created.Id);
        InstrumentEvaluationController.Workspace saved =
            InstrumentEvaluationController.saveWorkOrderFields(
                created.Id,
                started.subStatus,
                false,
                2,
                1,
                'Saved notes',
                null,
                null,
                null);
        List<InstrumentEvaluationController.EvalCategoryCard> categories =
            InstrumentEvaluationController.getEvalCategories(created.Id);
        List<InstrumentEvaluationController.ProductCard> products =
            InstrumentEvaluationController.getProductsForEvalCategory(created.Id, 'Forceps');
        InstrumentEvaluationController.RepairCodeWorkspace codes;
        try {
            codes = InstrumentEvaluationController.getRepairCodesForProduct(created.Id, null);
        } catch (AuraHandledException e) {
            codes = new InstrumentEvaluationController.RepairCodeWorkspace();
        }
        List<InstrumentEvaluationController.EvaluationItem> items =
            InstrumentEvaluationController.getEvaluationItems(created.Id);
        List<InstrumentEvaluationController.RepairSignatureRow> signatures =
            InstrumentEvaluationController.getRepairSignatures(created.Id);
        List<Id> draftIds = InstrumentEvaluationController.saveDraftItems(
            created.Id,
            new List<InstrumentEvaluationController.DraftItemInput>(),
            false
        );
        Test.stopTest();

        Assert.areEqual(created.Id, started.workOrderId);
        Assert.areEqual(created.Status, started.status);
        Assert.areEqual(created.SubStatus__c, started.subStatus);
        Assert.isTrue(started.showItemSelection);
        Assert.isTrue(started.canAddItems);
        Assert.areEqual('Saved notes', saved.evaluationNotes);
        Assert.areEqual(2, saved.turnTime);
        Assert.isNotNull(categories);
        Assert.isNotNull(products);
        Assert.isNotNull(codes);
        Assert.isNotNull(items);
        Assert.isNotNull(signatures);
        Assert.isNotNull(draftIds);
    }

    /**
     * @description GW-3400 - Verifies service exceptions are wrapped as AuraHandledException.
     */
    @IsTest
    static void testInitializeAndSave_WhenServiceThrows_WrapsAura() {
        InstrumentEvaluationController.clientOverride = new ThrowingClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Boolean initializeThrew = false;
        Boolean saveThrew = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.initializeEvaluation(created.Id);
        } catch (AuraHandledException e) {
            initializeThrew = true;
            Assert.isTrue(e.getMessage().contains('was not found'));
        }
        try {
            InstrumentEvaluationController.saveWorkOrderFields(
                created.Id,
                null,
                false,
                null,
                null,
                null,
                null,
                null,
                null);
        } catch (AuraHandledException e) {
            saveThrew = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();

        Assert.isTrue(initializeThrew, 'Service initialize exception should wrap as Aura');
        Assert.isTrue(saveThrew, 'Service save exception should wrap as Aura');
    }

    /**
     * @description GW-3400 - Verifies unexpected exceptions use a generic Aura message.
     */
    @IsTest
    static void testInitializeAndSave_WhenUnexpectedThrows_WrapsGeneric() {
        InstrumentEvaluationController.clientOverride = new UnexpectedExceptionClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Boolean initializeThrew = false;
        Boolean saveThrew = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.initializeEvaluation(created.Id);
        } catch (AuraHandledException e) {
            initializeThrew = true;
            Assert.isTrue(e.getMessage().contains('Unable to start Instrument Evaluation.'));
        }
        try {
            InstrumentEvaluationController.saveWorkOrderFields(
                created.Id,
                null,
                false,
                null,
                null,
                null,
                null,
                null,
                null);
        } catch (AuraHandledException e) {
            saveThrew = true;
            Assert.isTrue(e.getMessage().contains('Unable to save Instrument Evaluation.'));
        }
        Test.stopTest();

        Assert.isTrue(initializeThrew, 'Unexpected initialize exception should wrap as Aura');
        Assert.isTrue(saveThrew, 'Unexpected save exception should wrap as Aura');
    }

    /**
     * @description GW-3400 - Verifies Step 2 catalog and persist methods return stub DTOs.
     */
    @IsTest
    static void testCatalogAndPersist_WhenStubClient_ReturnsDtos() {
        InstrumentEvaluationController.clientOverride = new StubClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Test.startTest();
        List<InstrumentEvaluationController.EvalCategoryCard> categories =
            InstrumentEvaluationController.getEvalCategories(created.Id);
        List<InstrumentEvaluationController.ProductCard> products =
            InstrumentEvaluationController.getProductsForEvalCategory(created.Id, 'Forceps');
        InstrumentEvaluationController.RepairCodeWorkspace codes =
            InstrumentEvaluationController.getRepairCodesForProduct(created.Id, created.Id);
        Id savedId = InstrumentEvaluationController.saveProductServicedItem(
            created.Id,
            created.Id,
            2,
            new List<Id>{ created.Id }
        );
        List<InstrumentEvaluationController.EvaluationItem> items =
            InstrumentEvaluationController.getEvaluationItems(created.Id);
        Test.stopTest();

        Assert.areEqual(1, categories.size());
        Assert.areEqual('Forceps', categories[0].evalCategory);
        Assert.areEqual(1, products.size());
        Assert.areEqual('INST-001', products[0].productCode);
        Assert.areEqual(1, codes.categoryCodes.size());
        Assert.areEqual(1, codes.serviceCodes.size());
        Assert.areEqual('Approved', codes.categoryCodes[0].status);
        Assert.areEqual(created.Id, savedId);
        Assert.areEqual(1, items.size());
        Assert.areEqual('Waiting for Approval', items[0].status);
        Assert.areEqual(2, items[0].quantity);
        Assert.areEqual(1, items[0].repairCodes.size());
        Assert.areEqual('Approved', items[0].repairCodes[0].status);
        Assert.areEqual(1, items[0].photos.size());
        Assert.areEqual('IE Photo', items[0].photos[0].title);
        Assert.areEqual('/sfc/download', items[0].photos[0].thumbnailUrl);
    }

    /**
     * @description GW-3400 - Verifies Return to Eval delegates to the service client.
     */
    @IsTest
    static void testReturnToEvaluation_WhenStubClient_Succeeds() {
        InstrumentEvaluationController.clientOverride = new StubClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Test.startTest();
        InstrumentEvaluationController.returnToEvaluation(created.Id);
        Test.stopTest();
        Assert.isTrue(true, 'Return to Eval should complete without error');
    }

    /**
     * @description GW-3400 - Verifies Return to Eval requires a Work Order Id.
     */
    @IsTest
    static void testReturnToEvaluation_WhenNullId_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.returnToEvaluation(null);
        } catch (AuraHandledException e) {
            threw = true;
            Assert.isTrue(e.getMessage().contains('required'));
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null Work Order Id should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Verifies Step 2 required-input guards.
     */
    @IsTest
    static void testCatalogAndPersist_WhenMissingRequiredInput_Throws() {
        Boolean categoriesThrew = false;
        Boolean productsThrew = false;
        Boolean productsCategoryThrew = false;
        Boolean codesThrew = false;
        Boolean saveWorkOrderThrew = false;
        Boolean saveProductThrew = false;
        Boolean itemsThrew = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.getEvalCategories(null);
        } catch (AuraHandledException e) {
            categoriesThrew = e.getMessage().contains('required');
        }
        try {
            InstrumentEvaluationController.getProductsForEvalCategory(null, 'Forceps');
        } catch (AuraHandledException e) {
            productsThrew = e.getMessage().contains('required');
        }
        try {
            InstrumentEvaluationController.getProductsForEvalCategory(UserInfo.getUserId(), '  ');
        } catch (AuraHandledException e) {
            productsCategoryThrew = e.getMessage().contains('Eval Category');
        }
        try {
            InstrumentEvaluationController.getRepairCodesForProduct(null, null);
        } catch (AuraHandledException e) {
            codesThrew = e.getMessage().contains('required');
        }
        try {
            InstrumentEvaluationController.saveProductServicedItem(null, UserInfo.getUserId(), 1, null);
        } catch (AuraHandledException e) {
            saveWorkOrderThrew = e.getMessage().contains('required');
        }
        try {
            InstrumentEvaluationController.saveProductServicedItem(
                UserInfo.getUserId(),
                null,
                1,
                null
            );
        } catch (AuraHandledException e) {
            saveProductThrew = e.getMessage().contains('Product');
        }
        try {
            InstrumentEvaluationController.getEvaluationItems(null);
        } catch (AuraHandledException e) {
            itemsThrew = e.getMessage().contains('required');
        }
        Test.stopTest();

        Assert.isTrue(categoriesThrew);
        Assert.isTrue(productsThrew);
        Assert.isTrue(productsCategoryThrew);
        Assert.isTrue(codesThrew);
        Assert.isTrue(saveWorkOrderThrew);
        Assert.isTrue(saveProductThrew);
        Assert.isTrue(itemsThrew);
    }

    /**
     * @description GW-3400 - Verifies Step 2 service and unexpected exceptions wrap as Aura.
     */
    @IsTest
    static void testCatalogAndPersist_WhenClientThrows_WrapsAura() {
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        InstrumentEvaluationController.clientOverride = new ThrowingClient();
        Boolean serviceThrew = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.getEvalCategories(created.Id);
        } catch (AuraHandledException e) {
            serviceThrew = e.getMessage().contains('required');
        }

        InstrumentEvaluationController.clientOverride = new UnexpectedExceptionClient();
        Boolean unexpectedThrew = false;
        try {
            InstrumentEvaluationController.getEvalCategories(created.Id);
        } catch (AuraHandledException e) {
            unexpectedThrew = e.getMessage().contains('Unable to load evaluation categories.');
        }
        Boolean persistUnexpected = false;
        try {
            InstrumentEvaluationController.saveProductServicedItem(
                created.Id,
                created.Id,
                1,
                null
            );
        } catch (AuraHandledException e) {
            persistUnexpected = e.getMessage().contains('Unable to save the evaluation item.');
        }
        Test.stopTest();

        Assert.isTrue(serviceThrew, 'Service exception should wrap as Aura');
        Assert.isTrue(unexpectedThrew, 'Unexpected catalog exception should wrap as Aura');
        Assert.isTrue(persistUnexpected, 'Unexpected persist exception should wrap as Aura');
    }

    /**
     * @description GW-3400 - Verifies completeDraftItems delegates through the stub client.
     */
    @IsTest
    static void testCompleteDraftItems_WhenValid_ReturnsIds() {
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;
        InstrumentEvaluationController.clientOverride = new StubClient();
        InstrumentEvaluationController.DraftItemInput draft =
            new InstrumentEvaluationController.DraftItemInput();
        draft.productId = created.Id;
        draft.quantity = 1;
        draft.repairCodeProductIds = new List<Id>();
        draft.contentDocumentIds = new List<Id>();

        Test.startTest();
        List<Id> ids = InstrumentEvaluationController.completeDraftItems(
            created.Id,
            new List<InstrumentEvaluationController.DraftItemInput>{ draft }
        );
        Test.stopTest();

        Assert.areEqual(1, ids.size());
        Assert.areEqual(created.Id, ids[0]);
    }

    /**
     * @description GW-3400 - Verifies completeDraftItems requires a Work Order Id.
     */
    @IsTest
    static void testCompleteDraftItems_WhenNullWorkOrder_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.completeDraftItems(null, null);
        } catch (AuraHandledException e) {
            threw = e.getMessage().contains('required');
        }
        Test.stopTest();
        Assert.isTrue(threw);
    }

    /**
     * @description GW-3400 - Verifies removeEvaluationPhoto unlinks and deletes the photo.
     */
    @IsTest
    static void testRemoveEvaluationPhoto_WhenLinked_RemovesPhoto() {
        WorkOrder workOrder = createInstrumentEvaluationParentWorkOrder();
        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            Description = 'IE photo remove',
            Status = 'New'
        );
        insert productServiced;

        Id contentDocumentId = insertStagedContentDocument('IE-Remove-Photo');
        ContentDocumentLinksService.attachDocumentsToLinkedEntity(
            productServiced.Id,
            new List<Id>{ contentDocumentId }
        );

        Test.startTest();
        InstrumentEvaluationController.removeEvaluationPhoto(
            workOrder.Id,
            productServiced.Id,
            contentDocumentId
        );
        Test.stopTest();

        Assert.areEqual(
            0,
            [
                SELECT COUNT()
                FROM ContentDocumentLink
                WHERE
                    LinkedEntityId = :productServiced.Id
                    AND ContentDocumentId = :contentDocumentId
            ],
            'Photo link should be removed from the Product Serviced line'
        );
        Assert.areEqual(
            0,
            [SELECT COUNT() FROM ContentDocument WHERE Id = :contentDocumentId],
            'Orphaned ContentDocument should be deleted'
        );
    }

    /**
     * @description GW-3400 - Verifies removeEvaluationPhoto requires all Ids.
     */
    @IsTest
    static void testRemoveEvaluationPhoto_WhenMissingArgs_Throws() {
        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.removeEvaluationPhoto(null, null, null);
        } catch (AuraHandledException e) {
            threw = e.getMessage().contains('required');
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Null arguments should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Verifies removeEvaluationPhoto rejects items not on the Work Order.
     */
    @IsTest
    static void testRemoveEvaluationPhoto_WhenItemNotOnWorkOrder_Throws() {
        WorkOrder workOrder = createInstrumentEvaluationParentWorkOrder();
        WorkOrder otherWorkOrder = createInstrumentEvaluationParentWorkOrder();
        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = otherWorkOrder.Id,
            Description = 'Other WO line',
            Status = 'New'
        );
        insert productServiced;
        Id contentDocumentId = insertStagedContentDocument('IE-Remove-Wrong-WO');

        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.removeEvaluationPhoto(
                workOrder.Id,
                productServiced.Id,
                contentDocumentId
            );
        } catch (AuraHandledException e) {
            threw = e.getMessage().contains('not found');
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Mismatched Work Order / item should throw');
    }

    /**
     * @description GW-3400 - Verifies removeEvaluationPhoto rejects photos not linked to the item.
     */
    @IsTest
    static void testRemoveEvaluationPhoto_WhenNotAttached_Throws() {
        WorkOrder workOrder = createInstrumentEvaluationParentWorkOrder();
        WorkOrderLineItem productServiced = new WorkOrderLineItem(
            WorkOrderId = workOrder.Id,
            Description = 'IE photo not attached',
            Status = 'New'
        );
        insert productServiced;
        Id contentDocumentId = insertStagedContentDocument('IE-Remove-Unlinked');

        Boolean threw = false;
        Test.startTest();
        try {
            InstrumentEvaluationController.removeEvaluationPhoto(
                workOrder.Id,
                productServiced.Id,
                contentDocumentId
            );
        } catch (AuraHandledException e) {
            threw =
                e.getMessage().contains('not attached') ||
                e.getMessage().contains('Unable to remove');
        }
        Test.stopTest();
        Assert.isTrue(threw, 'Unlinked photo should throw AuraHandledException');
    }

    /**
     * @description GW-3400 - Covers rich workspace mapping, draft save, vendor address, and
     *              signature Aura paths (success + validation failures).
     */
    @IsTest
    static void testWorkspaceDraftVendorAndSignatures_WhenStubAndValidation_CoverPaths() {
        InstrumentEvaluationController.clientOverride = new StubClient();
        adb_WorkOrder builder = new adb_WorkOrder();
        builder.persist();
        WorkOrder created = (WorkOrder) builder.record;

        Account vendorAccount = (Account) new adb_Account().name('IE Vendor Coverage').persist();

        InstrumentEvaluationController.DraftItemInput draft =
            new InstrumentEvaluationController.DraftItemInput();
        draft.productServicedId = null;
        draft.productId = created.Id;
        draft.quantity = 1;
        draft.repairCodeProductIds = new List<Id>{ created.Id };
        draft.contentDocumentIds = new List<Id>{ fakeId(ContentDocument.SObjectType) };
        draft.vendorProcessingRequired = true;
        draft.vendorAccountId = vendorAccount.Id;
        draft.instructionsToVendor = 'Ship overnight';
        draft.vendorNotes = 'Notes';
        draft.vendorReferenceNumber = 'VR-1';
        draft.vendorCost = 12.5;
        draft.shippedToVendorDate = Date.today();
        draft.trackingNumber = '1Z999';

        Test.startTest();
        InstrumentEvaluationController.Workspace workspace =
            InstrumentEvaluationController.initializeEvaluation(created.Id);
        List<Id> savedDraftIds = InstrumentEvaluationController.saveDraftItems(
            created.Id,
            new List<InstrumentEvaluationController.DraftItemInput>{ draft, null },
            false
        );
        WorkOrdersService.VendorAddressResult address =
            InstrumentEvaluationController.getVendorAddress(vendorAccount.Id);
        List<InstrumentEvaluationController.RepairSignatureRow> signatures =
            InstrumentEvaluationController.getRepairSignatures(created.Id);

        Boolean addSignatureThrew = false;
        try {
            InstrumentEvaluationController.addRepairSignature(created.Id, created.Id);
        } catch (Exception e) {
            addSignatureThrew = true;
        }
        // Happy-path sign-all (no matching WOLIs) covers the success mapping branch.
        List<InstrumentEvaluationController.RepairSignatureRow> signAllRows =
            InstrumentEvaluationController.signAllRepairCodes(
                created.Id,
                new List<Id>{ created.Id }
            );
        Boolean signAllThrew = false;
        try {
            InstrumentEvaluationController.signAllRepairCodes(
                null,
                new List<Id>{ created.Id }
            );
        } catch (Exception e) {
            signAllThrew = true;
        }
        Boolean removeSignatureThrew = false;
        try {
            InstrumentEvaluationController.removeRepairSignature(created.Id, null);
        } catch (Exception e) {
            removeSignatureThrew = true;
        }
        WorkOrdersService.VendorAddressResult blankAddress =
            InstrumentEvaluationController.getVendorAddress(null);
        Boolean saveDraftThrew = false;
        try {
            InstrumentEvaluationController.saveDraftItems(null, null, false);
        } catch (Exception e) {
            saveDraftThrew = true;
        }
        Test.stopTest();

        Assert.areEqual(created.Id, workspace.workOrderId);
        Assert.isTrue(workspace.photosRequired);
        Assert.isTrue(workspace.hasAsset);
        Assert.areEqual('STERIS', workspace.manufacturer);
        Assert.areEqual(1, workspace.customerPreferences.size());
        Assert.areEqual(1, workspace.repairHistory.size());
        Assert.areEqual(
            'Angulation up/down is loose.',
            workspace.repairHistory[0].reportedProblem
        );
        Assert.areEqual(true, workspace.repairHistory[0].isWithinLastTwelveMonths);
        Assert.isTrue(workspace.repairHistoryHasMore);
        Assert.isFalse(workspace.subStatusOptions.isEmpty());
        Set<String> subStatusValues = new Set<String>();
        for (PlatformUtilities.PicklistOption option : workspace.subStatusOptions) {
            subStatusValues.add(option.value);
        }
        Assert.isFalse(
            subStatusValues.contains('Angulation'),
            'Device-only Sub Status values must be excluded for Instruments'
        );
        Assert.areEqual(1, savedDraftIds.size());
        Assert.isNotNull(address);
        Assert.areEqual('', blankAddress.formattedAddress);
        Assert.isNotNull(signatures);
        Assert.isTrue(addSignatureThrew, 'Invalid add signature should throw');
        Assert.isNotNull(signAllRows, 'Sign-all with unmatched WOLI Ids should return rows');
        Assert.isTrue(signAllThrew, 'Null Work Order Id on sign-all should throw');
        Assert.isTrue(removeSignatureThrew, 'Null signature Id should throw');
        Assert.isTrue(saveDraftThrew, 'Null Work Order Id should throw');
    }

    /**
     * @description GW-3400 - Creates a staged ContentDocument for photo remove tests.
     * @param title Document title
     * @return ContentDocument Id
     */
    private static Id insertStagedContentDocument(String title) {
        ContentVersion version = new ContentVersion(
            Title = title,
            PathOnClient = title + '.jpg',
            VersionData = Blob.valueOf('IE-photo-remove-test'),
            IsMajorVersion = true
        );
        insert version;
        return [
            SELECT ContentDocumentId
            FROM ContentVersion
            WHERE Id = :version.Id
        ]
        .ContentDocumentId;
    }

    /**
     * @description GW-3400 - Parent Instruments Work Order with Account for evaluation tests.
     * @return Persisted parent Instruments Work Order
     */
    private static WorkOrder createInstrumentEvaluationParentWorkOrder() {
        adb_WorkOrder builder = new adb_WorkOrder()
            .setRecordType('RepairCenterInstruments')
            .account(new adb_Account())
            .status('Evaluate & Quote');
        builder.persist();
        return (WorkOrder) builder.record;
    }

    /**
     * @description Sub Status options for Instruments exclude Device-only values and keep
     *              Status dependency (Evaluate & Quote omits Waiting/Rejected/PO Required unless current).
     */
    @IsTest
    private static void testGetSubStatusOptionsInstrumentsRecordTypeFilter() {
        Test.startTest();
        List<PlatformUtilities.PicklistOption> repairOptions =
            InstrumentEvaluationController.getSubStatusOptions('Repair', null);
        List<PlatformUtilities.PicklistOption> evaluateOptions =
            InstrumentEvaluationController.getSubStatusOptions('Evaluate & Quote', null);
        List<PlatformUtilities.PicklistOption> evaluateWithWaiting =
            InstrumentEvaluationController.getSubStatusOptions(
                'Evaluate & Quote',
                'Waiting for Approval'
            );
        List<PlatformUtilities.PicklistOption> evaluateWithPoRequired =
            InstrumentEvaluationController.getSubStatusOptions(
                'Evaluate & Quote',
                'PO Required'
            );
        Test.stopTest();

        Set<String> repairValues = new Set<String>();
        for (PlatformUtilities.PicklistOption option : repairOptions) {
            repairValues.add(option.value);
        }
        Set<String> evaluateValues = new Set<String>();
        for (PlatformUtilities.PicklistOption option : evaluateOptions) {
            evaluateValues.add(option.value);
        }
        Set<String> evaluateWaitingValues = new Set<String>();
        for (PlatformUtilities.PicklistOption option : evaluateWithWaiting) {
            evaluateWaitingValues.add(option.value);
        }

        Assert.isFalse(repairValues.contains('Angulation'));
        Assert.isFalse(repairValues.contains('Assembly'));
        Assert.isTrue(
            repairValues.contains('Contaminated'),
            'GW-5687 Contaminated must be available during Repair for Instrument Eval'
        );
        Assert.isFalse(evaluateValues.contains('Waiting for Approval'));
        Assert.isFalse(evaluateValues.contains('Rejected'));
        Assert.isFalse(evaluateValues.contains('PO Required'));
        Assert.isTrue(evaluateWaitingValues.contains('Waiting for Approval'));
        Set<String> evaluatePoRequiredValues = new Set<String>();
        for (PlatformUtilities.PicklistOption option : evaluateWithPoRequired) {
            evaluatePoRequiredValues.add(option.value);
        }
        Assert.isTrue(evaluatePoRequiredValues.contains('PO Required'));
    }

    @IsTest
    private static void testMapReturnOrderLineAssignmentMapsOptions() {
        WorkOrdersService.InstrumentReturnOrderLineOption sourceOption =
            new WorkOrdersService.InstrumentReturnOrderLineOption();
        sourceOption.id = fakeId(ReturnOrderLineItem.SObjectType);
        sourceOption.lineItemNumber = 'ROLI-0001';
        sourceOption.serialNumber = 'SERIAL-1';
        sourceOption.productName = 'Instrument';
        sourceOption.itemDescription = 'Description';
        sourceOption.model = 'MODEL-1';
        sourceOption.quantity = 2;
        sourceOption.selected = true;
        WorkOrdersService.InstrumentReturnOrderLineAssignment source =
            new WorkOrdersService.InstrumentReturnOrderLineAssignment();
        source.returnOrderNumber = 'RO-0001';
        source.options.add(sourceOption);

        InstrumentEvaluationController.ReturnOrderLineAssignment result =
            InstrumentEvaluationController.mapReturnOrderLineAssignment(source);

        Assert.areEqual('RO-0001', result.returnOrderNumber);
        Assert.areEqual(1, result.options.size());
        Assert.areEqual('ROLI-0001', result.options[0].lineItemNumber);
        Assert.isTrue(result.options[0].selected);
    }

    @IsTest
    private static void testGetReturnOrderLineAssignmentRequiresIds() {
        Boolean threw = false;
        try {
            InstrumentEvaluationController.getReturnOrderLineAssignment(null, null);
        } catch (AuraHandledException e) {
            threw = e.getMessage().contains('required');
        }
        Assert.isTrue(threw, 'Missing identifiers should be rejected');
    }
}