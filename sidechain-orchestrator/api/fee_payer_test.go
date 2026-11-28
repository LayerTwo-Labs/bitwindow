package api

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestFeePayerAfterFollowsAPaymentCode(t *testing.T) {
	before := map[string]int64{"addr-a": 1_000, "PM8T-code": 2_000}
	after := map[string]int64{"addr-a": 1_000, "addr-derived": 2_000}

	assert.Equal(t, "addr-derived", feePayerAfter("PM8T-code", before, after))
	assert.Equal(t, "addr-a", feePayerAfter("addr-a", before, after))
	assert.Equal(t, "", feePayerAfter("", before, after))
	assert.Equal(t, "addr-unknown", feePayerAfter("addr-unknown", before, after))
}
