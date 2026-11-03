// Dummy data for the Pricing Programs tab (UI only, no Apex yet).
// Replace with an Apex / picklist source once the Pricing Program data model is decided.

// Known programs. "program" is the program name and the only value stored for a row's Program;
// typing a known name fills the row's Description and CT Code.
export const PRICING_PROGRAMS_JSON = `[
    { "program": "PP-ENDO-01", "description": "Flexible endoscope repair, contract rate", "ctCode": "CT-4100" },
    { "program": "PP-ENDO-02", "description": "Flexible endoscope repair, flat rate", "ctCode": "CT-4110" },
    { "program": "PP-RIGID-01", "description": "Rigid scope repair, contract rate", "ctCode": "CT-4200" },
    { "program": "PP-SURG-01", "description": "Surgical instrument repair, contract rate", "ctCode": "CT-4300" },
    { "program": "PP-VIDEO-01", "description": "Video equipment repair, contract rate", "ctCode": "CT-4400" },
    { "program": "PP-LOAN-01", "description": "Repair with loaner device included", "ctCode": "CT-5200" }
]`;

// Sample rows shown when a line has no Pricing Programs yet
export const PRICING_PROGRAM_SAMPLE_ROWS_JSON = `[
    { "program": "PP-ENDO-01", "description": "Flexible endoscope repair, contract rate", "ctCode": "CT-4100" },
    { "program": "PP-RIGID-01", "description": "Rigid scope repair, contract rate", "ctCode": "CT-4200" }
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