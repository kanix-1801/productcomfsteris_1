/**
 * @description GW-5892: Rate List option builders shared by Field Service components.
 *              Same rules as woDebriefES _buildTravelTypeOptionsFromRateList / _buildLaborRateOptionsFromRateList
 *              (GW-2967): an option is offered only when the Rate List has an amount for it.
 *              rateList is the WoDebriefRateListController.RateListPrices DTO.
 */
export const TRAVEL_TYPE_ACTUAL = 'Actual Travel';

export const RATE_OPTIONS = [
    { label: 'Standard', value: 'Standard' },
    { label: 'Overtime', value: 'Overtime' },
    { label: 'Premium', value: 'Premium' }
];

/**
 * @description True when a Rate List amount is populated (0 counts as populated).
 * @param {*} amount Rate List amount
 * @return {boolean}
 */
export function isPopulatedRateAmount(amount) {
    return amount !== null && amount !== undefined && amount !== '';
}

/**
 * @description Travel Type options from populated Rate List fields; Actual Travel first.
 * @param {object} rateList Rate List prices
 * @return {{label: string, value: string, amount: number}[]}
 */
export function buildTravelTypeOptionsFromRateList(rateList) {
    const options = [];
    if (!rateList) {
        return options;
    }
    if (isPopulatedRateAmount(rateList.travelHour)) {
        options.push({ label: TRAVEL_TYPE_ACTUAL, value: TRAVEL_TYPE_ACTUAL, amount: rateList.travelHour });
    }
    const zones = [
        { value: 'Travel Zone 1', amount: rateList.travelZone1 },
        { value: 'Travel Zone 2', amount: rateList.travelZone2 },
        { value: 'Travel Zone 3', amount: rateList.travelZone3 },
        { value: 'Travel Zone 4', amount: rateList.travelZone4 }
    ];
    for (const zone of zones) {
        if (isPopulatedRateAmount(zone.amount)) {
            options.push({ label: zone.value, value: zone.value, amount: zone.amount });
        }
    }
    return options;
}

/**
 * @description Labor Rate options from populated Rate List fields.
 * @param {object} rateList Rate List prices
 * @return {{label: string, value: string, amount: number}[]}
 */
export function buildLaborRateOptionsFromRateList(rateList) {
    if (!rateList) {
        return [];
    }
    const options = [];
    if (isPopulatedRateAmount(rateList.laborHour)) {
        options.push({ label: 'Standard', value: 'Standard', amount: rateList.laborHour });
    }
    if (isPopulatedRateAmount(rateList.premiumRateHour)) {
        options.push({ label: 'Premium', value: 'Premium', amount: rateList.premiumRateHour });
    }
    if (isPopulatedRateAmount(rateList.extendedOvertimeRatePerHour)) {
        options.push({ label: 'Overtime', value: 'Overtime', amount: rateList.extendedOvertimeRatePerHour });
    }
    return options;
}

/**
 * @description Default Travel Type: Actual Travel when on the Rate List, else the first zone.
 * @param {object} rateList Rate List prices
 * @return {string}
 */
export function defaultTravelType(rateList) {
    if (isPopulatedRateAmount(rateList?.travelHour)) {
        return TRAVEL_TYPE_ACTUAL;
    }
    return buildTravelTypeOptionsFromRateList(rateList)[0]?.value ?? '';
}