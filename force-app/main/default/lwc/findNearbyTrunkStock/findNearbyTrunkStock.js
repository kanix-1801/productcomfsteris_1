import { LightningElement, wire } from "lwc";
import { gql, graphql } from "lightning/uiGraphQLApi";
import { NavigationMixin } from "lightning/navigation";
import Id from "@salesforce/user/Id";
import ConfirmModal from "c/confirmModal";
import overrideCSS from "./overrideCSS";

const DISTANCE_UNIT = "km";
const EARTH_RADIUS_KM = 6371;

export default class FindNearbyTrunkStock extends NavigationMixin(
  LightningElement
) {
  userId = Id;

  // Resolved from the technician query
  center; // { lat, lng } of the working tech (map center / distance origin)
  ownLocationId; // working tech's own van - excluded from results
  resourceCoordsByLocation = {}; // LocationId -> { lat, lng, technicianName, asOf }

  // Raw query state
  techDataLoaded = false;
  partsDataLoaded = false;
  rawParts = [];
  resourceMarkerSet = false;

  // Marker state
  allMarkers = [];
  filteredMarkers = [];
  currentMarker;
  currentMarkerInd = 0;

  // Filter state
  currentProductName = "";
  productNameOptions = [];
  currentObject; // { label, plural } - drives the list loaded state

  init = false;

  connectedCallback() {
    const myStyle = document.createElement("style");
    // eslint-disable-next-line @lwc/lwc/no-inner-html
    myStyle.innerHTML = overrideCSS;
    document.head.appendChild(myStyle);
  }

  renderedCallback() {
    if (!this.init) {
      this.init = true;
      window.visualViewport?.addEventListener("resize", () => {
        if (window.visualViewport.height === window.innerHeight)
          window.scrollTo(0, 0);
      });
    }
    if (this.center && !this.resourceMarkerSet) {
      const map = this.template.querySelector("c-mobile-map");
      if (map) {
        map.setResourceMarker({ lat: this.center.lat, lng: this.center.lng });
        this.resourceMarkerSet = true;
      }
    }
  }

  // Query 1 - technicians (working tech + adjacent techs).
  // One query gives both the map center and the per-van coordinates.
  @wire(graphql, {
    query: gql`
      query Technicians {
        uiapi {
          query {
            ServiceResource(
              where: {
                and: [{ IsActive: { eq: true } }, { LocationId: { ne: null } }]
              }
              first: 2000
            ) {
              edges {
                node {
                  Id
                  RelatedRecordId {
                    value
                  }
                  RelatedRecord {
                    ... on User {
                      MobilePhone {
                        value
                      }
                    }
                  }
                  Name {
                    value
                  }
                  LocationId {
                    value
                  }
                  LastKnownLatitude {
                    value
                  }
                  LastKnownLongitude {
                    value
                  }
                  LastKnownLocationDate {
                    value
                  }
                }
              }
            }
          }
        }
      }
    `
  })
  wiredTechnicians({ data, errors }) {
    if (data) {
      this.processTechnicians(data);
      this.techDataLoaded = true;
      this.buildMarkers();
    } else if (errors) {
      this.handleError(errors);
    }
  }

  // Query 2 - product items (trunk stock).
  @wire(graphql, {
    query: gql`
      query Parts {
        uiapi {
          query {
            ProductItem(
              where: {
                and: [
                  { LocationId: { ne: null } }
                  { QuantityOnHand: { gt: 0 } }
                ]
              }
              first: 2000
            ) {
              edges {
                node {
                  Id
                  ProductName {
                    value
                  }
                  QuantityOnHand {
                    value
                  }
                  QuantityUnitOfMeasure {
                    value
                  }
                  SerialNumber {
                    value
                  }
                  IsProduct2Serialized {
                    value
                  }
                  LocationId {
                    value
                  }
                  Location {
                    Name {
                      value
                    }
                  }
                }
              }
            }
          }
        }
      }
    `
  })
  wiredParts({ data, errors }) {
    if (data) {
      this.rawParts = data.uiapi?.query?.ProductItem?.edges ?? [];
      this.partsDataLoaded = true;
      this.buildMarkers();
    } else if (errors) {
      this.handleError(errors);
    }
  }

  processTechnicians(data) {
    const edges = data.uiapi?.query?.ServiceResource?.edges ?? [];
    const map = {};
    edges.forEach((edge) => {
      const node = edge.node;
      const locId = node.LocationId?.value;
      const lat = node.LastKnownLatitude?.value;
      const lng = node.LastKnownLongitude?.value;
      const relatedId = node.RelatedRecordId?.value;
      const phone = node.RelatedRecord?.MobilePhone?.value;

      // Working tech: capture own van + map center
      if (relatedId === this.userId) {
        this.ownLocationId = locId;
        if (lat != null && lng != null) this.center = { lat, lng };
      }

      if (locId && lat != null && lng != null) {
        map[locId] = {
          lat,
          lng,
          technicianName: node.Name?.value,
          technicianPhone: phone,
          asOf: node.LastKnownLocationDate?.value
        };
      }
    });
    this.resourceCoordsByLocation = map;
  }

  buildMarkers() {
    if (!this.techDataLoaded || !this.partsDataLoaded) return;
    try {
      const markers = [];
      const names = new Set();
      this.rawParts.forEach((edge) => {
        const node = edge.node;
        const locId = node.LocationId?.value;
        if (!locId) return;
        // Exclude the working tech's own van
        if (this.ownLocationId && locId === this.ownLocationId) return;
        const coords = this.resourceCoordsByLocation[locId];
        // Skip parts whose technician has no known location
        if (!coords) return;
        markers.push(this.createMarker(node, coords));
        const productName = node.ProductName?.value;
        if (productName) names.add(productName);
      });
      this.allMarkers = markers;
      this.productNameOptions = [...names].sort((a, b) =>
        a.toLowerCase() < b.toLowerCase() ? -1 : 1
      );
      this.currentObject = { label: "Product Item", plural: "Product Items" };
      this.applyFilter();
    } catch (error) {
      this.handleError(error);
    }
  }

  createMarker(node, coords) {
    const id = node.Id;
    const lat = coords.lat;
    const lng = coords.lng;
    const qty = node.QuantityOnHand?.value;
    const navUrl = `com.salesforce.fieldservice://v1/sObject/${id}/details`;
    const routeUrl = `https://www.google.com/maps/dir/?api=1&destination=${lat},${lng}&travelmode=driving`;
    return {
      location: { Latitude: lat, Longitude: lng },
      mapIcon: this.getMarkerSVG("#0d7fa8"),
      value: {
        id,
        titleFieldValue: node.ProductName?.value,
        firstDetailFieldLabel: "Quantity On Hand",
        firstDetailFieldValue: this.formatQuantity(qty),
        unitOfMeasure: node.QuantityUnitOfMeasure?.value,
        serialNumber: node.SerialNumber?.value,
        isSerialized: node.IsProduct2Serialized?.value,
        locationName: node.Location?.Name?.value,
        technicianName: coords.technicianName,
        technicianPhone: coords.technicianPhone,
        distance: this.getDistanceText(lat, lng),
        asOf: this.formatAsOf(coords.asOf),
        iconUrl: undefined,
        color: "#0d7fa8",
        navUrl,
        routeUrl
      }
    };
  }

  applyFilter() {
    let markers = this.allMarkers;
    if (this.currentProductName) {
      markers = markers.filter(
        (m) => m.value.titleFieldValue === this.currentProductName
      );
    }
    this.filteredMarkers = markers;
    this.setCurrentMarker(0, true);
  }

  setProductNameFilter = (name) => {
    this.currentProductName = name;
    this.applyFilter();
  };

  setCurrentMarker = (ind, init = false) => {
    try {
      this.currentMarkerInd = ind;
      this.currentMarker = this.filteredMarkers.length
        ? { ...this.filteredMarkers[ind] }
        : undefined;
      this.template.querySelector("c-locations-list")?.currentMarkerSet();
      this.template.querySelector("c-mobile-map")?.currentMarkerSet(init);
    } catch (error) {
      this.handleError(error);
    }
  };

  // Navigation handlers

  redirectToMarkerDetails = async (ind) => {
    const index = ind ?? this.currentMarkerInd;
    let toOpen = true;
    if (this.isIos()) {
      toOpen = await ConfirmModal.open({
        content: "Opening the record resets your search.",
        header: "Open Record?",
        okButtonText: "Open Record",
        cancelButtonText: "Cancel"
      });
    }
    if (toOpen) {
      // Use standard__recordPage (in-app navigation) so the Field Service
      // mobile back button returns to this map instead of resetting to the
      // schedule. The deep-link scheme is treated as an external request and
      // loses the back-stack context.
      this[NavigationMixin.Navigate]({
        type: "standard__recordPage",
        attributes: {
          recordId: this.filteredMarkers[index].value.id,
          objectApiName: "ProductItem",
          actionName: "view"
        }
      });
    }
  };

  routeToMarkerLocation = (ind) => {
    const index = ind ?? this.currentMarkerInd;
    this[NavigationMixin.Navigate]({
      type: "standard__webPage",
      attributes: { url: this.filteredMarkers[index].value.routeUrl }
    });
  };

  // Helpers

  formatQuantity(qty) {
    if (qty === null || qty === undefined) return "";
    return Number(qty).toFixed(2);
  }

  formatAsOf(dateStr) {
    if (!dateStr) return "";
    const d = new Date(dateStr);
    if (isNaN(d.getTime())) return "";
    return d.toLocaleString();
  }

  getDistanceText(lat, lng) {
    if (!this.center) return "";
    const dist = this.getDistance(this.center.lat, this.center.lng, lat, lng);
    return `${dist.toFixed(2)} ${DISTANCE_UNIT}`;
  }

  getDistance(lat1, lng1, lat2, lng2) {
    const deg2rad = (deg) => deg * (Math.PI / 180);
    const dLat = deg2rad(lat2 - lat1);
    const dLng = deg2rad(lng2 - lng1);
    const a =
      Math.sin(dLat / 2) * Math.sin(dLat / 2) +
      Math.cos(deg2rad(lat1)) *
        Math.cos(deg2rad(lat2)) *
        Math.sin(dLng / 2) *
        Math.sin(dLng / 2);
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return EARTH_RADIUS_KM * c;
  }

  isIos = () => {
    const isIpad =
      navigator.userAgent.includes("Macintosh") &&
      navigator.maxTouchPoints &&
      navigator.maxTouchPoints > 1;
    const isIphone = navigator.platform.includes("iPhone");
    return isIpad || isIphone;
  };

  getMarkerSVG(color) {
    const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="36" height="44" viewBox="0 0 36 44"><path d="M18 1C9.2 1 2 8.2 2 17c0 11 16 26 16 26s16-15 16-26C34 8.2 26.8 1 18 1z" fill="${color}" stroke="white" stroke-width="2"/><circle cx="18" cy="17" r="6" fill="white"/></svg>`;
    return "data:image/svg+xml;charset=UTF-8," + encodeURIComponent(icon);
  }

  handleError = (error) => {
    // eslint-disable-next-line no-console
    console.error("FindNearbyTrunkStock error", error);
  };
}