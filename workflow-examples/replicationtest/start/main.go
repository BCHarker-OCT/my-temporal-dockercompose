package main

import (
	"context"
	"errors"
	"fmt"
	"log"
	"strconv"
	"sync"
	"time"

	replicationtest "replicationtest"

	"go.temporal.io/api/serviceerror"
	"go.temporal.io/sdk/client"
	"golang.org/x/sync/errgroup"
)

func main() {
	clientOptions := client.Options{Namespace: "replicationtest"}

	c, err := client.Dial(clientOptions)
	if err != nil {
		log.Fatalln("Unable to create client", err)
	}
	defer c.Close()

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	const totalWorkflows = 30
	const workflowsToSignal = 20

	workflowIDs := make([]string, totalWorkflows)
	startedWorkflowIDs := make([]string, totalWorkflows)
	for i := 0; i < totalWorkflows; i++ {
		workflowIDs[i] = replicationtest.WorkflowIDPrefix + strconv.Itoa(i)
	}

	// Fan out starts so seed data appears quickly instead of one call at a time.
	startGroup, startCtx := errgroup.WithContext(ctx)
	startGroup.SetLimit(10)
	for i := 0; i < totalWorkflows; i++ {
		idx := i
		workflowID := workflowIDs[i]
		startGroup.Go(func() error {
			opts := client.StartWorkflowOptions{
				ID:                                       workflowID,
				TaskQueue:                                replicationtest.TaskQueue,
				WorkflowExecutionErrorWhenAlreadyStarted: true,
			}

			we, err := c.ExecuteWorkflow(startCtx, opts, replicationtest.GreetSomeone, "Temporal Replication")
			if err != nil {
				var alreadyStarted *serviceerror.WorkflowExecutionAlreadyStarted
				if !errors.As(err, &alreadyStarted) {
					return fmt.Errorf("start %s: %w", workflowID, err)
				}

				fallbackID := fmt.Sprintf("%s-rerun-%d", workflowID, time.Now().UnixMilli())
				opts.ID = fallbackID
				we, err = c.ExecuteWorkflow(startCtx, opts, replicationtest.GreetSomeone, "Temporal Replication")
				if err != nil {
					return fmt.Errorf("start fallback %s: %w", fallbackID, err)
				}

				startedWorkflowIDs[idx] = fallbackID
				log.Println("Started workflow (fallback ID)", "WorkflowID", we.GetID(), "RunID", we.GetRunID())
				return nil
			}

			startedWorkflowIDs[idx] = workflowID
			log.Println("Started workflow", "WorkflowID", we.GetID(), "RunID", we.GetRunID())
			return nil
		})
	}

	if err := startGroup.Wait(); err != nil {
		log.Fatalln("Unable to execute workflow", err)
	}

	// Fan out signaling to quickly complete 20 and leave 10 running.
	signalGroup, signalCtx := errgroup.WithContext(ctx)
	signalGroup.SetLimit(10)
	var signalMu sync.Mutex
	for i := 0; i < workflowsToSignal; i++ {
		workflowID := startedWorkflowIDs[i]
		signalGroup.Go(func() error {
			err := c.SignalWorkflow(signalCtx, workflowID, "", replicationtest.ContinueSignalName, nil)
			if err != nil {
				return fmt.Errorf("signal %s: %w", workflowID, err)
			}

			signalMu.Lock()
			log.Println("Signaled workflow", "WorkflowID", workflowID)
			signalMu.Unlock()
			return nil
		})
	}

	if err := signalGroup.Wait(); err != nil {
		log.Fatalln("Unable to signal workflow", err)
	}

	log.Println("Replication test setup complete: 30 started, 20 signaled, 10 left running")
}
