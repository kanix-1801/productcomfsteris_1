trigger ContactDuplicatePrevention on Contact (before insert, before update) {

    // Exclude current records when updating (so we don't match against itself)
    Set<Id> excludeIds = Trigger.isUpdate ? Trigger.newMap.keySet() : new Set<Id>();

    Map<String, List<Contact>> keyToIncoming = new Map<String, List<Contact>>();
    Set<String> emails = new Set<String>();

    // Build incoming keys
    for (Contact c : Trigger.new) {
        if (String.isBlank(c.FirstName) || String.isBlank(c.LastName) || String.isBlank(c.Email)) {
            continue;
        }

        String first  = c.FirstName  == null ? '' : c.FirstName.replace('\u00A0',' ').trim().toLowerCase();
        String middle = c.MiddleName == null ? '' : c.MiddleName.replace('\u00A0',' ').trim().toLowerCase();
        String last   = c.LastName   == null ? '' : c.LastName.replace('\u00A0',' ').trim().toLowerCase();
        String email  = c.Email      == null ? '' : c.Email.replace('\u00A0',' ').trim().toLowerCase();

        String key = first + '|' + middle + '|' + last + '|' + email;

        emails.add(email);

        if (!keyToIncoming.containsKey(key)) {
            keyToIncoming.put(key, new List<Contact>());
        }
        keyToIncoming.get(key).add(c);
    }

    // Nothing to validate
    if (keyToIncoming.isEmpty()) return;

    // 1) Block duplicates INSIDE the same save request (Trigger.new itself)
    // Example: import or UI creates 2 identical Contacts in one transaction.
    for (String key : keyToIncoming.keySet()) {
        if (keyToIncoming.get(key).size() > 1) {
            for (Contact incoming : keyToIncoming.get(key)) {
                incoming.addError('Duplicate Contact found in this save request (same Name + Email).');
            }
        }
    }

    // 2) Query existing Contacts that share incoming emails
    List<Contact> existing = [
        SELECT Id, FirstName, MiddleName, LastName, Email
        FROM Contact
        WHERE Email IN :emails
        AND Id NOT IN :excludeIds
        LIMIT 50000
    ];

    // Map existing contacts by the same composite key
    Map<String, Contact> keyToExisting = new Map<String, Contact>();
    for (Contact e : existing) {
        String firstE  = e.FirstName  == null ? '' : e.FirstName.replace('\u00A0',' ').trim().toLowerCase();
        String middleE = e.MiddleName == null ? '' : e.MiddleName.replace('\u00A0',' ').trim().toLowerCase();
        String lastE   = e.LastName   == null ? '' : e.LastName.replace('\u00A0',' ').trim().toLowerCase();
        String emailE  = e.Email      == null ? '' : e.Email.replace('\u00A0',' ').trim().toLowerCase();

        String eKey = firstE + '|' + middleE + '|' + lastE + '|' + emailE;

        if (!keyToExisting.containsKey(eKey)) {
            keyToExisting.put(eKey, e);
        }
    }

    // 3) Add errors (hard block) for duplicates against DB
    for (String key : keyToIncoming.keySet()) {
        if (keyToExisting.containsKey(key)) {
            Contact dup = keyToExisting.get(key);
            String msg = 'Duplicate Contact found. Existing Contact Id: ' + dup.Id;

            for (Contact incoming : keyToIncoming.get(key)) {
                incoming.addError(msg);
            }
        }
    }
}