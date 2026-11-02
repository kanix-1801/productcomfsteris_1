/**
 * @author Uptima
 * @date 2026-09-21
 * @group Repair Center
 * @description Service for NonconformanceReportLineItem__c operations.
 */
public with sharing class NonconformanceReportLineItemsService {
    /** @description Returns NCR lines for header Ids. */
    public static List<NonconformanceReportLineItem__c> getByReportIds(Set<Id> reportIds) {
        return NonconformanceReportLineItemsSelector.selectByReportIds(reportIds);
    }

    /** @description Creates an NCR line in user mode. */
    public static NonconformanceReportLineItem__c createLine(
        NonconformanceReportLineItem__c line
    ) {
        if (line == null) {
            throw new NonconformanceReportLineItemsServiceException('NCR Line is required.');
        }
        try {
            Database.insert(line, AccessLevel.USER_MODE);
            return line;
        } catch (DmlException exceptionValue) {
            Logger.error('NonconformanceReportLineItemsService.createLine failed.', exceptionValue);
            throw new NonconformanceReportLineItemsServiceException(
                'Unable to create NCR Line: ' + exceptionValue.getDmlMessage(0),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /** @description Updates an NCR line in user mode. */
    public static void updateLine(NonconformanceReportLineItem__c line) {
        if (line == null || line.Id == null) {
            throw new NonconformanceReportLineItemsServiceException('NCR Line Id is required.');
        }
        try {
            Database.update(line, AccessLevel.USER_MODE);
        } catch (DmlException exceptionValue) {
            Logger.error('NonconformanceReportLineItemsService.updateLine failed.', exceptionValue);
            throw new NonconformanceReportLineItemsServiceException(
                'Unable to update NCR Line: ' + exceptionValue.getDmlMessage(0),
                exceptionValue
            );
        } finally {
            Logger.saveLog();
        }
    }

    /** @description NCR line service exception. */
    public class NonconformanceReportLineItemsServiceException extends Exception {}
}