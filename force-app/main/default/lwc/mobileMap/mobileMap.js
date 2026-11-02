import { LightningElement, api, track } from "lwc";

export default class MobileMap extends LightningElement {
  // Markers
  @api filteredMarkers = [];
  @api currentMarker;
  @api currentMarkerInd = 0;
  @api setCurrentMarker;
  @api redirectToMarkerDetails;
  @api routeToMarkerLocation;
  @api handleError;
  resourceMarker;
  markersWithResource = [];
  // Center on the technician by default; only re-center on a part once selected.
  located = true;

  @track showCard;
  @api currentMarkerSet(init) {
    // init = initial load / filter change -> keep map centered on the technician.
    // Marker selection (init falsy) -> center on the chosen part and show its card.
    this.located = !!init;
    this.setCardState(!init);
  }

  // Map options
  zoom = 13;
  listView = "";
  mapOptions = {
    disableDefaultUI: true,
    zoomControl: false
  };

  renderedCallback() {
    if (!this.isMarkersListEqual()) {
      this.markersWithResource = this.resourceMarker
        ? [...this.filteredMarkers, this.resourceMarker]
        : [...this.filteredMarkers];
    }
  }

  isMarkersListEqual() {
    const markers = this.markersWithResource.filter(
      (m) => m.value !== undefined
    );
    return (
      this.filteredMarkers.length === markers.length &&
      this.filteredMarkers.every(
        (m, ind) => m.value.id === markers[ind].value.id
      )
    );
  }

  @api setResourceMarker({ lat, lng }) {
    if (!lat || !lng) return;
    this.resourceMarker = {
      location: {
        Latitude: lat,
        Longitude: lng
      },
      mapIcon: this.getResourceMarkerSVG()
    };
  }

  onMarkerSelect(event) {
    try {
      if (!event.target.selectedMarkerValue) return;
      const ind = this.filteredMarkers.findIndex(
        (m) => m.value.id === event.target.selectedMarkerValue.id
      );
      if (ind > -1) this.setCurrentMarker(ind);
    } catch (error) {
      this.handleError(error);
    }
  }

  // Buttons Handlers

  handleLocatorClick() {
    this.located = true;
    this.setCardState(false);
  }

  handleCloseCardClick() {
    this.setCardState(false);
  }

  handleRedirectClick = () => {
    this.redirectToMarkerDetails();
  };

  handleRouteClick = () => {
    this.routeToMarkerLocation();
  };

  handleBackCardClick() {
    let ind = this.currentMarkerInd - 1;
    if (ind < 0) ind = this.filteredMarkers.length - 1;
    this.setCurrentMarker(ind);
  }

  handleNextCardClick() {
    const ind = (this.currentMarkerInd + 1) % this.filteredMarkers.length;
    this.setCurrentMarker(ind);
  }

  // Getters & Helpers

  get center() {
    if (this.located) return this.resourceMarker ?? this.currentMarker;
    return this.currentMarker ?? this.resourceMarker;
  }

  get currentMarkerTitle() {
    return this.currentMarker?.value?.titleFieldValue;
  }

  get currentMarkerFirstDetailFieldName() {
    return this.currentMarker?.value?.firstDetailFieldLabel;
  }

  get currentMarkerFirstDetailFieldValue() {
    return this.currentMarker?.value?.firstDetailFieldValue;
  }

  get currentMarkerIndexUi() {
    const indUi = this.currentMarkerInd + 1;
    return isNaN(indUi) ? 0 : indUi;
  }

  get currentMarkerDistance() {
    return this.currentMarker?.value?.distance;
  }

  get currentMarkerTechnicianName() {
    return this.currentMarker?.value?.technicianName;
  }

  get currentMarkerTechnicianPhone() {
    return this.currentMarker?.value?.technicianPhone;
  }

  get currentMarkerPhoneHref() {
    const phone = this.currentMarker?.value?.technicianPhone;
    return phone ? `tel:${phone}` : undefined;
  }

  get currentMarkerAsOf() {
    return this.currentMarker?.value?.asOf;
  }

  get currentMarkerIconUrl() {
    return this.currentMarker?.value?.iconUrl;
  }

  setCardState = (state) => {
    this.showCard = state;
  };

  getResourceMarkerSVG() {
    const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="22" height="22" viewBox="0 0 22 22"><circle cx="11" cy="11" r="7" fill="#1b96ff" stroke="white" stroke-width="3"/></svg>`;
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(icon);
  }
}