/**
 * @description Covers Product PSAM lookup reads used by quote line grouping.
 */
@IsTest
private class ProductPsamLookupServiceTest {
	@IsTest
	static void readsInMemoryProductAndEmptySelections() {
		PSAM__c psamRecord = new PSAM__c(
			Name = 'AER 027',
			ProductFAMCode__c = '027',
			ProductGroupName__c = 'Test Group',
			ProductSubgroupName__c = 'Test Subgroup',
			ProductSubgroupDetailName__c = 'AER'
		);
		insert psamRecord;
		Product2 productRecord = new Product2();
		productRecord.put(ProductPsamLookupService.PRODUCT_PSAM_LOOKUP_FIELD, psamRecord.Id);
		productRecord.putSObject(ProductPsamLookupService.PRODUCT_PSAM_RELATIONSHIP, psamRecord);

		System.assertEquals(true, ProductPsamLookupService.isProductPsamLookupAvailable());
		System.assertEquals(null, ProductPsamLookupService.getPsamId(null));
		System.assertEquals(null, ProductPsamLookupService.getPsamId(new Product2()));
		System.assertEquals(psamRecord.Id, ProductPsamLookupService.getPsamId(productRecord));
		System.assertEquals(null, ProductPsamLookupService.getPsamRelationship(null));
		System.assertEquals(null, ProductPsamLookupService.getPsamRelationship(new Product2()));
		System.assertEquals('AER', ProductPsamLookupService.getPsamRelationship(productRecord).ProductSubgroupDetailName__c);
		System.assertEquals(0, ProductPsamLookupService.selectPsamByProduct2Ids(null).size());
		System.assertEquals(0, ProductPsamLookupService.selectPsamByProduct2Ids(new Set<Id>()).size());
		System.assertEquals(0, ProductPsamLookupService.selectPsamByPricebookEntryIds(null).size());
		System.assertEquals(0, ProductPsamLookupService.selectPsamByPricebookEntryIds(new Set<Id>()).size());
	}

	@IsTest
	static void selectsPsamByProductAndPricebookEntry() {
		PSAM__c psamRecord = new PSAM__c(
			Name = 'AER 027',
			ProductFAMCode__c = '027',
			ProductGroupName__c = 'Test Group',
			ProductSubgroupName__c = 'Test Subgroup',
			ProductSubgroupDetailName__c = 'AER'
		);
		insert psamRecord;

		Product2 linkedProduct = new Product2(Name = 'Linked PSAM Product', IsActive = true);
		linkedProduct.put(ProductPsamLookupService.PRODUCT_PSAM_LOOKUP_FIELD, psamRecord.Id);
		Product2 unlinkedProduct = new Product2(Name = 'Unlinked Product', IsActive = true);
		insert new List<Product2>{ linkedProduct, unlinkedProduct };

		Id pricebookId = Test.getStandardPricebookId();
		update new Pricebook2(Id = pricebookId, IsActive = true);
		PricebookEntry linkedEntry = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = linkedProduct.Id,
			UnitPrice = 10,
			IsActive = true,
			CurrencyIsoCode = 'USD'
		);
		PricebookEntry unlinkedEntry = new PricebookEntry(
			Pricebook2Id = pricebookId,
			Product2Id = unlinkedProduct.Id,
			UnitPrice = 20,
			IsActive = true,
			CurrencyIsoCode = 'USD'
		);
		insert new List<PricebookEntry>{ linkedEntry, unlinkedEntry };

		Test.startTest();
		Map<Id, PSAM__c> psamByProductId = ProductPsamLookupService.selectPsamByProduct2Ids(
			new Set<Id>{ linkedProduct.Id, unlinkedProduct.Id }
		);
		Map<Id, PSAM__c> psamByEntryId = ProductPsamLookupService.selectPsamByPricebookEntryIds(
			new Set<Id>{ linkedEntry.Id, unlinkedEntry.Id }
		);
		Test.stopTest();

		System.assertEquals('AER', psamByProductId.get(linkedProduct.Id).ProductSubgroupDetailName__c);
		System.assertEquals(false, psamByProductId.containsKey(unlinkedProduct.Id));
		System.assertEquals(psamRecord.Id, psamByEntryId.get(linkedEntry.Id).Id);
		System.assertEquals(false, psamByEntryId.containsKey(unlinkedEntry.Id));
	}
}