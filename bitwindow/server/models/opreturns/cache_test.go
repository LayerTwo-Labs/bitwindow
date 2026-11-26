package opreturns

import (
	"fmt"
	"testing"
	"time"

	"github.com/samber/lo"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
)

// List(..., limit) must cap rows at the requested limit.
func TestList_LimitCaps(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	const total = 50
	const limit = 10
	rows := make([]OPReturn, 0, total)
	for i := 0; i < total; i++ {
		h := uint32(i + 1)
		now := time.Now().Add(time.Duration(i) * time.Millisecond)
		rows = append(rows, OPReturn{
			Height:    &h,
			TxID:      fmt.Sprintf("tx-%d", i),
			Vout:      0,
			Data:      []byte("payload"),
			CreatedAt: &now,
		})
	}
	require.NoError(t, Persist(ctx, db, rows))

	got, err := List(ctx, db, limit)
	require.NoError(t, err)
	assert.Len(t, got, limit)
}

// List(..., 0) is the explicit "full table" escape hatch (bitdrive).
func TestList_LimitZeroIsUnbounded(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	const n = 50
	rows := make([]OPReturn, 0, n)
	for i := 0; i < n; i++ {
		h := uint32(i + 1)
		now := time.Now().Add(time.Duration(i) * time.Millisecond)
		rows = append(rows, OPReturn{
			Height:    &h,
			TxID:      fmt.Sprintf("tx-%d", i),
			Vout:      0,
			Data:      []byte("payload"),
			CreatedAt: &now,
		})
	}
	require.NoError(t, Persist(ctx, db, rows))

	got, err := List(ctx, db, 0)
	require.NoError(t, err)
	assert.Len(t, got, n)
}

// Closing the DB after the first call proves the second read is served
// purely from cache (a real query would fail).
func TestListCache_HitAfterMiss(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	h := uint32(1)
	now := time.Now()
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		Height: &h, TxID: "tx", Vout: 0, Data: []byte("hi"), CreatedAt: &now,
	}}))

	first, err := List(ctx, db, 100)
	require.NoError(t, err)
	require.Len(t, first, 1)

	require.NoError(t, db.Close())

	// If the cache wasn't honored, this would error with "sql: database is closed".
	second, err := List(ctx, db, 100)
	require.NoError(t, err)
	assert.Equal(t, first, second)
}

// Persist must drop the cache so the next read sees the new row.
func TestListCache_InvalidatedByPersist(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	first, err := List(ctx, db, 100)
	require.NoError(t, err)
	require.Empty(t, first)

	h := uint32(1)
	now := time.Now()
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		Height: &h, TxID: "tx", Vout: 0, Data: []byte("hi"), CreatedAt: &now,
	}}))

	second, err := List(ctx, db, 100)
	require.NoError(t, err)
	assert.Len(t, second, 1)
}

// Cache must not bleed entries across DBs.
func TestListCache_PerDBIsolation(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	dbA := database.Test(t)
	dbB := database.Test(t)

	h := uint32(1)
	now := time.Now()
	require.NoError(t, Persist(ctx, dbA, []OPReturn{{
		Height: &h, TxID: "in-a", Vout: 0, Data: []byte("a"), CreatedAt: &now,
	}}))

	gotA, err := List(ctx, dbA, 100)
	require.NoError(t, err)
	require.Len(t, gotA, 1)

	gotB, err := List(ctx, dbB, 100)
	require.NoError(t, err)
	assert.Empty(t, gotB)
}

// ListCoinNews reads from the canonical CoinNews tables, not raw
// op_returns rows.
func TestListCoinNews_ReadsCanonicalStories(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "abcd1234") // non-default so the seeded name wins
	seedCurrentTopic(t, ctx, db, topic, "Known", 0, 1)
	seedCurrentNews(t, ctx, db, topic, "headline", "body", "matching", 0, 2, time.Now())

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, "headline", got[0].Headline)
	assert.Equal(t, "body", got[0].Content)
	assert.Equal(t, "Known", got[0].TopicName)
}

