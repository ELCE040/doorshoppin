-- PayChangu Direct MoMo: store PayChangu's charge_id for verification and status updates.
-- Run this once before using the updated /initiate and /verify endpoints.

ALTER TABLE transactions ADD COLUMN charge_id VARCHAR(50) NULL;

-- Optional: index for verify updates
-- CREATE INDEX idx_transactions_charge_id ON transactions(charge_id);
