public with sharing class ServiceRequestHandler {
  public class ConfigurationException extends Exception {
  }

  public static void handle(
    List<ServiceRequest__c> newRecords,
    Map<Id, ServiceRequest__c> oldMap,
    Boolean isInsert,
    Boolean isUpdate
  ) {
    if (newRecords == null || newRecords.isEmpty()) {
      return;
    }

    // we collect the ids first so we don't need to query inside the loop
    Set<Id> customerIds = new Set<Id>();
    Set<Id> criticalRequestIds = new Set<Id>();

    for (ServiceRequest__c req : newRecords) {
      // we need a saved request id before we can connect a task or audit to it
      if (req == null || req.Id == null) {
        continue;
      }
      if (req.Customer__c != null) {
        customerIds.add(req.Customer__c);
      }

      ServiceRequest__c oldReq = oldMap == null ? null : oldMap.get(req.Id);
      Boolean becameCritical =
        req.Priority__c == 'Critical' &&
        (isInsert == true ||
        (isUpdate == true &&
        oldReq != null &&
        oldReq.Priority__c != req.Priority__c));
      if (becameCritical) {
        criticalRequestIds.add(req.Id);
      }
    }

    // we only need the manager id if we're actually creating a task
    Id serviceManagerId = criticalRequestIds.isEmpty()
      ? null
      : getServiceManagerId();

    Map<Id, Customer__c> customersByIds = new Map<Id, Customer__c>();
    if (!customerIds.isEmpty()) {
      // i used ai for the soql syntax here. this gets customers by id and returns Id and Name
      customersByIds = new Map<Id, Customer__c>(
        [
          SELECT Id, Name
          FROM Customer__c
          WHERE Id IN :customerIds
          WITH SYSTEM_MODE
        ]
      );
    }

    List<Task> tasksToInsert = new List<Task>();
    List<ServiceAudit__c> auditsToInsert = new List<ServiceAudit__c>();
    Map<Id, Customer__c> customersToUpdate = new Map<Id, Customer__c>();

    for (ServiceRequest__c req : newRecords) {
      if (req == null || req.Id == null) {
        continue;
      }
      Customer__c customer = customersByIds.get(req.Customer__c);
      ServiceRequest__c oldReq = oldMap == null ? null : oldMap.get(req.Id);
      Boolean statusChanged =
        isUpdate == true &&
        oldReq != null &&
        oldReq.Status__c != req.Status__c;

      if (criticalRequestIds.contains(req.Id)) {
        tasksToInsert.add(
          new Task(
            OwnerId = serviceManagerId,
            Subject = 'Critical Service Request',
            WhatId = req.Id,
            Status = 'Not Started',
            Priority = 'High'
          )
        );
      }

      if (statusChanged && req.Status__c == 'Resolved' && customer != null) {
        customersToUpdate.put(
          customer.Id,
          new Customer__c(
            Id = customer.Id,
            LastResolvedRequestDate__c = Date.today()
          )
        );
      }

      if (statusChanged) {
        auditsToInsert.add(
          new ServiceAudit__c(
            ServiceRequest__c = req.Id,
            OldStatus__c = oldReq.Status__c,
            NewStatus__c = req.Status__c,
            CustomerName__c = customer == null ? null : customer.Name,
            ChangedAt__c = Datetime.now()
          )
        );
      }
    }

    // these records are created by our automation, so the user doesn't need permission to write audits
    // we keep this in one transaction so a failure doesn't leave half the work saved
    if (!tasksToInsert.isEmpty()) {
      insert as system tasksToInsert;
    }
    if (!auditsToInsert.isEmpty()) {
      insert as system auditsToInsert;
    }
    if (!customersToUpdate.isEmpty()) {
      update as system customersToUpdate.values();
    }
  }

  private static Id getServiceManagerId() {
    // the pdf only gives us the metadata type, so i chose these record and field names
    Service_Settings__mdt settings = Service_Settings__mdt.getInstance(
      'Default'
    );
    if (settings == null || String.isBlank(settings.ServiceManagerId__c)) {
      throw new ConfigurationException(
        'Configure Service_Settings__mdt.Default.ServiceManagerId__c before saving a Critical request.'
      );
    }

    Id managerId;
    try {
      managerId = Id.valueOf(settings.ServiceManagerId__c.trim());
    } catch (Exception ex) {
      throw new ConfigurationException(
        'The configured service manager must be a valid User Id.'
      );
    }
    if (managerId.getSObjectType() != User.SObjectType) {
      throw new ConfigurationException(
        'The configured service manager must be a User Id.'
      );
    }

    List<User> managers = [
      SELECT Id
      FROM User
      WHERE Id = :managerId AND IsActive = TRUE
      WITH SYSTEM_MODE
      LIMIT 1
    ];
    if (managers.isEmpty()) {
      throw new ConfigurationException(
        'The configured service manager must be an active user.'
      );
    }
    return managers[0].Id;
  }
}
