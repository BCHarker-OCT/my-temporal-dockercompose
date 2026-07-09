# Replication Test Workflow (Go)

This directory contains a Temporal workflow + worker used for replication testing in the `replicationtest` namespace.

Modified from:
- https://gist.github.com/tsurdilo/f0ef3ea2940e877aaec7489370ae099c
- https://github.com/temporalio/edu-101-go-code/tree/main/exercises/hello-workflow

## Part A: Prepare Dependencies

From this directory, run:

```bash
go mod tidy
```

## Part B: Ensure Namespace Exists

If you have not created it yet, run:

```bash
temporal --address 127.0.0.1:7233 operator namespace create replicationtest
```

## Part C: Start the Worker

In terminal window 1, from this directory, run:

```bash
go run worker/main.go
# OR run in background
nohup go run worker/main.go > worker.log 2>&1 &
```

The worker listens on task queue `greeting-tasks` in namespace `replicationtest`.

## Part D: Start One Workflow from the Command Line

In terminal window 2, from this directory, run:

```bash
temporal workflow start \
	--type GreetSomeone \
	--task-queue greeting-tasks \
	--workflow-id replicationtest-single \
	--namespace replicationtest \
	--input '"BC"'
```

This workflow waits for a signal before it completes.

## Part E: Signal the Workflow to Continue

To complete the workflow started above:

```bash
temporal workflow signal \
	--workflow-id replicationtest-single \
	--name doContinue \
	--namespace replicationtest
```

## Part F: Seed Replication Test Data (30 Workflows)

This starts 30 workflow executions and signals 20 of them, leaving 10 running (useful for replication validation):

```bash
go run start/main.go
```

The seeded workflow IDs are:

- `replicationtest-workflow-0`
- `replicationtest-workflow-1`
- ...
- `replicationtest-workflow-29`

If you rerun the seeding command while some of these IDs are still running, the starter now appends a `-rerun-<timestamp>` suffix for those conflicts so each run still creates 30 new executions.

## Part G: Cleanup After Testing

### Stop the background worker (if started with `nohup`)

```bash
pgrep -af "go run worker/main.go"
pkill -f "go run worker/main.go"
```

If you launched it with `nohup ... & echo $!`, you can also stop it directly:

```bash
kill <pid>
```

### Terminate all running replication test workflows

This safely terminates all currently running `GreetSomeone` workflows in namespace `replicationtest` (including `-rerun-...` IDs):

```bash
temporal workflow list \
	--namespace replicationtest \
	--query "ExecutionStatus='Running' AND WorkflowType='GreetSomeone'" \
	--output json \
| jq -r '.[].execution.workflowId' \
| while read -r wid; do
		temporal workflow terminate \
			--namespace replicationtest \
			--workflow-id "$wid" \
			--reason "Replication test cleanup"
	done
```

Verify no running test workflows remain:

```bash
temporal workflow list \
	--namespace replicationtest \
	--query "ExecutionStatus='Running' AND WorkflowType='GreetSomeone'"
```
