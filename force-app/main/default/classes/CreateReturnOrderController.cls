/**
 * @description Thin Aura controller for the Create Return Order LWC wizard (GW-1509).
 */
public with sharing class CreateReturnOrderController {

	private static AuraHandledException asAura(Exception e) {
		return PlatformUtilities.buildAuraException(
			PlatformUtilities.resolveExceptionMessage(e)
		);
	}

	@AuraEnabled
	public static CreateReturnOrderService.AssetReturnOrderCheckResult checkOpenReturnOrdersForAsset(
		Id assetId
	) {
		try {
			return CreateReturnOrderService.checkOpenReturnOrdersForAsset(assetId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.InitContext getInitialContext(
		String recordId,
		String objectApiName,
		List<String> recordIds
	) {
		try {
			return CreateReturnOrderService.getInitialContext(recordId, objectApiName, recordIds);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static Account getAccountDetails(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.getAccountDetails(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.ShipToAddressOption> getShipToAddressesForAccount(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.getShipToAddressesForAccount(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static Product2 getDefaultProduct() {
		try {
			return CreateReturnOrderService.getDefaultProduct();
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static Product2 getProductDetails(
		Id productId,
		Boolean requireServiceAssetType
	) {
		try {
			return CreateReturnOrderService.getProductDetails(productId, requireServiceAssetType);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	public static List<CreateReturnOrderService.ProductPicklistOption> getProductsForReturnOrderLine(
		String productLine,
		Boolean requireServiceAssetType,
		String searchTerm
	) {
		return getProductsForReturnOrderLine(productLine, requireServiceAssetType, searchTerm, null);
	}

	@AuraEnabled(cacheable=true)
	public static List<CreateReturnOrderService.ProductPicklistOption> getProductsForReturnOrderLine(
		String productLine,
		Boolean requireServiceAssetType,
		String searchTerm,
		String deviceType
	) {
		try {
			return CreateReturnOrderService.getProductsForReturnOrderLine(
				productLine,
				requireServiceAssetType,
				searchTerm,
				deviceType
			);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<Contact> getContactsForAccount(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.getContactsForAccount(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.CreateContactResult createAccountContact(
		Id accountId,
		String firstName,
		String lastName,
		String email,
		String phone,
		String title,
		Boolean requireEmail
	) {
		try {
			return CreateReturnOrderService.createAccountContact(
				accountId,
				firstName,
				lastName,
				email,
				phone,
				title,
				requireEmail
			);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static void updateContactEmail(
		Id contactId,
		String email
	) {
		try {
			CreateReturnOrderService.updateContactEmail(contactId, email);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<Case> getOpenCasesForAccount(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.getOpenCasesForAccount(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<CreateReturnOrderService.LocationOption> getRepairCenterLocations() {
		try {
			return CreateReturnOrderService.getRepairCenterLocations();
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<User> getActiveInternalUsers() {
		try {
			return CreateReturnOrderService.getActiveInternalUsers();
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<CreateReturnOrderService.AssetLineData> getAssetsForAccount(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.getAssetsForAccount(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<CreateReturnOrderService.PicklistOption> getDepartmentsForAccount(
		Id accountId,
		List<String> additionalDepartmentIds
	) {
		try {
			return CreateReturnOrderService.getDepartmentsForAccount(accountId, additionalDepartmentIds);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.AssetLineData> getAssetsByIds(
		List<String> assetIds
	) {
		try {
			return CreateReturnOrderService.getAssetsByIds(assetIds);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.ScanSerialAssetResult> findAssetsBySerial(
		String serialNumber
	) {
		try {
			return CreateReturnOrderService.findAssetsBySerial(serialNumber);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.ScanSerialAssetResult> searchAssetsBySerial(
		String serialNumber,
		Id accountId
	) {
		try {
			return CreateReturnOrderService.searchAssetsBySerial(serialNumber, accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled(cacheable=true)
	public static List<CreateReturnOrderService.ProductPicklistOption> searchProductsByModel(
		String modelSearchTerm,
		Boolean requireServiceAssetType,
		String productLine
	) {
		try {
			return CreateReturnOrderService.searchProductsByModel(
				modelSearchTerm,
				requireServiceAssetType,
				productLine
			);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.AccountReadinessResult validateAccountForReturnOrder(
		Id accountId
	) {
		try {
			return CreateReturnOrderService.validateAccountForReturnOrder(accountId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.LineRoutingValidation validateLineRoutingMatches(
		String headerJson,
		String lineItemsJson
	) {
		try {
			return CreateReturnOrderService.validateLineRoutingMatches(headerJson, lineItemsJson);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.ProposedReturnOrderGroup> buildReturnOrderPlan(
		String headerJson,
		String lineItemsJson
	) {
		try {
			return CreateReturnOrderService.buildReturnOrderPlan(headerJson, lineItemsJson);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.CreateOrdersResult createReturnOrders(
		String headerJson,
		String groupsJson
	) {
		try {
			return CreateReturnOrderService.createReturnOrders(headerJson, groupsJson);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static CreateReturnOrderService.CreateResult createReturnOrder(
		String headerJson,
		String lineItemsJson
	) {
		try {
			return CreateReturnOrderService.createReturnOrder(headerJson, lineItemsJson);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

	@AuraEnabled
	public static List<CreateReturnOrderService.SiteVisitInstrumentLine> getSiteVisitRepairCenterLines(
		Id workOrderId
	) {
		try {
			return CreateReturnOrderService.getSiteVisitRepairCenterLines(workOrderId);
		} catch (Exception e) {
			throw asAura(e);
		}
	}

}