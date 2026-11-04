/**
 * @author Vinay Soni
 * @date 2026/11/04
 *
 * @group ES Service Product Configurator
 *
 * @description Tests for EsServiceOtCoveragePreHook.
 */
@IsTest
private class EsServiceOtCoveragePreHookTest {

    private static Map<String, Object> tag(Object value) {
        return new Map<String, Object>{ 'tagValue' => value };
    }

    private static Map<String, Object> attributeNode(String attributeName, String value, String lineId) {
        return new Map<String, Object>{
            'tagValue' => new Map<String, Object>{
                'Attribute' => tag(attributeName),
                'AttributeValue' => tag(value),
                'SalesTransactionItemAttrParent' => tag(lineId)
            }
        };
    }

    private static Map<String, Object> lineNode(String lineId, String linePath, String dmlStatus) {
        Map<String, Object> lineItemTag = tag(lineId);
        lineItemTag.put('dmlStatus', dmlStatus);
        return new Map<String, Object>{
            'tagValue' => new Map<String, Object>{ 'LineItem' => lineItemTag, 'LineItemPath' => tag(linePath) },
            'dataPath' => new List<Object>{ 'ctx', lineId, 'item' }
        };
    }

    /**
     * @description The OT Coverage value is read per line; other attributes and nodes without tags are skipped.
     */
    @IsTest
    static void testReadOtCoverageByLineMatchesAttribute() {
        List<Object> nodeList = new List<Object>{
            attributeNode('OT_Coverage', '24/7', 'ref_root'),
            attributeNode('Visits', '2', 'ref_child'),
            new Map<String, Object>()
        };

        Test.startTest();
        Map<String, String> otCoverageByLineIdMap = EsServiceOtCoveragePreHook.readOtCoverageByLine(nodeList);
        Test.stopTest();

        Assert.areEqual(new Map<String, String>{ 'ref_root' => '24/7' }, otCoverageByLineIdMap,
                        'Only the OT Coverage attribute should be read');
    }

    /**
     * @description Lines get their own value or their root line's; deleted, incomplete and unrelated lines are skipped.
     */
    @IsTest
    static void testBuildLineUpdatesUsesOwnOrRootValue() {
        Map<String, Object> incompleteNode = lineNode('ref_short', 'ref_short', null);
        incompleteNode.put('dataPath', new List<Object>{ 'ctx' });
        List<Object> lineNodeList = new List<Object>{
            lineNode('ref_root', 'ref_root', null),
            lineNode('ref_child', 'ref_root/ref_child', null),
            lineNode('ref_deleted', 'ref_root/ref_deleted', 'DELETED'),
            lineNode('ref_other', 'ref_other', null),
            incompleteNode
        };

        Test.startTest();
        List<Map<String, Object>> lineUpdateList = EsServiceOtCoveragePreHook.buildLineUpdates(
            lineNodeList, new Map<String, String>{ 'ref_root' => '24/7' }
        );
        Test.stopTest();

        Assert.areEqual(2, lineUpdateList.size(), 'The root line and its child should be updated');
        List<Object> childAttributeList = (List<Object>) lineUpdateList[1].get('attributes');
        Map<String, Object> childAttribute = (Map<String, Object>) childAttributeList[0];
        Assert.areEqual('OT_Coverage__c', childAttribute.get('attributeName'), 'Target context attribute');
        Assert.areEqual('24/7', childAttribute.get('attributeValue'), 'The child should use the root line value');
    }

    /**
     * @description A failure returns FAILED with the error instead of throwing.
     */
    @IsTest
    static void testExecuteReturnsFailedForUnknownContext() {
        RevSignaling.TransactionRequest request = new RevSignaling.TransactionRequest(null, 'notARealContextId');

        Test.startTest();
        RevSignaling.TransactionResponse response = new EsServiceOtCoveragePreHook().execute(request);
        Test.stopTest();

        Assert.areEqual(RevSignaling.TransactionStatus.FAILED, response.status, 'An unknown context should fail');
        Assert.isTrue(response.message.startsWith('OT Coverage pre-hook failed'), 'Failure message should be returned');
    }
}