// A story past the retention of its topic stays in the list, with the outdated flag.
func TestListCoinNews_FlagsOutdatedStories(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "b2b2b2b2")
	seedCurrentTopic(t, ctx, db, topic, "Weekly", 7, 1)

	seedCurrentNews(t, ctx, db, topic, "stale", "stale", "old-news", 0, 2, time.Now().AddDate(0, 0, -30))
	seedCurrentNews(t, ctx, db, topic, "fresh", "fresh", "fresh-news", 1, 3, time.Now())

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	outdated := lo.SliceToMap(got, func(n CoinNews) (string, bool) { return n.Headline, n.Outdated })
	assert.Equal(t, map[string]bool{"stale": true, "fresh": false}, outdated)
}

func TestListCoinNews_RetentionIgnoresTimeZone(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "b3b3b3b3")
	seedCurrentTopic(t, ctx, db, topic, "Weekly", 7, 1)

	cutoff := time.Now().AddDate(0, 0, -7)
	east := time.FixedZone("UTC+14", 14*60*60)
	west := time.FixedZone("UTC-12", -12*60*60)
	seedCurrentNews(t, ctx, db, topic, "outside", "outside", "outside-news", 0, 2, cutoff.Add(-time.Hour).In(east))
	seedCurrentNews(t, ctx, db, topic, "inside", "inside", "inside-news", 1, 3, cutoff.Add(time.Hour).In(west))

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	outdated := lo.SliceToMap(got, func(n CoinNews) (string, bool) { return n.Headline, n.Outdated })
	assert.Equal(t, map[string]bool{"outside": true, "inside": false}, outdated)
}

func TestOutdated(t *testing.T) {
	t.Parallel()
	now := time.Date(2026, 11, 25, 12, 0, 0, 0, time.UTC)

	assert.False(t, Outdated(now.AddDate(-5, 0, 0), 0, now), "a retention of 0 keeps a story forever")
	assert.False(t, Outdated(now.Add(-24*time.Hour), 1, now), "a story at the limit stays current")
	assert.True(t, Outdated(now.Add(-24*time.Hour-time.Second), 1, now))
	assert.False(t, Outdated(now.Add(time.Hour), 1, now), "a block time ahead of the clock is current")
}

// A caller mutating the returned slice must not corrupt the cache.
func TestList_CallerCannotPoisonCache(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	h := uint32(1)
	now := time.Now()
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		Height: &h, TxID: "real", Vout: 0, Data: []byte("real"), CreatedAt: &now,
	}}))

	first, err := List(ctx, db, 100)
	require.NoError(t, err)
	require.Len(t, first, 1)

	// Mutate the returned slice — clobber the row, then append junk.
	first[0] = OPReturn{TxID: "POISONED"}
	_ = append(first, OPReturn{TxID: "EXTRA"})

	second, err := List(ctx, db, 100)
	require.NoError(t, err)
	require.Len(t, second, 1)
	assert.Equal(t, "real", second[0].TxID)
}

// Same mutation guard for the ListCoinNews path.
func TestListCoinNews_CallerCannotPoisonCache(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "d4d4d4d4")
	seedCurrentTopic(t, ctx, db, topic, "T", 0, 1)
	seedCurrentNews(t, ctx, db, topic, "real-headline", "real-body", "tx", 0, 2, time.Now())

	first, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, first, 1)

	first[0] = CoinNews{Headline: "POISONED"}
	_ = append(first, CoinNews{Headline: "EXTRA"})

	second, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, second, 1)
	assert.Equal(t, "real-headline", second[0].Headline)
}

// Topic creations live in cn_topics, not cn_stories, so they never
// surface as articles.
func TestListCoinNews_TopicCreationRowFiltered(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "e5e5e5e5")
	seedCurrentTopic(t, ctx, db, topic, "T", 0, 1)
	seedCurrentNews(t, ctx, db, topic, "real", "real", "news-row", 1, 2, time.Now())

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, "real", got[0].Headline)
}

