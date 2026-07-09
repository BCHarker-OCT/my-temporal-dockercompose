package replicationtest

import (
	"context"
	"time"

	"go.temporal.io/sdk/activity"
	"go.temporal.io/sdk/workflow"
)

const (
	TaskQueue          = "greeting-tasks"
	ContinueSignalName = "doContinue"
	WorkflowIDPrefix   = "replicationtest-workflow-"
)

func GreetSomeone(ctx workflow.Context, name string) (string, error) {
	opts := workflow.ActivityOptions{StartToCloseTimeout: 2 * time.Second}
	ctx = workflow.WithActivityOptions(ctx, opts)

	var greeting string
	err := workflow.ExecuteActivity(ctx, ComposeGreeting, "Replication test", name).Get(ctx, &greeting)
	if err != nil {
		return "", err
	}

	// Keep some executions open until explicitly signaled.
	workflow.GetSignalChannel(ctx, ContinueSignalName).Receive(ctx, nil)

	return greeting, nil
}

func ComposeGreeting(ctx context.Context, greeting string, name string) (string, error) {
	activity.GetLogger(ctx).Info("Composing replication test greeting")
	return greeting + " " + name + "!", nil
}
