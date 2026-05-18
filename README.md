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
| `aov_summary` | AOV per segment calculated from completed order items | Financial projections in Section 8 |

### 5.4 Derived Metric: AOV per Segment

AOV is calculated directly from completed transaction records using `SUM(sale_price) / COUNT(DISTINCT order_id)` per segment. The full reference table is included below and used as the financial multiplier across all projections in Section 8.

| Segment | AOV | Total Orders | Total Revenue |
|---|---|---|---|
| At Risk | $105.24 | 2,548 | $268,156 |
| Champions | $121.94 | 1,126 | $137,305 |
| Cant Lose Them | $152.89 | 602 | $92,038 |
| Loyal Customers | $128.88 | 1,827 | $235,466 |
| Potential Loyalist | $71.39 | 3,080 | $219,874 |
| Hibernating | $43.97 | 2,402 | $105,611 |
| About to Sleep | $42.84 | 1,098 | $47,043 |

---

## 6. Exploratory Data Analysis (EDA)

EDA was conducted in Google Colab (Python) with a direct BigQuery connection. Libraries: `pandas`, `matplotlib`, `seaborn`. All data was queried directly from the BigQuery analytical tables built in Section 5 — no local file exports.

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
 
**Implication:** Anonymous users cannot complete a purchase without registering first — creating a mandatory friction point precisely at the moment of highest purchase intent. The fix must be architectural, not tactical. Reallocating budget between channels will not move this number.
 
**Business Impact:** Approximately **250,000 sessions per cycle** are abandoned at the product page. Any improvement here requires zero additional acquisition spend — the audience is already on the platform, already paid for.

---

#### Finding 2: Traffic Volume and Composition by Channel

<img width="1384" height="583" alt="EDA 3" src="https://github.com/user-attachments/assets/1b8160af-91cb-49a8-9993-ecf1a6b5428a" />
<img width="1384" height="583" alt="EDA 2" src="https://github.com/user-attachments/assets/ee82561f-c05b-4055-9131-9d5cf622444f" />


Email dominates Anonymous session volume with 224,690 sessions, followed by Adwords at 150,115. The remaining channels (Facebook, YouTube, Organic) contribute ~50K sessions each.
 
When viewed as proportional composition, every channel shows a near-identical split: ~73% Anonymous, ~22% Registered Lead, ~5% Existing Buyer — with less than 0.2 percentage point variance across all five channels.
 
**Insight:** There is no meaningful difference in audience quality or user-type composition across traffic channels. The platform attracts the same mix of user types regardless of acquisition channel.
 
**Implication:** The drop-off problem cannot be attributed to any specific channel's targeting. This rules out the common misdiagnosis of shifting ad spend as a fix. Email, as the highest-volume channel, represents the largest single immediate opportunity — improving the Anonymous conversion experience on Email-sourced sessions alone would impact **224K sessions per cycle**.
 
**Business Impact:** This finding protects against misallocating marketing budget. The root cause is platform-wide, and the solution sits in product and engineering, not in media planning.

---

### 6.2 Objective 2 — RFM Segmentation & Retention Analysis

#### Finding 3: Revenue Distribution and Segment Risk Profile

<img width="1382" height="784" alt="EDA 4" src="https://github.com/user-attachments/assets/969892f1-532c-45d1-8c2a-16a86eacd4af" />

The RFM Segment Bubble Map positions each segment across three dimensions simultaneously: X-axis (avg recency / days inactive), Y-axis (total revenue), and bubble size (unique user count). Segments in the top-right quadrant carry both high revenue and high inactivity — the most financially dangerous combination.
 
| Segment | Unique Users | Total Revenue | % of Total Revenue | Avg Recency | Avg CLV | Status |
|---|---|---|---|---|---|---|
| At Risk | 2,171 | $245,441 | 22.1% | 248 days | $113 | 🔴 Deteriorating |
| Loyal Customers | 1,248 | $226,086 | 20.4% | 92 days | $181 | ⚠️ At threshold |
| Potential Loyalist | 2,866 | $204,951 | 18.5% | 36 days | $72 | ✅ Active — activation window open |
| Champions | 735 | $135,387 | 12.2% | 11 days | $184 | ✅ Healthiest |
| Cant Lose Them | 496 | $85,653 | 7.7% | 309 days | $173 | 🔴 Deteriorating |
 
