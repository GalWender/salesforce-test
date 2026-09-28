# Salesforce assignment

- [Answers](ANSWERS.md)
- [Flow diagram](docs/service-request-flow.png)
- [Editable Excalidraw file](docs/service-request-flow.excalidraw)

The code is in `force-app/main/default`.

## Setup

```powershell
sf org login web --alias service-request-dev
sf project deploy start --source-dir force-app --target-org service-request-dev --wait 30
```

In Custom Metadata Types → Service Settings, create a record named `Default` and set `ServiceManagerId__c` to the manager's User ID.

Assign `Service_Agent` to users. Managers also need `Service_Manager`. Add `serviceRequestForm` and `serviceRequestSummary` to a Lightning App or Home page. The team-sharing setup is described in Part E of the answers.

Part C is the diagram only. The Apex and UI still need checking in a Salesforce org.
