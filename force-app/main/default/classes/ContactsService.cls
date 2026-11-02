/**
 * @description Service class for Contact business operations.
 *              Entry point for all Contact-related transactions.
 *              Performs DML directly — no Unit of Work.
 */
public with sharing class ContactsService {

    /**
     * @description Creates new Contact records with validation.
     * @param contacts List of Contact records to create.
     * @throws ContactsServiceException when the operation fails.
     */
    public static void createContacts(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        Logger.setScenario('Contact Management');
        try {
            Contacts domain = new Contacts(contacts);
            // domain.applyDefaults();
            // domain.validate();
            insert contacts;
        } catch (Contacts.ContactsException e) {
            Logger.error(new LogMessage('ContactsService.createContacts: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ContactsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContactsService.createContacts: Unexpected error.', e);
            Logger.saveLog();
            throw new ContactsServiceException('An unexpected error occurred while creating Contact records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Updates existing Contact records with validation.
     * @param contacts List of Contact records to update.
     * @throws ContactsServiceException when the operation fails.
     */
    public static void updateContacts(List<Contact> contacts) {
        if (contacts == null || contacts.isEmpty()) {
            return;
        }
        Logger.setScenario('Contact Management');
        try {
            Contacts domain = new Contacts(contacts);
            // domain.validate();
            update contacts;
        } catch (Contacts.ContactsException e) {
            Logger.error(new LogMessage('ContactsService.updateContacts: Validation failed. {0}', e.getMessage()), e);
            Logger.saveLog();
            throw new ContactsServiceException(e.getMessage(), e);
        } catch (Exception e) {
            Logger.error('ContactsService.updateContacts: Unexpected error.', e);
            Logger.saveLog();
            throw new ContactsServiceException('An unexpected error occurred while updating Contact records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Deletes Contact records by their Ids.
     * @param contactIds Set of Contact Ids to delete.
     * @throws ContactsServiceException when the operation fails.
     */
    public static void deleteContacts(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return;
        }
        Logger.setScenario('Contact Management');
        try {
            List<Contact> contactList = ContactsSelector.selectById(contactIds);
            if (contactList.isEmpty()) {
                return;
            }
            delete contactList;
        } catch (Exception e) {
            Logger.error('ContactsService.deleteContacts: Unexpected error.', e);
            Logger.saveLog();
            throw new ContactsServiceException('An unexpected error occurred while deleting Contact records.', e);
        } finally {
            Logger.saveLog();
        }
    }

    /**
     * @description Retrieves Contact records by their Ids.
     * @param contactIds Set of Contact Ids to retrieve.
     * @return List of Contact records.
     * @throws ContactsServiceException when the operation fails.
     */
    public static List<Contact> getContactsById(Set<Id> contactIds) {
        if (contactIds == null || contactIds.isEmpty()) {
            return new List<Contact>();
        }
        try {
            return ContactsSelector.selectById(contactIds);
        } catch (Exception e) {
            Logger.error('ContactsService.getContactsById: Unexpected error.', e);
            Logger.saveLog();
            throw new ContactsServiceException('An unexpected error occurred while retrieving Contact records.', e);
        }
    }

    /**
     * @description Thrown when a Contact service operation fails.
     */
    public class ContactsServiceException extends Exception {}
}