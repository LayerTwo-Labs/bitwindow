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

func (s stubRemote) ListFrontPage(_ context.Context, topicHex string, _ uint32) ([]engines.RemoteItem, error) {
	return lo.Filter(s, func(item engines.RemoteItem, _ int) bool { return item.TopicHex == topicHex }), nil
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
