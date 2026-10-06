const express = require("express");
const crypto = require("crypto");

const app = express();
app.use(express.json());

const payments = new Map();
const idempotency = new Map();

const seed = (id, status) =>
  payments.set(id, {
    id,
    amount: 2500,
    currency: "USD",
    status,
    createdAt: new Date().toISOString(),
  });
seed("pay_1001", "PENDING");
seed("pay_1002", "SETTLED");

const error = (res, status, message) => res.status(status).json({ error: message });

/**
 * POST /v1/payments
 * Idempotency-Key header is required; replaying a key returns the original payment.
 */
app.post("/v1/payments", (req, res) => {
  const key = req.get("Idempotency-Key");
  if (!key) return error(res, 400, "Idempotency-Key header is required");

  const { amount, currency, method } = req.body || {};
  if (!Number.isInteger(amount) || amount <= 0) return error(res, 400, "amount must be a positive integer");
  if (typeof currency !== "string" || !currency) return error(res, 400, "currency is required");
  if (!method || method.type !== "card") return error(res, 400, "method.type must be 'card'");

  const existing = idempotency.get(key);
  if (existing) return res.status(201).json(payments.get(existing));

  const payment = {
    id: `pay_${crypto.randomBytes(5).toString("hex")}`,
    amount,
    currency,
    status: "PENDING",
    createdAt: new Date().toISOString(),
  };
  payments.set(payment.id, payment);
  idempotency.set(key, payment.id);
  res.status(201).json(payment);
});

app.get("/v1/payments/:paymentId", (req, res) => {
  const payment = payments.get(req.params.paymentId);
  if (!payment) return error(res, 404, "payment not found");
  res.json(payment);
});

/**
 * POST /v1/payments/:paymentId/cancel
 * Cancelling is idempotent; payments that already settled or failed return 409.
 */
app.post("/v1/payments/:paymentId/cancel", (req, res) => {
  const payment = payments.get(req.params.paymentId);
  if (!payment) return error(res, 404, "payment not found");
  if (payment.status === "SETTLED" || payment.status === "FAILED") {
    return error(res, 409, `cannot cancel a ${payment.status} payment`);
  }
  payment.status = "CANCELLED";
  res.json(payment);
});

app.get("/health", (_req, res) => {
  res.json({ status: "ok", service: "payments-api" });
});

const port = Number(process.env.PORT) || 3002;
app.listen(port, () => {
  console.log(`payments-api listening on ${port}`);
});
