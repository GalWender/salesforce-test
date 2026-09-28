import { LightningElement, wire } from "lwc";
import {
  APPLICATION_SCOPE,
  MessageContext,
  subscribe,
  unsubscribe
} from "lightning/messageService";
import SERVICE_REQUEST_SAVED from "@salesforce/messageChannel/ServiceRequestSaved__c";
import getServiceRequest from "@salesforce/apex/ServiceRequestController.getServiceRequest";

export default class ServiceRequestSummary extends LightningElement {
  messageContext;

  @wire(MessageContext)
  setMessageContext(context) {
    this.messageContext = context;
    this.subscribeToMessages();
  }

  subscription;
  recordId;
  request;
  isLoading = false;
  errorMessage = "";
  loadVersion = 0;

  connectedCallback() {
    this.subscribeToMessages();
  }

  subscribeToMessages() {
    if (this.isConnected && this.messageContext && !this.subscription) {
      this.subscription = subscribe(
        this.messageContext,
        SERVICE_REQUEST_SAVED,
        (message) => this.handleMessage(message),
        { scope: APPLICATION_SCOPE }
      );
    }
  }

  disconnectedCallback() {
    if (this.subscription) unsubscribe(this.subscription);
    this.subscription = null;
    this.loadVersion += 1;
    this.isLoading = false;
  }

  get customerName() {
    return this.request?.Customer__r?.Name || "No customer available";
  }

  handleMessage(message) {
    if (
      typeof message?.recordId !== "string" ||
      !/^[a-zA-Z0-9]{15}(?:[a-zA-Z0-9]{3})?$/.test(message.recordId)
    ) {
      return;
    }
    this.recordId = message.recordId;
    this.loadRequest();
  }

  async loadRequest() {
    // we only want the latest response if two saves happen close together
    const version = ++this.loadVersion;
    this.isLoading = true;
    this.errorMessage = "";
    this.request = null;
    try {
      const request = await getServiceRequest({ recordId: this.recordId });
      if (version === this.loadVersion && this.isConnected) {
        this.request = request;
      }
    } catch (error) {
      if (version === this.loadVersion && this.isConnected) {
        this.errorMessage =
          error?.body?.message ||
          "Unable to load the request. Please try again.";
      }
    } finally {
      if (version === this.loadVersion && this.isConnected)
        this.isLoading = false;
    }
  }
}
