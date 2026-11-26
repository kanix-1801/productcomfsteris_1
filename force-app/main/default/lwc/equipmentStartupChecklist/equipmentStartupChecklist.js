import { LightningElement, api } from "lwc";
import { ShowToastEvent } from "lightning/platformShowToastEvent";
import { CloseActionScreenEvent } from "lightning/actions";
import definition from "./amsco600Definition";
import { buildView, missingRequired } from "./checklistEngine";

// The checklist only guides and validates the technician on the device; answers are not
// stored, so it needs no Apex, no record access and works offline in Field Service mobile.
export default class EquipmentStartupChecklist extends LightningElement {
  @api recordId;

  title = definition.title;
  answers = {};
  showErrors = false;

  get sections() {
    return buildView(definition, this.answers, this.showErrors);
  }

  handleOptionSelect(event) {
    const { id, value } = event.currentTarget.dataset;
    this.answers = { ...this.answers, [id]: value };
  }

  handleNumberChange(event) {
    this.answers = {
      ...this.answers,
      [event.target.dataset.id]: event.target.value
    };
  }

  handleSubmit() {
    this.showErrors = true;
    const missing = missingRequired(definition, this.answers);
    if (missing.length) {
      this.toast(
        "Checklist incomplete",
        `${missing.length} required answer(s) missing.`,
        "error"
      );
      this.template
        .querySelector(`[data-card="${missing[0]}"]`)
        ?.scrollIntoView({ block: "center" });
      return;
    }
    this.toast("Checklist complete", "", "success");
    this.dispatchEvent(new CloseActionScreenEvent());
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}