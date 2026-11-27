-- The topics that the user subscribes to. Coin News shows only these topics.
CREATE TABLE cn_subscriptions (
    topic BLOB(4) PRIMARY KEY
);

-- Keep each topic that the app shows today.
INSERT INTO cn_subscriptions (topic) SELECT topic FROM cn_topics;