**Insight:** At Risk alone accounts for 22.1% of total revenue — the single largest contributor — while being one of the most inactive segments at 248 days since last purchase. At Risk and Cant Lose Them combined represent **$331K (29.8%)** of total platform revenue in active deterioration.
 
However, the risk picture extends beyond the two red segments. **Loyal Customers ($226K, 20.4%)** are currently active but approaching their average purchase gap threshold of 188 days. Without a preventive trigger, a portion of this $226K will migrate into the At Risk zone within 3–6 months. The total revenue under threat — including Loyal Customers at risk of downgrade — approaches **$557K**.
 
**Implication:** The platform's retention challenge is not limited to recovering churned customers. It includes preventing currently active high-value customers from churning in the first place. Prevention is structurally cheaper than recovery, which informs the sequencing of interventions in Section 8.
 
**Business Impact:** Potential Loyalist (2,866 users, $205K, recency 36 days) is frequently overlooked because their avg_gap appears long at 672 days. This is a measurement artifact — their gap is long because most of them have only made one purchase over a multi-year dataset. Their recency of 36 days means they just bought. The window to drive a second purchase is open right now and closing. See Finding 4 for full interpretation.

---

#### Finding 4: Purchase Interval per Segment — The Behavioral Clock

<img width="1184" height="684" alt="EDA 5" src="https://github.com/user-attachments/assets/0ba7a4fb-9308-4c82-a501-240a3157d6d0" />

Average days between orders varies dramatically across segments, functioning as a behavioral clock: segments with short intervals are healthy and engaged; segments with long intervals are drifting toward permanent churn.
 
| Segment | Avg Days Between Orders | Relative to Benchmark | Interpretation |
|---|---|---|---|
| Champions | 91.4 days | ✅ Benchmark | Healthiest purchase cycle |
| Loyal Customers | 188.0 days | 2.1× benchmark | Active but approaching threshold |
| Cant Lose Them | 327.3 days | 3.6× benchmark | Early danger — high CLV at risk |
| At Risk | 480.0 days | 5.3× benchmark | Critical — behavioral churn already occurred |
| Need Attention | 546.3 days | 6.0× benchmark | Critical |
| Hibernating | 601.8 days | 6.6× benchmark | Near-lost |
| About to Sleep | 659.6 days | 7.2× benchmark | Most concerning recoverable segment |
| Potential Loyalist | 672.1 days | — | Artifact — see note below |
| New Customers | 708.2 days | — | Artifact — see note below |
| Promising | 838.7 days | — | Artifact — see note below |
 
> **Interpreting long-tail avg_gap values:** The extreme avg_gap figures for Potential Loyalist, New Customers, and Promising are not behavioral signals — they are measurement artifacts. These segments consist largely of single-purchase users. When a user has only one order in a multi-year dataset, the "days between orders" calculation draws on their entire account history rather than a meaningful repeat-purchase cycle. The operative signal for these segments is **recency**, not avg_gap. Potential Loyalist recency of 36 days is what matters, not the 672-day gap figure.
 
**Insight:** Champions (91.4 days) establish the healthy benchmark. The gap between Champions and At Risk is not gradual — it represents a fundamental behavioral break. At Risk customers are not "buying less often"; they have behaviorally churned and simply haven't been officially classified as lost yet.
 
**Implication:** Purchase intervals are a **leading indicator** of churn, not a lagging one. A customer approaching the 188-day Loyal Customer threshold should be contacted at day 150 — before the threshold, not after. This is the basis for the preventive trigger in Section 8 (Phase 2A).
 
**Business Impact:** The interval data directly determines intervention timing across all retention phases. Phase 1 targets segments that have already exceeded their thresholds (reactive). Phase 2 targets segments approaching their thresholds (preventive). Both are necessary; neither can substitute for the other.

---

#### Finding 5: Category Affinity by Segment — The Personalization Map

<img width="1475" height="1318" alt="EDA 6" src="https://github.com/user-attachments/assets/77e4a421-d787-426e-a927-65adbd8a91bf" />

