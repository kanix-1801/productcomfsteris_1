/**
 * @description GW-5492 / GW-4162 / GW-4542 - Finish Receiving persistence for the new Receiving LWC.
 *              Ported from legacy receive behavior (read-only reference); invoked only by ReceivingService.
 *              Queries Selectors directly. Finish DML uses AccessLevel.USER_MODE (CRUD/FLS),
 *              except Return Order Case mapping onto Work Orders (elevated for queue-owned Cases).
 *              GW-4162 maps Internal Repair Account, Bill-To, and Ship-To on Finish Receiving.
 *              GW-4542 branches Repair Exchange match (Invoice + Internal WO) vs mismatch
 *              (Serialized + Customer Care).
 */
public with sharing class ReceivingFinishService {
	private static final String RO_TYPE_SERIALIZED = 'Serialized';
	private static final String RO_TYPE_INSTRUMENTS = 'Instruments';
	private static final String RO_TYPE_OTHER_SERIALIZED = 'Other (Serialized)';
	private static final String RO_TYPE_OTHER_NON_SERIALIZED = 'Other (Non-Serialized)';
	private static final String RO_TYPE_REPAIR_EXCHANGE = 'Repair Exchange';

	private static final String STATUS_CREATED = 'Created';
	private static final String STATUS_RECEIVED = 'Received';
	private static final String STATUS_REDIRECTED = 'Redirected';
	private static final String LINE_TYPE_OUTBOUND = 'Outbound';
	private static final String REASON_REPAIR_EXCHANGE_MODEL_MISMATCH =
		'Repair Exchange Model Mismatch';

	private static final String WO_STATUS_RECEIVED = 'Received';
	private static final String WO_STATUS_EVALUATE = 'Evaluate';
	private static final String WO_SUB_STATUS_CUSTOMER_CARE = 'Customer Care';
	private static final String WO_SUB_STATUS_SHIP_TO_VENDOR = 'Ship to Vendor';
	private static final String WO_SUB_STATUS_READY_FOR_EVAL = 'Ready for Eval';
	private static final String WO_SUB_STATUS_CONTAMINATED = 'Contaminated';
	private static final String WO_SUB_STATUS_TRIAGE = 'Triage';

	private static final String RT_DEVICES = 'RepairCenterDevices';
	private static final String RT_INSTRUMENTS = 'RepairCenterInstruments';
	private static final String RT_VENDOR = 'RepairCenterVendor';
	private static final String RT_CUSTOMER_RETURN = 'CustomerReturn';
	private static final String WOLI_RT_PRODUCT_SERVICED = 'ProductServiced';
	private static final String WOLI_LINE_TYPE_PRODUCT_SERVICED = 'Product Serviced';
	private static final String WOLI_LINE_TYPE_ACCESSORY = 'Accessory';
	private static final String PRODUCT_LINE_RIGID_SCOPE = 'RIGID SCOPE';
	private static final String DEVICE_TYPE_STIRRUP = 'STIRRUP';
	private static final String MACHINE_SHOP = 'Machine Shop';
	private static final String UI_CONTAMINATED = 'Contaminated';
	private static final String CIO_CATEGORY = 'Continuous Improvement Opportunity (CIO)';
	private static final Integer ADDITIONAL_SERVICES_MAX_LENGTH = 32000;

	private static Id cachedDefaultPricebookId;
	private static Map<Id, Account> billingAddressByAccountId = new Map<Id, Account>();
	private static Map<Id, Account> primaryBillToByAccountId = new Map<Id, Account>();
	private static Map<Id, Account> primaryShipToByAccountId = new Map<Id, Account>();

	/**
	 * @description Clears cached Repair Center default price book and account lookups (tests only).
	 */
	@TestVisible
	private static void resetDefaultPricebookCacheForTest() {
		cachedDefaultPricebookId = null;
		billingAddressByAccountId.clear();
		primaryBillToByAccountId.clear();
		primaryShipToByAccountId.clear();
	}

	/**
	 * @description Completes Finish Receiving for one item (redirect or WO create).
	 * @param request Finish payload from the Receiving LWC
	 * @return Result with WO / redirect Ids for navigation and badges
	 */
	public static ReceivingService.FinishReceivingResult finishItem(
		ReceivingService.FinishReceivingRequest request
	) {
		if (request == null || request.returnOrderId == null) {
			throw new ReceivingService.ReceivingServiceException('Return Order is required.');
		}
		if (request.isRedirected == true) {
			return processRedirect(request);
		}
		if (request.lineItemId == null && request.isAdHoc != true) {
			throw new ReceivingService.ReceivingServiceException(
				'Return Order Line Item is required.'
			);
		}
		return processReceive(request);
	}

	private static ReceivingService.FinishReceivingResult processRedirect(
		ReceivingService.FinishReceivingRequest request
	) {
		if (request.redirectLocationId == null) {
			throw new ReceivingService.ReceivingServiceException(
				'Redirect Repair Center is required.'
			);
		}
		if (request.lineItemId == null) {
			throw new ReceivingService.ReceivingServiceException(
				'Return Order Line Item is required for Redirect.'
			);
		}

		Set<Id> redirectLineIds = resolveRedirectLineIds(request);
		if (redirectLineIds.isEmpty()) {
			ReceivingService.FinishReceivingResult alreadyDone =
				new ReceivingService.FinishReceivingResult();
			alreadyDone.isRedirected = true;
			alreadyDone.returnOrderFullyReceived = true;
			return alreadyDone;
		}
		ReturnOrdersService.ReceivingRedirectResult redirectResult =
			ReturnOrdersService.redirectLinesForReceiving(
				request.returnOrderId,
				redirectLineIds,
				request.redirectLocationId,
				request.redirectionNotes
			);

		ReceivingService.FinishReceivingResult result = new ReceivingService.FinishReceivingResult();
		result.isRedirected = true;
		result.redirectReturnOrderId = redirectResult.returnOrderId;
		result.redirectReturnOrderNumber = redirectResult.returnOrderNumber;
		result.returnOrderFullyReceived = redirectResult.sourceReturnOrderFullyRedirected;
		return result;
	}

	/**
	 * @description GW-5492 - Add Item to Receive persists a return line with the work order.
	 *              The line stays on the receiving screen after Finish Receiving reloads.
	 * @param returnOrder Return Order being received
	 * @param request Finish payload for the added item
	 */
	private static void ensureAdHocReturnOrderLine(
		ReturnOrder returnOrder,
		ReceivingService.FinishReceivingRequest request
	) {
		if (request == null || request.isAdHoc != true || request.lineItemId != null) {
			return;
		}
		if (request.product2Id == null) {
			throw new ReceivingService.ReceivingServiceException(
				'Product is required to add an item.'
			);
		}

		Product2 product = queryAdHocProduct(request.product2Id);
		Decimal quantity = request.quantityReceived != null && request.quantityReceived > 0
			? request.quantityReceived
			: 1;
		ReturnOrderLineItem lineItem = new ReturnOrderLineItem();
		lineItem.ReturnOrderId = returnOrder.Id;
		lineItem.RecordTypeId = inboundReturnLineRecordTypeId();
		lineItem.Product2Id = request.product2Id;
		lineItem.AssetId = request.assetId;
		lineItem.QuantityReturned = quantity;
		lineItem.QuantityExpected = quantity;
		lineItem.Status__c = STATUS_CREATED;
		lineItem.LineType__c = resolveAdHocLineType(returnOrder.ReturnOrderType__c);
		lineItem.SerialNumber__c = request.serialNumber;
		lineItem.Model__c = String.isNotBlank(request.model)
			? request.model
			: (product == null ? null : product.Model__c);
		lineItem.ProductLine__c = product == null ? null : product.ProductLine__c;
		lineItem.DestinationLocationId = returnOrder.DestinationLocationId;
		lineItem.Contact__c = returnOrder.ContactId;
		lineItem.CustomerPO__c = returnOrder.CustomerPO__c;
		lineItem.CustomerReference__c = returnOrder.CustomerReference__c;
		if (String.isNotBlank(request.disinfected)) {
			lineItem.Disinfected__c = mapDisinfected(request.disinfected);
		}
		ReturnOrderLineItemsService.createReturnOrderLineItems(
			new List<ReturnOrderLineItem>{ lineItem }
		);
		request.lineItemId = lineItem.Id;
	}

	private static Product2 queryAdHocProduct(Id product2Id) {
		List<Product2> products = (List<Product2>) new ProductsSelector()
			.selectFields(new List<String>{ 'Id', 'Model__c', 'ProductLine__c' })
			.whereEquals('Id', product2Id)
			.limitTo(1)
			.execute();
		return products.isEmpty() ? null : products[0];
	}

	private static Id inboundReturnLineRecordTypeId() {
		Schema.RecordTypeInfo inboundInfo = Schema.SObjectType.ReturnOrderLineItem
			.getRecordTypeInfosByDeveloperName()
			.get('Inbound');
		return inboundInfo == null ? null : inboundInfo.getRecordTypeId();
	}

	/**
	 * @description Line Type follows the return order type. Instruments use the singular value.
	 * @param returnOrderType ReturnOrder.ReturnOrderType__c
	 * @return Restricted Line Type value, or null when the return type has no line type
	 */
	private static String resolveAdHocLineType(String returnOrderType) {
		if (returnOrderType == RO_TYPE_INSTRUMENTS) {
			return 'Instrument';
		}
		if (
			returnOrderType == RO_TYPE_SERIALIZED
			|| returnOrderType == RO_TYPE_OTHER_SERIALIZED
			|| returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED
		) {
			return returnOrderType;
		}
		return null;
	}

	/**
	 * @description Instruments are one receiving item, so Redirect includes every Created line.
	 *              Other return order types redirect only the selected line.
	 */
	private static Set<Id> resolveRedirectLineIds(ReceivingService.FinishReceivingRequest request) {
		List<ReturnOrder> returnOrders = ReturnOrdersSelector.selectForReceivingFinish(
			request.returnOrderId
		);
		if (
			returnOrders.isEmpty()
			|| returnOrders[0].ReturnOrderType__c != RO_TYPE_INSTRUMENTS
		) {
			return new Set<Id>{ request.lineItemId };
		}
		Set<Id> createdLineIds = new Set<Id>();
		for (
			ReturnOrderLineItem lineItem :
				ReturnOrderLineItemsService.getLinesForReceivingFinishByReturnOrderId(
					request.returnOrderId
				)
		) {
			if (lineItem.Status__c == STATUS_CREATED) {
				createdLineIds.add(lineItem.Id);
			}
		}
		return createdLineIds;
	}

	private static ReceivingService.FinishReceivingResult processReceive(
		ReceivingService.FinishReceivingRequest request
	) {
		Id receiverId = request.receiverId != null ? request.receiverId : UserInfo.getUserId();
		Datetime receivedDateTime = request.receivedDateTime != null
			? request.receivedDateTime
			: System.now();

		List<ReturnOrder> returnOrders = ReturnOrdersSelector.selectForReceivingFinish(
			request.returnOrderId
		);
		if (returnOrders.isEmpty()) {
			throw new ReceivingService.ReceivingServiceException('Return Order was not found.');
		}
		ReturnOrder returnOrder = returnOrders[0];
		ensureAdHocReturnOrderLine(returnOrder, request);

		String returnOrderType = returnOrder.ReturnOrderType__c;
		ReturnOrderLineItem lineItem = null;
		if (request.lineItemId != null) {
			List<ReturnOrderLineItem> lines =
				ReturnOrderLineItemsService.getLinesForReceivingFinish(
					new Set<Id>{ request.lineItemId }
				);
			if (lines.isEmpty()) {
				throw new ReceivingService.ReceivingServiceException(
					'Return Order Line Item was not found.'
				);
			}
			lineItem = lines[0];
			if (lineItem.ReturnOrderId != returnOrder.Id) {
				throw new ReceivingService.ReceivingServiceException(
					'Line item does not belong to the Return Order.'
				);
			}
			if (lineItem.Status__c == STATUS_RECEIVED || lineItem.Status__c == STATUS_REDIRECTED) {
				throw new ReceivingService.ReceivingServiceException(
					'This line item has already been finished.'
				);
			}
			applyLineCorrections(lineItem, request);
			lineItem = ReturnOrderLineItemsService.getLinesForReceivingFinish(
				new Set<Id>{ request.lineItemId }
			)[0];
		}

		Boolean isRepairExchange = returnOrderType == RO_TYPE_REPAIR_EXCHANGE;
		Boolean isRepairExchangeMismatch = isRepairExchange
			&& isRepairExchangeModelMismatch(request, returnOrder.Id, lineItem);
		ReceivingService.FinishReceivingRequest finishRequest = request;
		if (isRepairExchange) {
			finishRequest = prepareRepairExchangeFinishRequest(
				request,
				isRepairExchangeMismatch
			);
		}

		String childSubStatus = resolveChildSubStatus(finishRequest, returnOrderType);
		Boolean isContaminated = UI_CONTAMINATED.equalsIgnoreCase(finishRequest.disinfected);

		WorkOrdersService.ReceivingWorkOrderCreateResult woResult;
		if (returnOrderType == RO_TYPE_SERIALIZED || isRepairExchange) {
			// GW-4542 - Repair Exchange creates Device parent/child WOs like Serialized.
			woResult = createSerializedReceive(
				returnOrder,
				lineItem,
				finishRequest,
				receiverId,
				childSubStatus,
				isContaminated
			);
			if (isRepairExchange && !isRepairExchangeMismatch) {
				ensureInternalRepairFlagOnCreatedWorkOrders(woResult, finishRequest);
			}
		} else if (returnOrderType == RO_TYPE_INSTRUMENTS) {
			woResult = createInstrumentsReceive(
				returnOrder,
				lineItem,
				finishRequest,
				receiverId,
				childSubStatus,
				isContaminated
			);
		} else {
			woResult = createOtherReceive(
				returnOrder,
				lineItem,
				finishRequest,
				receiverId,
				childSubStatus,
				isContaminated,
				returnOrderType
			);
		}

		if (returnOrderType == RO_TYPE_INSTRUMENTS) {
			// Instruments are one receiving item for every line. Mark them all received
			// so the Return Order completes and the screen can return to the record.
			markInstrumentLinesReceived(returnOrder.Id, receiverId, receivedDateTime);
			ReturnOrdersService.setQuantityReceivedForReceiving(
				returnOrder.Id,
				finishRequest.quantityReceived
			);
		} else if (isRepairExchange) {
			// GW-4542 - Only Inbound is received. Outbound RT Status__c does not allow Received.
			markRepairExchangeInboundReceived(
				finishRequest.lineItemId,
				receiverId,
				receivedDateTime,
				finishRequest.quantityReceived
			);
		} else if (finishRequest.lineItemId != null) {
			ReturnOrderLineItemsService.markLinesReceivedForReceiving(
				new Set<Id>{ finishRequest.lineItemId },
				receiverId,
				receivedDateTime,
				finishRequest.quantityReceived
			);
		}

		ReturnOrdersService.syncReceivingWorkOrderCount(returnOrder.Id);
		Boolean fullyReceived;
		if (isRepairExchange && !isRepairExchangeMismatch) {
			// GW-4542 match - RO moves to Invoice (not Received).
			fullyReceived = ReturnOrdersService.markRepairExchangeInvoice(returnOrder.Id);
		} else if (isRepairExchange) {
			// Outbound stays Created, so do not wait on open-line completion.
			fullyReceived = ReturnOrdersService.markRepairExchangeReceived(returnOrder.Id);
		} else {
			fullyReceived = ReturnOrdersService.markReturnOrderReceivedIfComplete(
				returnOrder.Id
			);
		}

		List<Id> workOrderImageIds = finishRequest.contentDocumentIds;
		if (returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED) {
			workOrderImageIds = collectVendorItemImageIds(
				lineItem,
				finishRequest.contentDocumentIds
			);
		}
		linkPhotos(woResult.navigationWorkOrderId, workOrderImageIds);
		if (returnOrderType == RO_TYPE_INSTRUMENTS) {
			linkReturnOrderFiles(
				returnOrder.Id,
				woResult.navigationWorkOrderId,
				finishRequest.contentDocumentIds
			);
		}
		createResiTestHistoryIfNeeded(finishRequest, woResult, lineItem);

		ReceivingService.FinishReceivingResult result = new ReceivingService.FinishReceivingResult();
		result.hasWorkOrderCreated = true;
		result.workOrderId = woResult.navigationWorkOrderId;
		result.parentWorkOrderId = woResult.parentWorkOrderId;
		result.returnOrderFullyReceived = fullyReceived;
		return result;
	}

	private static WorkOrdersService.ReceivingWorkOrderCreateResult createSerializedReceive(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request,
		Id receiverId,
		String childSubStatus,
		Boolean isContaminated
	) {
		Id devicesRtId = requireWorkOrderRecordType(RT_DEVICES);
		Id parentWorkOrderId = resolveExistingParentWorkOrderId(returnOrder);
		WorkOrder parentWorkOrder;
		if (parentWorkOrderId == null) {
			parentWorkOrder = buildParentWorkOrder(
				returnOrder,
				lineItem,
				receiverId,
				devicesRtId,
				null,
				request
			);
			parentWorkOrder.Contaminated__c = isContaminated;
			applyDeviceParentLineMappings(parentWorkOrder, returnOrder, lineItem);
			applySharedHeaderMappings(parentWorkOrder, returnOrder, request);
			WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ parentWorkOrder });
			parentWorkOrderId = parentWorkOrder.Id;
			ReturnOrdersService.linkWorkOrderForReceiving(returnOrder.Id, parentWorkOrderId);
		}

		WorkOrder childWorkOrder = buildChildWorkOrder(
			parentWorkOrderId,
			returnOrder,
			lineItem,
			receiverId,
			devicesRtId,
			childSubStatus,
			request,
			isContaminated
		);
		applySharedHeaderMappings(childWorkOrder, returnOrder, request);
		applyChildVerificationMappings(childWorkOrder, request);
		applyActionOverlays(childWorkOrder, request, false);
		WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ childWorkOrder });
		List<WorkOrder> createdWorkOrders = new List<WorkOrder>{ childWorkOrder };
		if (parentWorkOrder != null) {
			createdWorkOrders.add(parentWorkOrder);
		}
		// One restore update for parent+child avoids a second Work Order trigger pass (SOQL).
		restoreInternalMappingsAfterCreate(createdWorkOrders, request);
		applyReturnOrderCaseMappings(createdWorkOrders, returnOrder);
		alignParentStatusWithChildren(parentWorkOrderId);

		Id productServicedId = WorkOrderLineItemsService.createReceivingProductServicedLine(
			childWorkOrder.Id,
			parentWorkOrderId,
			returnOrder.Id,
			lineItem,
			toReceivingProductServicedInput(request)
		);
		WorkOrderLineItemsService.createReceivingAccessoryLines(
			childWorkOrder.Id,
			productServicedId,
			lineItem != null ? lineItem.Product2Id : request.product2Id,
			toReceivingAccessoryInputs(request.accessories)
		);

		WorkOrdersService.ReceivingWorkOrderCreateResult result =
			new WorkOrdersService.ReceivingWorkOrderCreateResult();
		result.parentWorkOrderId = parentWorkOrderId;
		result.navigationWorkOrderId = childWorkOrder.Id;
		result.productServicedLineItemId = productServicedId;
		return result;
	}

	/**
	 * @description GW-5492 - Receives every Created line on an Instruments Return Order.
	 *              Each line keeps its own quantity returned. The header quantity is stored
	 *              on the Return Order separately.
	 * @param returnOrderId Instruments Return Order Id
	 * @param receiverId User who finished receiving
	 * @param receivedDateTime Finish timestamp
	 */
	private static void markInstrumentLinesReceived(
		Id returnOrderId,
		Id receiverId,
		Datetime receivedDateTime
	) {
		Set<Id> lineIds = new Set<Id>();
		for (
			ReturnOrderLineItem lineItem :
				ReturnOrderLineItemsService.getLinesForReceivingFinishByReturnOrderId(returnOrderId)
		) {
			if (lineItem.Status__c == STATUS_CREATED) {
				lineIds.add(lineItem.Id);
			}
		}
		ReturnOrderLineItemsService.markLinesReceivedForReceiving(
			lineIds,
			receiverId,
			receivedDateTime,
			null
		);
	}

	private static WorkOrdersService.ReceivingWorkOrderCreateResult createInstrumentsReceive(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request,
		Id receiverId,
		String childSubStatus,
		Boolean isContaminated
	) {
		Id instrumentsRtId = requireWorkOrderRecordType(RT_INSTRUMENTS);
		WorkOrder workOrder = buildExtendedWorkOrder(
			returnOrder,
			lineItem,
			receiverId,
			instrumentsRtId,
			childSubStatus,
			'Instruments Receive',
			RO_TYPE_INSTRUMENTS,
			request
		);
		workOrder.QuantityReceived__c = request.quantityReceived;
		workOrder.Contaminated__c = isContaminated;
		applyChildVerificationMappings(workOrder, request);
		applyInstrumentParentMappings(
			workOrder,
			returnOrder,
			ReturnOrderLineItemsService.getLinesForReceivingFinishByReturnOrderId(returnOrder.Id)
		);
		applySharedHeaderMappings(workOrder, returnOrder, request);
		applyActionOverlays(workOrder, request, false);
		// GW-6479 / GW-5677: instrument receive (no asset) stores the list on the parent Work Order.
		applyAdditionalServicesRequested(workOrder, returnOrder.Id);
		WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ workOrder });
		restoreInternalMappingsAfterCreate(new List<WorkOrder>{ workOrder }, request);
		applyReturnOrderCaseMappings(new List<WorkOrder>{ workOrder }, returnOrder);
		ReturnOrdersService.linkWorkOrderForReceiving(returnOrder.Id, workOrder.Id);

		WorkOrdersService.ReceivingWorkOrderCreateResult result =
			new WorkOrdersService.ReceivingWorkOrderCreateResult();
		result.parentWorkOrderId = workOrder.Id;
		result.navigationWorkOrderId = workOrder.Id;
		return result;
	}

	private static WorkOrdersService.ReceivingWorkOrderCreateResult createOtherReceive(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request,
		Id receiverId,
		String childSubStatus,
		Boolean isContaminated,
		String returnOrderType
	) {
		Boolean hasVendor = request.vendorAccountId != null;
		Boolean isStirrup = isStirrupProduct(lineItem);

		if (hasVendor || returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED) {
			return createVendorOtherReceive(
				returnOrder,
				lineItem,
				request,
				receiverId,
				childSubStatus,
				isContaminated,
				returnOrderType
			);
		}

		if (isStirrup) {
			return createStirrupInstrumentReceive(
				returnOrder,
				lineItem,
				request,
				receiverId,
				childSubStatus,
				isContaminated
			);
		}

		return createSerializedReceive(
			returnOrder,
			lineItem,
			request,
			receiverId,
			childSubStatus,
			isContaminated
		);
	}

	private static WorkOrdersService.ReceivingWorkOrderCreateResult createVendorOtherReceive(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request,
		Id receiverId,
		String childSubStatus,
		Boolean isContaminated,
		String returnOrderType
	) {
		if (returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED && request.vendorAccountId != null) {
			WorkOrder existingVendorWorkOrder = WorkOrdersSelector.selectReceivingVendorWorkOrder(
				returnOrder.Id,
				request.vendorAccountId
			);
			if (existingVendorWorkOrder != null) {
				return addProductServicedLineToVendorWorkOrder(
					existingVendorWorkOrder,
					returnOrder,
					lineItem,
					request
				);
			}
		}

		Id vendorRtId = requireWorkOrderRecordType(RT_VENDOR);
		String subStatus = hasCustomerCare(request)
			? WO_SUB_STATUS_CUSTOMER_CARE
			: WO_SUB_STATUS_SHIP_TO_VENDOR;
		WorkOrder workOrder = buildExtendedWorkOrder(
			returnOrder,
			lineItem,
			receiverId,
			vendorRtId,
			subStatus,
			'Outside Vendor Receive',
			RO_TYPE_OTHER_SERIALIZED,
			request
		);
		workOrder.Contaminated__c = isContaminated;
		if (returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED) {
			applyChildVerificationMappings(workOrder, request);
		}
		workOrder.Vendor__c = request.vendorAccountId;
		workOrder.InstructionsToVendor__c = request.instructionsToVendor;
		applyLineReferenceMappings(workOrder, lineItem);
		applySharedHeaderMappings(workOrder, returnOrder, request);
		applyActionOverlays(workOrder, request, true);
		if (returnOrderType == RO_TYPE_OTHER_NON_SERIALIZED && isContaminated == true) {
			workOrder.SubStatus__c = WO_SUB_STATUS_CONTAMINATED;
		}
		if (workOrder.SubStatus__c == WO_SUB_STATUS_SHIP_TO_VENDOR) {
			workOrder.ShippedToVendorDate__c = Date.today();
		}
		WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ workOrder });
		restoreInternalMappingsAfterCreate(new List<WorkOrder>{ workOrder }, request);
		applyReturnOrderCaseMappings(new List<WorkOrder>{ workOrder }, returnOrder);
		ReturnOrdersService.linkWorkOrderForReceiving(returnOrder.Id, workOrder.Id);

		Id productServicedId = WorkOrderLineItemsService.createReceivingProductServicedLine(
			workOrder.Id,
			workOrder.Id,
			returnOrder.Id,
			lineItem,
			toReceivingProductServicedInput(request)
		);
		WorkOrderLineItemsService.createReceivingAccessoryLines(
			workOrder.Id,
			productServicedId,
			lineItem != null ? lineItem.Product2Id : request.product2Id,
			toReceivingAccessoryInputs(request.accessories)
		);

		WorkOrdersService.ReceivingWorkOrderCreateResult result =
			new WorkOrdersService.ReceivingWorkOrderCreateResult();
		result.parentWorkOrderId = workOrder.Id;
		result.navigationWorkOrderId = workOrder.Id;
		result.productServicedLineItemId = productServicedId;
		return result;
	}

	/**
	 * @description Adds a Product Serviced line to the Vendor Work Order already used
	 *              for this Return Order and vendor. Instruction changes are appended.
	 * @param vendorWorkOrder Existing Vendor Work Order
	 * @param returnOrder Return Order being received
	 * @param lineItem Return Order line for this item
	 * @param request Finish Receiving request
	 * @return Create result pointing at the existing Vendor Work Order
	 */
	private static WorkOrdersService.ReceivingWorkOrderCreateResult addProductServicedLineToVendorWorkOrder(
		WorkOrder vendorWorkOrder,
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request
	) {
		String mergedInstructions = mergeVendorInstructions(
			vendorWorkOrder.InstructionsToVendor__c,
			request.instructionsToVendor
		);
		Boolean instructionsChanged = mergedInstructions != vendorWorkOrder.InstructionsToVendor__c;
		Boolean markPriority = lineItem != null
			&& lineItem.IsPriorityRepair__c == true
			&& vendorWorkOrder.IsPriorityRepair__c != true;
		Boolean markContaminated = UI_CONTAMINATED.equalsIgnoreCase(request.disinfected);
		Boolean markResiTestFailed = request.resiTestFailed == true;
		Boolean markVisualInspection = request.visualInspection == true;
		Boolean markBioBag = request.bioBag == true;
		if (
			instructionsChanged
			|| markPriority
			|| markContaminated
			|| markResiTestFailed
			|| markVisualInspection
			|| markBioBag
		) {
			WorkOrder vendorUpdate = new WorkOrder(Id = vendorWorkOrder.Id);
			if (instructionsChanged) {
				vendorUpdate.InstructionsToVendor__c = mergedInstructions;
			}
			if (markPriority) {
				vendorUpdate.IsPriorityRepair__c = true;
			}
			if (markContaminated) {
				vendorUpdate.Contaminated__c = true;
				vendorUpdate.SubStatus__c = WO_SUB_STATUS_CONTAMINATED;
			}
			if (markResiTestFailed) {
				vendorUpdate.IsResiTestFailed__c = true;
			}
			if (markVisualInspection) {
				vendorUpdate.IsVisualInspection__c = true;
			}
			if (markBioBag) {
				vendorUpdate.IsBioBag__c = true;
			}
			WorkOrdersService.updateWorkOrders(new List<WorkOrder>{ vendorUpdate });
		}
		ReturnOrdersService.linkWorkOrderForReceiving(returnOrder.Id, vendorWorkOrder.Id);

		Id productServicedId = WorkOrderLineItemsService.createReceivingProductServicedLine(
			vendorWorkOrder.Id,
			vendorWorkOrder.Id,
			returnOrder.Id,
			lineItem,
			toReceivingProductServicedInput(request)
		);
		WorkOrderLineItemsService.createReceivingAccessoryLines(
			vendorWorkOrder.Id,
			productServicedId,
			lineItem != null ? lineItem.Product2Id : request.product2Id,
			toReceivingAccessoryInputs(request.accessories)
		);

		WorkOrdersService.ReceivingWorkOrderCreateResult result =
			new WorkOrdersService.ReceivingWorkOrderCreateResult();
		result.parentWorkOrderId = vendorWorkOrder.Id;
		result.navigationWorkOrderId = vendorWorkOrder.Id;
		result.productServicedLineItemId = productServicedId;
		return result;
	}

	/**
	 * @description Appends new vendor instructions without dropping text already stored.
	 * @param existingText Instructions already on the Work Order or item
	 * @param incomingText Instructions from the item being received
	 * @return Combined instructions
	 */
	@TestVisible
	private static String mergeVendorInstructions(String existingText, String incomingText) {
		String existingValue = existingText == null ? '' : existingText.trim();
		String incomingValue = incomingText == null ? '' : incomingText.trim();
		if (String.isBlank(incomingValue)) {
			return existingText;
		}
		if (String.isBlank(existingValue) || existingValue == incomingValue) {
			return incomingValue;
		}
		if (existingValue.contains(incomingValue)) {
			return existingValue;
		}
		if (incomingValue.contains(existingValue)) {
			return incomingValue;
		}
		return existingValue + '\n' + incomingValue;
	}

	private static WorkOrdersService.ReceivingWorkOrderCreateResult createStirrupInstrumentReceive(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request,
		Id receiverId,
		String childSubStatus,
		Boolean isContaminated
	) {
		Id instrumentsRtId = requireWorkOrderRecordType(RT_INSTRUMENTS);
		WorkOrder parentWorkOrder = buildParentWorkOrder(
			returnOrder,
			lineItem,
			receiverId,
			instrumentsRtId,
			childSubStatus,
			request
		);
		parentWorkOrder.Contaminated__c = isContaminated;
		Id machineShopRackId = resolveMachineShopRackId();
		parentWorkOrder.RepairCategory__c = MACHINE_SHOP;
		parentWorkOrder.Rack__c = machineShopRackId;
		// Parent must carry line Customer PO before Case mapping. Updating the parent Case
		// syncs parent Customer PO onto children, which would clear a child-only PO.
		applyLineReferenceMappings(parentWorkOrder, lineItem);
		applySharedHeaderMappings(parentWorkOrder, returnOrder, request);
		WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ parentWorkOrder });
		ReturnOrdersService.linkWorkOrderForReceiving(returnOrder.Id, parentWorkOrder.Id);

		WorkOrder childWorkOrder = buildChildWorkOrder(
			parentWorkOrder.Id,
			returnOrder,
			lineItem,
			receiverId,
			instrumentsRtId,
			childSubStatus,
			request,
			isContaminated
		);
		childWorkOrder.RepairCategory__c = MACHINE_SHOP;
		childWorkOrder.Rack__c = machineShopRackId;
		applySharedHeaderMappings(childWorkOrder, returnOrder, request);
		applyChildVerificationMappings(childWorkOrder, request);
		applyActionOverlays(childWorkOrder, request, false);
		WorkOrdersService.createReceivingWorkOrders(new List<WorkOrder>{ childWorkOrder });
		List<WorkOrder> createdWorkOrders = new List<WorkOrder>{ parentWorkOrder, childWorkOrder };
		// One restore update for parent+child avoids a second Work Order trigger pass (SOQL).
		restoreInternalMappingsAfterCreate(createdWorkOrders, request);
		applyReturnOrderCaseMappings(createdWorkOrders, returnOrder);
		alignParentStatusWithChildren(parentWorkOrder.Id);

		Id productServicedId = WorkOrderLineItemsService.createReceivingProductServicedLine(
			childWorkOrder.Id,
			parentWorkOrder.Id,
			returnOrder.Id,
			lineItem,
			toReceivingProductServicedInput(request)
		);
		WorkOrderLineItemsService.createReceivingAccessoryLines(
			childWorkOrder.Id,
			productServicedId,
			lineItem != null ? lineItem.Product2Id : request.product2Id,
			toReceivingAccessoryInputs(request.accessories)
		);

		WorkOrdersService.ReceivingWorkOrderCreateResult result =
			new WorkOrdersService.ReceivingWorkOrderCreateResult();
		result.parentWorkOrderId = parentWorkOrder.Id;
		result.navigationWorkOrderId = childWorkOrder.Id;
		result.productServicedLineItemId = productServicedId;
		return result;
	}

	/**
	 * @description GW-5492 - Rack is a Location lookup. Resolve the Machine Shop rack by Repair Category.
	 * @return Location Id, or null when no Machine Shop rack exists
	 */
	private static Id resolveMachineShopRackId() {
		List<Schema.Location> racks = LocationsSelector.selectRacksByRepairCategories(
			new Set<String>{ MACHINE_SHOP }
		);
		return racks.isEmpty() ? null : racks[0].Id;
	}

	private static void applyLineCorrections(
		ReturnOrderLineItem lineItem,
		ReceivingService.FinishReceivingRequest request
	) {
		Boolean hasModelCorrection = String.isNotBlank(request.overrideCorrectedModel);
		Boolean hasSerialCorrection = String.isNotBlank(request.overrideCorrectedSerial);
		if (!hasModelCorrection && !hasSerialCorrection && request.product2Id == null) {
			return;
		}
		ReturnOrderLineItem updateLine = new ReturnOrderLineItem(Id = lineItem.Id);
		if (hasSerialCorrection) {
			updateLine.SerialNumber__c = request.overrideCorrectedSerial.trim();
		}
		if (hasModelCorrection) {
			updateLine.Model__c = request.overrideCorrectedModel.trim();
		}
		if (request.product2Id != null) {
			updateLine.Product2Id = request.product2Id;
		}
		if (String.isNotBlank(request.disinfected)) {
			updateLine.Disinfected__c = mapDisinfected(request.disinfected);
		}
		Database.update(
			new List<ReturnOrderLineItem>{ updateLine },
			AccessLevel.USER_MODE
		);
	}

	private static String mapDisinfected(String uiValue) {
		if (UI_CONTAMINATED.equalsIgnoreCase(uiValue)) {
			return 'No, Item is not Disinfected';
		}
		if ('Clean'.equalsIgnoreCase(uiValue)) {
			return 'Yes, Item is Disinfected';
		}
		return uiValue;
	}

	private static String resolveChildSubStatus(
		ReceivingService.FinishReceivingRequest request,
		String returnOrderType
	) {
		if (UI_CONTAMINATED.equalsIgnoreCase(request.disinfected)) {
			return WO_SUB_STATUS_CONTAMINATED;
		}
		if (hasCustomerCare(request)) {
			return WO_SUB_STATUS_CUSTOMER_CARE;
		}
		if (request.vendorAccountId != null && allowsOutsideVendor(returnOrderType)) {
			return WO_SUB_STATUS_SHIP_TO_VENDOR;
		}
		if (returnOrderType == RO_TYPE_INSTRUMENTS) {
			return WO_SUB_STATUS_READY_FOR_EVAL;
		}
		return WO_SUB_STATUS_READY_FOR_EVAL;
	}

	/**
	 * @description GW-4542 - True when Repair Exchange Model Mismatch reason is present
	 *              or Inbound MD # differs from Outbound Model Sent.
	 */
	private static Boolean isRepairExchangeModelMismatch(
		ReceivingService.FinishReceivingRequest request,
		Id returnOrderId,
		ReturnOrderLineItem inboundLine
	) {
		if (hasReasonCode(request, REASON_REPAIR_EXCHANGE_MODEL_MISMATCH)) {
			return true;
		}
		// Use ROLI.Model__c only — finish SOQL may load Product2 without Model__c.
		String inboundModel = inboundLine == null ? null : inboundLine.Model__c;
		String outboundModel = selectOutboundModelSent(returnOrderId);
		if (String.isBlank(inboundModel) || String.isBlank(outboundModel)) {
			return true;
		}
		return !inboundModel.trim().equalsIgnoreCase(outboundModel.trim());
	}

	private static Boolean hasReasonCode(
		ReceivingService.FinishReceivingRequest request,
		String reasonCode
	) {
		if (
			request == null
			|| request.customerCareReasonCodes == null
			|| String.isBlank(reasonCode)
		) {
			return false;
		}
		for (String code : request.customerCareReasonCodes) {
			if (reasonCode.equalsIgnoreCase(code)) {
				return true;
			}
		}
		return false;
	}

	private static String selectOutboundModelSent(Id returnOrderId) {
		if (returnOrderId == null) {
			return null;
		}
		List<ReturnOrderLineItem> outboundLines = (List<ReturnOrderLineItem>) new ReturnOrderLineItemsSelector()
			.selectFields(new List<String>{ 'Model__c', 'Product2.Model__c' })
			.whereEquals('ReturnOrderId', returnOrderId)
			.whereEquals('LineType__c', LINE_TYPE_OUTBOUND)
			.orderBy('CreatedDate')
			.execute();
		if (outboundLines.isEmpty()) {
			return null;
		}
		ReturnOrderLineItem outbound = outboundLines[0];
		return firstNonBlank(outbound.Model__c, outbound.Product2?.Model__c);
	}

	/**
	 * @description GW-4542 - Mismatch ignores Internal Repair action data and ensures the
	 *              Repair Exchange Model Mismatch reason code is present for Customer Care.
	 */
	private static ReceivingService.FinishReceivingRequest prepareRepairExchangeFinishRequest(
		ReceivingService.FinishReceivingRequest request,
		Boolean isMismatch
	) {
		ReceivingService.FinishReceivingRequest finishRequest =
			new ReceivingService.FinishReceivingRequest();
		finishRequest.returnOrderId = request.returnOrderId;
		finishRequest.lineItemId = request.lineItemId;
		finishRequest.receiverId = request.receiverId;
		finishRequest.receivedDateTime = request.receivedDateTime;
		finishRequest.isAdHoc = request.isAdHoc;
		finishRequest.assetId = request.assetId;
		finishRequest.product2Id = request.product2Id;
		finishRequest.serialNumber = request.serialNumber;
		finishRequest.model = request.model;
		finishRequest.quantityReceived = request.quantityReceived;
		finishRequest.disinfected = request.disinfected;
		finishRequest.resiTestPerformed = request.resiTestPerformed;
		finishRequest.resiTestFailed = request.resiTestFailed;
		finishRequest.visualInspection = request.visualInspection;
		finishRequest.bioBag = request.bioBag;
		finishRequest.customerCareNotes = request.customerCareNotes;
		finishRequest.overrideCorrectedSerial = request.overrideCorrectedSerial;
		finishRequest.overrideCorrectedModel = request.overrideCorrectedModel;
		finishRequest.isRedirected = request.isRedirected;
		finishRequest.redirectLocationId = request.redirectLocationId;
		finishRequest.redirectionNotes = request.redirectionNotes;
		finishRequest.vendorAccountId = request.vendorAccountId;
		finishRequest.instructionsToVendor = request.instructionsToVendor;
		finishRequest.accessories = request.accessories;
		finishRequest.contentDocumentIds = request.contentDocumentIds;
		finishRequest.customerCareReasonCodes = request.customerCareReasonCodes == null
			? new List<String>()
			: new List<String>(request.customerCareReasonCodes);

		if (isMismatch) {
			// Ignore Internal Repair action data on mismatch (treat like Serialized).
			finishRequest.internalAccountId = null;
			finishRequest.internalRepairNotes = null;
			if (!hasReasonCode(finishRequest, REASON_REPAIR_EXCHANGE_MODEL_MISMATCH)) {
				finishRequest.customerCareReasonCodes.add(REASON_REPAIR_EXCHANGE_MODEL_MISMATCH);
			}
		} else {
			finishRequest.internalAccountId = request.internalAccountId;
			finishRequest.internalRepairNotes = request.internalRepairNotes;
		}
		return finishRequest;
	}

	/**
	 * @description GW-4542 - Mark the Inbound ROLI Received. Outbound stays Created because
	 *              Outbound record-type Status__c does not allow Received.
	 */
	private static void markRepairExchangeInboundReceived(
		Id inboundLineItemId,
		Id receiverId,
		Datetime receivedDateTime,
		Decimal quantityReceived
	) {
		if (inboundLineItemId == null) {
			return;
		}
		ReturnOrderLineItemsService.markLinesReceivedForReceiving(
			new Set<Id>{ inboundLineItemId },
			receiverId,
			receivedDateTime,
			quantityReceived
		);
	}

	/**
	 * @description GW-4542 match - Always mark created WOs Internal Repair; Account mapping
	 *              still follows GW-4162 when an Internal Account was selected.
	 */
	private static void ensureInternalRepairFlagOnCreatedWorkOrders(
		WorkOrdersService.ReceivingWorkOrderCreateResult woResult,
		ReceivingService.FinishReceivingRequest request
	) {
		if (woResult == null) {
			return;
		}
		Set<Id> workOrderIds = new Set<Id>();
		if (woResult.navigationWorkOrderId != null) {
			workOrderIds.add(woResult.navigationWorkOrderId);
		}
		if (woResult.parentWorkOrderId != null) {
			workOrderIds.add(woResult.parentWorkOrderId);
		}
		if (workOrderIds.isEmpty()) {
			return;
		}
		List<WorkOrder> updates = new List<WorkOrder>();
		for (Id workOrderId : workOrderIds) {
			WorkOrder updateRow = new WorkOrder(
				Id = workOrderId,
				IsInternalRepair__c = true
			);
			if (request != null && String.isNotBlank(request.internalRepairNotes)) {
				updateRow.Notes__c = request.internalRepairNotes.trim();
			}
			updates.add(updateRow);
		}
		Database.update(updates, AccessLevel.USER_MODE);
	}

	private static String firstNonBlank(String firstValue, String secondValue) {
		if (String.isNotBlank(firstValue)) {
			return firstValue;
		}
		return secondValue;
	}

	/**
	 * @description Serialized and Instruments receiving ignore Outside Vendor.
	 *              Other return order types still create a vendor work order.
	 */
	private static Boolean allowsOutsideVendor(String returnOrderType) {
		return returnOrderType != RO_TYPE_SERIALIZED
			&& returnOrderType != RO_TYPE_INSTRUMENTS
			&& returnOrderType != RO_TYPE_REPAIR_EXCHANGE;
	}

	private static Boolean hasCustomerCare(ReceivingService.FinishReceivingRequest request) {
		return request != null
			&& request.customerCareReasonCodes != null
			&& !request.customerCareReasonCodes.isEmpty();
	}

	/**
	 * @description GW-5492 - When every child Work Order has the same status, the parent
	 *              gets that status and no sub-status. An instrument parent with no children
	 *              keeps its sub-status.
	 * @param parentWorkOrderId Parent Work Order created for this receive
	 */
	private static void alignParentStatusWithChildren(Id parentWorkOrderId) {
		List<WorkOrder> children = WorkOrdersSelector.selectChildStatusesForReceiving(
			parentWorkOrderId
		);
		if (children.isEmpty()) {
			return;
		}
		String sharedStatus = null;
		for (WorkOrder child : children) {
			if (String.isBlank(child.Status)) {
				return;
			}
			if (sharedStatus == null) {
				sharedStatus = child.Status;
			} else if (sharedStatus != child.Status) {
				return;
			}
		}
		WorkOrdersService.updateWorkOrders(
			new List<WorkOrder>{
				new WorkOrder(
					Id = parentWorkOrderId,
					Status = sharedStatus,
					SubStatus__c = null
				)
			}
		);
	}

	private static Boolean isStirrupProduct(ReturnOrderLineItem lineItem) {
		if (lineItem == null || lineItem.Product2 == null) {
			return false;
		}
		return DEVICE_TYPE_STIRRUP.equalsIgnoreCase(
			String.valueOf(lineItem.Product2.DeviceType__c)
		);
	}

	private static Id resolveExistingParentWorkOrderId(ReturnOrder returnOrder) {
		if (returnOrder.WorkOrder__c != null) {
			return returnOrder.WorkOrder__c;
		}
		return WorkOrdersSelector.selectReceivingParentWorkOrderId(returnOrder.Id);
	}

	private static WorkOrder buildParentWorkOrder(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		Id receiverId,
		Id recordTypeId,
		String subStatus,
		ReceivingService.FinishReceivingRequest request
	) {
		WorkOrder parentWorkOrder = new WorkOrder();
		parentWorkOrder.RecordTypeId = recordTypeId;
		parentWorkOrder.Status = WO_STATUS_RECEIVED;
		if (String.isNotBlank(subStatus)) {
			parentWorkOrder.SubStatus__c = subStatus;
		}
		parentWorkOrder.AccountId = resolveWorkOrderAccountId(returnOrder, request);
		parentWorkOrder.ContactId = returnOrder.ContactId;
		parentWorkOrder.LocationId = returnOrder.DestinationLocationId;
		parentWorkOrder.RepairCenter__c = returnOrder.DestinationLocationId;
		parentWorkOrder.Receiver__c = receiverId;
		parentWorkOrder.ReturnOrder__c = returnOrder.Id;
		parentWorkOrder.Subject = 'Parent Receive ' + returnOrder.ReturnOrderNumber;
		parentWorkOrder.AssignedSalesPerson__c = returnOrder.SalesRep__c;
		applyDefaultPricebook(parentWorkOrder);
		applyInternalRepair(parentWorkOrder, request);
		return parentWorkOrder;
	}

	private static WorkOrder buildChildWorkOrder(
		Id parentWorkOrderId,
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		Id receiverId,
		Id recordTypeId,
		String subStatus,
		ReceivingService.FinishReceivingRequest request,
		Boolean isContaminated
	) {
		WorkOrder child = new WorkOrder();
		child.RecordTypeId = recordTypeId;
		child.ParentWorkOrderId = parentWorkOrderId;
		child.Status = WO_STATUS_RECEIVED;
		child.SubStatus__c = subStatus;
		child.AccountId = resolveWorkOrderAccountId(returnOrder, request);
		child.ContactId = lineItem != null && lineItem.Contact__c != null
			? lineItem.Contact__c
			: returnOrder.ContactId;
		if (lineItem != null) {
			child.ReturnOrderLineItemId = lineItem.Id;
			child.AssetId = lineItem.AssetId;
			child.Product__c = lineItem.Product2Id;
			child.Model__c = String.isNotBlank(request.overrideCorrectedModel)
				? request.overrideCorrectedModel
				: lineItem.Model__c;
			child.SerialNumber__c = String.isNotBlank(request.overrideCorrectedSerial)
				? request.overrideCorrectedSerial
				: lineItem.SerialNumber__c;
			child.TrayName__c = lineItem.HospitalReferencedTrayName__c;
			applyLineReferenceMappings(child, lineItem);
			child.Department__c = lineItem.Department__c;
			child.EstimateRequired__c = lineItem.EstimateRequired__c;
			child.EstimateContact__c = lineItem.EstimateContact__c;
			child.RepairWarranty__c = lineItem.RepairWarranty__c;
			child.WarrantyNotes__c = lineItem.WarrantyNotes__c;
			child.IsPriorityRepair__c = lineItem.IsPriorityRepair__c == true;
			if (
				WO_SUB_STATUS_READY_FOR_EVAL.equals(subStatus)
				&& PRODUCT_LINE_RIGID_SCOPE.equalsIgnoreCase(lineItem.ProductLine__c)
			) {
				child.Status = WO_STATUS_EVALUATE;
				child.SubStatus__c = WO_SUB_STATUS_TRIAGE;
			}
		} else if (request.isAdHoc == true) {
			child.AssetId = request.assetId;
			child.Product__c = request.product2Id;
			child.SerialNumber__c = request.serialNumber;
			child.Model__c = request.model;
		}
		child.ReturnOrder__c = returnOrder.Id;
		child.LocationId = returnOrder.DestinationLocationId;
		child.RepairCenter__c = returnOrder.DestinationLocationId;
		child.Receiver__c = receiverId;
		child.AssignedSalesPerson__c = returnOrder.SalesRep__c;
		child.Subject = lineItem != null
			? 'Line ' + lineItem.ReturnOrderLineItemNumber
			: 'Ad Hoc Item';
		child.QuantityReceived__c = 1;
		child.Contaminated__c = isContaminated;
		applyDefaultPricebook(child);
		applyInternalRepair(child, request);
		// GW-6479 / GW-5677: asset receive stores the list on the child Work Order.
		applyAdditionalServicesRequested(child, returnOrder.Id);
		return child;
	}

	private static WorkOrder buildExtendedWorkOrder(
		ReturnOrder returnOrder,
		ReturnOrderLineItem lineItem,
		Id receiverId,
		Id recordTypeId,
		String subStatus,
		String subject,
		String returnOrderType,
		ReceivingService.FinishReceivingRequest request
	) {
		WorkOrder workOrder = new WorkOrder();
		workOrder.RecordTypeId = recordTypeId;
		workOrder.Status = WO_STATUS_RECEIVED;
		workOrder.SubStatus__c = subStatus;
		workOrder.AccountId = resolveWorkOrderAccountId(returnOrder, request);
		if (returnOrderType != RO_TYPE_INSTRUMENTS && lineItem != null) {
			workOrder.ContactId = lineItem.Contact__c != null
				? lineItem.Contact__c
				: returnOrder.ContactId;
			workOrder.AssetId = lineItem.AssetId;
			workOrder.Product__c = lineItem.Product2Id;
			workOrder.Model__c = lineItem.Model__c;
			workOrder.SerialNumber__c = lineItem.SerialNumber__c;
			workOrder.ReturnOrderLineItemId = lineItem.Id;
			workOrder.EstimateContact__c = lineItem.EstimateContact__c;
			workOrder.RepairWarranty__c = lineItem.RepairWarranty__c;
			workOrder.WarrantyNotes__c = lineItem.WarrantyNotes__c;
		} else {
			workOrder.ContactId = returnOrder.ContactId;
		}
		if (lineItem != null) {
			workOrder.IsPriorityRepair__c = lineItem.IsPriorityRepair__c == true;
		}
		workOrder.LocationId = returnOrder.DestinationLocationId;
		workOrder.RepairCenter__c = returnOrder.DestinationLocationId;
		workOrder.Receiver__c = receiverId;
		workOrder.ReturnOrder__c = returnOrder.Id;
		workOrder.Subject = subject;
		workOrder.AssignedSalesPerson__c = returnOrder.SalesRep__c;
		applyDefaultPricebook(workOrder);
		applyInternalRepair(workOrder, request);
		return workOrder;
	}

	/**
	 * @description Copies the child Work Order header fields onto the parent Device
	 *              Work Order from the first return line. Contact falls back to the
	 *              Return Order only when that line has no Contact.
	 * @param parentWorkOrder Parent Work Order being created
	 * @param returnOrder Return Order being received
	 * @param currentLine Line that triggered parent creation
	 */
	private static void applyDeviceParentLineMappings(
		WorkOrder parentWorkOrder,
		ReturnOrder returnOrder,
		ReturnOrderLineItem currentLine
	) {
		if (parentWorkOrder == null) {
			return;
		}
		ReturnOrderLineItem sourceLine = resolveFirstReturnLine(returnOrder, currentLine);
		if (sourceLine == null) {
			return;
		}
		parentWorkOrder.CustomerPO__c = sourceLine.CustomerPO__c;
		parentWorkOrder.CustomerReference__c = sourceLine.CustomerReference__c;
		parentWorkOrder.Department__c = sourceLine.Department__c;
		parentWorkOrder.EstimateContact__c = sourceLine.EstimateContact__c;
		parentWorkOrder.ContactId = sourceLine.Contact__c != null
			? sourceLine.Contact__c
			: (returnOrder != null ? returnOrder.ContactId : null);
	}

	/**
	 * @description First return line on the order, matching the old parent mapping source.
	 * @param returnOrder Return Order being received
	 * @param currentLine Line that triggered parent creation
	 * @return First line, or the current line when the order has none
	 */
	private static ReturnOrderLineItem resolveFirstReturnLine(
		ReturnOrder returnOrder,
		ReturnOrderLineItem currentLine
	) {
		if (returnOrder == null || returnOrder.Id == null) {
			return currentLine;
		}
		List<ReturnOrderLineItem> lines =
			ReturnOrderLineItemsService.getLinesForReceivingFinishByReturnOrderId(returnOrder.Id);
		if (lines.isEmpty()) {
			return currentLine;
		}
		return lines[0];
	}

	/**
	 * @description GW-5492 - Copies return-line reference fields onto a Work Order.
	 *              Reported Problem maps to Description. Case and Continuous Improvement
	 *              Opportunity come from the Return Order after insert.
	 * @param workOrder Work Order being created
	 * @param lineItem Return Order line being received
	 */
	private static void applyLineReferenceMappings(
		WorkOrder workOrder,
		ReturnOrderLineItem lineItem
	) {
		if (workOrder == null || lineItem == null) {
			return;
		}
		workOrder.CustomerPO__c = lineItem.CustomerPO__c;
		workOrder.CustomerReference__c = lineItem.CustomerReference__c;
		workOrder.PreviousReturnOrder__c = lineItem.PreviousReturnOrder__c;
		if (String.isNotBlank(lineItem.ReportedProblem__c)) {
			workOrder.Description = lineItem.ReportedProblem__c.trim();
		}
	}

	/**
	 * @description GW-5492 / GW-4162 - Internal Repair notes go to Work Order Notes, not Description.
	 * @param workOrder Work Order being created
	 * @param request Finish Receiving request
	 */
	private static void applyInternalRepair(
		WorkOrder workOrder,
		ReceivingService.FinishReceivingRequest request
	) {
		if (request == null || request.internalAccountId == null || workOrder == null) {
			return;
		}
		workOrder.IsInternalRepair__c = true;
		if (String.isNotBlank(request.internalRepairNotes)) {
			workOrder.Notes__c = request.internalRepairNotes.trim();
		}
	}

	/**
	 * @description GW-4162 - Work Order Account is the selected Internal Account when specified.
	 * @param returnOrder Source Return Order
	 * @param request Finish Receiving request
	 * @return Internal Account Id when present, otherwise Return Order Account Id
	 */
	private static Id resolveWorkOrderAccountId(
		ReturnOrder returnOrder,
		ReceivingService.FinishReceivingRequest request
	) {
		if (request != null && request.internalAccountId != null) {
			return request.internalAccountId;
		}
		return returnOrder != null ? returnOrder.AccountId : null;
	}

	private static void applyActionOverlays(
		WorkOrder workOrder,
		ReceivingService.FinishReceivingRequest request,
		Boolean allowVendorOnThisWo
	) {
		if (workOrder == null || request == null) {
			return;
		}
		if (hasCustomerCare(request)) {
			workOrder.SubStatus__c = WO_SUB_STATUS_CUSTOMER_CARE;
			workOrder.ReasonCode__c = String.join(request.customerCareReasonCodes, ';');
			workOrder.CustomerCareNotes__c = request.customerCareNotes;
		} else if (allowVendorOnThisWo && request.vendorAccountId != null) {
			workOrder.SubStatus__c = WO_SUB_STATUS_SHIP_TO_VENDOR;
			workOrder.Vendor__c = request.vendorAccountId;
			workOrder.InstructionsToVendor__c = request.instructionsToVendor;
		}
	}

	/**
	 * @description GW-5492 - Maps Resi-Test Failed, Visual Inspection, and Bio Bag.
	 *              Instruments have no child Work Order, so these land on the parent.
	 */
	private static void applyChildVerificationMappings(
		WorkOrder workOrder,
		ReceivingService.FinishReceivingRequest request
	) {
		if (workOrder == null || request == null) {
			return;
		}
		workOrder.IsResiTestFailed__c = request.resiTestFailed == true;
		workOrder.IsVisualInspection__c = request.visualInspection == true;
		workOrder.IsBioBag__c = request.bioBag == true;
	}

	private static void applySharedHeaderMappings(
		WorkOrder workOrder,
		ReturnOrder returnOrder,
		ReceivingService.FinishReceivingRequest request
	) {
		if (workOrder == null || returnOrder == null) {
			return;
		}
		workOrder.OperatingUnit__c = returnOrder.OperatingUnit__c;
		if (returnOrder.DestinationLocation != null) {
			workOrder.RepairCenterName__c = returnOrder.DestinationLocation.Name;
		}
		// AccountManager__c is text. SalesRep__c is a User Id, so copying it shows a
		// Salesforce Id. Leave Account Manager blank until that mapping is defined.
		if (request != null && request.internalAccountId != null) {
			applyInternalShipTo(workOrder, request.internalAccountId);
			applyInternalBillTo(workOrder, request.internalAccountId);
			return;
		}
		if (returnOrder.ShipToAddressAccount__c != null) {
			workOrder.ShipTo__c = returnOrder.ShipToAddressAccount__c;
			workOrder.ShipToAddressAccount__c = returnOrder.ShipToAddressAccount__c;
			applyShipToAddress(
				workOrder,
				loadBillingAddress(returnOrder.ShipToAddressAccount__c)
			);
		}
		Account billToAccount = resolvePrimaryBillToAccount(returnOrder.AccountId);
		if (billToAccount != null) {
			workOrder.BillTo__c = billToAccount.Id;
			workOrder.BillToAddressAccount__c = billToAccount.Id;
			applyBillToAddress(workOrder, billToAccount);
			if (String.isNotBlank(billToAccount.CurrencyIsoCode)) {
				workOrder.CurrencyIsoCode = billToAccount.CurrencyIsoCode;
			}
		}
	}

	/**
	 * @description GW-5492 / GW-4162 - Internal Repair bills the internal account, not the
	 *              customer primary bill-to. Bill-To Address Account only accepts an Address
	 *              account whose parent is the Work Order account. When no allowed address
	 *              account exists, the lookup stays blank and Bill To Address uses the
	 *              internal account billing address (or matching AccountNumber address).
	 * @param workOrder Work Order being created or corrected
	 * @param internalAccountId Account selected on the Internal Repair action
	 */
	private static void applyInternalBillTo(WorkOrder workOrder, Id internalAccountId) {
		if (workOrder == null || internalAccountId == null) {
			return;
		}
		workOrder.BillTo__c = internalAccountId;
		Account internalAccount = loadBillingAddress(internalAccountId);
		if (internalAccount != null && String.isNotBlank(internalAccount.CurrencyIsoCode)) {
			workOrder.CurrencyIsoCode = internalAccount.CurrencyIsoCode;
		}
		Account addressAccount = resolvePrimaryBillToAccount(internalAccountId);
		if (isBillToAddressAccountAllowed(addressAccount, workOrder.AccountId)) {
			workOrder.BillToAddressAccount__c = addressAccount.Id;
			applyBillToAddress(workOrder, addressAccount);
			return;
		}
		workOrder.BillToAddressAccount__c = null;
		if (addressAccount != null) {
			applyBillToAddress(workOrder, addressAccount);
		} else if (internalAccount != null) {
			applyBillToAddress(workOrder, internalAccount);
		}
	}

	/**
	 * @description GW-4162 - Ship-To Address Account and address come from the Internal
	 *              Account primary ship-to, not the Return Order ship-to.
	 * @param workOrder Work Order being created or corrected
	 * @param internalAccountId Account selected on the Internal Repair action
	 */
	private static void applyInternalShipTo(WorkOrder workOrder, Id internalAccountId) {
		if (workOrder == null || internalAccountId == null) {
			return;
		}
		Account shipToAccount = resolvePrimaryShipToAccount(internalAccountId);
		if (isShipToAddressAccountAllowed(shipToAccount, workOrder.AccountId)) {
			workOrder.ShipTo__c = shipToAccount.Id;
			workOrder.ShipToAddressAccount__c = shipToAccount.Id;
			applyShipToAddress(workOrder, shipToAccount);
			return;
		}
		workOrder.ShipTo__c = null;
		workOrder.ShipToAddressAccount__c = null;
		if (shipToAccount != null) {
			applyShipToAddress(workOrder, shipToAccount);
			return;
		}
		Account internalAccount = loadBillingAddress(internalAccountId);
		if (internalAccount != null) {
			applyShipToAddress(workOrder, internalAccount);
		}
	}

	/**
	 * @description Bill-To Address Account lookup requires Type Address, an Active or
	 *              Primary bill-to status, and a parent equal to the Work Order account.
	 * @param addressAccount Candidate address account
	 * @param workOrderAccountId Work Order AccountId
	 * @return True when the account can be saved in BillToAddressAccount__c
	 */
	private static Boolean isBillToAddressAccountAllowed(
		Account addressAccount,
		Id workOrderAccountId
	) {
		if (addressAccount == null || workOrderAccountId == null) {
			return false;
		}
		if (addressAccount.Type != 'Address' || addressAccount.ParentId != workOrderAccountId) {
			return false;
		}
		return addressAccount.BilltoAddressStatus__c == 'Active' ||
			addressAccount.BilltoAddressStatus__c == 'Primary';
	}

	/**
	 * @description Ship-To Address Account requires Type Address, Primary ship-to status,
	 *              and a parent equal to the Work Order account.
	 * @param addressAccount Candidate address account
	 * @param workOrderAccountId Work Order AccountId
	 * @return True when the account can be saved in ShipTo / ShipToAddressAccount
	 */
	private static Boolean isShipToAddressAccountAllowed(
		Account addressAccount,
		Id workOrderAccountId
	) {
		if (addressAccount == null || workOrderAccountId == null) {
			return false;
		}
		if (addressAccount.Type != 'Address' || addressAccount.ParentId != workOrderAccountId) {
			return false;
		}
		return addressAccount.ShiptoAddressStatus__c == 'Primary';
	}

	/**
	 * @description GW-5492 / GW-4162 - Before Save may overwrite customer bill-to / account
	 *              mappings. Restore Internal Repair Account, Ship-To, and Bill-To after insert.
	 * @param workOrders Work Orders just inserted for this receive
	 * @param request Finish Receiving request
	 */
	private static void restoreInternalMappingsAfterCreate(
		List<WorkOrder> workOrders,
		ReceivingService.FinishReceivingRequest request
	) {
		if (
			request == null ||
			request.internalAccountId == null ||
			workOrders == null ||
			workOrders.isEmpty()
		) {
			return;
		}
		List<WorkOrder> updates = new List<WorkOrder>();
		for (WorkOrder workOrder : workOrders) {
			if (workOrder == null || workOrder.Id == null) {
				continue;
			}
			WorkOrder updateRow = new WorkOrder(Id = workOrder.Id);
			updateRow.AccountId = request.internalAccountId;
			applyInternalShipTo(updateRow, request.internalAccountId);
			applyInternalBillTo(updateRow, request.internalAccountId);
			updates.add(updateRow);
		}
		if (updates.isEmpty()) {
			return;
		}
		Database.update(updates, AccessLevel.USER_MODE);
	}

	private static Account loadBillingAddress(Id accountId) {
		if (accountId == null) {
			return null;
		}
		if (!billingAddressByAccountId.containsKey(accountId)) {
			List<Account> accounts = AccountSelector.selectBillingAddressByIds(
				new Set<Id>{ accountId }
			);
			billingAddressByAccountId.put(
				accountId,
				accounts.isEmpty() ? null : accounts[0]
			);
		}
		return billingAddressByAccountId.get(accountId);
	}

	private static void applyBillToAddress(WorkOrder workOrder, Account addressAccount) {
		if (workOrder == null || addressAccount == null) {
			return;
		}
		workOrder.BillToAddress__Street__s = addressAccount.BillingStreet;
		workOrder.BillToAddress__City__s = addressAccount.BillingCity;
		workOrder.BillToAddress__PostalCode__s = addressAccount.BillingPostalCode;
		String stateCode = resolveAddressCode(
			addressAccount.BillingStateCode,
			addressAccount.BillingState
		);
		String countryCode = resolveAddressCode(
			addressAccount.BillingCountryCode,
			addressAccount.BillingCountry
		);
		if (stateCode != null) {
			workOrder.BillToAddress__StateCode__s = stateCode;
		}
		if (countryCode != null) {
			workOrder.BillToAddress__CountryCode__s = countryCode;
		}
	}

	private static void applyShipToAddress(WorkOrder workOrder, Account addressAccount) {
		if (workOrder == null || addressAccount == null) {
			return;
		}
		workOrder.Street = addressAccount.BillingStreet;
		workOrder.City = addressAccount.BillingCity;
		workOrder.PostalCode = addressAccount.BillingPostalCode;
		String stateCode = resolveAddressCode(
			addressAccount.BillingStateCode,
			addressAccount.BillingState
		);
		String countryCode = resolveAddressCode(
			addressAccount.BillingCountryCode,
			addressAccount.BillingCountry
		);
		if (stateCode != null) {
			workOrder.StateCode = stateCode;
		}
		if (countryCode != null) {
			workOrder.CountryCode = countryCode;
		}
	}

	private static String resolveAddressCode(String code, String fallback) {
		String value = String.isNotBlank(code) ? code : fallback;
		if (String.isBlank(value) || value.length() > 3) {
			return null;
		}
		return value;
	}

	/**
	 * @description Resolves the Primary Bill-To Address Account by customer Account Number.
	 *              Cached per transaction — Finish Receiving applies this for parent, child,
	 *              and post-insert restore.
	 * @param customerAccountId RO.AccountId or Internal Account Id
	 * @return Bill-To Account, including currency, or null
	 */
	private static Account resolvePrimaryBillToAccount(Id customerAccountId) {
		if (customerAccountId == null) {
			return null;
		}
		if (primaryBillToByAccountId.containsKey(customerAccountId)) {
			return primaryBillToByAccountId.get(customerAccountId);
		}
		List<Account> customers = AccountSelector.selectAccountNumberByIdForReceiving(
			customerAccountId
		);
		Account resolved;
		if (customers.isEmpty() || String.isBlank(customers[0].AccountNumber)) {
			resolved = null;
		} else {
			List<Account> billToAccounts = AccountSelector.selectPrimaryBillToByAccountNumber(
				customers[0].AccountNumber
			);
			resolved = billToAccounts.isEmpty() ? null : billToAccounts[0];
		}
		primaryBillToByAccountId.put(customerAccountId, resolved);
		return resolved;
	}

	/**
	 * @description GW-4162 - Primary Ship-To Address Account under the Internal Account.
	 *              Cached per transaction for parent/child/restore reuse.
	 * @param parentAccountId Internal Account Id
	 * @return Primary ship-to Address account, or null
	 */
	private static Account resolvePrimaryShipToAccount(Id parentAccountId) {
		if (parentAccountId == null) {
			return null;
		}
		if (primaryShipToByAccountId.containsKey(parentAccountId)) {
			return primaryShipToByAccountId.get(parentAccountId);
		}
		List<Account> shipToAccounts = AccountSelector.selectShipToAddressAccountsByParentId(
			parentAccountId
		);
		Account resolved = null;
		for (Account shipToAccount : shipToAccounts) {
			if (shipToAccount != null && shipToAccount.ShiptoAddressStatus__c == 'Primary') {
				resolved = shipToAccount;
				break;
			}
		}
		primaryShipToByAccountId.put(parentAccountId, resolved);
		return resolved;
	}

	private static void applyDefaultPricebook(WorkOrder workOrder) {
		Id pricebookId = resolveDefaultPricebookId();
		if (pricebookId != null) {
			workOrder.Pricebook2Id = pricebookId;
		}
	}

	/**
	 * @description Repair center work orders use RepairCenterDefaults.PriceList
	 *              (IMS Service Pricebook), not the standard price book.
	 */
	private static Id resolveDefaultPricebookId() {
		if (cachedDefaultPricebookId != null) {
			return cachedDefaultPricebookId;
		}
		RepairCenterDefaults__mdt defaults = RepairCenterDefaults__mdt.getInstance('Default');
		if (defaults == null || String.isBlank(defaults.PriceList__c)) {
			return null;
		}
		List<Pricebook2> pricebooks = PricebooksSelector.selectActiveByName(
			defaults.PriceList__c.trim()
		);
		if (!pricebooks.isEmpty()) {
			cachedDefaultPricebookId = pricebooks[0].Id;
		}
		return cachedDefaultPricebookId;
	}

	private static Id requireWorkOrderRecordType(String developerName) {
		Schema.RecordTypeInfo info = Schema.SObjectType.WorkOrder
			.getRecordTypeInfosByDeveloperName()
			.get(developerName);
		if (info == null || !info.isAvailable()) {
			throw new ReceivingService.ReceivingServiceException(
				'Work Order record type ' + developerName + ' is not available.'
			);
		}
		return info.getRecordTypeId();
	}

	/**
	 * @description GW-5492 - Copies the Return Order Case onto Work Orders after insert.
	 *              A CIO Case also sets Continuous Improvement Opportunity.
	 *              Case is applied after insert so Work Order Created Before Save does not
	 *              replace the line Customer PO with the Case order.
	 *              Elevated DML is required because Repair Technicians often lack sharing on
	 *              Customer Care Cases owned by queue, and USER_MODE CaseId updates fail with
	 *              INSUFFICIENT_ACCESS_ON_CROSS_REFERENCE_ENTITY.
	 * @param workOrders Work Orders created for this receive
	 * @param returnOrder Return Order that owns the Case
	 */
	private static void applyReturnOrderCaseMappings(
		List<WorkOrder> workOrders,
		ReturnOrder returnOrder
	) {
		if (
			workOrders == null ||
			workOrders.isEmpty() ||
			returnOrder == null ||
			returnOrder.CaseId == null
		) {
			return;
		}
		Boolean isCio = returnOrder.Case != null
			&& returnOrder.Case.Category__c == CIO_CATEGORY;
		List<WorkOrder> updates = new List<WorkOrder>();
		for (WorkOrder workOrder : workOrders) {
			if (workOrder == null || workOrder.Id == null) {
				continue;
			}
			WorkOrder updateRow = new WorkOrder(Id = workOrder.Id);
			updateRow.CaseId = returnOrder.CaseId;
			if (isCio) {
				updateRow.ContinuousImprovementOpportunity__c = true;
			}
			updates.add(updateRow);
		}
		if (updates.isEmpty()) {
			return;
		}
		new CaseMappingAccess().updateWorkOrders(updates);
	}

	/**
	 * @description Elevates Finish Receiving CaseId mapping so Repair Technicians can finish
	 *              when the Return Order Case is owned by a Customer Care queue they cannot see.
	 */
	private without sharing class CaseMappingAccess {
		void updateWorkOrders(List<WorkOrder> updates) {
			Database.update(updates, AccessLevel.SYSTEM_MODE);
		}
	}

	/**
	 * @description GW-5492 - Copies Instrument header values onto the parent Work Order.
	 *              Mod Request is true when any line is flagged or a Mod Form file was uploaded.
	 */
	private static void applyInstrumentParentMappings(
		WorkOrder workOrder,
		ReturnOrder returnOrder,
		List<ReturnOrderLineItem> lineItems
	) {
		if (workOrder == null || returnOrder == null) {
			return;
		}
		workOrder.CustomerPO__c = returnOrder.CustomerPO__c;
		workOrder.CustomerReference__c = returnOrder.CustomerReference__c;
		workOrder.RepairWarranty__c = returnOrder.RepairWarranty__c;
		workOrder.WarrantyNotes__c = returnOrder.WarrantyNotes__c;
		workOrder.EstimateContact__c = returnOrder.EstimateContact__c;
		workOrder.PreviousReturnOrder__c = returnOrder.PreviousReturnOrder__c;
		workOrder.ModRequestContact__c = returnOrder.ModRequestContact__c;
		if (lineItems != null) {
			for (ReturnOrderLineItem lineItem : lineItems) {
				if (lineItem.ModRequest__c == true) {
					workOrder.ModRequest__c = true;
					break;
				}
			}
		}
		if (workOrder.ModRequest__c != true && hasModFormFile(returnOrder.Id)) {
			workOrder.ModRequest__c = true;
		}
	}

	/**
	 * @description GW-5492 - True when a Mod Form file is already on the Return Order.
	 */
	private static Boolean hasModFormFile(Id returnOrderId) {
		if (returnOrderId == null) {
			return false;
		}
		for (ContentDocumentLink fileLink :
			ContentDocumentLinksSelector.selectWithVersionDescriptionByLinkedEntityId(returnOrderId)
		) {
			if (
				fileLink.ContentDocument != null &&
				fileLink.ContentDocument.LatestPublishedVersion != null &&
				fileLink.ContentDocument.LatestPublishedVersion.Description ==
					ReceivingService.MOD_FORM_FILE_DESCRIPTION
			) {
				return true;
			}
		}
		return false;
	}

	/**
	 * @description GW-5492 - Links Mod Form files already on the Return Order to the parent Work Order.
	 */
	private static void linkReturnOrderFiles(
		Id returnOrderId,
		Id workOrderId,
		List<Id> alreadyLinkedDocumentIds
	) {
		if (returnOrderId == null || workOrderId == null) {
			return;
		}
		Set<Id> skipIds = new Set<Id>();
		if (alreadyLinkedDocumentIds != null) {
			skipIds.addAll(alreadyLinkedDocumentIds);
		}
		List<Id> documentIds = new List<Id>();
		for (ContentDocumentLink sourceLink :
			ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(returnOrderId)
		) {
			if (
				sourceLink.ContentDocumentId != null
				&& !skipIds.contains(sourceLink.ContentDocumentId)
			) {
				documentIds.add(sourceLink.ContentDocumentId);
			}
		}
		linkPhotos(workOrderId, documentIds);
	}

	/**
	 * @description Images for one Other (Non-Serialized) item: photos from Finish Receiving
	 *              plus files already stored on that line.
	 * @param lineItem Return Order line being received
	 * @param requestDocumentIds Photos staged in Receiving
	 * @return Document Ids to attach to the Vendor Work Order
	 */
	private static List<Id> collectVendorItemImageIds(
		ReturnOrderLineItem lineItem,
		List<Id> requestDocumentIds
	) {
		Set<Id> documentIds = new Set<Id>();
		if (requestDocumentIds != null) {
			documentIds.addAll(requestDocumentIds);
		}
		if (lineItem != null) {
			documentIds.addAll(loadContentDocumentIdsForLine(lineItem.Id));
		}
		documentIds.remove(null);
		return new List<Id>(documentIds);
	}

	private static void linkPhotos(Id workOrderId, List<Id> contentDocumentIds) {
		if (workOrderId == null || contentDocumentIds == null || contentDocumentIds.isEmpty()) {
			return;
		}
		Set<Id> documentIds = new Set<Id>();
		for (Id contentDocumentId : contentDocumentIds) {
			if (contentDocumentId != null) {
				documentIds.add(contentDocumentId);
			}
		}
		if (documentIds.isEmpty()) {
			return;
		}
		for (
			ContentDocumentLink existingLink :
				ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(workOrderId)
		) {
			documentIds.remove(existingLink.ContentDocumentId);
		}
		if (documentIds.isEmpty()) {
			return;
		}
		List<ContentDocumentLink> links = new List<ContentDocumentLink>();
		for (Id contentDocumentId : documentIds) {
			links.add(
				new ContentDocumentLink(
					ContentDocumentId = contentDocumentId,
					LinkedEntityId = workOrderId,
					ShareType = 'V',
					Visibility = 'AllUsers'
				)
			);
		}
		if (!links.isEmpty()) {
			Database.insert(links, AccessLevel.USER_MODE);
		}
	}

	private static void createResiTestHistoryIfNeeded(
		ReceivingService.FinishReceivingRequest request,
		WorkOrdersService.ReceivingWorkOrderCreateResult woResult,
		ReturnOrderLineItem lineItem
	) {
		if (request == null || request.resiTestPerformed != true) {
			return;
		}
		if (woResult == null || woResult.navigationWorkOrderId == null) {
			return;
		}
		ResiTestHistoriesService.createForReceiving(
			woResult.navigationWorkOrderId,
			woResult.productServicedLineItemId,
			request.disinfected
		);
	}

	/**
	 * @description GW-4348 / GW-5996 - After Create Order builds a Serialized Customer RO,
	 *              create parent + child RepairCenterDevices WOs (Receiving mappings) per ROLI.
	 * @param returnOrderId Newly created Return Order Id
	 * @return Created parent Work Order Id and number for confirmation
	 */
	public static ReceivingService.CreateOrderCreatedWorkOrder createWorkOrdersForCreateOrder(
		Id returnOrderId
	) {
		if (returnOrderId == null) {
			throw new ReceivingService.ReceivingServiceException('Return Order is required.');
		}

		List<ReturnOrder> returnOrders = ReturnOrdersSelector.selectForReceivingFinish(returnOrderId);
		if (returnOrders.isEmpty()) {
			throw new ReceivingService.ReceivingServiceException('Return Order was not found.');
		}
		ReturnOrder returnOrder = returnOrders[0];
		if (returnOrder.ReturnOrderType__c != RO_TYPE_SERIALIZED) {
			throw new ReceivingService.ReceivingServiceException(
				'Create Order Work Orders are supported for Serialized Return Orders only.'
			);
		}

		List<ReturnOrderLineItem> lineItems =
			ReturnOrderLineItemsService.getLinesForReceivingFinishByReturnOrderId(returnOrderId);
		if (lineItems.isEmpty()) {
			throw new ReceivingService.ReceivingServiceException(
				'Return Order has no line items to create Work Orders for.'
			);
		}

		Id receiverId = UserInfo.getUserId();
		Datetime receivedDateTime = System.now();
		Id parentWorkOrderId;
		Id firstChildWorkOrderId;

		for (ReturnOrderLineItem lineItem : lineItems) {
			ReceivingService.FinishReceivingRequest request = buildCreateOrderFinishRequest(
				returnOrder.Id,
				lineItem
			);
			String childSubStatus = resolveChildSubStatus(request, RO_TYPE_SERIALIZED);
			Boolean isContaminated = UI_CONTAMINATED.equalsIgnoreCase(request.disinfected);

			WorkOrdersService.ReceivingWorkOrderCreateResult woResult = createSerializedReceive(
				returnOrder,
				lineItem,
				request,
				receiverId,
				childSubStatus,
				isContaminated
			);
			parentWorkOrderId = woResult.parentWorkOrderId;
			if (firstChildWorkOrderId == null) {
				firstChildWorkOrderId = woResult.navigationWorkOrderId;
			}

			ReturnOrderLineItemsService.markLinesReceivedForReceiving(
				new Set<Id>{ lineItem.Id },
				receiverId,
				receivedDateTime,
				1
			);
			linkPhotos(woResult.navigationWorkOrderId, request.contentDocumentIds);

			// Keep the parent id in memory so the next line does not reload the Return Order.
			if (returnOrder.WorkOrder__c == null && woResult.parentWorkOrderId != null) {
				returnOrder.WorkOrder__c = woResult.parentWorkOrderId;
			}
		}

		ReturnOrdersService.syncReceivingWorkOrderCount(returnOrderId);
		ReturnOrdersService.markReturnOrderReceivedIfComplete(returnOrderId);

		Id workOrderId = parentWorkOrderId != null ? parentWorkOrderId : firstChildWorkOrderId;
		ReceivingService.CreateOrderCreatedWorkOrder created =
			new ReceivingService.CreateOrderCreatedWorkOrder();
		created.workOrderId = workOrderId;
		if (workOrderId != null) {
			WorkOrder numbered = WorkOrdersSelector.selectWorkOrderNumberById(workOrderId);
			if (numbered != null) {
				created.workOrderNumber = numbered.WorkOrderNumber;
			}
		}
		return created;
	}

	private static ReceivingService.FinishReceivingRequest buildCreateOrderFinishRequest(
		Id returnOrderId,
		ReturnOrderLineItem lineItem
	) {
		ReceivingService.FinishReceivingRequest request =
			new ReceivingService.FinishReceivingRequest();
		request.returnOrderId = returnOrderId;
		request.lineItemId = lineItem.Id;
		request.receiverId = UserInfo.getUserId();
		request.receivedDateTime = System.now();
		request.assetId = lineItem.AssetId;
		request.product2Id = lineItem.Product2Id;
		request.serialNumber = lineItem.SerialNumber__c;
		request.model = lineItem.Model__c;
		request.quantityReceived = 1;
		request.disinfected = mapRoliDisinfectedToUi(lineItem.Disinfected__c);
		request.contentDocumentIds = loadContentDocumentIdsForLine(lineItem.Id);
		return request;
	}

	private static String mapRoliDisinfectedToUi(String roliValue) {
		if (String.isBlank(roliValue)) {
			return null;
		}
		if (roliValue.containsIgnoreCase('not Disinfected') || roliValue.equalsIgnoreCase('No')) {
			return UI_CONTAMINATED;
		}
		if (roliValue.containsIgnoreCase('is Disinfected') || roliValue.equalsIgnoreCase('Yes')) {
			return 'Clean';
		}
		return roliValue;
	}

	private static List<Id> loadContentDocumentIdsForLine(Id lineItemId) {
		List<Id> documentIds = new List<Id>();
		if (lineItemId == null) {
			return documentIds;
		}
		for (ContentDocumentLink link :
			ContentDocumentLinksSelector.selectByLinkedEntityIdForReceiving(lineItemId)
		) {
			if (link.ContentDocumentId != null) {
				documentIds.add(link.ContentDocumentId);
			}
		}
		return documentIds;
	}

	/**
	 * @description Maps the receiving finish payload to the Work Order Line Item input.
	 * @param request Finish Receiving request from the receiving process
	 * @return Line input, or null when the request is null
	 */
	private static WorkOrderLineItemsService.ReceivingProductServicedInput toReceivingProductServicedInput(
		ReceivingService.FinishReceivingRequest request
	) {
		if (request == null) {
			return null;
		}
		WorkOrderLineItemsService.ReceivingProductServicedInput input =
			new WorkOrderLineItemsService.ReceivingProductServicedInput();
		input.product2Id = request.product2Id;
		input.assetId = request.assetId;
		input.serialNumber = request.serialNumber;
		input.model = request.model;
		input.quantityReceived = request.quantityReceived;
		return input;
	}

	/**
	 * @description Maps finish accessory rows to Work Order Line Item accessory inputs.
	 * @param accessories Accessory rows from the finish request
	 * @return Accessory inputs, or null when the source list is null
	 */
	private static List<WorkOrderLineItemsService.ReceivingAccessoryInput> toReceivingAccessoryInputs(
		List<ReceivingService.FinishAccessoryInput> accessories
	) {
		if (accessories == null) {
			return null;
		}
		List<WorkOrderLineItemsService.ReceivingAccessoryInput> inputs =
			new List<WorkOrderLineItemsService.ReceivingAccessoryInput>();
		for (ReceivingService.FinishAccessoryInput accessory : accessories) {
			if (accessory == null) {
				continue;
			}
			WorkOrderLineItemsService.ReceivingAccessoryInput input =
				new WorkOrderLineItemsService.ReceivingAccessoryInput();
			input.accessoryType = accessory.accessoryType;
			input.storageLocation = accessory.storageLocation;
			input.condition = accessory.condition;
			input.quantity = accessory.quantity;
			inputs.add(input);
		}
		return inputs;
	}

	/**
	 * @description GW-6479 / GW-5677 - Copies the numbered additional-services list onto a Work Order
	 *              when the running user can create the field.
	 * @param workOrder Work Order being inserted
	 * @param returnOrderId Return Order that owns the line items
	 */
	private static void applyAdditionalServicesRequested(WorkOrder workOrder, Id returnOrderId) {
		if (
			workOrder == null ||
			returnOrderId == null ||
			!Schema.SObjectType.WorkOrder.fields.AdditionalServicesRequested__c.isCreateable()
		) {
			return;
		}
		workOrder.AdditionalServicesRequested__c = buildAdditionalServicesRequested(
			ReturnOrderLineItemsSelector.selectAdditionalServicesByReturnOrderId(returnOrderId)
		);
	}

	/**
	 * @description GW-6479 / GW-5677 - Builds one numbered line per Return Order line that requested
	 *              an additional service. Lines with no requested service are omitted.
	 * @param lineItems Return Order lines ordered by line number
	 * @return Concatenated list, or null when nothing was requested
	 */
	@TestVisible
	private static String buildAdditionalServicesRequested(List<ReturnOrderLineItem> lineItems) {
		if (lineItems == null || lineItems.isEmpty()) {
			return null;
		}

		List<String> lines = new List<String>();
		Integer sequence = 1;
		for (ReturnOrderLineItem lineItem : lineItems) {
			if (lineItem == null) {
				continue;
			}
			List<String> segments = buildAdditionalServiceSegments(lineItem);
			if (segments.isEmpty()) {
				continue;
			}
			lines.add(
				sequence +
					'. ' +
					buildAdditionalServiceHeading(lineItem) +
					' - ' +
					String.join(segments, ' | ')
			);
			sequence++;
		}
		if (lines.isEmpty()) {
			return null;
		}
		String requested = String.join(lines, '\n');
		return requested.length() > ADDITIONAL_SERVICES_MAX_LENGTH
			? requested.substring(0, ADDITIONAL_SERVICES_MAX_LENGTH)
			: requested;
	}

	/**
	 * @description GW-6479 / GW-5677 - Line number and item description that precede the service list.
	 * @param lineItem Return Order line
	 * @return Heading text without the trailing dash separator
	 */
	private static String buildAdditionalServiceHeading(ReturnOrderLineItem lineItem) {
		List<String> parts = new List<String>();
		if (String.isNotBlank(lineItem.ReturnOrderLineItemNumber)) {
			parts.add(lineItem.ReturnOrderLineItemNumber.trim());
		}
		if (String.isNotBlank(lineItem.ItemDescription__c)) {
			parts.add(lineItem.ItemDescription__c.trim());
		}
		return String.join(parts, ' ');
	}

	/**
	 * @description GW-6479 / GW-5677 - Service phrases for one Return Order line, in story order.
	 * @param lineItem Return Order line
	 * @return Phrases to join with a pipe
	 */
	private static List<String> buildAdditionalServiceSegments(ReturnOrderLineItem lineItem) {
		List<String> segments = new List<String>();
		if (lineItem.AdditionalServiceRepair__c == true) {
			segments.add('Repair');
		}
		String colorDipping = formatAdditionalServiceValue(lineItem.ColorDipping__c);
		if (colorDipping != null) {
			String colorSegment = 'Color Dipping: ' + colorDipping;
			String numberOfRings = formatAdditionalServiceValue(lineItem.NumberOfRings__c);
			if (numberOfRings != null) {
				colorSegment += ', Number of Rings: ' + numberOfRings;
			}
			segments.add(colorSegment);
		}
		String insulation = formatAdditionalServiceValue(lineItem.InsulationPowderCoating__c);
		if (insulation != null) {
			segments.add('Insulation Powder Coating: ' + insulation);
		}
		String laserMarking = formatAdditionalServiceValue(lineItem.LaserMarking__c);
		if (laserMarking != null) {
			segments.add('Laser Marking: ' + laserMarking);
		}
		String stirrups = formatAdditionalServiceValue(lineItem.LegPositionersStirrup__c);
		if (stirrups != null) {
			segments.add('Stirrups: ' + stirrups);
		}
		return segments;
	}

	/**
	 * @description GW-6479 / GW-5677 - Trims a service value and turns multiselect semicolons into commas.
	 * @param value Field value
	 * @return Display text, or null when the value is blank
	 */
	private static String formatAdditionalServiceValue(String value) {
		if (String.isBlank(value)) {
			return null;
		}
		return value.trim().replace(';', ', ');
	}

}