import { LightningElement, api } from "lwc";

const FIELD_SHEET = "field-filter-bottom-sheet";

export default class MapFilters extends LightningElement {
  @api productNameOptions = [];
  @api currentProductName;
  @api setProductNameFilter;
  @api handleError;

  // Getters

  get typeText() {
    return "Product Item";
  }

  get filteredFieldText() {
    return this.currentProductName ? this.currentProductName : "Product Name";
  }

  get filterFieldButtonClass() {
    return `button filter-button ${
      this.currentProductName ? "active-button" : "inactive-button"
    }`;
  }

  get radioOptions() {
    const options = (this.productNameOptions || []).map((name) => ({
      label: name,
      value: name
    }));
    return [{ label: "All Products", value: "" }, ...options];
  }

  get selectedValue() {
    return this.currentProductName || "";
  }

  // Button Handlers

  handleTopFiltersFieldClick = () => {
    this.openSheet(FIELD_SHEET);
  };

  handleCloseFieldFiltersClick = () => {
    this.closeSheet(FIELD_SHEET);
  };

  onProductRadioChange = (e) => {
    try {
      this.setProductNameFilter(e.detail.value);
      this.closeSheet(FIELD_SHEET);
    } catch (error) {
      this.handleError(error);
    }
  };

  // Helpers

  openSheet(sheet) {
    const sheetClasses = this.template.querySelector(`.${sheet}`).classList;
    sheetClasses.add("pt-page-moveToTop");
    sheetClasses.add("shadow");
    sheetClasses.remove("pt-page-moveFromTop");
  }

  closeSheet(sheet) {
    const sheetClasses = this.template.querySelector(`.${sheet}`).classList;
    if (Array.from(sheetClasses).includes("pt-page-moveToTop")) {
      sheetClasses.add("pt-page-moveFromTop");
      sheetClasses.remove("pt-page-moveToTop");
    }
    sheetClasses.remove("shadow");
    this.template
      .querySelectorAll(".sheet-content")
      .forEach((s) => (s.scrollTop = 0));
  }
}