Category affinity analysis reveals consistent purchasing patterns that differ significantly between premium and entry-level segments — and maps directly onto the personalization strategy in Section 8.
 
| Segment | Category #1 | Revenue Share | Category #2 | Revenue Share | Avg Item Price |
|---|---|---|---|---|---|
| Champions | Jeans | 13.3% | Sweaters | 8.2% | $120 |
| Loyal Customers | Jeans | 12.9% | Outerwear & Coats | 16.2% | $110–$184 |
| At Risk | Jeans | 14.8% | Fashion Hoodies | 5.2% | $113 |
| Cant Lose Them | Jeans | 12.1% | Outerwear & Coats | 14.7% | $122–$165 |
| Potential Loyalist | Intimates | 5.5% | Sleep & Lounge | 6.7% | $35–$48 |
| Hibernating | Intimates | 7.3% | Tops & Tees | 6.5% | $26–$31 |
 
**Insight:** Two structurally different customer profiles emerge. Premium segments (Champions, Loyal Customers, At Risk, Cant Lose Them) are anchored by **Jeans** as the #1 revenue category and show affinity for high-ticket items — Outerwear & Coats averaging $165–$184 per item. Entry-level segments (Potential Loyalist, Hibernating, New Customers) concentrate in **Intimates and Tops & Tees** at $26–$48 per item.
 
**Implication:** Category preference is **segment-stable** — At Risk customers were Jeans and Outerwear buyers before they became inactive. They are premium fashion buyers who have disengaged, not price-sensitive shoppers. This distinction is critical for campaign design: a win-back email referencing Jeans (not a generic discount) is the right message for this cohort. For Potential Loyalist, the personalization input is different — Intimates and Sleep & Lounge at entry-level price points, with the goal of building habit rather than selling premium.
 
**Business Impact:** This finding enables precise sub-bucket targeting within the At Risk win-back campaign (Jeans lovers / Fashion Hoodies lovers / Swim lovers) without requiring any additional data collection. The personalization input already exists in the purchase history. It also defines the cross-sell logic for Champions: Jeans purchasers shown Outerwear recommendations is not a guess — it is supported by the co-occurrence of these categories at the top of Champions' affinity profile.

---

#### Finding 6: Low-Frequency Signal — Dataset Constraint and Analytical Adjustment

Even the top segment (Champions) averages only 1.5 orders; Loyal Customers average 1.4 orders. This is atypically low for a fashion e-commerce platform — real-world Champions typically show 4–8+ orders per year.
 
**Insight:** This pattern reflects a constraint of the synthetic TheLook dataset, where repeat purchase rates do not replicate real consumer behavior at scale. It is not a signal about the platform's actual retention performance.
 
**Implication:** Any revenue projection that multiplies avg_clv by a recovery rate would silently amplify this frequency artifact. All financial projections in this analysis use **AOV** (average order value per transaction) as the multiplier instead — a deliberate conservative adjustment that keeps estimates grounded in observable transaction values rather than synthetic frequency assumptions.
 
**Business Impact:** The RFM scoring remains valid as a relative ranking tool — Champions are genuinely more valuable than At Risk customers within this dataset. But absolute frequency thresholds and CLV projections would require recalibration against real business baselines before operational deployment.

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
1. **Structural acquisition barrier:** ~250,000 sessions per cycle are lost at the product page — not due to poor ad quality, but because the mandatory registration requirement blocks Anonymous users from completing a purchase at the moment of highest intent.
2. **Channel-agnostic drop-off:** The ~50% product-to-cart rate and 0% cart-to-purchase rate are identical across all five channels, confirming the problem is platform-wide and cannot be solved by reallocating marketing budget.

**Objective 2 — Retention:**

