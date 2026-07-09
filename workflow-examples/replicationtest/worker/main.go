package main

import (
	"log"
	replicationtest "replicationtest"

	"go.temporal.io/sdk/client"
	"go.temporal.io/sdk/worker"
)

func main() {
	clientOptions := client.Options{Namespace: "replicationtest"}

	c, err := client.Dial(clientOptions)
	if err != nil {
		log.Fatalln("Unable to create client", err)
	}
	defer c.Close()

	w := worker.New(c, replicationtest.TaskQueue, worker.Options{})

	w.RegisterWorkflow(replicationtest.GreetSomeone)
	w.RegisterActivity(replicationtest.ComposeGreeting)

	err = w.Run(worker.InterruptCh())
	if err != nil {
		log.Fatalln("Unable to start worker", err)
	}
}
