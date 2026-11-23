@IsTest
private class CaseContactRolesSelectorTest {

    /*
     * POSITIVE SCENARIO
     * Covers:
     * - SOQL query
     * - !csList.isEmpty() = true
     * - return csList
     */
    @IsTest
    static void testCaseContactRecordPositive() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'Test',
            LastName = 'Contact',
            AccountId = acc.Id
        );
        insert con;

        Case cs = new Case(
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert cs;

        CaseContactRole ccr = new CaseContactRole(
            CasesId = cs.Id,
            ContactId = con.Id,
            Role = 'Trade-in Contact'
        );
        insert ccr;

        Test.startTest();

        List<CaseContactRole> result =
            CaseContactRolesSelector.caseContactRecord(cs.Id);

        Test.stopTest();

        System.assertNotEquals(
            null,
            result,
            'Result should not be null'
        );

        System.assertEquals(
            1,
            result.size(),
            'One CaseContactRole should be returned'
        );

        System.assertEquals(
            ccr.Id,
            result[0].Id
        );

        System.assertEquals(
            con.Id,
            result[0].ContactId
        );

        System.assertEquals(
            'Trade-in Contact',
            result[0].Role
        );

        System.assertEquals(
            'Test',
            result[0].Contact.FirstName
        );
    }


    /*
     * NEGATIVE SCENARIO
     * Covers:
     * - SOQL query
     * - csList.isEmpty()
     * - return NULL
     */
    @IsTest
    static void testCaseContactRecordNegative() {

        Account acc = new Account(
            Name = 'Negative Test Account'
        );
        insert acc;

        Case cs = new Case(
            AccountId = acc.Id,
            Status = 'New',
            Origin = 'Phone'
        );
        insert cs;

        Test.startTest();

        List<CaseContactRole> result =
            CaseContactRolesSelector.caseContactRecord(cs.Id);

        Test.stopTest();

        System.assertEquals(
            null,
            result,
            'Null should be returned when CaseContactRole is not found'
        );
    }


    /*
     * EXCEPTION SCENARIO
     * Covers:
     *
     * forceException condition
     * throw new CaseContactRoleSelectorException
     * catch (Exception ex)
     * ErrorLogger.logException(...)
     * throw ex
     */
    @IsTest
    static void testCaseContactRecordException() {

        Boolean exceptionCaught = false;

        caseContactRolesSelector.forceException = true;

        Test.startTest();

        try {

            CaseContactRolesSelector.caseContactRecord(null);

            System.assert(
                false,
                'Exception should have been thrown'
            );

        } catch (CaseContactRolesSelector.CaseContactRoleSelectorException ex) {

            exceptionCaught = true;

            System.assertEquals(
                'Forced exception for test coverage',
                ex.getMessage()
            );
        }

        Test.stopTest();

        CaseContactRolesSelector.forceException = false;

        System.assertEquals(
            true,
            exceptionCaught,
            'Expected exception was not caught'
        );
    }
}