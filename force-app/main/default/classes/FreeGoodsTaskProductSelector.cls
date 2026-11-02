/**
 * @author PWC Developer
 * @date 2026/08/18
 *
 * @group Free Good Task
 *
 * @description
 * GC-3230 - SOQL selector for Free Goods Task Product records linked to a standard Task through TaskId__c.
 */
public with sharing class FreeGoodsTaskProductSelector {

    /**
     * @description
     * GC-3230 - Returns Free Goods Task Product rows for the given Task Id, including the related
     * Product and Account display fields used on the Task record page.
     *
     * @param taskId 18 digit Id of the standard Task.
     * @return Matching Free_Goods_Task_Product__c rows ordered by CreatedDate.
     *
     * @example
     * FreeGoodsTaskProductSelector.selectByTaskId(taskId);
     */
    public static List<Free_Goods_Task_Product__c> selectByTaskId(String taskId) {
        if (String.isBlank(taskId)) {
            return new List<Free_Goods_Task_Product__c>();
        }

        String taskId18 = String.valueOf(Id.valueOf(taskId));

        return [
            SELECT TaskId__c,
                   Quantity__c,
                   SalesPrice__c,
                   LineDescription__c,
                   ConsumptionFrequency__c,
                   Status__c,
                   ConfidenceLevel__c,
                   ExpectedShipDateConsumptionStart__c,
                   Contract__c,
                   Comments__c,
                   Product__c,
                   Product__r.Name,
                   Product__r.ProductCode,
                   Account__c,
                   Account__r.Name,
                   CreatedDate,
                   CreatedBy.Name
            FROM Free_Goods_Task_Product__c
            WHERE TaskId__c = :taskId18
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
        ];
    }
}