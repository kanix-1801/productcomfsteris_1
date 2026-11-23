import { LightningElement, api } from "lwc";
import getCurrentWorkOrderSummaries from "@salesforce/apex/CurrentWorkOrderStatusController.getCurrentWorkOrderSummaries";

const RECORD_TYPE_DEVICES = "RepairCenterDevices";
const RECORD_TYPE_INSTRUMENTS = "RepairCenterInstruments";

/**
 * GW-5310 - Lists current Device and Instrument Repair Center Work Orders.
 */
export default class CurrentDeviceInstrumentWorkOrders extends LightningElement {
  /**
   * GW-5310 - When true, shows Return to Actions Menu and notifies the parent.
   */
  @api showReturnToMenu = false;

  workOrders = [];
  errorMessage = "";
  isBusy = false;

  /**
   * GW-5310 - Loads the summary when the coordinator opens this screen.
   */
  connectedCallback() {
    this.loadWorkOrders();
  }

  /**
   * GW-5310 - Device rows for the summary table.
   */
  get deviceRows() {
    return this.rowsForRecordType(RECORD_TYPE_DEVICES);
  }

  /**
   * GW-5310 - Instrument rows for the summary table.
   */
  get instrumentRows() {
    return this.rowsForRecordType(RECORD_TYPE_INSTRUMENTS);
  }

  /**
   * GW-5310 - True when at least one Device Work Order is current.
   */
  get hasDeviceRows() {
    return this.deviceRows.length > 0;
  }

  /**
   * GW-5310 - True when at least one Instrument Work Order is current.
   */
  get hasInstrumentRows() {
    return this.instrumentRows.length > 0;
  }

  /**
   * GW-5310 - Queries open Device and Instrument Work Orders.
   */
  async loadWorkOrders() {
    this.isBusy = true;
    this.errorMessage = "";
    try {
      this.workOrders = (await getCurrentWorkOrderSummaries()) || [];
    } catch (error) {
      this.workOrders = [];
      this.errorMessage = this.reduceError(error);
    } finally {
      this.isBusy = false;
    }
  }

  /**
   * GW-5310 - Tells Repair Coordinator Actions to return to the menu.
   */
  handleReturnToMenu() {
    this.dispatchEvent(new CustomEvent("returntomenu"));
  }

  /**
   * GW-5310 - Maps one record type to table rows with number and status.
   * @param {string} developerName Work Order record type developer name
   * @return {object[]} rows for that record type
   */
  rowsForRecordType(developerName) {
    return (this.workOrders || [])
      .filter(
        (workOrder) => workOrder?.RecordType?.DeveloperName === developerName
      )
      .map((workOrder) => ({
        id: workOrder.Id,
        workOrderNumber: workOrder.WorkOrderNumber,
        status: workOrder.Status
      }));
  }

  /**
   * GW-5310 - Normalizes Lightning/Apex errors for inline display.
   * @param {object} error Lightning error payload
   * @return {string} user-facing error message
   */
  reduceError(error) {
    if (Array.isArray(error?.body)) {
      return error.body.map((entry) => entry.message).join(", ");
    }
    return (
      error?.body?.message || error?.message || "An unexpected error occurred."
    );
  }
}