/**
 * @author PWC Developer
 * @date 2026/10/16
 *
 * @group CSC Visit
 *
 * @description
 * GC-3564 - Physician directory for Sunshine search.
 * This story returns matches from the list in this class. A later sprint replaces
 * selectByCriteria with the approved NPI integration. Keep the method signature.
 */
public with sharing class PhysicianSearchSelector {

    /**
     * @description One physician and the taxonomy stored on the Visit.
     */
    public class PhysicianRecord {
        public String npi;
        public String firstName;
        public String lastName;
        public String city;
        public String physicianState;
        public String credential;
        public String taxonomyCode;
        public String taxonomyDescription;
    }

    /**
     * @description Returns directory physicians that match the search.
     * NPI is an exact match. Otherwise first name, last name, and city must all match.
     * @param firstName Physician first name.
     * @param lastName Physician last name.
     * @param city Physician city.
     * @param npi National Provider Identifier.
     * @return Matching physicians from the local directory.
     */
    public static List<PhysicianRecord> selectByCriteria(String firstName, String lastName, String city, String npi) {
        String normalNpi = normalizeNpi(npi);
        String normalFirst = normalize(firstName);
        String normalLast = normalize(lastName);
        String normalCity = normalize(city);
        List<PhysicianRecord> matches = new List<PhysicianRecord>();

        for (PhysicianRecord physician : directory()) {
            if (String.isNotBlank(normalNpi)) {
                if (physician.npi == normalNpi) {
                    matches.add(physician);
                }
                continue;
            }
            if (physician.firstName.toLowerCase() == normalFirst
                && physician.lastName.toLowerCase() == normalLast
                && physician.city.toLowerCase() == normalCity) {
                matches.add(physician);
            }
        }
        return matches;
    }

    private static String normalize(String value) {
        return value == null ? '' : value.trim().toLowerCase();
    }

    private static String normalizeNpi(String value) {
        if (String.isBlank(value)) {
            return '';
        }
        return value.replaceAll('[^0-9]', '');
    }

    /**
     * @description Sample physicians for GC-3564. Names are fictional. Taxonomy codes are NUCC codes.
     * @return The local directory.
     */
    private static List<PhysicianRecord> directory() {
        return new List<PhysicianRecord>{
            physician('1234567893', 'Jordan', 'Hale', 'Mentor', 'OH', 'MD', '207R00000X', 'Internal Medicine Physician'),
            physician('1679576722', 'Avery', 'Lang', 'Cleveland', 'OH', 'DO', '207Q00000X', 'Family Medicine Physician'),
            physician('1063493807', 'Riley', 'Chen', 'Columbus', 'OH', 'MD', '208600000X', 'Surgery Physician')
        };
    }

    private static PhysicianRecord physician(
        String npi,
        String firstName,
        String lastName,
        String city,
        String physicianState,
        String credential,
        String taxonomyCode,
        String taxonomyDescription
    ) {
        PhysicianRecord record = new PhysicianRecord();
        record.npi = npi;
        record.firstName = firstName;
        record.lastName = lastName;
        record.city = city;
        record.physicianState = physicianState;
        record.credential = credential;
        record.taxonomyCode = taxonomyCode;
        record.taxonomyDescription = taxonomyDescription;
        return record;
    }
}