-- Built-in UPI payments, used while Razorpay is not set up (UPI_PAYEE_VPA set, no Razorpay keys).
-- Checkout makes an order with a short reference that goes in the UPI note; the owner pays our UPI
-- ID from any UPI app and enters the 12-digit UTR. The operator checks the bank statement and
-- confirms or rejects it on the ops page. A confirmed order becomes a payments row (method 'upi',
-- razorpay_payment_id 'upi:<utr>') and is applied to the plan exactly like a Razorpay payment.
--
-- status: 'pending' = order made, no UTR yet; 'submitted' = UTR entered, waiting for the operator;
-- 'confirmed' = applied to the plan; 'rejected' = the operator found no such payment.
CREATE TABLE IF NOT EXISTS upi_orders (
  id           TEXT PRIMARY KEY,
  reference    TEXT NOT NULL UNIQUE,
  business_id  TEXT NOT NULL,
  plan_id      TEXT NOT NULL,
  kind         TEXT NOT NULL,
  amount_paise INTEGER NOT NULL,
  base_paise   INTEGER NOT NULL,
  gst_paise    INTEGER NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'submitted', 'confirmed', 'rejected')),
  utr          TEXT,
  submitted_at TEXT,
  decided_at   TEXT,
  created_at   TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX IF NOT EXISTS idx_upi_orders_business ON upi_orders(business_id, created_at);
CREATE INDEX IF NOT EXISTS idx_upi_orders_status ON upi_orders(status, submitted_at);
-- One UTR pays one order: a UTR already entered for another order is refused.
CREATE UNIQUE INDEX IF NOT EXISTS idx_upi_orders_utr ON upi_orders(utr) WHERE utr IS NOT NULL;

-- How a payment was made: 'razorpay' (webhook) or 'upi' (confirmed on the ops page).
ALTER TABLE payments ADD COLUMN method TEXT NOT NULL DEFAULT 'razorpay';
