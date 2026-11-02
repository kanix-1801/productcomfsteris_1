/**
 * @description GW-3600 - Tests for active Document Template resolution.
 */
@IsTest
private class DocumentTemplatesServiceTest {
    @IsTest
    static void selector_constructs() {
        Assert.isNotNull(new DocumentTemplateSelector(), 'Selector should construct');
    }

    @IsTest
    static void selectActiveIdByName_returnsNullWhenNameIsBlankOrMissing() {
        Assert.isNull(DocumentTemplatesService.selectActiveIdByName(null));
        Assert.isNull(DocumentTemplatesService.selectActiveIdByName('   '));
        Assert.isNull(
            DocumentTemplatesService.selectActiveIdByName('Repair Center Quote Missing')
        );
        Assert.areEqual(
            0,
            DocumentTemplatesService.selectActiveIdsByNames(null).size(),
            'Null names should not query'
        );
        Assert.areEqual(
            0,
            DocumentTemplatesService.selectActiveIdsByNames(new Set<String>()).size(),
            'Empty names should not query'
        );
        Assert.areEqual(
            0,
            DocumentTemplatesService.selectActiveIdsByNames(new Set<String>{ '   ' }).size(),
            'Blank names should not query'
        );
    }

    @IsTest
    static void selectActiveIdByName_keepsNewestActiveVersion() {
        DocumentTemplate olderVersion = new DocumentTemplate(
            Name = 'RC DocGen Standard Test',
            Type = 'MicrosoftWord',
            TokenMappingType = 'JSON',
            TokenMappingMethodType = 'OmniDataTransform',
            IsActive = true,
            VersionNumber = 1
        );
        DocumentTemplate newerVersion = new DocumentTemplate(
            Name = 'RC DocGen Standard Test',
            Type = 'MicrosoftWord',
            TokenMappingType = 'JSON',
            TokenMappingMethodType = 'OmniDataTransform',
            IsActive = true,
            VersionNumber = 2
        );
        DocumentTemplate inactiveVersion = new DocumentTemplate(
            Name = 'RC DocGen Standard Test',
            Type = 'MicrosoftWord',
            TokenMappingType = 'JSON',
            TokenMappingMethodType = 'OmniDataTransform',
            IsActive = false,
            VersionNumber = 3
        );
        insert new List<DocumentTemplate>{ olderVersion, newerVersion, inactiveVersion };

        Assert.areEqual(
            newerVersion.Id,
            DocumentTemplatesService.selectActiveIdByName('RC DocGen Standard Test'),
            'The highest active version should be chosen'
        );
    }
}