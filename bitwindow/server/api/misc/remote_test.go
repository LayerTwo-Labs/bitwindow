package misc_test

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/samber/lo"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/api/misc"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/database"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/engines"
	miscv1 "github.com/LayerTwo-Labs/sidesail/bitwindow/server/gen/misc/v1"
	"github.com/LayerTwo-Labs/sidesail/bitwindow/server/models/opreturns"
)

type stubRemote []engines.RemoteItem

func (s stubRemote) ListFrontPage(_ context.Context, topicHex string, limit, offset uint32) ([]engines.RemoteItem, error) {
	items := lo.Filter(s, func(item engines.RemoteItem, _ int) bool { return item.TopicHex == topicHex })
	return lo.Subset(items, int(offset), uint(limit)), nil
}

type noIndexer struct{}

func (noIndexer) ListFrontPage(context.Context, string, uint32, uint32) ([]engines.RemoteItem, error) {
	return nil, engines.ErrNoIndexer
}

func TestService_ListCoinNews_RemoteFee(t *testing.T) {
	t.Parallel()
	remote := stubRemote{
		{ItemIDHex: "aa", TopicHex: "a1a1a1a1", Headline: "Dear", FeeSats: 5000, BlockTime: time.Now()},
		{ItemIDHex: "bb", TopicHex: "a2a2a2a2", Headline: "Cheap", FeeSats: 100, BlockTime: time.Now()},
	}
	srv := misc.New(database.Test(t), nil, nil, nil, remote)

	resp, err := srv.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.CoinNews, 2)
	assert.Equal(t, "Dear", resp.CoinNews[0].Headline)
	assert.EqualValues(t, 5000, resp.CoinNews[0].FeeSats)
	assert.EqualValues(t, 100, resp.CoinNews[1].FeeSats)
}

func TestService_ListCoinNews_RemoteConfirmedHidesPending(t *testing.T) {
	t.Parallel()
	db := database.Test(t)
	topic, err := opreturns.ValidNewsTopicID("a1a1a1a1")
	require.NoError(t, err)
	payload, err := opreturns.EncodeNewsMessageWithOptions(topic, "Mined", "", opreturns.StoryOptions{})
	require.NoError(t, err)
	txid := fmt.Sprintf("%064x", 42)
	require.NoError(t, opreturns.Persist(t.Context(), db, []opreturns.OPReturn{{TxID: txid, Vout: 1, Data: payload, Fee: 300}}))
	remote := stubRemote{
		{ItemIDHex: "cc", TopicHex: "a1a1a1a1", Headline: "Mined", FeeSats: 300, BlockTime: time.Now(), TxID: txid, Vout: 1},
	}
	srv := misc.New(db, nil, nil, nil, remote)

	resp, err := srv.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)
	require.Len(t, resp.CoinNews, 1)
	assert.Equal(t, "cc", resp.CoinNews[0].ItemId)
}

func TestService_ListCoinNews_RemoteOutdated(t *testing.T) {
	t.Parallel()
	remote := stubRemote{
		{ItemIDHex: "aa", TopicHex: "a1a1a1a1", Headline: "Old", FeeSats: 5000, BlockTime: time.Now().AddDate(0, 0, -40)},
		{ItemIDHex: "bb", TopicHex: "a1a1a1a1", Headline: "New", FeeSats: 100, BlockTime: time.Now()},
	}
	srv := misc.New(database.Test(t), nil, nil, nil, remote)

	resp, err := srv.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)
	outdated := lo.SliceToMap(resp.CoinNews, func(n *miscv1.CoinNews) (string, bool) { return n.Headline, n.Outdated })
	assert.Equal(t, map[string]bool{"Old": true, "New": false}, outdated)
}

