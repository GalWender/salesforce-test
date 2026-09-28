# Salesforce Full Stack Test

## Part A - Apex, Triggers and Bulkification

### Task 1 - Trigger

The code is in `ServiceRequestTrigger.trigger` and `ServiceRequestHandler.cls`.

I used AI for Salesforce-specific help, including Apex/SOQL syntax. I'm still getting familiar with Apex and don't remember the query syntax off by heart.

Explanation:

1. I used after insert and after update because we need the saved request ID for the Task and audit.
2. The trigger calls the handler, where the actual logic is.
3. We collect the Customer IDs in a Set first, then query them together. We don't want SOQL inside the loop.
4. On update, we get the old request from `oldMap` and compare its status with the new one.
5. If the priority starts as Critical or changes to Critical, we create a Task for the service manager.
6. If the status changes to Resolved, we update the customer's date. A Map stops us from updating the same customer several times.
7. Any real status change gets an audit with the request ID, old/new status, customer name, and time. An insert doesn't have an old status to compare.
8. We prepare the Tasks, audits, and customer updates in memory, then save each collection outside the loops.

**Manager ID:** The PDF doesn't name the record or field, so I used `Default.ServiceManagerId__c` in `Service_Settings__mdt`. We still need to create that record in Salesforce and enter an active manager's User ID. The helper checks the ID when a Task is needed; there's no hard-coded user.

**Missing customer:** We can still create a Task or audit. We leave the audit's customer name empty and skip updating the customer. The code also checks for missing old records before comparing values.