// retention_days = 0 means "keep forever": a story of any age stays current.
func TestListCoinNews_ZeroRetentionKeepsForever(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "f6f6f6f6")
	seedCurrentTopic(t, ctx, db, topic, "Forever", 0, 1)

	ancient := time.Now().AddDate(-5, 0, 0)
	seedCurrentNews(t, ctx, db, topic, "old", "old", "ancient", 0, 2, ancient)

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, "old", got[0].Headline)
	assert.False(t, got[0].Outdated)
}

// Junk rows where headline is blank-or-padding-only must not surface.
func TestListCoinNews_EmptyPayloadFiltered(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topic := mustTopicID(t, "07070707")
	seedCurrentTopic(t, ctx, db, topic, "T", 0, 1)
	seedCurrentNews(t, ctx, db, topic, "", "", "junk", 0, 2, time.Now())
	seedCurrentNews(t, ctx, db, topic, "real", "real", "real", 1, 3, time.Now())

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, got, 1)
	assert.Equal(t, "real", got[0].Headline)
}

// Multi-topic, multi-row check that the JOIN populates TopicName
// correctly per row (rather than e.g. carrying over the previous row's
// topic). Catches a class of JOIN-mapping bug.
func TestListCoinNews_TopicNameMatchesEachRow(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	topicA := mustTopicID(t, "aaaaaaaa")
	topicB := mustTopicID(t, "bbbbbbbb")
	seedCurrentTopic(t, ctx, db, topicA, "A name", 0, 1)
	seedCurrentTopic(t, ctx, db, topicB, "B name", 0, 2)

	seedCurrentNews(t, ctx, db, topicA, "ha", "ba", "txA", 0, 3, time.Now())
	seedCurrentNews(t, ctx, db, topicB, "hb", "bb", "txB", 1, 4, time.Now())

	got, err := ListCoinNews(ctx, db)
	require.NoError(t, err)
	require.Len(t, got, 2)
	byHeadline := map[string]CoinNews{}
	for _, n := range got {
		byHeadline[n.Headline] = n
	}
	assert.Equal(t, "A name", byHeadline["ha"].TopicName)
	assert.Equal(t, "B name", byHeadline["hb"].TopicName)
	assert.Equal(t, topicA, byHeadline["ha"].Topic)
	assert.Equal(t, topicB, byHeadline["hb"].Topic)
}

// A node with no txindex cannot read the fee of a confirmed transaction, so
// the scan records zero. ZMQ already stored the real fee from the mempool, and
// the confirming write must not erase it.
func TestConfirmingARowKeepsAFeeTheMempoolAlreadyGave(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	const txid = "a1b2c3"
	unconfirmed := time.Now()
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		TxID: txid, Vout: 0, Data: []byte{0x01}, Fee: 4200, CreatedAt: &unconfirmed,
	}}))

	height := uint32(995432)
	blockTime := unconfirmed.Add(time.Minute)
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		TxID: txid, Vout: 0, Data: []byte{0x01}, Fee: 0, Height: &height, CreatedAt: &blockTime,
	}}))

	rows, err := List(ctx, db, 10)
	require.NoError(t, err)
	require.Len(t, rows, 1)
	assert.EqualValues(t, 4200, rows[0].Fee)
	require.NotNil(t, rows[0].Height)
	assert.EqualValues(t, height, *rows[0].Height)
}

// A fee the scan does read still replaces whatever the row held.
func TestConfirmingARowStillWritesAKnownFee(t *testing.T) {
	t.Parallel()
	ctx := t.Context()
	db := database.Test(t)

	const txid = "d4e5f6"
	unconfirmed := time.Now()
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		TxID: txid, Vout: 0, Data: []byte{0x02}, Fee: 4200, CreatedAt: &unconfirmed,
	}}))

	height := uint32(995433)
	blockTime := unconfirmed.Add(time.Minute)
	require.NoError(t, Persist(ctx, db, []OPReturn{{
		TxID: txid, Vout: 0, Data: []byte{0x02}, Fee: 999, Height: &height, CreatedAt: &blockTime,
	}}))

	rows, err := List(ctx, db, 10)
	require.NoError(t, err)
	require.Len(t, rows, 1)
	assert.EqualValues(t, 999, rows[0].Fee)
}
