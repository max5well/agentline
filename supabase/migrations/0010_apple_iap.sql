-- Apple In-App Purchase ledger (ADR pending in docs): every processed
-- StoreKit transaction, keyed by Apple's transaction id. Consumable
-- credit grants dedupe against this table so a re-synced receipt can
-- never top up twice.
create table apple_transactions (
  transaction_id text primary key,
  user_id uuid references auth.users(id) on delete set null,
  product_id text not null,
  type text not null,
  raw jsonb not null default '{}',
  created_at timestamptz not null default now()
);

create index apple_transactions_user_idx on apple_transactions(user_id, created_at);
