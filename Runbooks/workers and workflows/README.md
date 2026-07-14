# Temporal Workers and Workflows

# Table of Contents

- [Temporal Workers and Workflows](#temporal-workers-and-workflows)
- [Table of Contents](#table-of-contents)
- [Terms to Know](#terms-to-know)
- [Basic Temporal Workflow Run](#basic-temporal-workflow-run)
- [What does the Temporal Service do when Something Goes Wrong](#what-does-the-temporal-service-do-when-something-goes-wrong)
  - [Platform Failures](#platform-failures)
  - [Application Failures](#application-failures)

# Terms to Know

| Term | Definition |
| --- | --- |
| Worker | A general term that can refer to a Worker Program, Worker Process, or Worker Entity. |
| Worker Program | The static code, written with a Temporal SDK, that defines how worker logic is implemented. |
| Worker Process | A running process that polls a Task Queue, receives tasks, executes workflow or activity code, and reports results back to the Temporal Service. Worker Processes run outside the Temporal Service. |
| Workflow | A sequence of executable steps that must be deterministic so replay can safely reconstruct state. |
| Workflow Definition | The static code that defines a workflow type. |
| Workflow Execution | A running instance created when a workflow definition is started. |
| Workflow Execution Chain | A sequence of workflow runs that share the same Workflow Id, connected by Continue-As-New, Retry, or Schedule/Cron behavior. |
| Workflow Run | A single run in a Workflow Execution Chain. |
| Workflow Type | The registered name that maps to a workflow definition and distinguishes it from other workflow definitions. |
| Event History | The durable, ordered list of events recorded for a Workflow Execution. |
| Replay | The mechanism Temporal uses to rebuild workflow state by re-running workflow code against existing Event History and validating command consistency. |
| Temporal Service | The Temporal backend (Temporal Server plus persistence) that stores workflow state and history, matches tasks, and orchestrates execution. Core services include Frontend, Matching, History, and Internal Worker services (not the same as your app workers). |
| Activity | A normal function or method that performs a well-defined action. Activities can be non-deterministic, and should be idempotent. |
| Activity Definition | The static code that defines an activity type. |
| Activity Execution | A running instance created when an activity definition is scheduled by a workflow. |
| Activity Type | The registered name that maps to an activity definition and distinguishes it from other activities. |
| gRPC | Remote Procedure Call protocol used by Temporal APIs, with Protocol Buffers (Protobuf) for message serialization. For more information, see [../protobuf-schemas/README.md](../protobuf-schemas/README.md). |

# Basic Temporal Workflow Run

1. A client starts a workflow by sending a StartWorkflowExecution request to the Temporal Service.
2. The Temporal Service accepts the request and records WorkflowExecutionStarted in Event History.
3. Temporal creates a Workflow Task and places it on the workflow Task Queue.
4. A Workflow Worker polls that Task Queue, receives the Workflow Task, replays Event History, and reconstructs deterministic in-memory workflow state.
5. The workflow code runs until it must wait or finish, then returns Commands such as:
   1. ScheduleActivityTask
   2. StartTimer
   3. RequestCancelExternalWorkflowExecution
   4. StartChildWorkflowExecution
   5. ContinueAsNewWorkflowExecution
   6. CompleteWorkflowExecution
   7. FailWorkflowExecution
6. Temporal persists those Commands as new Events in Event History and enqueues any resulting Activity Tasks or follow-up Workflow Tasks.
7. Workers poll the activity Task Queue, execute activities, and report completion, failure, cancellation, or timeout status back to Temporal.
8. Temporal records each outcome as Events and schedules the next Workflow Task so workflow code can continue from updated state.
9. Steps 4 through 8 repeat until the workflow reaches a terminal state (Completed, Failed, or Terminated).

Crucial behavior to remember:
- Workflow code does not directly mutate durable state; Event History is the source of truth.
- Workflow Tasks are retried by the service if a worker crashes or becomes unavailable.
- Activity execution is at-least-once, so activity handlers should be idempotent.
- Retry policies and timeouts (workflow and activity level) strongly influence recovery behavior.

# What does the Temporal Service do when Something Goes Wrong

## Platform Failures
- If a worker process crashes, restarts, or loses network connectivity, Temporal keeps workflow state in persistence and reschedules pending tasks.
- Another healthy worker can pick up the next Workflow Task and recover by replaying Event History.
- If a worker is unavailable, Activity Tasks remain pending until workers return or until configured timeouts are reached.
- Temporal applies retry policies and timeout settings (for example, Start-To-Close, Schedule-To-Close, and heartbeat timeout where configured) to decide whether to retry or fail an activity.
- When retries are exhausted or a non-retryable error is encountered, Temporal records failure events and hands control back to workflow logic so the workflow can handle, compensate, or fail.

## Application Failures
- Application-level failures (for example, validation errors, bad assumptions, downstream contract changes, or data corruption) usually require code changes, data fixes, or operational intervention.
- Retries help with transient faults, but retries alone do not fix deterministic workflow bugs or permanently invalid inputs.
- Workflows should explicitly model failure handling: retries with bounds, fallback paths, compensating activities, manual signals, and safe termination paths.
- After a fix is deployed, failed executions can often be recovered through workflow-specific remediation patterns (for example, signal-driven recovery, reset, or rerun strategies).
- Because activities are at-least-once, compensation logic and idempotency are key to preventing duplicate side effects during recovery.

