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
	registerControl(mux, &coreRPC{}, newIndex(&coreRPC{}), "qa", "")
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

func TestMineGoesThroughTheEnforcer(t *testing.T) {
	var got string
	enforcer := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		got = r.URL.Path + " " + string(body)
		_, _ = io.WriteString(w, `{"blockHashes":[{"hex":"aa"},{"hex":"bb"}]}`)
	}))
	defer enforcer.Close()
	mux := http.NewServeMux()
	registerControl(mux, &coreRPC{}, newIndex(&coreRPC{}), "qa", enforcer.URL)
	server := httptest.NewServer(mux)
	defer server.Close()

	resp, err := http.Post(server.URL+"/regtest/mine", "application/json", strings.NewReader(`{"blocks":2,"address":"bcrt1qx"}`))
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close() //nolint:errcheck
	body, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	if resp.StatusCode != http.StatusOK || !strings.Contains(string(body), `"hashes":["aa","bb"]`) {
		t.Fatalf("mine answered %d %s", resp.StatusCode, body)
	}
	if want := `/cusf.mainchain.v1.MiningService/GenerateToAddress {"address":"bcrt1qx","blocks":2}`; got != want {
		t.Errorf("enforcer got %q, want %q", got, want)
	}
}
