public with sharing class ServiceRequestController {
  private static final Set<String> PRIORITIES = new Set<String>{
    'Low',
    'Medium',
    'High',
    'Critical'
  };
  private static final Set<String> STATUSES = new Set<String>{
    'New',
    'In Progress',
    'Resolved',
    'Closed'
  };

  @AuraEnabled
  public static Id saveServiceRequest(
    Id customerId,
    String priority,
    String status,
    String description
  ) {
    if (!PRIORITIES.contains(priority) || !STATUSES.contains(status)) {
      throw new AuraHandledException('Choose a valid priority and status.');
    }
    if (String.isBlank(description) || description.length() > 32768) {
      throw new AuraHandledException(
        'Enter a description of up to 32,768 characters.'
      );
    }
    if (
      customerId != null &&
      customerId.getSObjectType() != Customer__c.SObjectType
    ) {
      throw new AuraHandledException('Choose a valid customer.');
    }

    try {
      // if we got a customer id, we need to check that the user can read it
      if (customerId != null) {
        List<Customer__c> customers = [
          SELECT Id
          FROM Customer__c
          WHERE Id = :customerId
          WITH USER_MODE
          LIMIT 1
        ];
        if (customers.isEmpty()) {
          throw new AuraHandledException('The customer is unavailable.');
        }
      }

      // we only take the fields from our form so the client can't set other fields
      ServiceRequest__c request = new ServiceRequest__c(
        Customer__c = customerId,
        Priority__c = priority,
        Status__c = status,
        Description__c = description.trim()
      );
      insert as user request;
      return request.Id;
    } catch (Exception error) {
      // we don't want to expose internal errors or records the user can't access
      throw new AuraHandledException(
        'Unable to save. Check your access and input, or contact your administrator.'
      );
    }
  }

  // we don't cache this because the summary needs the latest data after each save
  @AuraEnabled
  public static ServiceRequest__c getServiceRequest(Id recordId) {
    if (
      recordId == null ||
      recordId.getSObjectType() != ServiceRequest__c.SObjectType
    ) {
      throw new AuraHandledException('Choose a valid service request.');
    }
    try {
      // I used AI to help with the SOQL syntax here.
      ServiceRequest__c request = [
        SELECT Id, Name, Customer__c, Priority__c, Status__c, Description__c
        FROM ServiceRequest__c
        WHERE Id = :recordId
        WITH USER_MODE
        LIMIT 1
      ];
      // we read the customer separately to check its record permissions too
      if (request.Customer__c != null) {
        Id customerId = request.Customer__c;
        List<Customer__c> customers = [
          SELECT Id, Name
          FROM Customer__c
          WHERE Id = :customerId
          WITH USER_MODE
          LIMIT 1
        ];
        if (!customers.isEmpty()) {
          request.Customer__r = customers[0];
        }
      }
      return request;
    } catch (Exception error) {
      throw new AuraHandledException(
        'Unable to load this request. Check your access or contact your administrator.'
      );
    }
  }
}
