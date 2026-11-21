package main

import (
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestMailboxKeepsAValueForTheNextTest(t *testing.T) {
	mux := http.NewServeMux()
	registerControl(mux, &coreRPC{}, newIndex(&coreRPC{}), "qa")
	server := httptest.NewServer(mux)
	defer server.Close()

	resp, err := http.Get(server.URL + "/regtest/mailbox/check")
	if err != nil {
		t.Fatal(err)
	}
	resp.Body.Close() //nolint:errcheck
	if resp.StatusCode != http.StatusNotFound {
		t.Fatalf("empty mailbox answered %d", resp.StatusCode)
	}

	req, _ := http.NewRequest(http.MethodPut, server.URL+"/regtest/mailbox/check", strings.NewReader("cVwif"))
	if resp, err = http.DefaultClient.Do(req); err != nil {
		t.Fatal(err)
	}
	resp.Body.Close() //nolint:errcheck

	resp, err = http.Get(server.URL + "/regtest/mailbox/check")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close() //nolint:errcheck
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(body), `"value":"cVwif"`) {
		t.Errorf("mailbox answered %s", body)
	}
}
