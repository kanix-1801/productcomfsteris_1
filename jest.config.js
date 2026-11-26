const { jestConfig } = require('@salesforce/sfdx-lwc-jest/config');

module.exports = {
    ...jestConfig,
    moduleNameMapper: {
        ...(jestConfig.moduleNameMapper || {}),
        // sfdx-lwc-jest has no LightningModal stub (GW-6456 modals)
        '^lightning/modal$': '<rootDir>/jest-mocks/lightning/modal'
    },
    modulePathIgnorePatterns: ['<rootDir>/.localdevserver']
};