3. **Revenue concentration risk:** The top 4 segments account for 73% of total revenue. At Risk and Cant Lose Them together contribute $331K (29.8%) from segments in active deterioration, while Loyal Customers ($226K) are approaching the threshold that would migrate them into the at-risk zone.
4. **Behavioral churn signal:** At Risk customers are purchasing at 5× the interval of Champions (480 vs 91 days) — the inactivity gap has already exceeded the point where passive recovery is plausible without intervention.
5. **Untapped activation window:** Potential Loyalist (2,866 users, $205K revenue) are largely one-time buyers with a recency of just 36 days — the re-engagement window is still open, and a second purchase nudge carries outsized long-term CLV potential.
6. **Category anchor:** Jeans is the universal anchor category for all premium segments — consistently the #1 revenue driver for Champions, Loyal Customers, At Risk, and Cant Lose Them alike, enabling precise personalization without additional data collection.

---

### 8.2 The Cost of Inaction
 
Before presenting interventions, it is worth quantifying what happens if nothing is done. This framing anchors every subsequent recommendation in business consequence, not analytical preference.
 
| Scenario | Revenue at Stake | Timeframe |
|---|---|---|
| At Risk fully churns | $245,441 | 6–12 months |
| Cant Lose Them fully churns | $85,653 | 6–12 months |
| Loyal Customers migrate to At Risk (no prevention) | ~$45,000 | 3–6 months |
| **Total revenue at risk without intervention** | **~$376K–$557K** | **Within 12 months** |

> *Loyal Customers figure assumes a conservative 20% migration rate — not all 1,248 users will churn without intervention. The lower bound ($376K) uses this estimate; the upper bound ($557K) represents full Loyal Customers revenue for context only.*

Against this, the variable cost of email campaigns approaches zero. The question is not whether to intervene — the question is in which order.

---
 
### 8.3 Strategic Recommendations
 
All retention interventions are organized into two phases. Phase 1 is **reactive** — recovering revenue that is already at risk. Phase 2 is **preventive and growth-oriented** — protecting revenue that is currently healthy and activating segments with untapped potential.
 
Experiments within each phase are run **sequentially, not simultaneously**, to maintain data cleanliness and ensure each intervention's effect can be isolated and measured before the next begins.
 
---

#### Pillar 1 — Acquisition Optimization (Anonymous Users)
 
**Problem:** ~250,000 sessions drop off at the product page every cycle. The platform has already paid CAC to bring this traffic in but has yet to extract full return on that investment.
 
**Approach: Zero Additional Marketing Spend** — optimize conversion from existing traffic without acquiring new visitors. Experiments run sequentially to isolate each intervention's effect.
 
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
| Exit criteria | If lift <1% after 2 weeks, move to Phase 2 — the barrier is friction, not persuasion |
 
**Phase 2 — Cart Friction Reduction (One-Tap Sign-In)**
 
