/*poc class* shiv*/
public class EmailMessageRelationHelper {

    @future
    public static void nullifyRelationId(Set<Id> emailMessageIds) {
        List<EmailMessageRelation> relationsToUpdate = [
            SELECT Id, RelationId
            FROM EmailMessageRelation
            WHERE EmailMessageId IN :emailMessageIds
        ];

        if (relationsToUpdate.isEmpty()) return;

        for (EmailMessageRelation emr : relationsToUpdate) {
            emr.RelationId = null;
        }

        update relationsToUpdate;
    }
}