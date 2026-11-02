import { LightningElement, api } from "lwc";

export default class ObjectIcon extends LightningElement {
  @api iconUrl;
  @api color;

  get iconStyle() {
    return `background-color: ${this.color}`;
  }
}