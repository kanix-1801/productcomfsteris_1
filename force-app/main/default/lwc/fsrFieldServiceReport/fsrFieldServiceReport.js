import { LightningElement, api, wire } from 'lwc';
import { gql, graphql } from 'lightning/uiGraphQLApi';

// GW-1900: Field Service Report for Field Service Document Builder (lightning__ServiceDocument).
// Must work offline on the FSL mobile app, so all data comes from LDS GraphQL (no Apex).

const LABOR_TYPES = ['Labor', 'Travel'];
const EXPENSE_TYPES = ['Expense'];
const PART_TYPES = ['Parts', 'Part'];
const CHARGE_TYPES = [...LABOR_TYPES, ...EXPENSE_TYPES, ...PART_TYPES];
// Calibration lines hold the tool used (AssetId = calibration tool), see ServiceAppointment_MobileFlow_ReportCalibration.
const TOOL_TYPES = ['Calibration'];
const PROFORMA = 'Proforma Invoice';

const FSR_QUERY = gql`
    query GetFieldServiceReport($workOrderId: ID) {
        uiapi {
            query {
                WorkOrder(where: { Id: { eq: $workOrderId } }, first: 1) {
                    edges {
                        node {
                            Id
                            WorkOrderNumber { value }
                            CreatedDate { value }
                            CompletedTimestamp__c { value }
                            CurrencyIsoCode { value }
                            ServiceReportLanguage { value }
                            MaskPrices__c { value }
                            FSRDocumentType__c { value displayValue }
                            WorkOrderType__c { value displayValue }
                            PerceivedServiceNeed__c { value }
                            ResolutionDescription__c { value }
                            CustomerPO__c { value }
                            AssetUDI__c { value }
                            PhysicalLocation__c { value }
                            Street { value }
                            City { value }
                            State { value }
                            PostalCode { value }
                            RegionalControl__r {
                                FSRHeader__c { value }
                            }
                            Asset {
                                SerialNumber { value }
                                ControlNumber__c { value }
                                CustomerAssetNumber__c { value }
                                Product2 {
                                    Name { value }
                                }
                            }
                            Case {
                                Project__r {
                                    Name { value }
                                }
                            }
                            Contact {
                                Name { value }
                            }
                            BillTo__r {
                                AccountNumber { value }
                                Name { value }
                                BillingStreet { value }
                            }
                            ShipTo__r {
                                AccountNumber { value }
                                Name { value }
                            }
                        }
                    }
                }
                WorkOrderLineItem(
                    where: {
                        WorkOrderId: { eq: $workOrderId }
                        LineType__c: { in: ["Labor", "Travel", "Expense", "Parts", "Tool"] }
                    }
                    orderBy: { LineItemNumber: { order: ASC } }
                    first: 200
                ) {
                    edges {
                        node {
                            Id
                            LineType__c { value displayValue }
                            ExpenseType__c { value displayValue }
                            BillingType__c { value displayValue }
                            ProductCode__c { value }
                            ProductDescription__c { value }
                            StartDate { value }
                            Quantity { value }
                            UnitQty__c { value }
                            UnitPrice { value }
                            UnitPrice__c { value }
                            TotalPrice { value }
                            TotalPrice__c { value }
                            AssignedResource__r {
                                Name { value }
                            }
                            Asset {
                                Name { value }
                                SerialNumber { value }
                                CalibrationDueDate__c { value }
                            }
                        }
                    }
                }
            }
        }
    }
`;

const val = (field) => field?.value ?? null;
const display = (field) => field?.displayValue ?? field?.value ?? '';

// Labor/Travel lines carry custom price fields (standard UnitPrice needs a Product); Expense/Parts use standard.
const firstNumber = (...fields) => {
    for (const f of fields) {
        const v = val(f);
        if (v !== null && v !== undefined) return Number(v);
    }
    return null;
};

// TODO GW-1900: temporary fallback for test lines saved without LineType__c; remove before release.
// Guesses the type from the other fields: expense type -> Expense, part description/code -> Parts,
// work date -> Labor, no price -> Calibration (tool), anything else priced -> Labor.
const lineTypeOf = (line) => {
    const lineType = val(line.LineType__c);
    if (lineType) return lineType;
    if (val(line.ExpenseType__c)) return 'Expense';
    if (val(line.ProductDescription__c) || val(line.ProductCode__c)) return 'Parts';
    if (firstNumber(line.UnitPrice__c, line.UnitPrice) === null) return 'Calibration';
    return 'Labor';
};