**Queries/DML:** One customer query, and one active-user query if we need the manager. Reading the metadata with `getInstance` doesn't add a SOQL query. Then we have up to three DML statements: insert Tasks, insert audits, update customers. Empty collections are skipped. That's at most **2 SOQL queries and 3 DML statements per handler run**, even for 200 requests. The original save and any other automation still use the same transaction limits. [Metadata lookup reference](https://help.salesforce.com/s/articleView?id=release-notes.rn_forcecom_dev_static_accessor.htm&language=en_US&release=230&type=5).

I treated “when Critical” as entering Critical. Otherwise, changing only the description would create another Task. If a request leaves Critical and later becomes Critical again, it gets a new Task.

### Task 2 - Code Review

**A. Main problems:** There's a query inside the loop and an insert inside the loop. The customer query can also fail if the customer is missing. Checking only `Status__c == 'Resolved'` doesn't tell us whether the status changed, so unrelated edits can create extra audits. It also misses real changes to other statuses. The old status and change time are missing too.

**B. Bulk update:** With 200 records, we could try to run 200 queries and 200 inserts. The usual synchronous limits are 100 SOQL queries and 150 DML statements, so this can fail and roll back the transaction. Other automation may already have used some of that limit. [SOQL/DML reference](https://developer.salesforce.com/blogs/2022/08/working-with-salesforce-records-using-soql-and-dml).

**C. What I would change:** Collect the customer IDs, query once, and use a Map to find each customer. Collect the audits in a List and insert them after the loop. Check for missing customers before using their fields.

**D. How I check a change:** Get the old request from `oldMap`, check that it exists, and compare `oldReq.Status__c != req.Status__c`. For the resolved-date update, we also check that the new value is Resolved.

## Part B - Governor Limits, Performance and Scale

### 1. Five things I would check when Data Loader fails

- The actual errors and logs: is it a limit, validation, permission, or record-lock problem?
- Queries or DML inside loops, including calls hidden inside helper methods.
- CPU time, memory usage, and queries returning too many records.
- Other triggers and Flows running in the same transaction, especially if they keep updating each other.
- What happens with 200 records, including several requests for the same customer. Parallel batches might be trying to update that customer at the same time.

### 2. Recalculating SLA for 100,000 requests

I would use Batch Apex. It splits the work into smaller batches, with separate transaction limits for each batch. I would use a `Database.QueryLocator`, calculate the changes in `execute`, and update the batch together. I would also record failures so they can be retried.

A trigger would make a normal save do too much work. Queueable is useful for smaller background jobs, but Batch Apex fits this large set of records better. I wouldn't use a Flow for this calculation. [Batch Apex reference](https://developer.salesforce.com/docs/atlas.en-us.apexcode.meta/apexcode/apex_batch_interface.htm).

### 3. Why Governor Limits exist

Salesforce shares server resources between customers. One transaction can't be allowed to use everything. For us, that means thinking about the full batch, querying only what we need, and doing database operations together. Working with one record doesn't tell us much about how the code handles 200.

### 4. Three things to collect before doing them

- Customer IDs in a Set, then one query using `WHERE Id IN :customerIds`.
- Tasks in a List, then one insert.
- Customer updates in a Map by ID, then one update of the Map's values.

### 5. Flow/trigger recursion

I would check whether the Flow changes something that runs the trigger again, and whether the trigger causes the Flow to run again. We should compare old/new values and avoid updating a field when it already has the right value.

If we're only changing the current record, before-save logic can avoid an extra update. I would also keep each rule in one place. A single static Boolean isn't a great fix because it can skip other records that still need processing.

### 6. A query gets slow with millions of records

I would look at the Query Plan and how many records the filters actually match. We need filters that narrow the results enough, ideally using suitable indexed fields. An index won't help much if most records still match.

I would also check broad `OR` conditions, negative filters, and searches starting with a wildcard. Then I'd narrow the filters, return only the fields we need, and check whether an additional index would help.

## Part C - Record-Triggered Flow

I used AI to help create and arrange the Excalidraw diagram.

[Editable Excalidraw file](docs/service-request-flow.excalidraw) · [PNG](docs/service-request-flow.png) · [SVG](docs/service-request-flow.svg)

No org is configured yet, so this is just the Flow design.

**Entry criteria:** Run after a Service Request is updated, when its status changes to In Progress or Closed, or its priority changes to Critical. Just staying Critical isn't enough to run it again.

The decisions and actions are:

1. Check whether the status changed to In Progress or Closed.
2. If there's a customer, get it. For In Progress, the new `ServiceState__c` is Active Handling. For Closed, it's Needs Review.
3. Update the customer only if we found it and its state is different. Otherwise skip this update.
4. Then check the priority separately. We need both paths to work if status and priority changed in the same save.
5. If priority changed to Critical, get `Service_Settings__mdt.Default` and check its `ServiceManagerId__c` points to an active User.
6. Create an `Escalation__c` linked to the request and owned by that manager. The PDF doesn't give the escalation fields, so the diagram assumes a `ServiceRequest__c` lookup and `OwnerId`.
7. If a Get/Update/Create operation fails, or the manager setup is invalid, go to a Custom Error and roll back the save. A missing customer only skips the customer update.

**Notification:** The diagram has a second Flow when an Escalation is created. It runs asynchronously after the save commits. It gets the configured `CustomNotificationType`, puts the manager ID in the recipient collection, and sends a notification with the request as its target.

If that lookup or send fails, the fault path reports it to the administrator for a manual retry. If reporting also fails, it should reach Salesforce's Flow error monitoring. The saved request and escalation remain. We still need to configure the notification type and admin reporting in the org. [Notification action reference](https://help.salesforce.com/s/articleView?id=flow_ref_elements_actions_sendcustomnotification.htm&language=en_US&type=5).

**Why after-save:** We're updating another record and creating a related escalation, so I chose after-save. Before-save is useful when we're setting fields on the request itself. The normal after-save actions are still in the original transaction; the notification path runs after commit.

**When I would choose Apex:** Recalculating SLA for 100,000 requests; or handling several requests for the same customer when we need to decide which update wins.

**When I would choose Flow:** Setting a default field before save; or a small status-change rule that updates a related customer.

One missing business rule: if two requests for the same customer become In Progress and Closed together, which customer state should win? I'd confirm that before activating the Flow.

## Part D - LWC

I used AI to help build the LWC UI and with the Salesforce-specific parts. The UI uses the standard Salesforce inputs, buttons, and spinner.

The components are `serviceRequestForm` and `serviceRequestSummary`, with `ServiceRequestController` for saving and reading.

**Data flow:** Fill in the form → save through Apex → get the saved ID → publish it through Lightning Message Service → the summary receives it → fetch the current record from Salesforce.

I used LMS because these components don't have a shared parent. Sending only an ID also means the summary has to reload the real data, including any changes made by automation. It doesn't just display the values from the form.

The form checks input, shows a spinner, and blocks another save while a request is running. Both components show errors. The summary also handles loading and ignores an older response if a newer save has already started loading.

**Security:** The controller uses `with sharing`, `WITH USER_MODE`, and `insert as user` to check the user's record, object, and field permissions. It checks the customer separately, validates the inputs, and only accepts the form fields. It doesn't return `InternalCost__c`. The user also needs access to the Apex class. [Apex security reference](https://developer.salesforce.com/docs/platform/lwc/guide/apex-security).

The trigger's automatic Task/audit/customer operations explicitly use system mode. That lets the automation create audits without giving the representative direct permission to create them. The handler still uses `with sharing`.

**React → LWC:**

- **State:** In React I'd use `useState`. Here we use fields on the component class. For objects and arrays, we assign a new value so the UI updates.
- **Props/events:** LWC uses `@api` for public values and `CustomEvent` to communicate upward. The child shouldn't change a value owned by the parent. For our unrelated components, we use LMS.
- **API calls:** We import an Apex method and call it asynchronously for saving. `@wire` can provide data reactively. It's not a direct replacement for `useEffect`, and we still need to think about cached data and refreshing it.

## Part E - Data Model + Security

### 1. Relationships

One Customer can have many Service Requests, and one Request can have many Audits. The request points to the customer, and each audit points to its request.

The customer name on the audit is a saved copy from that moment. Renaming the customer later shouldn't change an old audit.

### 2. Lookup or Master-Detail

I chose an optional Lookup from Request to Customer because we need to handle requests without a customer. The request also keeps its own owner and sharing.

For Audit to Request, I chose a required Lookup that prevents deleting a request while its audits exist. Master-Detail would delete the audits along with the request. With Lookup, we need to configure audit sharing ourselves.

### 3. Keeping InternalCost private

Use field-level security: representatives don't get read/edit access to `InternalCost__c`, and managers do. Hiding it on a layout isn't enough.

Permission sets add permissions, so we also need to check that the representative's profile or another permission set doesn't already grant access.

### 4. Representatives see their team; managers see everything

- **OWD:** Private for Customers and Service Requests.
- **Role hierarchy:** Representatives under their team manager, and the service manager above the teams.
- **Sharing rules:** A group for each team, with rules sharing that team's records to the group. We need rules for both objects because the Lookup doesn't automatically share the customer. Integration-owned records also need to be assigned to the right team's sharing.
- **Permissions:** Representatives get Customer read access and Request create/read/edit access, with the fields they need. They don't get View All. Managers get access to InternalCost and View All Records for these objects.

The supplied `Service_Agent` and `Service_Manager` permission sets cover the object/field/class permissions. The actual roles, groups, and sharing memberships still need to be set up in the org. Audits are Private too; if representatives need to read their team's audits, those records need sharing rules as well.

### 5. What the Apex controller needs to check

Being able to open the component doesn't mean the user can read any ID they send to Apex. We need Apex class access, object permissions, field permissions, and record sharing. We also validate the input and check access to the selected customer. That's why the controller uses user-mode operations.

### 6. The three permission layers

- **Object:** Can I create a Service Request at all?
- **Field:** Can I read InternalCost? For a representative, no.
- **Record:** Can I read this particular request? A representative should only see their team's records.

## What still needs checking

There are no automated tests in this submission. Lint and formatting were checked locally, but there isn't a configured Salesforce org, so Apex execution, permissions, the live UI, and the Flow still need checking there.
