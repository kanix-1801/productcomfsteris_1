/**
 * @author Oskay Taskin
 * @date 2026/07/10
 * @description GW-3918: Service class for WorkOrder business orchestration.
 */
public with sharing class WorkOrderService {
    
    /**
     * @description Calculates Scheduled Ship Date from Flow
     * @param inputWorkOrderList List of Work Orders passed from Flow
     */
    @InvocableMethod(label='Calculate Scheduled Ship Date' description='Calculates ship date factoring Turn Time, timezone, and holidays')
    public static void calculateScheduledShipDate(List<WorkOrder> inputWorkOrderList) {

        try {
            Set<Id> workOrderIdSet = new Set<Id>();
            for(WorkOrder wo : inputWorkOrderList) {
                if(wo.Id != null) {
                    workOrderIdSet.add(wo.Id);
                }
            }
            
            List<WorkOrder> queriedWorkOrderList = WorkOrderSelector.selectWorkOrdersWithOperatingHours(workOrderIdSet);
            if (queriedWorkOrderList.isEmpty()) {
                return;
            }

            Map<Id, WorkOrder> queriedWorkOrderMap = new Map<Id, WorkOrder>(queriedWorkOrderList);
            Set<Id> operatingHoursIdSet = new Set<Id>();
            
            for (WorkOrder wo : queriedWorkOrderList) {
                if (wo.RepairCenter__r?.OperatingHours__c != null) {
                    operatingHoursIdSet.add(wo.RepairCenter__r.OperatingHours__c);
                }
            }

            List<OperatingHoursHoliday> holidayList = WorkOrderSelector.selectOperatingHoursHolidays(operatingHoursIdSet);
            Map<Id, Set<Date>> holidayDatesByOperatingHoursIdMap = new Map<Id, Set<Date>>();
            
            for (OperatingHoursHoliday ohh : holidayList) {
                if (!holidayDatesByOperatingHoursIdMap.containsKey(ohh.OperatingHoursId)) {
                    holidayDatesByOperatingHoursIdMap.put(ohh.OperatingHoursId, new Set<Date>());
                }
                if (ohh.Holiday?.ActivityDate != null) {
                    holidayDatesByOperatingHoursIdMap.get(ohh.OperatingHoursId).add(ohh.Holiday.ActivityDate);
                }
            }

            List<WorkOrder> workOrdersToUpdateList = new List<WorkOrder>();

            for (WorkOrder flowWo : inputWorkOrderList) {
                WorkOrder queriedWo = queriedWorkOrderMap.get(flowWo.Id);
                if (queriedWo == null) {
                    continue;
                }
                
                String timeZoneStr = queriedWo.RepairCenter__r?.OperatingHours__r?.TimeZone;
                if (String.isBlank(timeZoneStr) || flowWo.TurnTime__c == null) {
                    continue; 
                }

                Datetime referenceTime = flowWo.DateReadyforRepair__c != null ? flowWo.DateReadyforRepair__c : System.now();
                
                // Parse hour and date strictly in the Location's Timezone
                Integer hourOfDay = Integer.valueOf(referenceTime.format('H', timeZoneStr));
                Date currentDate = Date.valueOf(referenceTime.format('yyyy-MM-dd', timeZoneStr));
                
                // If it is 10:00 AM or later, base start date pushes to tomorrow
                if (hourOfDay >= 10) {
                    currentDate = currentDate.addDays(1);
                }

                Set<Date> centerHolidayDateSet = holidayDatesByOperatingHoursIdMap.containsKey(queriedWo.RepairCenter__r.OperatingHours__c) 
                    ? holidayDatesByOperatingHoursIdMap.get(queriedWo.RepairCenter__r.OperatingHours__c) 
                    : new Set<Date>();

                // Ensure the base start date is not a weekend or holiday
                while (true) {
                    Datetime dtFormat = Datetime.newInstance(currentDate, Time.newInstance(12, 0, 0, 0));
                    String dayOfWeek = dtFormat.format('E');
                    if (dayOfWeek == 'Sat' || dayOfWeek == 'Sun' || centerHolidayDateSet.contains(currentDate)) {
                        currentDate = currentDate.addDays(1);
                    } else {
                        break; 
                    }
                }

                // Calculate using the fresh Turn Time from the Flow (Which already includes aeration days via GW-3459)
                Integer turnTimeDays = Integer.valueOf(flowWo.TurnTime__c);

                Integer daysToAdd = turnTimeDays > 0 ? turnTimeDays - 1 : 0;
                Integer daysAdded = 0;
                
                while (daysAdded < daysToAdd) {
                    currentDate = currentDate.addDays(1);
                    Datetime dtFormat = Datetime.newInstance(currentDate, Time.newInstance(12, 0, 0, 0));
                    String dayOfWeek = dtFormat.format('E');
                    
                    if (dayOfWeek != 'Sat' && dayOfWeek != 'Sun' && !centerHolidayDateSet.contains(currentDate)) {
                        daysAdded++;
                    }
                }

                // Construct a new record instance for update 
                workOrdersToUpdateList.add(new WorkOrder(
                    Id = flowWo.Id,
                    ScheduledShipDate__c = currentDate
                ));
            }

            if (!workOrdersToUpdateList.isEmpty()) {
                update workOrdersToUpdateList;
            }

        } catch (Exception e) {
            Logger.error('Error calculating Scheduled Ship Date: ' + e.getMessage());
        } finally {
            Logger.saveLog();
        }
    }
}