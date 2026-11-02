/**
 * @author Uptima Development Team
 * @date 2026-06-14
 * @description Visualforce list controller that redirects Asset list view selections to the createReturnOrder LWC.
 * @group Return Order Process
 * @see createReturnOrder
 */
public with sharing class AssetCreateReturnOrderLaunchCtrl {
    private final ApexPages.StandardSetController setController;

    /**
     * @description Constructs the controller with the Asset list view standard set controller.
     * @param setController Standard set controller for the Asset list view action.
     */
    public AssetCreateReturnOrderLaunchCtrl(ApexPages.StandardSetController setController) {
        this.setController = setController;
    }

    /**
     * @description Builds a Lightning URL for createReturnOrder with the selected Asset record Ids.
     * @return PageReference redirect to the LWC, or null when no assets are selected.
     */
    public PageReference redirect() {
        List<Asset> selected = (List<Asset>) setController.getSelected();
        if (selected == null || selected.isEmpty()) {
            ApexPages.addMessage(
                new ApexPages.Message(
                    ApexPages.Severity.ERROR,
                    'Select at least one Asset from the list view.'
                )
            );
            return null;
        }

        List<String> assetIds = new List<String>();
        for (Asset asset : selected) {
            assetIds.add(asset.Id);
        }

        PageReference componentPage = new PageReference(
            '/lightning/cmp/c__createReturnOrder?c__recordIds=' + String.join(assetIds, ',')
        );
        componentPage.setRedirect(true);
        return componentPage;
    }
}