# TheLook E-commerce: Retention & Acquisition Analysis

> **End-to-end analytics project** using BigQuery SQL, Python (Google Colab), and Looker Studio to identify acquisition leakage and revenue threats from aging customer segments.

---

## Table of Contents

1. [Business Understanding](#1-business-understanding)
2. [Data Source](#2-data-source)
3. [Cloud Environment & Tech Stack](#3-cloud-environment--tech-stack)
4. [Data Cleaning](#4-data-cleaning)
5. [Data Extraction & Feature Engineering](#5-data-extraction--feature-engineering)
6. [Exploratory Data Analysis (EDA)](#6-exploratory-data-analysis-eda)
7. [Dashboard — Looker Studio](#7-dashboard--looker-studio)
8. [Insights & Strategic Recommendations](#8-insights--strategic-recommendations)

---

## 1. Business Understanding

### 1.1 Business Background

TheLook is a fictional e-commerce platform (Google BigQuery public dataset) selling fashion products including Jeans, Outerwear, Intimates, and Accessories. The platform serves three user types: **Anonymous** (guests without an account), **Registered Lead** (has an account but has never completed a successful purchase — including those with no order history or whose transactions were cancelled/returned), and **Existing Buyer** (has completed at least one successful, fully processed transaction).

The dataset covers historical transaction records, user behavioral event logs on the platform, and user demographic information spanning multiple years.

### 1.2 Business Problem

Management identified two critical problems threatening the platform's revenue efficiency and sustainability:
- **Problem 1 — Acquisition Leak**: The platform has spent marketing budget (CAC) to drive ~500,000 Anonymous sessions through various channels (Adwords, Email, Facebook, Organic, YouTube), yet there are signs of significant leakage at the early conversion stage before users complete a purchase.
- **Problem 2 — Revenue at Risk**: Several high-value customer segments are showing signs of significant activity decline. Without intervention, the platform risks losing substantial revenue contributions from previously active customers.

### 1.3 Project Objectives

| # | Objective | Analysis Focus |
|---|---|---|
| 1 | Identify the location and scale of conversion leakage in Anonymous traffic | Acquisition Funnel |
| 2 | Identify the highest-risk customer segments alongside their behavioral patterns and business value | Retention & RFM |

### 1.4 Key Business Questions (KBQ)

**Objective 1 — Acquisition:**
- At which funnel stage do Anonymous users drop off the most?
- Does the drop-off pattern differ across traffic sources (Adwords, Email, Facebook, etc.)?
- What is the scale of sessions being "wasted" from existing marketing investment?

**Objective 2 — Retention:**
- Which RFM segments contribute the most revenue yet are in the most concerning condition?
- What is the average purchase interval per segment, and which segments have already exceeded a safe threshold?
- What product categories are most preferred by each segment, and how can this be leveraged for personalization?

---

## 2. Data Source

**Platform:** Google BigQuery Public Dataset  
**Dataset:** `bigquery-public-data.thelook_ecommerce`

| Source Table | Description | Columns |
|---|---|---|
| `users` | Registered user demographics | 16 |
| `orders` | Transaction headers (status, date, user) | 9 |
| `order_items` | Per-transaction item details (price, product) | 12 |
| `events` | User behavioral event logs (clicks, page visits) | 13 |
| `products` | Product catalog (category, price, brand) | 9 |

**Data Range:** Multi-year (RFM computed using a 1-year trailing window: `2025-05-15` to `2026-05-15`)  
**Reference Date:** `2026-05-15` (max order date + 1 day)

---

## 3. Cloud Environment & Tech Stack

```
Raw Data (BigQuery Public Dataset)
        │
        ▼
┌─────────────────────┐
│   BigQuery (SQL)    │  ← Data Cleaning & Feature Engineering
│   GCP Cloud         │    RFM Scoring, Funnel Aggregation
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│  Google Colab       │  ← Exploratory Data Analysis
│  (Python)           │    Visualization: Matplotlib, Seaborn
│  Connected to BQ    │
└─────────────────────┘
        │
        ▼
┌─────────────────────┐
│  Looker Studio      │  ← Dashboard & Storytelling
│  (Data Studio)      │    Connected directly to BigQuery
└─────────────────────┘
```

**Tools:** BigQuery SQL · Python (Pandas, Seaborn, Matplotlib) · Google Colab · Looker Studio  
**Connection:** All layers connect directly to BigQuery — no data is exported to local files

---

## 4. Data Cleaning

All cleaning was performed in BigQuery, producing cleaned tables that serve as the foundation for all downstream analysis.

### 4.1 Cleaning Strategy per Table

**`users_cleaned`**
- Cast all columns to appropriate data types (INT64, STRING, TIMESTAMP, FLOAT64)
- Filter rows where `id IS NOT NULL`
- Audit column `is_clean`: TRUE if both `id` and `created_at` are not null

**`orders_cleaned`**
- Referential validation: JOIN to `users_cleaned` to ensure every order has a valid user in the master table
- Timestamp sequence validation: `shipped_at >= created_at`, `delivered_at >= shipped_at`, `returned_at >= delivered_at`
- Audit column `is_clean`: TRUE if all foreign keys are valid and the date sequence is logical

**`order_items_cleaned`**
- Dual referential validation: JOIN to both `orders_cleaned` and `products`
- Filter `sale_price > 0` (removes items with invalid zero prices)
- Audit column `is_clean`: TRUE if all foreign keys are valid and price is positive

**`events_cleaned`**
- Deduplication using `ROW_NUMBER()` partitioned by `(session_id, user_id, sequence_number)` — retains the earliest event when duplicates exist
- User referential validation: non-null user IDs must exist in `users_cleaned`
- Added column `user_behavior_type`: Anonymous (user_id IS NULL) vs Known (user_id exists)
- `COALESCE(traffic_source, 'Other')` to handle null values in traffic source

**`products_cleaned`**
- Deduplication using `ROW_NUMBER()` partitioned by `product_id` — retains the record with the highest cost when duplicates exist
- Filter `retail_price >= 0` and `cost >= 0`
- TRIM applied to text columns (category, name, brand, department)

### 4.2 Audit Column `is_clean`

Every cleaned table includes a boolean `is_clean` column used as a consistent filter across all downstream queries. Only rows where `is_clean IS TRUE` are included in the analysis.

---

## 5. Data Extraction & Feature Engineering

### 5.1 RFM Base & Scoring

**Analysis Window:** Trailing 1 year (`created_at >= '2025-05-15'`)

RFM metrics are computed from `orders_cleaned` and `order_items_cleaned` filtered to `status = 'Complete'`.

| Dimension | Definition | Scoring Logic |
|---|---|---|
| **Recency** | Days between reference date and user's last order date | NTILE(5) ORDER BY recency DESC — lower value (recent purchase) receives score 5 |
| **Frequency** | Count of distinct orders per user | NTILE(5) ORDER BY frequency ASC — higher order count receives score 5 |
| **Monetary** | Total sale_price per user | NTILE(5) ORDER BY monetary ASC — higher value receives score 5 |

**avg_fm** = average of F and M scores, used as a combined proxy for customer value.

**RFM Segmentation Rules:**

| Segment | Condition |
|---|---|
| Champions | r=5, avg_fm ≥ 4 |
| Loyal Customers | r≥3, avg_fm ≥ 4 |
| Potential Loyalist | r≥4, avg_fm ≥ 2 |
| New Customers | r=5, avg_fm < 2 |
| Promising | r=4, avg_fm < 2 |
| Need Attention | r=3, avg_fm ≥ 3 |
| About to Sleep | r=3, avg_fm < 3 |
| Cant Lose Them | r≤1, avg_fm ≥ 4 |
| At Risk | r≤2, avg_fm ≥ 3 |
| Hibernating | r≤2, avg_fm < 3 |

> **Methodology note:** This RFM uses a 1-year historical window. Large purchase gaps in some segments (e.g. At Risk avg_gap of 480 days) reflect actual buying behavior over a long history and should be validated against real business operations before drawing conclusions.

### 5.2 Acquisition Funnel

The funnel is built from `events_cleaned` with **session_id** as the unit of analysis (not user_id).

**User Type Classification:**
- `Anonymous`: `user_id IS NULL` in events
- `Registered Lead`: `user_id NOT NULL` in events but absent from `rfm_scores`
- `Existing Buyer`: `user_id` exists in `rfm_scores`

**Funnel Steps:**
```
Total Sessions
    → Reached Home     (MAX has_home per session)
    → Reached Product  (MAX has_product per session)
    → Add to Cart      (MAX has_cart per session)
    → Purchase         (MAX has_purchase per session)
```

**Denominator logic:** `product_to_cart_pct` = cart / product viewers (not total sessions), to accurately measure step-by-step conversion rates.

### 5.3 Final Analytical Tables

| Table | Contents | Used For |
|---|---|---|
| `rfm_scores` | RFM scores & segment per user | All retention analysis |
| `convertion_rate_summary` | Funnel rates per traffic_source × user_type | Acquisition analysis |
| `order_gap_summary` | Avg days between orders per segment | Purchase interval analysis |
| `top_product_summary` | Top 3 categories per segment by revenue | Category affinity |
| `value_summary` | CLV, total revenue, avg recency per segment | Revenue at risk quantification |

### 5.4 Derived Metric: AOV per Segment

The `avg_order_value` column is not natively available in the dataset. It was derived independently:

```sql
AOV = Total Revenue / Total Distinct Orders
    = SUM(sale_price) / COUNT(DISTINCT order_id)
```

| Segment | AOV |
|---|---|
| At Risk | $105.24 |
| Champions | $121.94 |

This metric is used as the multiplier in experiment financial projections — replacing avg_clv to avoid overstating projected impact.

---

## 6. Exploratory Data Analysis (EDA)

EDA was conducted in Google Colab (Python) with a direct BigQuery connection. Libraries: `pandas`, `matplotlib`, `seaborn`.

---

### 6.1 Objective 1 — Acquisition Funnel Analysis

#### Finding 1: Structural Drop-off at the Product Page (Cross-Channel)

<img width="1384" height="583" alt="EDA 1" src="https://github.com/user-attachments/assets/c2044f3c-2a82-47aa-851f-87e9cec65661" />

Funnel analysis across ~500,000 Anonymous sessions reveals a strikingly uniform pattern across all five traffic channels. Every channel reaches the product page at 100%, yet product-to-cart conversion hovers at exactly ~50% — and cart-to-purchase collapses to 0% without exception.

| Traffic Source | Total Sessions | Product-to-Cart Rate | Cart-to-Purchase Rate |
|---|---|---|---|
| Adwords | 150,115 | 49.9% | 0.0% |
| Email | 224,690 | 49.9% | 0.0% |
| Facebook | 50,146 | 50.2% | 0.0% |
| Organic | 24,994 | 50.1% | 0.0% |
| YouTube | 50,055 | 49.9% | 0.0% |

**Insight:** The near-identical ~50% product-to-cart rate across all channels eliminates channel quality as the root cause. This is a **platform-level structural barrier**, not a marketing problem.

**Implication:** Anonymous users cannot complete a purchase without registering first — creating a mandatory friction point precisely at the moment of highest purchase intent. This is a by-design constraint in the platform that is currently operating as a silent conversion killer.

**Business Impact:** Approximately **250,000 sessions per cycle** are abandoned at the product page. The marketing budget (CAC) invested to bring this traffic to the platform yields zero transaction return for half of all Anonymous visitors. Any improvement here requires zero additional acquisition spend — the audience is already on the platform.

---

#### Finding 2: Traffic Volume and Composition by Channel

<img width="1384" height="583" alt="EDA 3" src="https://github.com/user-attachments/assets/1b8160af-91cb-49a8-9993-ecf1a6b5428a" />
<img width="1384" height="583" alt="EDA 2" src="https://github.com/user-attachments/assets/ee82561f-c05b-4055-9131-9d5cf622444f" />


Email dominates Anonymous session volume with 224,690 sessions, followed by Adwords at 150,115. The remaining channels (Facebook, YouTube, Organic) contribute 50K sessions each.

Critically, when viewed as **proportional composition**, every channel shows a near-identical split: ~73% Anonymous, ~22% Registered Lead, ~5% Existing Buyer. This pattern holds across all five channels with less than 0.2 percentage point variance.

**Insight:** There is no meaningful difference in audience quality or user-type composition across traffic channels. The platform attracts the same mix of user types regardless of acquisition channel.

**Implication:** The drop-off problem is not a targeting problem — reallocating budget from Email to Adwords (or any other channel) will not improve conversion rates. The 73% Anonymous composition is a platform-wide characteristic, not a channel-specific artifact.

**Business Impact:** This finding protects against a common misdiagnosis — blaming underperforming channels. The fix must be architectural (reducing registration friction), not tactical (shifting ad spend). Email, as the highest-volume channel, represents the largest immediate opportunity: **improving the Anonymous conversion experience on Email-sourced sessions alone would impact 224K sessions per cycle**.

---

### 6.2 Objective 2 — RFM Segmentation & Retention Analysis

#### Finding 3: Revenue Distribution and Segment Risk Profile

<img width="1382" height="784" alt="EDA 4" src="https://github.com/user-attachments/assets/969892f1-532c-45d1-8c2a-16a86eacd4af" />

The RFM Segment Bubble Map positions each segment across three dimensions simultaneously: X-axis (avg recency / days inactive), Y-axis (total revenue), and bubble size (unique user count). This creates an immediate visual language for risk: segments in the top-right quadrant carry both high revenue and high inactivity — the most dangerous combination.

| Segment | Unique Users | Total Revenue | % of Total Revenue | Avg Recency (days inactive) | Avg CLV |
|---|---|---|---|---|---|
| At Risk | 2,171 | $245,441 | 22.1% | 248 days | $113 |
| Loyal Customers | 1,248 | $226,086 | 20.4% | 92 days | $181 |
| Potential Loyalist | 2,866 | $204,951 | 18.5% | 36 days | $72 |
| Champions | 735 | $135,387 | 12.2% | 11 days | $184 |
| Cant Lose Them | 496 | $85,653 | 7.7% | 309 days | $173 |

**Insight:** At Risk alone accounts for **22.1% of total revenue** — the single largest revenue-contributing segment — while simultaneously being one of the most inactive, with an average of 248 days since last purchase. Combined with Cant Lose Them, these two deteriorating segments represent **$331,094 (29.8% of total platform revenue)** currently at risk of permanent churn.

**Implication:** The platform's two most financially critical "danger zones" are not low-value segments — they are former high-value customers who have simply stopped coming back. This is a retention failure, not a value mismatch.

**Business Impact:** Recovering even a fraction of At Risk and Cant Lose Them represents a disproportionate revenue opportunity relative to the cost of intervention. These segments do not need to be acquired — they already know the platform, they already have purchase history, and their category preferences are known.

---

#### Finding 4: Purchase Interval per Segment — The Inactivity Gap

<img width="1184" height="684" alt="EDA 5" src="https://github.com/user-attachments/assets/0ba7a4fb-9308-4c82-a501-240a3157d6d0" />

Average days between orders varies dramatically across segments, providing a behavioral clock for each customer group.

| Segment | Avg Days Between Orders | Status vs Benchmark |
|---|---|---|
| Champions | 91.4 days | ✅ Benchmark — healthiest cycle |
| Loyal Customers | 188.0 days | ✅ Active, within tolerance |
| Cant Lose Them | 327.3 days | ⚠️ 3.6× benchmark — early danger |
| At Risk | 480.0 days | 🔴 5.3× benchmark — critical |
| Need Attention | 546.3 days | 🔴 6.0× benchmark — critical |
| Hibernating | 601.8 days | 🔴 6.6× benchmark — near-lost |
| About to Sleep | 659.6 days | 🔴 7.2× benchmark — most concerning |
| Potential Loyalist | 672.1 days | ⚠️ Artifact of single-purchase behavior |
| New Customers | 708.2 days | ⚠️ Artifact of single-purchase behavior |
| Promising | 838.7 days | ⚠️ Artifact of single-purchase behavior |

> **Note on long-tail segments:** The extreme avg_gap values for Potential Loyalist, New Customers, and Promising reflect the fact that these segments largely consist of single-purchase users — the "days between orders" calculation is drawn from a sparse multi-year history rather than indicating true inactivity.

**Insight:** Champions (91.4 days) establish the healthy purchase interval benchmark. Every segment beyond 2× this threshold (>183 days) requires proactive retention intervention. At Risk customers are purchasing at a cadence **5× slower than the platform's healthiest segment**.

**Implication:** Purchase intervals are a leading indicator — they measure the trajectory toward churn before it is officially recorded. A customer who used to buy every 91 days and now hasn't bought in 480 days is not "inactive yet" — they are already behaviorally churned.

**Business Impact:** The purchase interval data directly informs intervention timing. For Loyal Customers, a triggered re-engagement email at day 150 (before they cross the 188-day avg threshold) could prevent migration into the At Risk segment. For At Risk customers who have already exceeded the threshold, a higher-urgency win-back is required.

---

#### Finding 5: Category Affinity by Segment — The Personalization Map

<img width="1475" height="1318" alt="EDA 6" src="https://github.com/user-attachments/assets/77e4a421-d787-426e-a927-65adbd8a91bf" />

Category affinity analysis reveals consistent purchasing patterns that differ significantly between premium and entry-level segments — creating a direct input for personalized win-back campaigns.

| Segment | Category #1 | Revenue Share | Category #2 | Revenue Share |
|---|---|---|---|---|
| Champions | Jeans | 13.3% | Sweaters | 8.2% |
| Loyal Customers | Jeans | 12.9% | Outerwear & Coats | 16.2% |
| At Risk | Jeans | 14.8% | Fashion Hoodies & Sweatshirts | 5.2% |
| Cant Lose Them | Jeans | 12.1% | Outerwear & Coats | 14.7% |
| Hibernating | Intimates | 7.3% | Tops & Tees | 6.5% |
| Potential Loyalist | Intimates | 5.5% | Sleep & Lounge | 6.7% |

**Insight:** A clear two-tier pattern emerges. Premium segments (Champions, Loyal Customers, At Risk, Cant Lose Them) share **Jeans as the #1 revenue category** and are drawn to high-ticket categories like Outerwear & Coats. Entry-level segments (Hibernating, Potential Loyalist, New Customers) concentrate in **Intimates, Tops & Tees, and Sleep & Lounge** — lower-price-point categories.

**Implication:** Category preference is not random — it is a **segment-stable behavioral signal**. At Risk customers were Jeans buyers before they became inactive. They are not price-sensitive Intimates shoppers who happened to spend more; they are premium fashion buyers who have disengaged.

**Business Impact:** This finding unlocks segment-specific personalization without requiring additional data collection. A win-back email for At Risk customers referencing their Jeans purchase history will be categorically more relevant than a generic promotional message — and the sub-bucket structure (Jeans lovers vs. Swim lovers vs. Fashion Hoodies lovers within At Risk) enables further precision targeting within the segment.

---

#### Finding 6: Low-Frequency Signal — Dataset Constraint

Even the top segment (Champions) averages only 1.5 orders; Loyal Customers average 1.4 orders. This is notably lower than what one would expect from "loyal" or "champion" designations in a real-world fashion e-commerce context.

**Insight:** This pattern likely reflects a property of the synthetic dataset — TheLook is generated data where repeat purchase rates may not replicate real consumer behavior. In production analytics, Champions typically show 4–8+ orders per year.

**Implication:** Frequency-based recommendations (e.g., cross-sell timing based on order cadence) should be stress-tested before deployment. The RFM scoring itself remains valid as a relative ranking tool, but absolute frequency thresholds would need recalibration against real business baselines.

**Business Impact:** All experiment financial projections in this analysis use **AOV as the revenue multiplier** (not avg_clv) precisely to avoid overstating impact from frequency assumptions. This is a deliberate conservative adjustment.

---

## 7. Dashboard — Looker Studio

The dashboard is designed as a **single narrative arc** — not a daily monitoring tool, but a self-contained story flowing from problem identification through to recommendation foundations. Every panel answers one of the Key Business Questions defined in Section 1.4.

<img width="1086" height="767" alt="Screenshot 2026-05-17 190010" src="https://github.com/user-attachments/assets/7c3e0be3-42f0-4781-9a10-85316bdd9bb9" />

### Dashboard Layout

The dashboard is organized into three horizontal bands, each serving a distinct analytical purpose:

**Band 1 — KPI Scorecards (top row)**
Five headline metrics provide an immediate executive summary of both objectives before any chart is read.

**Band 2 — Acquisition Story (left + right, upper section)**
- Left: Funnel drop-off per channel — answers "where does the loss happen?"
- Right: Session volume by channel & user type — answers "how big is the loss?"

**Band 3 — Retention Story (full-width + lower section)**
- Center: RFM Segment Bubble Map — the centerpiece visual, communicating revenue-at-risk in a single chart
- Bottom-left: Purchase interval per segment — the behavioral clock
- Bottom-right: Category affinity by segment — the personalization input

### KPI Cards

| KPI | Value | Objective |
|---|---|---|
| Total anonymous sessions | 500K | Acquisition — scale of the opportunity |
| Product-to-cart rate (anonymous) | 50% | Acquisition — where the loss is happening |
| At risk revenue | $245.4K | Retention — the financial stake |
| At risk avg inactivity | 248 days | Retention — urgency signal |
| Champions purchase cycle | 91 days | Retention — healthy benchmark |

---

## 8. Insights & Strategic Recommendations

### 8.1 Key Findings Summary

**Objective 1 — Acquisition:**
1. **Structural acquisition barrier:** ~250,000 sessions per cycle are lost at the product page — not due to poor ad quality, but because the registration requirement blocks Anonymous users from completing a purchase at the moment of highest intent.
2. **Channel-agnostic drop-off:** The ~50% product-to-cart rate and 0% cart-to-purchase rate are identical across all five channels, confirming the problem is platform-wide and cannot be solved by reallocating marketing budget.

**Objective 2 — Retention:**

3. **Revenue concentration risk:** The top 4 segments account for 73% of total revenue. At Risk and Cant Lose Them together contribute $331K (29.8%) from segments currently in deteriorating condition.
4. **Behavioral churn signal:** At Risk customers are purchasing at 5× the interval of Champions — the inactivity gap has already exceeded the point where passive recovery is plausible.
5. **Category anchor:** Jeans is the universal anchor category for premium segments — consistently the #1 revenue driver for Champions, Loyal Customers, At Risk, and Cant Lose Them alike.

---

### 8.2 Strategic Recommendations

Three strategic pillars, sequenced by urgency and operational risk.

---

#### Pillar 1 — Acquisition Optimization (Anonymous Users)

**Problem:** ~250,000 sessions drop off at the product page every cycle. The platform has already paid CAC to bring this traffic in but has yet to extract full return on that investment.

**Approach: Zero Additional Marketing Spend** — optimize conversion from existing traffic without acquiring new visitors.

Experiments are run **sequentially** (not simultaneously) to maintain data cleanliness and isolate the effect of each intervention:

**Phase 1 — Product Page Optimization (Persuasion)**

| Element | Detail |
|---|---|
| Hypothesis | Adding social proof ("100+ sold") increases product-to-cart rate from ~50% to >55% |
| Design | A/B Test on product page UI — Group A (no social proof) vs Group B (social proof + clear ratings) |
| Randomization unit | session_id |
| Primary metric | Product-to-cart rate |
| Guardrail metric | Page load time must not increase by >0.5 seconds |
| Target lift | +5 percentage points (conservative) |
| Scale of impact | 5% of 250K dropping sessions = **12,500 additional sessions** entering cart per cycle |

**Phase 2 — Cart Friction Reduction (One-Tap Sign-In)**

| Element | Detail |
|---|---|
| Hypothesis | One-Tap Google Sign-In at cart page increases cart-to-registration rate to ≥10% |
| Design | A/B Test — Group A (standard registration form) vs Group B (One-Tap Google Sign-In) |
| Randomization unit | session_id |
| Primary metric | Cart-to-registered-lead rate |
| Guardrail metric | Registration page bounce rate must not increase |
| Target | 10% of cart sessions (conservative estimate below Baymard Institute's 20–35% benchmark for simplified checkout) |

---

#### Pillar 2 — Revenue Recovery (At Risk & Cant Lose Them)

**Problem:** $331K in revenue (29.8%) sits within two deteriorating segments — At Risk (248 days inactive) and Cant Lose Them (309 days inactive).

**Why Email?** Email accounts for 44.8% of all registered user sessions. Zero-CAC — leverages an existing database at near-zero operational cost.

**At Risk Win-back Campaign (Priority 1)**

| Element | Detail |
|---|---|
| Strategy | Stratified A/B Test based on category affinity |
| Sub-buckets | Jeans lovers · Fashion Hoodies lovers · Swim lovers (based on historical top categories) |
| Randomization | Within sub-group — each sub-group split 50/50 |
| Group A (Control) | Generic promotional email (site-wide sale) |
| Group B (Treatment) | Dynamic personalized email: *"We miss you — your favorite [Category] collection is waiting"* |
| Conversion window | 30 days |
| Primary metric | Re-activation rate (purchase within 30 days post-email) |
| Guardrail metric | Unsubscribe rate must not increase by >1% |
| Target lift | +3 percentage points incremental above control group |
| **Revenue projection** | 3% × 2,171 users = 65 users × AOV $105.24 = **$6,840 direct recovery** |
| Note | Future lifetime value is substantially larger if users return to permanent active status |

**Sample size:** From a total At Risk population of 2,171 users, ~1,085 users per group — feasible in a single batch, estimated duration 2–3 weeks.

---

#### Pillar 3 — Value Maximization (Champions)

**Problem:** Champions hold the highest CLV ($184) and shortest purchase cycle (91 days) — the healthiest segment on the platform. The goal here is not rescue but revenue growth, achieved without margin erosion through direct discounting.

| Element | Detail |
|---|---|
| Strategy | Automated cross-sell recommendations for complementary premium products at checkout |
| Trigger | User purchases Jeans → show Outerwear & Coats / Sweaters recommendations |
| Design | A/B Test — Group A (standard cart) vs Group B (cart + cross-sell recommendations) |
| Primary metric | Average Order Value (AOV) |
| Guardrail metric | Cart abandonment rate must not increase by >5% |
| Target | Purchase frequency increase from avg 1.5 → 1.8 orders (+0.3 incremental) |
| **Experiment phase projection** | 367 treatment users × (0.3 × $121.94) = **$13,425** |
| **Full rollout projection** | 735 users × (0.3 × $121.94) = **$26,887** within 6 months |

---

#### Tactical Maintenance (Tier 2 & 3 Segments)

| Segment | Action | Rationale |
|---|---|---|
| Potential Loyalist | Automated trigger email on day 30 post-first-purchase with second-purchase voucher | Recency still 36 days — the re-engagement window is still open |
| New Customers | Same trigger as Potential Loyalist | avg_orders = 1.0, needs a nudge toward second purchase |
| Loyal Customers | Pre-gap triggered email at day 150 | Prevent migration to At Risk before the threshold is crossed |
| Hibernating & About to Sleep | Automated low-touch email sequence every 3 months | Low CLV ($38) — full campaign cost is not justified by expected return |

---

### 8.3 Execution Priority & Expected Impact

| Priority | Segment | Strategy | Expected Impact | Timeline |
|---|---|---|---|---|
| 1 | At Risk | Personalized win-back email (stratified by category) | $6,840 direct + future CLV recovery | 2–3 weeks |
| 2 | Anonymous | Phase 1 — Product page social proof A/B test | 12,500 additional sessions to cart | 2 weeks |
| 3 | Cant Lose Them | High-value win-back (larger incentive justified by $173 CLV) | $85K at-risk revenue | 3–4 weeks |
| 4 | Champions | Cross-sell bundling at checkout | $13,425 (experiment) → $26,887 (rollout) | 6 months |
| 5 | Anonymous | Phase 2 — One-Tap Sign-In cart friction reduction | Cart-to-registration rate lift | After Phase 1 completes |
| 6 | Loyal Customers | Pre-gap triggered email at day 150 | Prevent At Risk migration | Ongoing |

### 8.4 What We Won't Do (and Why)

The **Hibernating** and **About to Sleep** segments are not prioritized as primary win-back targets. Their avg CLV is only $38 with purchase gaps exceeding 600 days. The cost of a full win-back campaign equivalent in intensity to the At Risk playbook would not be justified by the expected ROI from this cohort. These segments are placed into an **automated low-touch background sequence** requiring no dedicated resource allocation — preserving optionality without committing disproportionate effort.

---

## Limitations & Methodology Notes

1. **Synthetic dataset:** TheLook is a generated dataset — certain patterns (e.g. `cart_to_purchase = 0%` for Anonymous, uniformly low avg_orders) are by-design artifacts, not real business behavior. Findings should be interpreted as directionally valid, not operationally prescriptive.
2. **RFM lifetime vs rolling window:** RFM is computed from a trailing 1-year window. Large gaps in At Risk (avg_gap 480 days) reflect a long purchase history, not just the 1-year window — this should be factored into interpretation.
3. **A/B Testing is forward-looking:** Given the limitations of historical data, no retroactive randomization can be applied. All experiment designs are recommendations to be executed going forward, not tests that have already been run.
4. **AOV is a derived metric:** Since no native AOV column exists, the values of $105.24 (At Risk) and $121.94 (Champions) are derived from `total_revenue / (unique_users × avg_orders)` — valid as an estimate but not the actual per-order transaction value.
5. **Frequency anomaly:** The low avg_orders across all segments (1.0–1.5) is atypical for a fashion e-commerce platform and likely reflects dataset generation constraints. All revenue projections use AOV (not avg_clv) specifically to avoid amplifying this artifact.

---

*This project was built as part of a data analytics portfolio.*  
*Dataset: [TheLook Ecommerce — Google BigQuery Public Data](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce)*
