// Disposable go consumer for e2e-testing wrangle's reworked go publish
// model. The binary exists only so wrangle's go build action has
// something to compile, package, and attest.
package main

import "fmt"

func main() {
	fmt.Println(Hello())
}

// Hello returns the fixture's name.
func Hello() string {
	return "wrangle-agent-playground-go"
}
