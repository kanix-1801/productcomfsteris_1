/**
 * @author Sahithi PWC
 * @date 07-24-2026
 *
 * @group Enterprise Pipeline
 *
 * @description
 * Aura/LWC-facing entry point for the Enterprise Pipeline Roll-up component on
 * IDN and GPO Account record pages.
 */
public with sharing class EnterprisePipelineController {

    /**
     * @description Returns consolidated enterprise pipeline data for the Account record page.
     * @param accountId Account record Id from the record page.
     * @return EnterprisePipelineService.PipelineSummary roll-up data.
     */
    @AuraEnabled(cacheable=true)
    public static EnterprisePipelineService.PipelineSummary getEnterprisePipeline(Id accountId) {
        try {
            return EnterprisePipelineService.getPipelineRollup(accountId);
        } catch (Exception e) {
            ErrorLogger.logException(e, 'EnterprisePipelineController', 'getEnterprisePipeline');
            throw new AuraHandledException('Unable to load the enterprise pipeline roll-up.');
        }
    }
}