export default class FsrFieldServiceReport extends LightningElement {
    @api recordId;
    @api revision = 'Rev 26.0';
    @api formNumber = 'RSR033';
    @api fsrFooter = 'This is only an estimate and not an invoice. Tax is not included.';
    @api proformaFooter = '';

    workOrder;
    lines = [];
    errorMessage;

    get queryVariables() {
        if (!this.recordId) return undefined;
        return { workOrderId: this.recordId };
    }

    @wire(graphql, { query: FSR_QUERY, variables: '$queryVariables' })
    wiredReport({ data, errors }) {
        if (errors) {
            this.errorMessage = errors.map((e) => e.message).join('; ');
            return;
        }
        if (!data) return;
        this.errorMessage = undefined;
        this.workOrder = data.uiapi.query.WorkOrder.edges[0]?.node;
        this.lines = (data.uiapi.query.WorkOrderLineItem?.edges ?? []).map((e) => e.node);
    }

    // ---------- Locale / formatting ----------

    get locale() {
        return (val(this.workOrder?.ServiceReportLanguage) || 'en_GB').replace('_', '-');
    }

    formatDate(isoValue) {
        if (!isoValue) return '';
        return new Intl.DateTimeFormat(this.locale, { day: '2-digit', month: '2-digit', year: 'numeric' }).format(
            new Date(isoValue)
        );
    }

    formatMoney(amount) {
        if (amount === null || amount === undefined) return '';
        return new Intl.NumberFormat(this.locale, {
            style: 'currency',
            currency: val(this.workOrder?.CurrencyIsoCode) || 'GBP'
        }).format(amount);
    }

    // DD-MON-YYYY, month abbreviation in the report language
    get reportDate() {
        const now = new Date();
        const day = String(now.getDate()).padStart(2, '0');
        const month = new Intl.DateTimeFormat(this.locale, { month: 'short' })
            .format(now)
            .replace('.', '')
            .toUpperCase();
        return `${day}-${month}-${now.getFullYear()}`;
    }

    // ---------- Header / document type ----------

    get isLoaded() {
        return !!this.workOrder;
    }

    get headerHtml() {
        return val(this.workOrder?.RegionalControl__r?.FSRHeader__c) || '';
    }

    get isProforma() {
        return val(this.workOrder?.FSRDocumentType__c) === PROFORMA;
    }

    get documentTitle() {
        return display(this.workOrder?.FSRDocumentType__c) || 'Field Service Report';
    }

    get footerText() {
        return this.isProforma ? this.proformaFooter : this.fsrFooter;
    }

    // Proforma Invoice never masks; a blank checkbox is treated as masked (new WOs start masked).
    get showPrices() {
        if (this.isProforma) return true;
        return val(this.workOrder?.MaskPrices__c) === false;
    }

    get pricesHidden() {
        return !this.showPrices;
    }

    // ---------- Customer details ----------

    get equipment() {
        const wo = this.workOrder;
        return [
            { key: 'serial', label: 'Serial#:', value: val(wo?.Asset?.SerialNumber) },
            { key: 'udi', label: 'UDI:', value: val(wo?.AssetUDI__c) },
            { key: 'product', label: 'Product:', value: val(wo?.Asset?.Product2?.Name) },
            { key: 'location', label: 'Location:', value: val(wo?.PhysicalLocation__c) },
            { key: 'control', label: 'Control#:', value: val(wo?.Asset?.ControlNumber__c) },
            { key: 'asset', label: 'Asset#:', value: val(wo?.Asset?.CustomerAssetNumber__c) },
            { key: 'project', label: 'Project#:', value: val(wo?.Case?.Project__r?.Name) }
        ];
    }

    get billing() {
        const bill = this.workOrder?.BillTo__r;
        return [
            { key: 'customer', label: 'Customer#:', value: val(bill?.AccountNumber) },
            { key: 'name', label: 'Name:', value: val(bill?.Name) },
            { key: 'address', label: 'Address:', value: val(bill?.BillingStreet) },
            // Account.PaymentTerms__c (fed from Oracle) does not exist yet; add it to the query once built.
            { key: 'terms', label: 'Payment Terms:', value: '' },
            { key: 'po', label: 'PO#:', value: val(this.workOrder?.CustomerPO__c) }
        ];
    }