// Outdated stories with a high fee must not take the places of the current stories.
func TestService_ListCoinNews_OutdatedKeepCurrent(t *testing.T) {
	t.Parallel()
	db := database.Test(t)
	ctx := t.Context()
	topic := validTopicID()
	seedCurrentTopic(t, ctx, db, topic, "Weekly", 1)

	height := uint32(1)
	for i := range 105 {
		seedCurrentNews(t, ctx, db, topic, "Old", "", 3+i, time.Now().AddDate(0, 0, -30))
		require.NoError(t, opreturns.Persist(ctx, db, []opreturns.OPReturn{{
			Height: &height, TxID: fmt.Sprintf("%064x", 1000+3+i), Data: []byte("old"), Fee: 500,
		}}))
	}
	seedCurrentNews(t, ctx, db, topic, "New", "", 200, time.Now())

	srv := misc.New(db, nil, nil, nil, noIndexer{})
	resp, err := srv.ListCoinNews(ctx, &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)

	outdated, current := lo.FilterReject(resp.CoinNews, func(n *miscv1.CoinNews, _ int) bool { return n.Outdated })
	assert.Len(t, outdated, 100)
	require.Len(t, current, 1)
	assert.Equal(t, "New", current[0].Headline)
}

// The indexer ranks by fee with no retention, so current stories can be on a later page.
func TestService_ListCoinNews_RemoteCurrentAfterOutdated(t *testing.T) {
	t.Parallel()
	var remote stubRemote
	for i := range 150 {
		remote = append(remote, engines.RemoteItem{
			ItemIDHex: fmt.Sprintf("%024x", i), TopicHex: "a1a1a1a1", Headline: "Old", FeeSats: 5000,
			BlockTime: time.Now().AddDate(0, 0, -40), TxID: fmt.Sprintf("%064x", i),
		})
	}
	remote = append(remote, engines.RemoteItem{
		ItemIDHex: "ff", TopicHex: "a1a1a1a1", Headline: "New", FeeSats: 100, BlockTime: time.Now(), TxID: fmt.Sprintf("%064x", 999),
	})
	srv := misc.New(database.Test(t), nil, nil, nil, remote)

	resp, err := srv.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)

	outdated, current := lo.FilterReject(resp.CoinNews, func(n *miscv1.CoinNews, _ int) bool { return n.Outdated })
	assert.Len(t, outdated, 100)
	require.Len(t, current, 1)
	assert.Equal(t, "New", current[0].Headline)
}

// A story in a later block ranks first on equal fees, also with an older block
// time. A pending story is newer than both.
func TestService_ListCoinNews_RanksTiesByHeight(t *testing.T) {
	t.Parallel()
	db := database.Test(t)
	topic, err := opreturns.ValidNewsTopicID("a1a1a1a1")
	require.NoError(t, err)
	payload, err := opreturns.EncodeNewsMessageWithOptions(topic, "Pending", "", opreturns.StoryOptions{})
	require.NoError(t, err)
	require.NoError(t, opreturns.Persist(t.Context(), db, []opreturns.OPReturn{
		{TxID: fmt.Sprintf("%064x", 7), Vout: 0, Data: payload, Fee: 3000},
	}))
	now := time.Now()
	remote := stubRemote{
		{ItemIDHex: "bb", TopicHex: "a1a1a1a1", Headline: "Block 105", FeeSats: 3000, BlockHeight: 105, BlockTime: now.Add(-2 * time.Hour), TxID: fmt.Sprintf("%064x", 2)},
		{ItemIDHex: "aa", TopicHex: "a1a1a1a1", Headline: "Block 104", FeeSats: 3000, BlockHeight: 104, BlockTime: now.Add(-time.Hour), TxID: fmt.Sprintf("%064x", 1)},
		{ItemIDHex: "cc", TopicHex: "a2a2a2a2", Headline: "Block 103", FeeSats: 3000, BlockHeight: 103, BlockTime: now, TxID: fmt.Sprintf("%064x", 3)},
	}
	srv := misc.New(db, nil, nil, nil, remote)

	resp, err := srv.ListCoinNews(t.Context(), &miscv1.ListCoinNewsRequest{})
	require.NoError(t, err)
	assert.Equal(t,
		[]string{"Pending", "Block 105", "Block 104", "Block 103"},
		lo.Map(resp.CoinNews, func(n *miscv1.CoinNews, _ int) string { return n.Headline }))
}
