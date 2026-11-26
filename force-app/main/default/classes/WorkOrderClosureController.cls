/**
 * @author Sagar Anand
 * @date 2026-11-24
 * @description GW-6407: Aura entry point for the woClosureES LWC (Close Work Order action, ES).
 *              Relays requests to WorkOrderClosureService, which logs errors; here they are turned into
 *              user messages.
 * @group Field Service
 * @see WorkOrderClosureService
 */
public with sharing class WorkOrderClosureController {
	/**
	 * @description Returns the Expenses of all technicians on the Work Order, for the Work Order owner only.
	 * @param workOrderId Work Order Id
	 * @return Expenses of the Work Order
	 * @throws AuraHandledException When the running user is not the Work Order owner or the load fails.
	 */
	@AuraEnabled
	public static List<Expense> getWorkOrderExpenses(Id workOrderId) {
		try {
			return WorkOrderClosureService.getWorkOrderExpenses(workOrderId);
		} catch (Exception e) {
			throw PlatformUtilities.buildAuraException(PlatformUtilities.resolveExceptionMessage(e));
		}
	}

	/**
	 * @description Saves an edited Expense of any technician on the Work Order, for the Work Order owner only.
	 * @param workOrderId Work Order Id
	 * @param expense Expense with its Id and the edited fields
	 * @throws AuraHandledException When the running user is not the Work Order owner or the save fails.
	 */
	@AuraEnabled
	public static void saveWorkOrderExpense(Id workOrderId, Expense expense) {
		try {
			WorkOrderClosureService.saveWorkOrderExpense(workOrderId, expense);
		} catch (Exception e) {
			throw PlatformUtilities.buildAuraException(PlatformUtilities.resolveExceptionMessage(e));
		}
	}
}