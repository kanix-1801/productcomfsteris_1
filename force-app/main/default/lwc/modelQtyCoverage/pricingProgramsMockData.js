// Dummy data for the Pricing Programs tab (UI only, no Apex yet).
// Replace with an Apex / picklist source once the Pricing Program data model is decided.

// Known programs, searched by the "Add pricing program" search bar (program, CT code or category).
// "ctCodes" are the program's child CT Code records: { code, name }.
// "category" is only used for searching; a row stores program, description and CT codes.
export const PRICING_PROGRAMS_JSON = `[
    {
        "program": "PP-ENDO-01", "description": "Flexible endoscope repair, contract rate", "category": "Flexible Endoscopy",
        "ctCodes": [
            { "code": "4410", "name": "Flexible Gastroscope" },
            { "code": "4412", "name": "Flexible Colonoscope" },
            { "code": "4415", "name": "Flexible Duodenoscope" }
        ]
    },
    {
        "program": "PP-ENDO-02", "description": "Flexible endoscope repair, flat rate", "category": "Flexible Endoscopy",
        "ctCodes": [
            { "code": "4410", "name": "Flexible Gastroscope" },
            { "code": "4420", "name": "Flexible Bronchoscope" }
        ]
    },
    {
        "program": "PP-ENDO-03", "description": "Flexible endoscope preventive maintenance", "category": "Flexible Endoscopy",
        "ctCodes": [
            { "code": "4410", "name": "Flexible Gastroscope" },
            { "code": "4412", "name": "Flexible Colonoscope" },
            { "code": "4420", "name": "Flexible Bronchoscope" },
            { "code": "4425", "name": "Flexible Cystoscope" }
        ]
    },
    {
        "program": "PP-RIGID-01", "description": "Rigid scope repair, contract rate", "category": "Rigid Endoscopy",
        "ctCodes": [
            { "code": "4510", "name": "Rigid Laparoscope" },
            { "code": "4512", "name": "Rigid Arthroscope" }
        ]
    },
    {
        "program": "PP-RIGID-02", "description": "Rigid scope repair, flat rate", "category": "Rigid Endoscopy",
        "ctCodes": [
            { "code": "4510", "name": "Rigid Laparoscope" }
        ]
    },
    {
        "program": "PP-SURG-01", "description": "Surgical instrument repair, contract rate", "category": "Surgical Instruments",
        "ctCodes": [
            { "code": "4610", "name": "General Surgical Instruments" },
            { "code": "4612", "name": "Microsurgical Instruments" },
            { "code": "4614", "name": "Laparoscopic Instruments" }
        ]
    },
    {
        "program": "PP-SURG-02", "description": "Powered surgical instrument repair", "category": "Surgical Instruments",
        "ctCodes": [
            { "code": "4620", "name": "Powered Drills and Saws" },
            { "code": "4622", "name": "Powered Shavers" }
        ]
    },
    {
        "program": "PP-VIDEO-01", "description": "Video equipment repair, contract rate", "category": "Video Equipment",
        "ctCodes": [
            { "code": "4710", "name": "Camera Control Unit" },
            { "code": "4712", "name": "Camera Head" },
            { "code": "4714", "name": "Light Source" },
            { "code": "4716", "name": "Surgical Monitor" }
        ]
    },
    {
        "program": "PP-VIDEO-02", "description": "Camera head and light source repair", "category": "Video Equipment",
        "ctCodes": [
            { "code": "4712", "name": "Camera Head" },
            { "code": "4714", "name": "Light Source" }
        ]
    },
    {
        "program": "PP-LOAN-01", "description": "Repair with loaner device included", "category": "Loaner Program",
        "ctCodes": [
            { "code": "5210", "name": "Loaner Flexible Endoscope" }
        ]
    }
]`;

// Sample rows shown when a line has no Pricing Programs yet
export const PRICING_PROGRAM_SAMPLE_ROWS_JSON = `[
    {
        "program": "PP-ENDO-01", "description": "Flexible endoscope repair, contract rate",
        "ctCodes": [
            { "code": "4410", "name": "Flexible Gastroscope" },
            { "code": "4412", "name": "Flexible Colonoscope" },
            { "code": "4420", "name": "Flexible Colonoscope" },
            { "code": "4416", "name": "Flexible Colonoscope" },
            { "code": "4413", "name": "Rigid Colonoscope" },
            { "code": "4415", "name": "Flexible Colonoscope" },
            { "code": "4415", "name": "Flexible Duodenoscope" }
        ]
    },
    {
        "program": "PP-RIGID-01", "description": "Rigid scope repair, contract rate",
        "ctCodes": [
            { "code": "4510", "name": "Rigid Laparoscope" },
            { "code": "4512", "name": "Rigid Arthroscope" }
        ]
    }
]`;

const parse = (json) => {
    try {
        return JSON.parse(json);
    } catch (e) {
        return [];
    }
};

export const PRICING_PROGRAMS = parse(PRICING_PROGRAMS_JSON);
export const PRICING_PROGRAM_SAMPLE_ROWS = parse(PRICING_PROGRAM_SAMPLE_ROWS_JSON);