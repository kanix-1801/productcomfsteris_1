/**
 * @description Tests for WoDebriefRegionalExpenseController.
 * @see WoDebriefRegionalExpenseController
 */
@IsTest
private class WoDebriefRegionalExpenseControllerTest {
    @IsTest
    static void getAllowedExpenseTypes_nullId_returnsEmpty() {
        Test.startTest();
        List<String> result = WoDebriefRegionalExpenseController.resolveExpenseTypes(null, 'test');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Null Work Order Id should return no restriction');
    }

    @IsTest
    static void getAllowedExpenseTypes_noRegionalControl_returnsEmpty() {
        Account account = new Account(
            Name = 'GW3691 No RC Account',
            SourceSystemID__c = 'ORACLE-GW3691-NRC-' + String.valueOf(Crypto.getRandomInteger()),
            CustomerClassCode__c = 'HC'
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW3691 No Regional Control',
            Country = 'France'
        );
        insert workOrder;

        Test.startTest();
        List<String> result = WoDebriefRegionalExpenseController.resolveExpenseTypes(workOrder.Id, 'test');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'No Regional Control should return no restriction');
    }

    @IsTest
    static void getAllowedExpenseTypes_matchingControl_returnsAllowedValues() {
        Account account = new Account(
            Name = 'GW3691 RC Account',
            SourceSystemID__c = 'ORACLE-GW3691-RC-' + String.valueOf(Crypto.getRandomInteger()),
            CustomerClassCode__c = 'HC'
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW3691 Regional Control',
            Country = 'France'
        );
        insert workOrder;

        Regional_Control__c firstControl = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'France',
            Active__c = true
        );
        Regional_Control__c secondControl = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'France',
            Active__c = true
        );
        insert new List<Regional_Control__c>{ firstControl, secondControl };

        insert new Regional_Control_Setting__c(
            Regional_Control__c = firstControl.Id,
            SettingName__c = 'Expense Type',
            AllowedValues__c = 'Kilometers;Meals'
        );
        insert new Regional_Control_Setting__c(
            Regional_Control__c = secondControl.Id,
            SettingName__c = 'Expense Type',
            AllowedValues__c = 'Mileage;Tolls'
        );

        Test.startTest();
        List<String> result = WoDebriefRegionalExpenseController.resolveExpenseTypes(workOrder.Id, 'test');
        Test.stopTest();

        System.assertEquals(2, result.size(), 'First matching Regional Control should be used');
        System.assertEquals(true, result.contains('Kilometers'));
        System.assertEquals(true, result.contains('Meals'));
        System.assertEquals(false, result.contains('Mileage'), 'Second Regional Control must be ignored');
    }

    @IsTest
    static void getAllowedExpenseTypes_inactiveControl_isIgnored() {
        Account account = new Account(
            Name = 'GW3691 Inactive RC Account',
            SourceSystemID__c = 'ORACLE-GW3691-IRC-' + String.valueOf(Crypto.getRandomInteger()),
            CustomerClassCode__c = 'HC'
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW3691 Inactive Regional Control',
            Country = 'France'
        );
        insert workOrder;

        Regional_Control__c inactiveControl = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'France',
            Active__c = false
        );
        Regional_Control__c activeControl = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'France',
            Active__c = true
        );
        insert new List<Regional_Control__c>{ inactiveControl, activeControl };

        insert new Regional_Control_Setting__c(
            Regional_Control__c = inactiveControl.Id,
            SettingName__c = 'Expense Type',
            AllowedValues__c = 'Mileage;Tolls'
        );
        insert new Regional_Control_Setting__c(
            Regional_Control__c = activeControl.Id,
            SettingName__c = 'Expense Type',
            AllowedValues__c = 'Kilometers;Meals'
        );

        Test.startTest();
        List<String> result = WoDebriefRegionalExpenseController.resolveExpenseTypes(workOrder.Id, 'test');
        Test.stopTest();

        System.assertEquals(2, result.size(), 'Only the active Regional Control should be used');
        System.assertEquals(true, result.contains('Kilometers'));
        System.assertEquals(true, result.contains('Meals'));
        System.assertEquals(false, result.contains('Mileage'), 'Inactive Regional Control must be ignored');
    }

    @IsTest
    static void getAllowedExpenseTypes_blankCountry_returnsEmpty() {
        Account account = new Account(
            Name = 'GW3691 Blank Country Account',
            SourceSystemID__c = 'ORACLE-GW3691-BC-' + String.valueOf(Crypto.getRandomInteger()),
            CustomerClassCode__c = 'HC'
        );
        insert account;

        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW3691 Blank Country'
        );
        insert workOrder;

        insert new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'France'
        );

        Test.startTest();
        List<String> result = WoDebriefRegionalExpenseController.resolveExpenseTypes(workOrder.Id, 'test');
        Test.stopTest();

        System.assertEquals(0, result.size(), 'Blank Work Order Country should return no restriction');
    }

    @IsTest
    static void selector_blankOrEmptyInputs_returnEmpty() {
        Test.startTest();
        List<Regional_Control__c> noControl =
            RegionalControlSelector.selectByBusinessUnitAndCountry(null, 'France');
        List<Regional_Control_Setting__c> noSettings =
            RegionalControlSelector.selectExpenseTypeSettingsByControlIds(new Set<Id>());
        List<Pricing_Rule__c> noRules =
            RegionalControlSelector.selectPricingRulesByControlIds(new Set<Id>());
        Test.stopTest();

        System.assertEquals(0, noControl.size());
        System.assertEquals(0, noSettings.size());
        System.assertEquals(0, noRules.size());
    }

    @IsTest
    static void incrementalAmount_blankEndQty_stacksBandsAndCaps() {
        Regional_Control__c control = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'Canada'
        );
        insert control;
        insert new List<Pricing_Rule__c>{
            new Pricing_Rule__c(
                RegionalControl__c = control.Id,
                StartingQuantity__c = 1,
                EndingQuantity__c = 10,
                Rate__c = 0.67
            ),
            new Pricing_Rule__c(
                RegionalControl__c = control.Id,
                StartingQuantity__c = 11,
                Rate__c = 0.50
            )
        };
        List<Pricing_Rule__c> rules = RegionalControlSelector.selectPricingRulesByControlIds(
            new Set<Id>{ control.Id }
        );

        Test.startTest();
        Decimal uncapped = RegionalExpensePricingCalculator.calculateIncrementalAmount(15, rules, null);
        Decimal capped = RegionalExpensePricingCalculator.calculateIncrementalAmount(15, rules, 8);
        Decimal noRules = RegionalExpensePricingCalculator.calculateIncrementalAmount(
            15,
            new List<Pricing_Rule__c>(),
            null
        );
        Test.stopTest();

        System.assertEquals(9.20, uncapped, '10 x 0.67 + 5 x 0.50');
        System.assertEquals(8, capped, 'Maximum Price caps the amount without blocking');
        System.assertEquals(null, noRules, 'No rules means the LWC keeps manual unit price');
    }

    @IsTest
    static void resolveExpenseDebrief_returnsPricingBands() {
        Account account = new Account(
            Name = 'GW3691 Pricing Account',
            SourceSystemID__c = 'ORACLE-GW3691-PR-' + String.valueOf(Crypto.getRandomInteger()),
            CustomerClassCode__c = 'HC'
        );
        insert account;
        WorkOrder workOrder = new WorkOrder(
            AccountId = account.Id,
            Subject = 'GW3691 Pricing',
            Country = 'Canada'
        );
        insert workOrder;
        Regional_Control__c control = new Regional_Control__c(
            BusinessUnit__c = 'HC',
            Country__c = 'Canada',
            MaximumPrice__c = 25,
            Active__c = true
        );
        insert control;
        insert new Regional_Control_Setting__c(
            Regional_Control__c = control.Id,
            SettingName__c = 'Expense Type',
            AllowedValues__c = 'Mileage;Meals'
        );
        insert new Pricing_Rule__c(
            RegionalControl__c = control.Id,
            StartingQuantity__c = 1,
            Rate__c = 0.40
        );

        Test.startTest();
        WoDebriefRegionalExpenseController.ExpenseDebriefConfig config =
            WoDebriefRegionalExpenseController.resolveExpenseDebrief(workOrder.Id, 'test');
        Test.stopTest();

        System.assertEquals(2, config.allowedTypes.size());
        System.assertEquals(25, config.maximumPrice);
        System.assertEquals(1, config.pricingRules.size());
        System.assertEquals(1, config.pricingRules[0].startingQty);
        System.assertEquals(null, config.pricingRules[0].endingQty);
        System.assertEquals(0.40, config.pricingRules[0].rate);
    }

    @IsTest
    static void saveExpense_createsBillableFields() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW-528 Expense Save');
        insert workOrder;

        Map<String, Object> fields = new Map<String, Object>{
            'ExpenseType' => 'Airfare',
            'TransactionDate' => String.valueOf(Date.today()),
            'Amount' => 23,
            'WorkOrderId' => workOrder.Id,
            'OverrideCode__c' => 'N/C Warranty',
            'BillableAmount__c' => 0,
            'OverrideBillableAmount__c' => true
        };

        Test.startTest();
        Id expenseId = WoDebriefRegionalExpenseController.saveExpense(fields);
        Test.stopTest();

        Expense saved = [
            SELECT ExpenseType, Amount, BillableAmount__c, OverrideBillableAmount__c, OverrideCode__c
            FROM Expense
            WHERE Id = :expenseId
        ];
        System.assertEquals('Airfare', saved.ExpenseType);
        System.assertEquals(23, saved.Amount);
        System.assertEquals(0, saved.BillableAmount__c);
        System.assertEquals(true, saved.OverrideBillableAmount__c);
        System.assertEquals('N/C Warranty', saved.OverrideCode__c);
    }

    @IsTest
    static void saveExpense_updatesBillableFields() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW-528 Expense Update');
        insert workOrder;
        Expense existing = new Expense(
            WorkOrderId = workOrder.Id,
            ExpenseType = 'Meals',
            TransactionDate = Date.today(),
            Amount = 10,
            BillableAmount__c = 10,
            OverrideBillableAmount__c = false
        );
        insert existing;

        Test.startTest();
        Id expenseId = WoDebriefRegionalExpenseController.saveExpense(
            new Map<String, Object>{
                'Id' => existing.Id,
                'ExpenseType' => 'Meals',
                'Amount' => 12,
                'BillableAmount__c' => 8,
                'OverrideBillableAmount__c' => true,
                'OverrideCode__c' => 'N/C Sales Concession'
            }
        );
        Test.stopTest();

        Expense saved = [
            SELECT Amount, BillableAmount__c, OverrideBillableAmount__c, OverrideCode__c
            FROM Expense
            WHERE Id = :expenseId
        ];
        System.assertEquals(12, saved.Amount);
        System.assertEquals(8, saved.BillableAmount__c);
        System.assertEquals(true, saved.OverrideBillableAmount__c);
        System.assertEquals('N/C Sales Concession', saved.OverrideCode__c);
    }

    @IsTest
    static void listExpenseBillableFields_returnsSavedValues() {
        WorkOrder workOrder = new WorkOrder(Subject = 'GW-528 Expense List');
        insert workOrder;
        insert new Expense(
            WorkOrderId = workOrder.Id,
            ExpenseType = 'Mileage',
            TransactionDate = Date.today(),
            Amount = 151.7,
            BillableAmount__c = 100,
            OverrideBillableAmount__c = true,
            OverrideCode__c = 'Billable - Other'
        );

        Test.startTest();
        List<WoDebriefRegionalExpenseController.ExpenseBillableFields> rows =
            WoDebriefRegionalExpenseController.listExpenseBillableFields(workOrder.Id);
        Test.stopTest();

        System.assertEquals(1, rows.size());
        System.assertEquals(100, rows[0].billableAmount);
        System.assertEquals(true, rows[0].overrideBillableAmount);
        System.assertEquals('Billable - Other', rows[0].overrideCode);
    }
}