| Element | Detail |
|---|---|
| Hypothesis | One-Tap Google Sign-In at cart page increases cart-to-registration rate to ≥10% |
| Design | A/B Test — Group A (standard registration form) vs Group B (One-Tap Google Sign-In) |
| Randomization unit | session_id |
| Primary metric | Cart-to-registered-lead rate |
| Guardrail metric | Registration page bounce rate must not increase |
| Target | 10% of cart sessions (conservative estimate below Baymard Institute's 20–35% benchmark) |
| Exit criteria | If lift <3%, escalate to product team — architectural guest checkout may be required |
 
---

#### Pillar 2 — Retention: Phase 1 (Reactive Win-back)
 
**Problem:** $331K in revenue (29.8%) sits within two deteriorating segments that have stopped purchasing but whose category preferences and contact information are known.
 
**Why Email?** Email accounts for 44.8% of all registered user sessions (81,421 of 181,741 combined sessions). Near-zero variable cost — leverages an existing database with no incremental acquisition spend.
 
**Why sequential, not parallel?** Running At Risk and Cant Lose Them simultaneously would split team focus, complicate measurement, and reduce the learnings transferable from one campaign to the next. At Risk goes first because its revenue pool is nearly 3× larger.
 
---

##### Phase 1A — At Risk Win-back (Weeks 1–3)
 
**Rationale for priority:** Largest single revenue-at-risk pool ($245K, 22.1% of total). Population of 2,171 users provides sufficient sample size for a statistically valid experiment in a single batch.

| Element | Detail |
|---|---|
| Strategy | Stratified A/B Test based on historical category affinity |
| Sub-buckets | Jeans lovers · Fashion Hoodies lovers · Swim lovers |
| Randomization | Within sub-group — each sub-group split 50/50 independently |
| Group A (Control) | Generic promotional email (site-wide sale) |
| Group B (Treatment) | Dynamic personalized email: *"We miss you — your favorite [Category] collection is waiting"* |
| Conversion window | 30 days |
| Primary metric | Re-activation rate (purchase within 30 days post-email) |
| Guardrail metric | Unsubscribe rate must not increase by >1% |
| Target lift | +3 percentage points incremental above control baseline |
| AOV used | $105.24 (calculated from 2,548 completed orders, $268,156 total revenue) |
| **Revenue projection** | 3% × 2,171 users = 65 users × AOV $105.24 = **$6,840 direct recovery** |
| Exit criteria | If lift <1%, segment is likely beyond email recovery — do not proceed to Cant Lose Them with the same playbook; adjust intensity first |
 
> *Note: The $6,840 figure represents direct revenue from one campaign cycle. Future lifetime value is substantially larger if users return to permanent active status.*
 
**Sample size:** ~1,085 users per group from a total population of 2,171 — feasible in a single batch, estimated duration 2–3 weeks.

---

##### Phase 1B — Cant Lose Them Win-back (Weeks 3–6, after Phase 1A results are measured)
 
**Rationale for sequencing after At Risk:** Revenue pool is smaller ($85K, 7.7%) but AOV per transaction is the highest of all segments at **$152.89** — driven by their strong affinity for Outerwear & Coats and Jeans. Results from Phase 1A provide a tested playbook: if personalized email worked, replicate with higher incentive intensity. If it did not, adjust before committing to this cohort.
 
**Why this segment still warrants high-intensity intervention despite smaller revenue pool:** At AOV $152.89 and CLV $173, each recovered transaction and each recovered user returns more value per unit of intervention cost than any other segment. The smaller absolute revenue figure reflects population size (496 vs 2,171), not individual customer value.
 
| Element | Detail |
|---|---|
| Strategy | Category-personalized win-back email (Jeans + Outerwear & Coats) |
| Incentive level | Higher than At Risk — AOV $152.89 and CLV $173 justify a larger discount to trigger re-engagement |
| Group A (Control) | Generic promo email |
| Group B (Treatment) | Personalized email with category-specific offer + time-limited urgency framing |
| Conversion window | 30 days |
| Primary metric | Re-activation rate |
| Guardrail metric | Net margin after discount must remain positive |
| AOV used | $152.89 (calculated from 602 completed orders, $92,038 total revenue) |
| **Revenue projection** | 3% × 496 users = 15 users × $152.89 = **$2,293 direct recovery** |
| **Revenue at stake** | $85,653 total — recovery of even 10% = **$8,565** from a cohort that cost nothing to acquire |
| Exit criteria | If net margin after discount goes negative, reduce incentive or pause campaign |
 
> *Note: The direct recovery projection ($2,293) appears modest because the population is small. The strategic case rests on AOV and CLV — each recovered user is the highest-value transaction on the platform, and the total revenue pool ($85K) remains meaningful.*
 
---
#### Pillar 3 — Retention: Phase 2 (Preventive & Growth)
 
Phase 2 runs in parallel after Phase 1A is launched. These interventions are either **automated triggers** (low ongoing effort after initial setup) or **feature additions** (one-time engineering cost, ongoing return). They do not compete with Phase 1 for campaign resources.
 
---
 
##### Phase 2A — Loyal Customers: Pre-gap Triggered Email (Month 2, ongoing)
 
**Rationale:** $226K revenue (20.4%), avg CLV $181, currently active (recency 92 days). Their avg purchase gap is 188 days — without intervention, a portion of this segment will cross the threshold and migrate into At Risk within 3–6 months. Prevention cost is near-zero; recovery cost after migration is not.
 
| Element | Detail |
|---|---|
| Trigger | Automated email sent at day 150 post-last-purchase (before the 188-day avg threshold) |
| Content | New arrivals in Jeans or Outerwear — no discount required; they are still active |
| Design | A/B test: Group A no triggered email, Group B receives day-150 email |
| Primary metric | Purchase rate before day 188 |
| Guardrail metric | Unsubscribe rate must not increase by >1% |
| AOV used | $128.88 (calculated from 1,827 completed orders, $235,466 total revenue) |
| **Revenue defended** | If triggered email retains 5% of 1,248 users who would otherwise churn: 62 users × $128.88 = **~$7,990 revenue defended** per cycle |
| Ongoing effort | Near-zero after initial automation setup |
 
> *"Revenue defended" is the appropriate framing here — this is not new revenue generation but prevention of revenue loss from currently healthy customers.*
> 
> *The 5% retention assumption is conservative — it represents the minimum threshold at which this intervention generates positive expected value relative to near-zero email cost.*
 
---
 
##### Phase 2B — Potential Loyalist: Second Purchase Activation (Month 2–3)
 
**Rationale:** The 672-day avg_gap for this segment is a measurement artifact — it reflects the gap calculation across a multi-year dataset for users who have largely made only one purchase. The operative signal is their **recency of 36 days**. They just bought. The window to drive a second purchase is open now and closing fast.
 
With 2,866 users contributing $205K (18.5% of revenue) and an AOV of $71.39, converting even a modest share to repeat buyers would meaningfully compound their CLV trajectory.
 
| Element | Detail |
|---|---|
| Trigger | Automated email at day 30 post-first-purchase |
| Content | Second-purchase voucher, personalized to first-purchase category (Intimates / Sleep & Lounge / Tops & Tees) |
| Design | A/B test: Group A email at day 7, Group B email at day 30 (tests optimal timing window) |
| Primary metric | Second purchase rate within 60 days |
| Guardrail metric | Voucher redemption rate (ensure discount is not applied unnecessarily) |
| Ongoing effort | Near-zero after automation setup — triggers fire per-user based on transaction date |
| AOV used | $71.39 (calculated from 3,080 completed orders, $219,874 total revenue) |
| **Revenue projection** | 10% × 2,866 users = 287 users × $71.39 = **$20,489 additional revenue** |
 
---
 
##### Phase 2C — Champions: Value Maximization (Month 2–3, parallel)
 
**Rationale:** Champions are the healthiest segment — no rescue required. The intervention here is opportunistic: increase AOV at the point of purchase without discounting, protecting margin while growing revenue per transaction.
 
| Element | Detail |
|---|---|
| Strategy | Automated cross-sell recommendations at checkout — Jeans purchasers shown Outerwear & Coats / Sweaters |
| Design | A/B Test — Group A (standard cart) vs Group B (cart + cross-sell) |
| Primary metric | Average Order Value (AOV) |
| Guardrail metric | Cart abandonment rate must not increase by >5% |
| Target | Purchase frequency increase from avg 1.5 → 1.8 (+0.3 incremental per user) |
| AOV used | $121.94 (calculated from 1,126 completed orders, $137,305 total revenue) |
| **Experiment phase projection** | 367 treatment users × (0.3 × $121.94) = **$13,425** |
| **Full rollout projection** | 735 users × (0.3 × $121.94) = **$26,887** within 6 months |
 
### 8.4 Execution Roadmap
 
The sequencing below is designed to minimize simultaneous active effort while maximizing total coverage over a 3-month window. Phase 1 interventions require active campaign management. Phase 2 interventions are largely automated after initial setup.
 
| Week / Month | Action | Type | Segment | AOV Reference | Expected Output |
|---|---|---|---|---|---|
| Week 1–3 | At Risk win-back campaign | Active A/B test | At Risk | $105.24 | $6,840 direct recovery baseline |
| Week 2 | Acquisition Phase 1 — social proof A/B | Active A/B test | Anonymous | — | 12,500 sessions to cart |
| Week 3–6 | Cant Lose Them win-back (after 1A results) | Active A/B test | Cant Lose Them | $152.89 | $2,293 direct / $8,565 at 10% recovery |
| Month 2 | Loyal Customers day-150 trigger — setup & launch | Automated | Loyal Customers | $128.88 | ~$7,990 revenue defended per cycle |
| Month 2 | Potential Loyalist day-30 trigger — setup & launch | Automated | Potential Loyalist | $71.39 | $20,489 at 10% second purchase rate |
| Month 2–3 | Champions cross-sell feature — A/B test | Feature / A/B test | Champions | $121.94 | $13,425 (experiment) → $26,887 (rollout) |
| Month 2+ | Acquisition Phase 2 — One-Tap Sign-In | Active A/B test | Anonymous | — | Cart-to-registration rate lift |
 
---
 
### 8.5 What We Won't Do (and Why)
 
**Hibernating & About to Sleep** are not prioritized as active win-back targets. Their AOV ($42.84 and $43.97 respectively) and avg CLV (~$38) with purchase gaps exceeding 600 days make the ROI case difficult to justify against higher-value opportunities. They are placed into an **automated low-touch email sequence every 3 months** — preserving optionality at negligible cost, without committing team resources that are better allocated to higher-value segments.
 
**Running all segments simultaneously** was explicitly considered and rejected. Sequential execution ensures each campaign's results inform the next, prevents resource dilution, and gives each experiment a clean measurement window. The roadmap above covers all five priority segments within 3 months — this is not a trade-off between coverage and rigor, it is both.
 
---
 
### 8.6 Exit Criteria & Decision Rules
 
A recommendation without exit criteria is a commitment without conditions. The following rules define when to continue, adjust, or stop each intervention.
 
| Phase | Continue if | Adjust if | Stop if |
|---|---|---|---|
| At Risk win-back | Lift ≥3pp within 30 days | Lift 1–3pp — test higher incentive on Cant Lose Them | Lift <1pp — email channel insufficient; escalate to other channels |
| Cant Lose Them | Net margin positive after discount | Margin negative — reduce discount | Margin negative at minimum viable discount |
| Loyal Customers trigger | Purchase rate before day 188 increases | Open rate low — test subject line | Unsubscribe rate exceeds 1% |
| Potential Loyalist trigger | Second purchase rate >5% in 60 days | Rate 2–5% — test day-7 vs day-30 timing | Rate <2% — reconsider offer strength |
| Champions cross-sell | AOV increases without cart abandonment rise | Cart abandonment rises 3–5% — reduce recommendation aggressiveness | Cart abandonment exceeds +5% |
| Acquisition Phase 1 | Product-to-cart lift ≥+5pp | Lift +1–5pp — evaluate statistical significance | Lift <1pp — move directly to Phase 2 (friction, not persuasion, is the barrier) |
 
---
 
## Limitations & Methodology Notes
 
1. **Synthetic dataset:** TheLook is a generated dataset — certain patterns (e.g. `cart_to_purchase = 0%` for Anonymous, uniformly low avg_orders) are by-design artifacts, not real business behavior. Findings should be interpreted as directionally valid, not operationally prescriptive.
2. **RFM trailing window:** RFM is computed from a 1-year trailing window. Large avg_gap values in At Risk (480 days) reflect multi-year purchase history, not the 1-year analysis window — this distinction matters when interpreting inactivity severity.
3. **Potential Loyalist avg_gap interpretation:** The 672-day avg_gap for this segment is an artifact of measuring gaps for largely one-time buyers across a multi-year dataset, not a signal of behavioral inactivity. Recency (36 days) is the operative signal for this cohort.
4. **A/B Testing is forward-looking:** Historical data cannot be retroactively randomized. All experiment designs are recommendations to be executed going forward, not tests that have already been run.
5. **AOV calculation:** All AOV figures used in financial projections are calculated directly from transaction data using `SUM(sale_price) / COUNT(DISTINCT order_id)` per segment, joining `order_items_cleaned`, `orders_cleaned`, and `rfm_scores`. This is a direct calculation from completed order records — not a derived approximation. Full AOV reference: At Risk $105.24 · Cant Lose Them $152.89 · Loyal Customers $128.88 · Champions $121.94 · Potential Loyalist $71.39 · Hibernating $43.97 · About to Sleep $42.84.
6. **Frequency anomaly:** The low avg_orders across all segments (1.0–1.5) is atypical for a fashion e-commerce platform and likely reflects dataset generation constraints. All revenue projections use AOV (not avg_clv) specifically to avoid amplifying this artifact.

---

*This project was built as part of a data analytics portfolio.*  
*Dataset: [TheLook Ecommerce — Google BigQuery Public Data](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce)*
