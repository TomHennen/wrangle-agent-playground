package main

import "testing"

func TestHello(t *testing.T) {
	if got := Hello(); got != "wrangle-agent-playground-go" {
		t.Fatalf("Hello() = %q, want %q", got, "wrangle-agent-playground-go")
	}
}