    get shipping() {
        const wo = this.workOrder;
        return [
            { key: 'customer', label: 'Customer#:', value: val(wo?.ShipTo__r?.AccountNumber) },
            { key: 'name', label: 'Name:', value: val(wo?.ShipTo__r?.Name) },
            { key: 'address', label: 'Address:', value: val(wo?.Street) },
            { key: 'city', label: 'City:', value: val(wo?.City) },
            { key: 'state', label: 'State/Prov:', value: val(wo?.State) },
            { key: 'postal', label: 'Postal:', value: val(wo?.PostalCode) }
        ];
    }

    // ---------- Record ----------

    get serviceRequestNumber() {
        return val(this.workOrder?.WorkOrderNumber);
    }

    get dateOpened() {
        return this.formatDate(val(this.workOrder?.CreatedDate));
    }

    get dateClosed() {
        return this.formatDate(val(this.workOrder?.CompletedTimestamp__c));
    }

    get contactName() {
        return val(this.workOrder?.Contact?.Name);
    }

    get serviceNeeded() {
        return val(this.workOrder?.PerceivedServiceNeed__c);
    }

    get resolutionDescription() {
        return val(this.workOrder?.ResolutionDescription__c);
    }

    // No source field yet (TBD in GW-1900); the row prints so the layout matches the form.
    get unitCondition() {
        return '';
    }

    // ---------- Service charges ----------

    mapLine(line) {
        const qty = firstNumber(line.UnitQty__c, line.Quantity);
        const unitPrice = firstNumber(line.UnitPrice__c, line.UnitPrice);
        let total = firstNumber(line.TotalPrice__c, line.TotalPrice);
        if (total === null && qty !== null && unitPrice !== null) total = qty * unitPrice;
        return {
            id: line.Id,
            lineType: lineTypeOf(line),
            lineTypeLabel: display(line.LineType__c) || lineTypeOf(line),
            techName: val(line.AssignedResource__r?.Name),
            workDate: this.formatDate(val(line.StartDate)),
            type: display(this.workOrder?.WorkOrderType__c),
            comments: display(line.ExpenseType__c),
            item: val(line.ProductCode__c),
            description: val(line.ProductDescription__c),
            // Charge Reason values (T&M, N/C Quoted Price) have no source field yet; BillingType__c is the interim source.
            chargeReason: display(line.BillingType__c),
            qty: qty ?? '',
            total: total ?? 0,
            unitPriceText: this.formatMoney(unitPrice),
            totalText: this.formatMoney(total)
        };
    }

    get mappedLines() {
        return this.lines.filter((l) => CHARGE_TYPES.includes(lineTypeOf(l))).map((l) => this.mapLine(l));
    }

    get toolLines() {
        return this.lines
            .filter((l) => TOOL_TYPES.includes(lineTypeOf(l)))
            .map((l) => ({
                id: l.Id,
                techName: val(l.AssignedResource__r?.Name),
                tool: val(l.Asset?.Name),
                serialNumber: val(l.Asset?.SerialNumber),
                calibrationDue: this.formatDate(val(l.Asset?.CalibrationDueDate__c))
            }));
    }

    get noToolLines() {
        return this.toolLines.length === 0;
    }

    get laborLines() {
        return this.mappedLines.filter((l) => LABOR_TYPES.includes(l.lineType));
    }

    get expenseLines() {
        return this.mappedLines.filter((l) => EXPENSE_TYPES.includes(l.lineType));
    }

    get partLines() {
        return this.mappedLines.filter((l) => PART_TYPES.includes(l.lineType));
    }

    get noLaborLines() {
        return this.laborLines.length === 0;
    }

    get noExpenseLines() {
        return this.expenseLines.length === 0;
    }

    get noPartLines() {
        return this.partLines.length === 0;
    }

    // Column counts for the "None" row; the two price columns drop out when masked.
    get priceColumns() {
        return this.showPrices ? 2 : 0;
    }

    get laborColspan() {
        return 6 + this.priceColumns;
    }

    get expenseColspan() {
        return 5 + this.priceColumns;
    }

    get partColspan() {
        return 6 + this.priceColumns;
    }

    // Summed from the printed lines: WO.TotalPrice does not include the custom-priced Labor/Travel lines.
    get grandTotal() {
        const sum = this.mappedLines.reduce((acc, l) => acc + l.total, 0);
        return this.formatMoney(sum);
    }

    get partsConsumedQty() {
        return this.partLines.reduce((acc, l) => acc + (Number(l.qty) || 0), 0);
    }
}