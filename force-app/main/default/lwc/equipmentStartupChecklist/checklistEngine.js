// Pure functions over (definition, answers): no LWC or platform imports, so the same
// logic runs in the component, in Jest and in the static mockup.
const isBlank = (value) =>
  value === undefined || value === null || value === "";

export const dispositionId = (itemId) => `${itemId}__disposition`;

export function isVisible(item, answers) {
  const rule = item.showWhen;
  if (!rule) {
    return true;
  }
  const value = answers[rule.question];
  return rule.equals === undefined ? !isBlank(value) : value === rule.equals;
}

export function rangeFor(item, answers) {
  const range = item.range;
  if (!range) {
    return null;
  }
  return range.byAnswer
    ? (range.values[answers[range.byAnswer]] ?? null)
    : range;
}

export function isOutOfSpec(item, answers) {
  const range = rangeFor(item, answers);
  const raw = answers[item.id];
  if (!range || isBlank(raw)) {
    return false;
  }
  const value = Number(raw);
  return (
    (range.min !== undefined && value < range.min) ||
    (range.max !== undefined && value > range.max)
  );
}

function rangeText(item, answers) {
  const range = rangeFor(item, answers);
  if (!range) {
    return "";
  }
  const unit = item.range.unit ? ` ${item.range.unit}` : "";
  if (range.min === undefined) {
    return `Max ${range.max}${unit}`;
  }
  return range.max === undefined
    ? `Min ${range.min}${unit}`
    : `${range.min}-${range.max}${unit}`;
}

// Visible items in display order, with a disposition question inserted after every
// out-of-spec reading. A section's showWhen gates every item in it.
export function visibleItems(definition, answers) {
  const result = [];
  for (const section of definition.sections) {
    if (!isVisible(section, answers)) {
      continue;
    }
    for (const item of section.items) {
      if (!isVisible(item, answers)) {
        continue;
      }
      result.push({ section, item });
      if (item.type === "number" && isOutOfSpec(item, answers)) {
        result.push({
          section,
          item: {
            type: "radio",
            id: dispositionId(item.id),
            label: definition.disposition.label,
            required: true,
            options: definition.disposition.options,
            isDisposition: true
          }
        });
      }
    }
  }
  return result;
}

export function missingRequired(definition, answers) {
  return visibleItems(definition, answers)
    .filter(({ item }) => item.required && isBlank(answers[item.id]))
    .map(({ item }) => item.id);
}

// Flat view model for the template: LWC templates cannot call functions, so every flag
// and string the markup needs is computed here.
export function buildView(definition, answers, showErrors) {
  const missing = new Set(
    showErrors ? missingRequired(definition, answers) : []
  );
  const sections = [];
  let current;
  for (const { section, item } of visibleItems(definition, answers)) {
    if (current?.key !== section.id) {
      current = {
        key: section.id,
        title: section.title,
        hasTitle: Boolean(section.title),
        items: []
      };
      sections.push(current);
    }
    const value = answers[item.id];
    const outOfSpec = item.type === "number" && isOutOfSpec(item, answers);
    const hasError = missing.has(item.id);
    current.items.push({
      key: item.id,
      id: item.id,
      inputId: `${item.id}-input`,
      isInfo: item.type === "info",
      isNotice: item.type === "notice",
      isRadio: item.type === "radio",
      isNumber: item.type === "number",
      title: item.title,
      label: item.label,
      required: item.required,
      lines: (item.lines || []).map((text, index) => ({
        key: `${item.id}-${index}`,
        text
      })),
      value: isBlank(value) ? "" : value,
      rangeText: rangeText(item, answers),
      outOfSpec,
      hasError,
      options: (item.options || []).map((option) => ({
        key: `${item.id}-${option}`,
        value: option,
        checked: value === option,
        cssClass: value === option ? "option option_selected" : "option"
      })),
      cardClass: [
        "card",
        item.type === "notice" ? "card_notice" : "",
        item.uppercase ? "card_uppercase" : "",
        item.isDisposition ? "card_disposition" : "",
        hasError ? "card_error" : ""
      ]
        .filter(Boolean)
        .join(" "),
      inputClass: outOfSpec
        ? "number-input number-input_out-of-spec"
        : "number-input"
    });
  }
  return sections;
}