// Checklist content lives in data, not markup, so a new equipment type is a new definition
// file rather than a new component. Item types: info, notice, radio, number.
// showWhen hides an item until another answer matches; range drives the out-of-spec
// disposition that the engine inserts after a number item.
const YES_NO = ["Yes", "No"];

const VOLTAGE_RANGES = {
  "208V AC": { min: 187, max: 228 },
  "240V AC": { min: 216, max: 264 },
  "480V AC": { min: 432, max: 528 }
};

const phaseReading = (id, label) => ({
  type: "number",
  id,
  label,
  required: true,
  showWhen: { question: "nominalVoltage" },
  range: { byAnswer: "nominalVoltage", values: VOLTAGE_RANGES, unit: "V AC" }
});

export default {
  id: "AMSCO_600_STARTUP",
  version: 1,
  title: "AMSCO 600 Steam Sterilizer Equipment Startup Checklist",
  disposition: {
    label: "Disposition",
    options: ["Customer Acknowledge and Accepts"]
  },
  sections: [
    {
      id: "general",
      items: [
        {
          type: "info",
          id: "shp105",
          title: "Refer to SHP-105 Completing Equipment Startup Checklist",
          lines: [
            "Any utility out of spec must contain a disposition.",
            "All issues/failures in the start-up section must be corrected and pass before completion."
          ]
        },
        {
          type: "notice",
          id: "ppe",
          title:
            "Proper chemical and electrical PPE must be worn when completing this checklist"
        },
        {
          type: "info",
          id: "recordIssues",
          title: "Record all issues/failures on the service request.",
          lines: [
            "Any utility out of spec must contain a disposition.",
            "All issues/failures in the startup section must be corrected and pass before completion."
          ]
        },
        {
          type: "notice",
          id: "importantNote",
          title: "IMPORTANT NOTES:",
          uppercase: true,
          lines: [
            "1. All steam, water, compressed air, and ambient temperature readings must be taken with all equipment, sharing common supply lines and recessed area, running a cycle to ensure accurate readings.",
            "2. Before applying power or supplying air to the sterilizer, verify all pneumatic valve detents on the air manifold are unlocked. The screw slot is vertical when in the unlocked position.",
            "3. S54 and S57 are air cylinder brake modules that are recessed between two other modules on the air manifold. Ensure these are unlocked (screw slot is vertical) before applying power or supplying air to the sterilizer."
          ]
        },
        {
          type: "radio",
          id: "detentsVerified",
          label:
            "I have verified that all of the pneumatic valve detents on the air manifold, including S54 and S57 air cylinder brake modules that are recessed between two other modules, screw slot is vertical indicating unlocked prior to applying power or supplying air to the sterilizer.",
          required: true,
          options: ["Did not verify", "Verified"]
        }
      ]
    },
    {
      // Power and air readings are unsafe until the detents are confirmed unlocked, so the
      // rest of the checklist stays hidden until then.
      id: "utilities",
      title: "EQUIPMENT/UTILITY REQUIREMENTS",
      showWhen: { question: "detentsVerified", equals: "Verified" },
      items: [
        {
          type: "radio",
          id: "steamOrElectric",
          label: "Steam or Electric",
          required: true,
          options: ["Steam", "Electric"]
        },
        {
          type: "info",
          id: "threePhase",
          title:
            "Sterilizer Control and Vacuum Pump (if applicable): Three Phase (L1, L2, L3, GND)",
          lines: [
            "208 V AC +/- 10% = 187 V AC to 228 V AC",
            "240 V AC +/- 10% = 216 V AC to 264 V AC",
            "480 V AC +/- 10% = 432 V AC to 528 V AC"
          ]
        },
        {
          type: "radio",
          id: "nominalVoltage",
          label: "Obtain nominal voltage from Sterilizer Data Plate",
          required: true,
          options: Object.keys(VOLTAGE_RANGES)
        },
        phaseReading("l1ToL2", "L1 to L2 V AC"),
        phaseReading("l2ToL3", "L2 to L3 V AC"),
        phaseReading("l3ToL1", "L3 to L1 V AC"),
        {
          type: "info",
          id: "steamSupply",
          title: "Steam Supply",
          lines: ["50-80 PSIG Dynamic"],
          showWhen: { question: "steamOrElectric", equals: "Steam" }
        },
        {
          type: "number",
          id: "steamPsig",
          label: "PSIG",
          required: true,
          showWhen: { question: "steamOrElectric", equals: "Steam" },
          range: { min: 50, max: 80, unit: "PSIG" }
        },
        {
          type: "info",
          id: "coldWater",
          title: "Cold Water",
          lines: ["20-50 PSIG Dynamic"]
        },
        {
          type: "number",
          id: "coldWaterPsig",
          label: "PSIG",
          required: true,
          range: { min: 20, max: 50, unit: "PSIG" }
        },
        {
          type: "info",
          id: "coldWaterTemp",
          title: "Cold Water Temperature",
          lines: ["40-70°F"]
        },
        {
          type: "number",
          id: "coldWaterTempF",
          label: "°F",
          required: true,
          range: { min: 40, max: 70, unit: "°F" }
        },
        {
          type: "radio",
          id: "steriGreen",
          label: "Does this unit have SteriGreen+ option?",
          required: true,
          options: YES_NO
        },
        {
          type: "radio",
          id: "floorDrain",
          label: "Floor Drain Sterilizer",
          required: true,
          options: YES_NO
        },
        {
          type: "info",
          id: "compressedAir",
          title: "Compressed Air",
          lines: ["80-100 PSIG Dynamic"]
        },
        {
          type: "number",
          id: "compressedAirPsig",
          label: "PSIG",
          required: true,
          range: { min: 80, max: 100, unit: "PSIG" }
        },
        {
          type: "radio",
          id: "airCompressor",
          label: "Does the unit have an Optional Air Compressor?",
          required: true,
          options: YES_NO
        },
        {
          type: "info",
          id: "recessedArea",
          title: "Recessed Area Temperature",
          lines: [
            "Ambient air temperature of 90°F maximum with all sterilizers up to temperature in the service area."
          ]
        },
        {
          type: "number",
          id: "recessedAreaTempF",
          label: "°F",
          required: true,
          range: { max: 90, unit: "°F" }
        }
      ]
    }
  ]
};