@IsTest
private class InstallationProjectViewerAccessTest {
    @IsTest
    static void hasReadOnlyInstallationProjectViewerAccess_defaultUser_returnsBoolean() {
        Boolean readOnly = InstallationProjectViewerAccessService.hasReadOnlyInstallationProjectViewerAccess();
        System.assertNotEquals(null, readOnly);
    }

    @IsTest
    static void hasReadOnlyInstallationProjectViewerAccess_forcedTrue() {
        InstallationProjectViewerAccessService.setForceReadOnlyForTests(true);
        try {
            System.assertEquals(
                true,
                InstallationProjectViewerAccessService.hasReadOnlyInstallationProjectViewerAccess()
            );
            System.assertEquals(
                true,
                InstallationProjectViewerController.isReadOnlyInstallationProjectViewer()
            );
        } finally {
            InstallationProjectViewerAccessService.setForceReadOnlyForTests(false);
        }
    }
}