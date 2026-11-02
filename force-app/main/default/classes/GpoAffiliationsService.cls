public without sharing class GpoAffiliationsService {
    private static final String SCENARIO = 'GPO Affiliations';
    private static final String USER_ERROR_MESSAGE = 'Unable to load GPO Affiliations.';

    @TestVisible
    private static Boolean throwExceptionForTest = false;

    public static List<GpoAffiliationDTO> getGpoAffiliations(Id accountId) {
        List<GpoAffiliationDTO> gpoAffiliationList = new List<GpoAffiliationDTO>();
        Boolean shouldSaveLog = false;
        if (accountId == null) {
            return gpoAffiliationList;
        }

        try{

            if (throwExceptionForTest) {
                throw new QueryException('Forced exception for unit test.');
            }
            for (
            AccountAccountRelation accountAccountRelation :
            GpoAffiliationsSelector.getAccountAccountRelationsByRelatedAccountId(accountId)
        ) {
            gpoAffiliationList.add(new GpoAffiliationDTO(accountAccountRelation));
        }

        }
        catch (Exception exceptionRecord) {
            shouldSaveLog = true;

            Logger.setScenario(SCENARIO);
            Logger.error(
                'Unable to retrieve GPO Affiliations. Error: ' +
                exceptionRecord.getMessage()
            )
                .addTag('GPO Affiliation')
                .setRecord(new Account(Id = accountId));

            throw new GpoAffiliationsException(USER_ERROR_MESSAGE);
        } finally {
            if (shouldSaveLog) {
                Logger.saveLog();
            }
        }
        return gpoAffiliationList;
    }

    public class GpoAffiliationsException extends Exception {
    }
}