# Stripe Testing Notes

## FLEET Promo Code (Beta Testing)

During Beta Phase, we use a **FLEET** promotion code in the Stripe **sandbox** to allow purchasing any tier (Pioneer, Dreamer, Pilot) at no cost. This enables end-to-end testing of:

- **Stripe** — payment flows, checkout sessions, subscription creation
- **Supabase** — account creation, tier provisioning, database records
- **Client/Server** — authorization checks, tier-gated features, session handling

### Current Setup

| Resource | ID | Account |
|----------|-----|---------|
| Coupon | `01xZeJia` | Utmost Games sandbox (`acct_1T04zk23Y1RGTQS1`) |
| Promo Code | `FLEET` | Same sandbox account |

- **Coupon**: 100% off, `forever` duration (free for full subscription lifecycle)
- **Promo Code**: code `FLEET`, expires 24 hours after creation

### Renewing the FLEET Promo Code

The FLEET promo code expires every 24 hours by design. When it expires, Stripe permanently deactivates it and it **cannot be reactivated**. You must create a new one.

**Renewal command** (run from any terminal with curl):

```bash
# Step 1: Deactivate the old FLEET promo code (if still active)
# Find the current promo code ID first:
curl -s https://api.stripe.com/v1/promotion_codes \
  -u "sk_test_YOUR_KEY:" \
  -G -d code=FLEET -d active=true

# Deactivate it (replace promo_XXXXX with the actual ID):
curl -s https://api.stripe.com/v1/promotion_codes/promo_XXXXX \
  -u "sk_test_YOUR_KEY:" \
  -d active=false

# Step 2: Create a new FLEET promo code with fresh 24-hour expiry
EXPIRES_AT=$(date -d '+24 hours' +%s) && \
curl -s https://api.stripe.com/v1/promotion_codes \
  -u "sk_test_YOUR_KEY:" \
  -d "promotion[type]=coupon" \
  -d "promotion[coupon]=01xZeJia" \
  -d code=FLEET \
  -d expires_at="$EXPIRES_AT"
```

**Important notes:**
- The sandbox account uses Stripe API version `2026-01-28.clover`, which uses the polymorphic `promotion[type]` / `promotion[coupon]` syntax instead of the legacy top-level `coupon` parameter.
- The coupon `01xZeJia` is permanent and does not expire. Only the promotion code (the customer-facing `FLEET` string) needs renewal.
- Replace `sk_test_YOUR_KEY:` with the actual test secret key from `appsettings.Development.json`.
- The Stripe MCP plugin does not have a `create_promotion_code` tool, so this must be done via curl or the Stripe Dashboard.
