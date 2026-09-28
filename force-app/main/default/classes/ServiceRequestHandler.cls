public with sharing class ServiceRequestHandler {
    public static void handle(
        List<ServiceRequest__c> newRecords,
    Map<Id, ServiceRequest__c> oldMap,
    Boolean isInsert,
    Boolean isUpdate
    ) {
        Set<Id> customerIds = new Set<Id>(); // we don't want to soql in loops and we don't have the customers yet so we need to collect the ids
        
        for(ServiceRequest__c req:newRecords){// i used ai for the for loop syntax here because im still getting fimiliar with apex syntax
            
            if(req.Customer__c != null) {
                customerIds.add(req.Customer__c);
            }
        }
        
        // we have all ids now we need to query all in bulk
        Map<Id,Custemor__c> customersByIds = new Map<Id,Customer__c>();
        
        if(!customerIds.isEmpty()){
            customersByIds = new Map<Id,Customer__c>([ //needed some ai help for the query soql syntax
                SELECT Id, Name
                FROM Customer__c
                WHERE Id IN :customerIds // brings all the records/objects from db that are found in accordince with Id and Name
                ]);
        }
        
        for(ServiceRequest__c req:newRecords){
            
            Customer__c customer = req.Custemor__c;
        }
        
    }
}