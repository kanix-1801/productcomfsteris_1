/**
 * @author Sagar Anand
 * @date 2026-11-24
 * @description GW-6407: Tests for WorkOrderClosureController and WorkOrderClosureService.
 * @group Field Service
 * @see WorkOrderClosureController
 * @see WorkOrderClosureService
 */
@IsTest
private class WorkOrderClosureControllerTest {
	private static final String OWNER_LAST_NAME = 'GW6407 Owner';
	private static final String OTHER_LAST_NAME = 'GW6407 Other';

	@TestSetup
	static void setup() {
		Id profileId = [SELECT Id FROM Profile WHERE Name = 'ES Service Technician' LIMIT 1].Id;
		// Permission sets every ES technician has: BaseUser (Work Order read, Apex access) and FSL_Resource_Permissions (Expense edit).
		List<PermissionSet> permissionSets = [
			SELECT Id
			FROM PermissionSet
			WHERE Name IN ('BaseUser', 'FSL_Resource_Permissions')
		];
		User owner = buildUser(profileId, OWNER_LAST_NAME);
		User other = buildUser(profileId, OTHER_LAST_NAME);
		// Setup objects run in their own context to avoid mixed DML with the Work Order below.
		System.runAs(new User(Id = UserInfo.getUserId())) {
			Database.insert(new List<User>{ owner, other }, AccessLevel.SYSTEM_MODE);
			List<PermissionSetAssignment> assignments = new List<PermissionSetAssignment>();
			for (PermissionSet permissionSet : permissionSets) {
				assignments.add(new PermissionSetAssignment(AssigneeId = owner.Id, PermissionSetId = permissionSet.Id));
				assignments.add(new PermissionSetAssignment(AssigneeId = other.Id, PermissionSetId = permissionSet.Id));
			}
			Database.insert(assignments, AccessLevel.SYSTEM_MODE);
		}

		Account account = new Account(
			Name = 'GW6407 Closure Account',
			SourceSystemID__c = 'ORACLE-GW6407-' + String.valueOf(Crypto.getRandomInteger()),
			CustomerClassCode__c = 'HC'
		);
		Database.insert(account, AccessLevel.SYSTEM_MODE);
		WorkOrder workOrder = new WorkOrder(AccountId = account.Id, Subject = 'GW6407 Closure', OwnerId = owner.Id);
		Database.insert(workOrder, AccessLevel.SYSTEM_MODE);
		Database.insert(
			new Expense(
				WorkOrderId = workOrder.Id,
				OwnerId = other.Id,
				ExpenseType = 'Meals',
				Amount = 25,
				TransactionDate = Date.today()
			),
			AccessLevel.SYSTEM_MODE
		);
	}

	@IsTest
	static void ownerGetsExpensesOfOtherTechnicians() {
		User owner = [SELECT Id FROM User WHERE LastName = :OWNER_LAST_NAME LIMIT 1];
		Id workOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'GW6407 Closure' LIMIT 1].Id;

		List<Expense> expenses;
		Test.startTest();
		System.runAs(owner) {
			expenses = WorkOrderClosureController.getWorkOrderExpenses(workOrderId);
		}
		Test.stopTest();

		Assert.areEqual(1, expenses.size(), 'The owner should get the Expense entered by the other technician');
		Assert.areEqual('Meals', expenses[0].ExpenseType, 'Expense fields should be returned');
	}

	@IsTest
	static void ownerSavesExpenseOfOtherTechnician() {
		User owner = [SELECT Id FROM User WHERE LastName = :OWNER_LAST_NAME LIMIT 1];
		Id expenseId = [SELECT Id FROM Expense WHERE WorkOrder.Subject = 'GW6407 Closure' LIMIT 1].Id;

		Id workOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'GW6407 Closure' LIMIT 1].Id;

		Test.startTest();
		System.runAs(owner) {
			WorkOrderClosureController.saveWorkOrderExpense(workOrderId, new Expense(Id = expenseId, Quantity = 2));
		}
		Test.stopTest();

		Expense saved = [SELECT Quantity, OwnerId FROM Expense WHERE Id = :expenseId];
		Assert.areEqual(2, saved.Quantity, 'The owner should be able to edit the Expense of another technician');
		Assert.areNotEqual(owner.Id, saved.OwnerId, 'The Expense still belongs to the other technician');
	}

	@IsTest
	static void expenseNotOnWorkOrderIsRejected() {
		User owner = [SELECT Id FROM User WHERE LastName = :OWNER_LAST_NAME LIMIT 1];
		Id workOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'GW6407 Closure' LIMIT 1].Id;

		String message;
		Test.startTest();
		System.runAs(owner) {
			try {
				WorkOrderClosureController.saveWorkOrderExpense(workOrderId, new Expense(Quantity = 2));
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
		}
		Test.stopTest();

		Assert.areEqual(WorkOrderClosureService.NOT_ON_WORK_ORDER_MESSAGE, message, 'Only Expenses of the Work Order can be saved');
	}

	@IsTest
	static void nonOwnerIsBlocked() {
		User other = [SELECT Id FROM User WHERE LastName = :OTHER_LAST_NAME LIMIT 1];
		Id workOrderId = [SELECT Id FROM WorkOrder WHERE Subject = 'GW6407 Closure' LIMIT 1].Id;

		String message;
		Test.startTest();
		System.runAs(other) {
			try {
				WorkOrderClosureController.getWorkOrderExpenses(workOrderId);
			} catch (AuraHandledException e) {
				message = e.getMessage();
			}
		}
		Test.stopTest();

		Assert.areEqual(WorkOrderClosureService.NOT_OWNER_MESSAGE, message, 'Only the owner may load the Expenses');
	}

	private static User buildUser(Id profileId, String lastName) {
		String uniqueKey = String.valueOf(Crypto.getRandomInteger()).remove('-');
		return new User(
			ProfileId = profileId,
			LastName = lastName,
			Alias = 'gw' + uniqueKey.left(6),
			Email = 'gw6407' + uniqueKey + '@example.com',
			Username = 'gw6407' + uniqueKey + '@example.com.test',
			EmailEncodingKey = 'UTF-8',
			LanguageLocaleKey = 'en_US',
			LocaleSidKey = 'en_US',
			TimeZoneSidKey = 'America/New_York'
		);
	}
}