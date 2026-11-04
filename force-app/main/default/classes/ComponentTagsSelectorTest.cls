/**
 * @author Sagar Anand
 * @date 2026-10-28
 * @description GW-6095 - Tests for ComponentTagsSelector.
 *              Test data is inserted in SYSTEM_MODE because API 67.0 DML runs in user mode.
 * @group Work Order Debrief
 * @see ComponentTagsSelector
 */
@IsTest
private class ComponentTagsSelectorTest {
    /**
     * @description Returns only the tags of the requested BOM Component, ordered by Name.
     */
    @IsTest
    static void testSelectByBomComponentIdsReturnsTagsOrderedByName() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId()); // current user: debrief permission sets vary by org

        System.runAs(contextUser) {
            // GIVEN: two BOM Components, the first with tags B and A, the second with tag C
            ServiceBOM__c serviceBom = new ServiceBOM__c(
                Name = 'CTS SBOM ' + String.valueOf(Crypto.getRandomInteger()),
                Type__c = 'ES Asset BOM'
            );
            Database.insert(serviceBom, AccessLevel.SYSTEM_MODE);

            Product2 parentProduct = new Product2(
                Name = 'CTS Parent',
                IsActive = true,
                ProductType__c = 'Service Asset'
            );
            Product2 partOne = new Product2(Name = 'CTS Part One', IsActive = true, ProductType__c = 'Part');
            Product2 partTwo = new Product2(Name = 'CTS Part Two', IsActive = true, ProductType__c = 'Part');
            Database.insert(new List<Product2>{ parentProduct, partOne, partTwo }, AccessLevel.SYSTEM_MODE);

            ProductRelatedMaterial componentOne = new ProductRelatedMaterial(
                Name = 'CTS BOM One',
                ServiceBOM__c = serviceBom.Id,
                ProductId = parentProduct.Id,
                ProductComponentId = partOne.Id,
                QuantityPerProductUnit = 1
            );
            ProductRelatedMaterial componentTwo = new ProductRelatedMaterial(
                Name = 'CTS BOM Two',
                ServiceBOM__c = serviceBom.Id,
                ProductId = parentProduct.Id,
                ProductComponentId = partTwo.Id,
                QuantityPerProductUnit = 1
            );
            Database.insert(new List<ProductRelatedMaterial>{ componentOne, componentTwo }, AccessLevel.SYSTEM_MODE);

            PartTag__c partTag = new PartTag__c(Name = 'CTS Part Tag');
            Database.insert(partTag, AccessLevel.SYSTEM_MODE);

            Database.insert(
                new List<ComponentTag__c>{
                    new ComponentTag__c(Name = 'B', BomComponent__c = componentOne.Id, ComponentTagId__c = partTag.Id),
                    new ComponentTag__c(Name = 'A', BomComponent__c = componentOne.Id, ComponentTagId__c = partTag.Id),
                    new ComponentTag__c(Name = 'C', BomComponent__c = componentTwo.Id, ComponentTagId__c = partTag.Id)
                },
                AccessLevel.SYSTEM_MODE
            );

            // WHEN
            Test.startTest();
            List<ComponentTag__c> tags = ComponentTagsSelector.selectByBomComponentIds(new Set<Id>{ componentOne.Id });
            Test.stopTest();

            // THEN
            Assert.areEqual(2, tags.size(), 'Only the tags of the requested BOM Component should be returned');
            Assert.areEqual('A', tags[0].Name, 'Tags should be ordered by Name');
            Assert.areEqual('B', tags[1].Name, 'Tags should be ordered by Name');
            Assert.areEqual(componentOne.Id, tags[0].BomComponent__c, 'BOM Component Id should be selected');
        }
    }

    /**
     * @description Null, empty and null-only inputs return an empty list.
     */
    @IsTest
    static void testSelectByBomComponentIdsBlankInputs() {
        // SETUP
        User contextUser = new User(Id = UserInfo.getUserId());

        System.runAs(contextUser) {
            // GIVEN: no BOM Component Ids

            // WHEN
            Test.startTest();
            List<ComponentTag__c> fromNull = ComponentTagsSelector.selectByBomComponentIds(null);
            List<ComponentTag__c> fromEmpty = ComponentTagsSelector.selectByBomComponentIds(new Set<Id>());
            List<ComponentTag__c> fromNullId = ComponentTagsSelector.selectByBomComponentIds(new Set<Id>{ null });
            Test.stopTest();

            // THEN
            Assert.isTrue(fromNull.isEmpty(), 'Null input should return no tags');
            Assert.isTrue(fromEmpty.isEmpty(), 'Empty input should return no tags');
            Assert.isTrue(fromNullId.isEmpty(), 'Null Ids should be ignored');
        }
    }
}