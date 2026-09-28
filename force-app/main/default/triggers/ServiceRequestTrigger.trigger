trigger ServiceRequestTrigger on ServiceRequest__c(after insert, after update) {
  // we need the request id for its tasks and audits
  ServiceRequestHandler.handle(
    Trigger.new,
    Trigger.oldMap,
    Trigger.isInsert,
    Trigger.isUpdate
  );
}
