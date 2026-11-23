/**
 * @description Tests CIO Evaluation list and questionnaire defaults. GW-4749
 */
@IsTest(isParallel=false)
private class CIOEvaluationsControllerTest {
    private static final String SUBJECT = 'GW-4749 CIO WO';

    @TestSetup
    static void setupData() {
        assignPermissionSetIfNeeded('System_Administrator');
        adb_Account accountBuilder = new adb_Account()
            .name('GW-4749 Account')
            .systemId('GW4749-ACCOUNT')
            .sourceSystemId('GW4749-SOURCE')
            .orgIds('82');
        adb_Product2 productBuilder = new adb_Product2()
            .name('GW-4749 Product')
            .productCode('GW4749-PRODUCT')
            .productType('Service Asset')
            .productLine('FLEXIBLE SCOPE')
            .manufacturer('STERIS')
            .model('GW4749');
        adb_Asset assetBuilder = new adb_Asset()
            .name('GW-4749 Asset')
            .account(accountBuilder)
            .product(productBuilder)
            .serialNumber('GW4749-SERIAL');

        new adb_WorkOrder()
            .account(accountBuilder)
            .asset(assetBuilder)
            .status('Evaluate')
            .subject(SUBJECT)
            .setRecordType('RepairCenterDevices')
            .pricebook2Id(Test.getStandardPricebookId());
        accountBuilder.persist();
    }

    @IsTest
    static void getEvaluations_returnsEmptyUntilQuestionnaireIsSaved() {
        WorkOrder workOrder = selectWorkOrder();

        Test.startTest();
        List<CIOEvaluationsController.EvaluationRow> rows = CIOEvaluationsController.getEvaluations(
            workOrder.Id
        );
        Test.stopTest();

        Assert.isTrue(rows.isEmpty(), 'A new work order should not have a CIO Evaluation.');
    }

    @IsTest
    static void getFormContext_defaultsTechnicianDateAndRecordType() {
        WorkOrder workOrder = selectWorkOrder();

        Test.startTest();
        CIOEvaluationsController.FormContext context = CIOEvaluationsController.getFormContext(
            workOrder.Id
        );
        Test.stopTest();

        Assert.areEqual(UserInfo.getUserId(), context.technicianId);
        Assert.areEqual(Date.today(), context.evaluationDate);
        Assert.isNotNull(context.recordTypeId);
        Assert.areEqual(workOrder.ParentWorkOrderId, context.parentWorkOrderId);
    }

    @IsTest
    static void getEvaluations_returnsSavedQuestionnaire() {
        WorkOrder workOrder = selectWorkOrder();
        CIOEvaluation__c saved = new CIOEvaluation__c(
            WorkOrder__c = workOrder.Id,
            RecordTypeId = CIOEvaluation__c.SObjectType.getDescribe()
                .getRecordTypeInfosByDeveloperName()
                .get('RepairCenter')
                .getRecordTypeId(),
            Technician__c = UserInfo.getUserId(),
            Date__c = Date.today(),
            ConfirmedCustomerReportedIssue__c = 'Yes',
            IdentifiableRootCause__c = 'No',
            IdentifiableRootCauseDetails__c = 'Root cause cannot be determined from the returned device.',
            IssueRelatedToPreviousRepair__c = 'No',
            PreviousRepairDeficiencyDetails__c = 'No previous STERIS repair deficiency.',
            SignsOfDamageWearFailure__c = 'Yes',
            SignsOfDamageWearFailureDetails__c = 'Part 12345',
            DetermineExtentOfUsage__c = 'Yes',
            UsesLogged__c = '12',
            CorrectiveActionTaken__c = 'Yes',
            CorrectiveActionAdditionalDetails__c = 'Training record retained for Quality.'
        );
        insert saved;

        Test.startTest();
        List<CIOEvaluationsController.EvaluationRow> rows = CIOEvaluationsController.getEvaluations(
            workOrder.Id
        );
        Test.stopTest();

        Assert.areEqual(1, rows.size());
        Assert.areEqual(saved.Id, rows[0].id);
        Assert.isTrue(rows[0].name.startsWith('CIOE-'));
        Assert.areEqual('Yes', rows[0].confirmedCustomerReportedIssue);
        Assert.areEqual('No', rows[0].identifiableRootCause);
        Assert.areEqual('Yes', rows[0].determineExtentOfUsage);
        Assert.areEqual('Yes', rows[0].correctiveActionTaken);
        Assert.areEqual(UserInfo.getName(), rows[0].technicianName);
        Assert.areEqual(Date.today(), rows[0].evaluationDate);
    }

    @IsTest
    static void getFormContext_requiresWorkOrder() {
        try {
            CIOEvaluationsController.getFormContext(null);
            Assert.fail('A missing Work Order should be rejected.');
        } catch (AuraHandledException e) {
            Assert.isTrue(String.isNotBlank(e.getMessage()));
        }
    }

    @IsTest
    static void selectByWorkOrderId_nullReturnsEmpty() {
        Assert.isTrue(CIOEvaluationsSelector.selectByWorkOrderId(null).isEmpty());
    }

    private static void assignPermissionSetIfNeeded(String permissionSetName) {
        List<PermissionSet> permissionSets = (List<PermissionSet>) SoqlQueryBuilder.fromObject(
                'PermissionSet'
            )
            .selectField('Id')
            .whereEquals('Name', permissionSetName)
            .limitTo(1)
            .execute();
        if (permissionSets.isEmpty()) {
            return;
        }
        List<PermissionSetAssignment> existingAssignments = (List<PermissionSetAssignment>) SoqlQueryBuilder.fromObject(
                'PermissionSetAssignment'
            )
            .selectField('Id')
            .whereEquals('AssigneeId', UserInfo.getUserId())
            .whereEquals('PermissionSetId', permissionSets[0].Id)
            .limitTo(1)
            .execute();
        if (existingAssignments.isEmpty()) {
            new adb_PermissionSetAssignment()
                .assigneeId(UserInfo.getUserId())
                .permissionSetId(permissionSets[0].Id)
                .persist();
        }
    }

    private static WorkOrder selectWorkOrder() {
        List<WorkOrder> workOrders = (List<WorkOrder>) new WorkOrdersSelector()
            .selectFields(new List<String>{ 'Id', 'ParentWorkOrderId' })
            .whereEquals('Subject', SUBJECT)
            .limitTo(1)
            .execute();
        Assert.areEqual(1, workOrders.size(), 'Test Work Order should exist.');
        return workOrders[0];
    }
}