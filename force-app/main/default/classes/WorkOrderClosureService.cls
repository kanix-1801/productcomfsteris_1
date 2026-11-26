/**
 * @author Sagar Anand
 * @date 2026-11-24
 * @description GW-6407: Work Order closure (woClosureES). Only the Work Order owner (lead technician) can close a
 *              Work Order, and the closure screen shows and edits the lines of every technician on it. Expense is
 *              private (each technician owns the Expenses they entered), so this class runs without sharing and
 *              reads or saves those Expenses only after confirming that the running user owns the Work Order.
 *              User-facing problems are thrown as AuraHandledException; unexpected errors are logged here.
 * @group Field Service
 * @see WorkOrderClosureController
 */
public without sharing class WorkOrderClosureService {
	public static final String NOT_OWNER_MESSAGE = 'Only the Work Order Owner/Lead Technician is allowed to close the work order';
	public static final String NOT_ON_WORK_ORDER_MESSAGE = 'This Expense does not belong to the Work Order.';
	private static final String LOG_SCENARIO = 'Work Order Closure';
	private static final List<String> LOG_TAGS = new List<String>{ 'Work Order', 'Expense' };

	/**
	 * @description Returns the Expenses of all technicians on a Work Order for its owner.
	 * @param workOrderId Work Order Id
	 * @return Expenses ordered by Transaction Date
	 * @throws AuraHandledException When the running user is not the Work Order owner
	 */
	public static List<Expense> getWorkOrderExpenses(Id workOrderId) {
		try {
			assertOwner(workOrderId);
			// Static query: the query builder always applies sharing, and these Expenses belong to other technicians.
			return [
				SELECT
					Id,
					ExpenseType,
					Description,
					Quantity,
					UnitPrice,
					TotalPrice,
					Amount,
					TransactionDate,
					OverrideCode__c,
					BillableAmount__c,
					OverrideBillableAmount__c
				FROM Expense
				WHERE WorkOrderId = :workOrderId
				WITH SYSTEM_MODE
				ORDER BY TransactionDate, CreatedDate
			];
		} catch (Exception e) {
			logUnexpectedError(e, 'Work Order closure expenses could not be loaded for ' + workOrderId);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Saves an edited Expense of any technician on the Work Order, for the Work Order owner.
	 *              Runs in system mode because the Expense can belong to another technician.
	 * @param workOrderId Work Order Id
	 * @param expense Expense with its Id and the edited fields
	 * @throws AuraHandledException When the user is not the owner or the Expense is not on the Work Order
	 */
	public static void saveWorkOrderExpense(Id workOrderId, Expense expense) {
		try {
			assertOwner(workOrderId);
			List<Expense> existing = [SELECT WorkOrderId FROM Expense WHERE Id = :expense?.Id WITH SYSTEM_MODE];
			if (existing.isEmpty() || existing[0].WorkOrderId != workOrderId) {
				throw PlatformUtilities.buildAuraException(NOT_ON_WORK_ORDER_MESSAGE);
			}
			Database.update(expense, AccessLevel.SYSTEM_MODE);
		} catch (Exception e) {
			logUnexpectedError(e, 'Work Order closure expense could not be saved for ' + workOrderId);
			throw e;
		} finally {
			Logger.saveLog();
		}
	}

	/**
	 * @description Throws when the running user does not own the Work Order. Runs in user mode, so a Work Order
	 *              the user cannot see is treated like one they do not own.
	 */
	private static void assertOwner(Id workOrderId) {
		WorkOrder workOrder = (WorkOrder) new WorkOrdersSelector()
			.selectField('OwnerId')
			.whereEquals('Id', workOrderId)
			.first();
		if (workOrder?.OwnerId != UserInfo.getUserId()) {
			throw PlatformUtilities.buildAuraException(NOT_OWNER_MESSAGE);
		}
	}

	/**
	 * @description Logs errors that are not user-facing messages.
	 */
	private static void logUnexpectedError(Exception e, String message) {
		if (!(e instanceof AuraHandledException)) {
			Logger.setScenario(LOG_SCENARIO);
			Logger.error(message, e).addTags(LOG_TAGS);
		}
	}
}