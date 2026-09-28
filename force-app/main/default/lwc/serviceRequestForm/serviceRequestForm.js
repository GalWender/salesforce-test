import { LightningElement, wire } from "lwc";
import { MessageContext, publish } from "lightning/messageService";
import SERVICE_REQUEST_SAVED from "@salesforce/messageChannel/ServiceRequestSaved__c";
import saveServiceRequest from "@salesforce/apex/ServiceRequestController.saveServiceRequest";

const PRIORITIES = ["Low", "Medium", "High", "Critical"];
const STATUSES = ["New", "In Progress", "Resolved", "Closed"];

export default class ServiceRequestForm extends LightningElement {
  @wire(MessageContext) messageContext;

  customerId = null;
  priority = "Medium";
  status = "New";
  description = "";
  isSaving = false;
  errorMessage = "";
  successMessage = "";

  priorityOptions = PRIORITIES.map((value) => ({ label: value, value }));
  statusOptions = STATUSES.map((value) => ({ label: value, value }));

  handleCustomerChange(event) {
    this.customerId = event.detail.recordId;
  }

  handleFieldChange(event) {
    const { name } = event.target;
    if (["priority", "status", "description"].includes(name)) {
      this[name] = event.detail.value;
    }
  }

  async handleSave(event) {
    event.preventDefault();
    if (this.isSaving) return;

    this.errorMessage = "";
    this.successMessage = "";
    const fields = this.template.querySelectorAll(
      "lightning-record-picker, lightning-combobox, lightning-textarea"
    );
    let validFields = true;
    for (const field of fields) {
      field.reportValidity();
      if (!field.checkValidity()) {
        validFields = false;
      }
    }
    if (
      !validFields ||
      !this.description.trim() ||
      this.description.length > 32768 ||
      !PRIORITIES.includes(this.priority) ||
      !STATUSES.includes(this.status)
    ) {
      this.errorMessage =
        "Check the fields and enter a description before saving.";
      return;
    }

    this.isSaving = true;
    try {
      const recordId = await saveServiceRequest({
        customerId: this.customerId,
        priority: this.priority,
        status: this.status,
        description: this.description.trim()
      });
      this.successMessage = "Service request saved.";
      try {
        publish(this.messageContext, SERVICE_REQUEST_SAVED, { recordId });
      } catch {
        this.errorMessage =
          "The request was saved, but the summary could not be notified.";
      }
    } catch (error) {
      this.errorMessage =
        error?.body?.message || "Unable to save. Please try again.";
    } finally {
      this.isSaving = false;
    }
  }
}
