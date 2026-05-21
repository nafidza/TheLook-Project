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
<img width="1920" height="500" alt="Modern Minimalist Data Analytics Workflow Infographic (1)" src="https://github.com/user-attachments/assets/e182b420-bfb0-4881-b8f8-8aa5d3ff0f3a" />

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

RFM metrics are computed from `orders_cleaned` and `order_items_cleaned` filtered to `status = 'Complete'`.

| Dimension | Definition | Scoring Logic |
|---|---|---|
| **Recency** | Days between reference date and user's last order date | NTILE(5) DESC — lower recency → score 5 |
| **Frequency** | Count of distinct orders per user | NTILE(5) ASC — higher count → score 5 |
| **Monetary** | Total sale_price per user | NTILE(5) ASC — higher value → score 5 |

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

### 5.3 Derived Metric: AOV per Segment

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

>*Note: Revenue figures here differ slightly from Section 6 due to stricter dual-status filtering at the transaction level. AOV calculations in Section 8 use this table exclusively.*

### 5.4 Final Analytical Tables

| Table | Contents | Used For |
|---|---|---|
| `rfm_scores` | RFM scores & segment per user | All retention analysis |
| `convertion_rate_summary` | Funnel rates per traffic_source × user_type | Acquisition analysis |
| `order_gap_summary` | Avg days between orders per segment | Purchase interval analysis |
| `top_product_summary` | Top 3 categories per segment by revenue | Category affinity |
| `value_summary` | CLV, total revenue, avg recency per segment | Revenue at risk quantification |
| `aov_summary` | AOV per segment calculated from completed order items | Financial projections in Section 8 |

---

## 6. Key Findings

EDA conducted in Google Colab with direct BigQuery connection. Full notebook: [Python for EDA →](https://colab.research.google.com/drive/1YXuW8Oy3rV-GknxEYwetqXd3Xl7fZ15n?usp=sharing)

---

### Finding 1 — 250K Sessions Lost Per Cycle: The Problem Isn't the Ads, It's the Platform

<img width="1384" height="583" alt="EDA 1" src="https://github.com/user-attachments/assets/c2044f3c-2a82-47aa-851f-87e9cec65661" />

Across ~500K Anonymous sessions, every traffic channel shows an identical pattern: product-to-cart conversion holds at ~50%, then cart-to-purchase collapses to exactly 0%.
 
| Traffic Source | Total Sessions | Product-to-Cart Rate | Cart-to-Purchase Rate |
|---|---|---|---|
| Adwords | 150,115 | 49.9% | 0.0% |
| Email | 224,690 | 49.9% | 0.0% |
| Facebook | 50,146 | 50.2% | 0.0% |
| Organic | 24,994 | 50.1% | 0.0% |
| YouTube | 50,055 | 49.9% | 0.0% |
 
**The insight:** Near-identical rates across all five channels eliminate ad quality as the root cause. Anonymous users hit a mandatory registration wall at the exact moment of highest purchase intent. This is a platform-level architectural barrier — not a media planning problem.

**Why it matters:** Approximately **250,000 sessions per cycle** are abandoned at the product page. These users are already on the platform, already paid for. Any improvement here requires zero additional acquisition spend.

---

### Finding 2 — Same Audience, Every Channel: Budget Reallocation Won't Fix This

<img width="1384" height="583" alt="EDA 3" src="https://github.com/user-attachments/assets/1b8160af-91cb-49a8-9993-ecf1a6b5428a" />
<img width="1384" height="583" alt="EDA 2" src="https://github.com/user-attachments/assets/ee82561f-c05b-4055-9131-9d5cf622444f" />


Email dominates volume (224,690 sessions), followed by Adwords (150,115). All other channels contribute ~50K each. Despite this volume difference, every channel shows a near-identical user-type split: ~73% Anonymous / ~22% Registered Lead / ~5% Existing Buyer — with less than 0.2 percentage point variance across all five.
 
**The insight:** The platform attracts the same audience composition regardless of channel. Shifting budget from Email to Adwords or Facebook does not change the type of user arriving — and therefore does not change the conversion outcome.
 
**Why it matters:** This suggests that the root cause is structural — the fix likely resides in product and engineering rather than media planning. Email's position as highest-volume channel makes it the single largest immediate opportunity — improving the Anonymous conversion experience on Email-sourced sessions alone could impact 224K sessions per cycle.

---

### Finding 3 — $331K Revenue in Active Deterioration (and $226K More Approaching the Edge)

<img width="1382" height="784" alt="EDA 4" src="https://github.com/user-attachments/assets/969892f1-532c-45d1-8c2a-16a86eacd4af" />

The bubble map positions each segment across revenue (Y-axis), inactivity (X-axis), and user count (bubble size). Top-right = highest revenue, highest inactivity — the most financially dangerous quadrant.
 
| Segment | Unique Users | Total Revenue | % of Total Revenue | Avg Recency | Avg CLV | Status |
|---|---|---|---|---|---|---|
| At Risk | 2,171 | $245,441 | 22.1% | 248 days | $113 | 🔴 Deteriorating |
| Loyal Customers | 1,248 | $226,086 | 20.4% | 92 days | $181 | ⚠️ At threshold |
| Potential Loyalist | 2,866 | $204,951 | 18.5% | 36 days | $72 | ✅ Active — activation window open |
| Champions | 735 | $135,387 | 12.2% | 11 days | $184 | ✅ Healthiest |
| Cant Lose Them | 496 | $85,653 | 7.7% | 309 days | $173 | 🔴 Deteriorating |

**The insight:**

- At Risk and Cant Lose Them together contribute approximately **$331K (29.8% of total revenue)** despite showing prolonged inactivity patterns, making them the platform's most immediate retention priority.
- Loyal Customers remain active and contribute an additional **$226K (20.4%)**, but their purchase-gap behavior suggests a portion of the segment may require preventive engagement before transitioning into higher-risk inactivity patterns.
- Rather than interpreting this as guaranteed future revenue loss, the analysis highlights where retention monitoring and intervention efforts are likely to have the highest business relevance.

---

### Finding 4 — The Behavioral Clock: At Risk Customers Have Already Churned

<img width="1184" height="684" alt="EDA 5" src="https://github.com/user-attachments/assets/0ba7a4fb-9308-4c82-a501-240a3157d6d0" />

Average days between orders varies dramatically — and functions as a leading indicator of churn, not a lagging one.
 
| Segment | Avg Days Between Orders | vs. Champion Benchmark |
|---|---|---|
| **Champions** | 91.4 days | — Benchmark |
| Loyal Customers | 188.0 days | 2.1× |
| Cant Lose Them | 327.3 days | 3.6× |
| **At Risk** | 480.0 days | **5.3×** |
| Need Attention | 546.3 days | 6.0× |
| Hibernating | 601.8 days | 6.6× |
| About to Sleep | 659.6 days | 7.2× |
 
> **Note on long avg_gap figures:** Potential Loyalist (672 days), New Customers (708 days), and Promising (838 days) show extreme gaps because most users in these segments have only made one purchase. The gap calculation spans their entire account history — not a meaningful repeat cycle. For these cohorts, **recency is the operative signal** (Potential Loyalist: 36 days). The gap figures are measurement artifacts.
 
**The insight:** At Risk customers are not "buying less often" — at 480 days vs the 91-day Champions benchmark, they exhibit behavioral patterns consistent with advanced disengagement. They simply haven't been classified as lost yet. The difference between Champions and At Risk suggests a meaningful behavioral shift rather than a simple gradual decline in activity.
 
**Why it matters:** Interval data determines intervention timing across all phases. Loyal Customers should be contacted at day 150 — before the 188-day threshold, not after.

---

### Finding 5 — Category Affinity: The Personalization Map Already Exists in the Data

<img width="1475" height="1318" alt="EDA 6" src="https://github.com/user-attachments/assets/77e4a421-d787-426e-a927-65adbd8a91bf" />

Category affinity analysis reveals consistent purchasing patterns that differ significantly between premium and entry-level segments — and maps directly onto the personalization strategy in Section 8.
 
| Profile | Segments | Top Categories | Avg Item Price |
|---|---|---|---|
| **Premium** | Champions, Loyal, At Risk, Cant Lose Them | Jeans + Outerwear & Coats | $110–$184 |
| **Entry-level** | Potential Loyalist, Hibernating, New Customers | Intimates + Tops & Tees | $26–$48 |
 
**The insight:** At Risk customers were Jeans and Outerwear buyers before they became inactive. They are disengaged premium fashion buyers — not price-sensitive shoppers. A win-back email referencing their specific category ("Your favorite Jeans collection is waiting") is the right message, not a generic discount.
 
**Why it matters:** Precise sub-bucket targeting is possible without additional data collection. The personalization input already exists in purchase history — sub-buckets for At Risk: Jeans lovers · Fashion Hoodies lovers · Swim lovers.

---

### Finding 6 — Dataset Constraint: Low Frequency Is an Artifact

Even Champions average only 1.5 orders; Loyal Customers average 1.4. This is atypically low for fashion e-commerce — real-world Champions typically show 4–8+ orders per year.

**Why this matters:** This reflects a limitation of the synthetic TheLook dataset, not actual retention performance. To avoid amplifying this artifact, all financial projections in this analysis use AOV (not CLV) as the multiplier. RFM scoring remains valid as a relative ranking tool within this dataset, but absolute frequency thresholds would need recalibration for real business data.

---

## 7. Dashboard

Designed as a single narrative arc — not a daily monitoring tool, but a self-contained story flowing from problem identification to recommendation foundations.

🔗 [Open Dashboard in Looker Studio →](https://datastudio.google.com/reporting/fe05a7e8-44a2-4b7b-b4dd-2d945c90b409)

<img width="4375" height="3125" alt="TheLook_E-commerce__Retention_ _Acquisition_Analysis (2)_page-0001" src="https://github.com/user-attachments/assets/3995ce16-c71b-4982-95d5-7e8edb77bb7f" />


**Layout:**
- **Top row** — 5 KPI scorecards: immediate executive summary before any chart is read
- **Upper section** — Acquisition story: funnel drop-off per channel (left) + session volume by user type (right)
- **Bottom left** — RFM Segment Bubble Map: revenue-at-risk in one view
- **Bottom right** — Purchase interval per segment (center) + Category affinity heatmap (right)

---

## 8. Insights & Strategic Recommendations
> *The recommendations below are based on observed behavioral patterns within the available dataset. Revenue figures represent historical contribution, not guaranteed future loss or recovery projections. Where future outcomes are discussed, they are framed as directional opportunities requiring validation through experimentation.*

### 8.1 Key Findings Summary

**Objective 1 — Acquisition:**
1. **Structural acquisition barrier:** ~250,000 sessions per cycle (per dataset) are lost between product view and purchase completion. The near-identical funnel pattern across channels strongly suggests a platform-level friction point — likely related to registration or checkout access requirements — rather than channel quality itself.
2. **Channel-agnostic drop-off:** The ~50% product-to-cart rate and 0% cart-to-purchase rate are identical across all five channels, indicating the issue is likely platform-wide and cannot be solved by reallocating marketing budget.

**Objective 2 — Retention:**

3. **Revenue concentration risk:** The top 4 segments account for 73% of total revenue. At Risk and Cant Lose Them together contribute $331K (29.8%) from segments in active deterioration, while Loyal Customers ($226K) are approaching behavioral thresholds associated with higher inactivity risk.
4. **Behavioral churn signal:** At Risk customers are purchasing at 5× the interval of Champions (480 vs 91 days) — suggesting that spontaneous re-engagement becomes increasingly unlikely without intervention.
5. **Untapped activation window:** Potential Loyalist (2,866 users, $205K revenue) are largely one-time buyers with a recency of just 36 days — creating a meaningful opportunity to encourage second-purchase behavior and future customer value growth.
6. **Category anchor:** Jeans consistently appears as the top revenue-driving category across premium segments (more than 10% revenue constribution per each premium segment) — consistently the #1 revenue driver for Champions, Loyal Customers, At Risk, and Cant Lose Them alike, enabling precise personalization without additional data collection.

---

### 8.2 What We Know About Potential Downside

Without intervention, the following revenue is associated with segments already showing deterioration:

| Segment | Revenue (12 mo) | Current Status |
|---------|-----------------|----------------|
| At Risk | $245,441 | Already inactive (248 days) |
| Cant Lose Them | $85,653 | Already inactive (309 days) |

Loyal Customers ($226,086) remain active but show early warning signs (approaching 188-day purchase gap). The proportion that would deteriorate without intervention cannot be accurately predicted from available data.

**What this means:** The $331K from already-deteriorating segments represents revenue that is unlikely to recover passively. For Loyal Customers, the appropriate next step is preventive monitoring — not assuming they will churn.

---

### 8.3 Pillar 1 — Acquisition Optimization (Anonymous Users)
 
**Problem:** Funnel analysis reveals two separate conversion barriers among Anonymous users:

- Approximately half of sessions never progress from product view to cart, suggesting a persuasion or purchase-intent issue.
- Sessions that do reach cart cannot complete checkout due to the mandatory registration requirement, resulting in a 0% cart-to-purchase rate.

Together, these drop-offs represent a significant loss of already-acquired traffic.
 
**Approach: Zero Additional Marketing Spend** — Improve conversion efficiency from existing traffic before increasing acquisition spend. Experiments are sequenced to isolate the effect of persuasion improvements versus checkout-friction reduction.
 
**Phase 1 — Product Page Optimization (Persuasion)**
 
| Element | Detail |
|---|---|
| Hypothesis | Adding social proof elements may improve product-to-cart progression |
| Design | A/B test on product page UI — Group A (standard layout) vs Group B (social proof + ratings visibility) |
| Randomization unit | session_id |
| Primary metric | Product-to-cart rate |
| Guardrail metric | Page load time must not increase materially |
| Success threshold | Positive statistically significant lift vs control |
| Potential implication (to be measured) | Higher downstream checkout opportunities if more users progress into cart |
| Exit criteria | If lift remains negligible after test period, prioritize friction-reduction experiments instead |
 
**Phase 2 — Cart Friction Reduction (One-Tap Sign-In)**
 
| Element | Detail |
|---|---|
| Hypothesis | Reducing registration friction may improve cart-to-registration progression |
| Design | A/B Test — Group A (standard registration flow) vs Group B (One-Tap Google Sign-In) |
| Randomization unit | session_id |
| Primary metric | Cart-to-registered-lead rate |
| Guardrail metric | Registration page bounce rate must not increase |
| Benchmark reference | Simplified checkout flows are commonly associated with improved conversion completion in e-commerce UX studies |
| Success threshold | Measurable lift relative to control group |
| Exit criteria | If impact remains limited, the barrier may require broader checkout-flow redesign |
 
---

### 8.4 Pillar 2 — Retention: Phase 1 (Reactive Win-back)
 
**Problem:** $331K in revenue (29.8%) sits within two deteriorating segments that have stopped purchasing but whose category preferences and contact information are known.
 
**Why Email?** Email accounts for 44.8% of all registered user sessions (81,421 of 181,741 combined sessions). Near-zero variable cost — leverages an existing database with no incremental acquisition spend.
 
**Why sequential, not parallel?** Running At Risk and Cant Lose Them simultaneously would split team focus, complicate measurement, and reduce the learnings transferable from one campaign to the next. At Risk goes first because its revenue pool is nearly 3× larger.
 
---

#### Phase 1A — At Risk Win-back (Weeks 1–3)
 
**Rationale for priority:** Largest single revenue-at-risk pool ($245K, 22.1% of total). The segment size is large enough to support an initial controlled experiment and directional measurement.

| Element | Detail |
|---|---|
| Strategy | Stratified A/B Test based on historical category affinity |
| Sub-buckets | Jeans lovers · Fashion Hoodies lovers · Swim lovers |
| Randomization | Independent 50/50 split within each subgroup |
| Group A (Control) | Generic re-engagement email |
| Group B (Treatment) | Personalized category-based re-engagement email |
| Conversion window | 30 days |
| Primary metric | Re-activation rate |
| Guardrail metric | Unsubscribe rate |
| Success threshold | Positive lift relative to control group |
| AOV reference | $105.24 (calculated from segment transaction data) |
| Revenue implication | Due to the segment's size (2,171 users) and existing purchase history, even modest improvements in re-activation rate may create meaningful incremental revenue without additional acquisition spend. |
| Exit criteria | If lift remains negligible, alternative channels or incentive structures should be evaluated |

---

#### Phase 1B — Cant Lose Them Win-back (Weeks 3–6, after Phase 1A results are measured)
 
**Rationale for sequencing after At Risk:** Although the revenue pool is smaller ($85K, 7.7%), this segment shows one of the platform's highest average transaction values ($152.89) and strong affinity toward premium categories such as Outerwear & Coats and Jeans. Results from Phase 1A serve as a directional learning input before expanding personalization efforts into a smaller but higher-value cohort.
 
**Why this segment still warrants intervention despite smaller population size:** The segment combines prolonged inactivity with relatively high AOV and CLV, suggesting that even limited re-activation improvements may produce meaningful business impact on a per-customer basis.
 
| Element | Detail |
|---|---|
| Strategy | Category-personalized win-back email |
| Focus categories | Jeans + Outerwear & Coats |
| Incentive approach | Test different re-engagement approaches (e.g., urgency framing, category personalization, or selective incentives) while monitoring margin impact |
| Group A (Control) | Generic re-engagement email |
| Group B (Treatment) | Personalized category-focused re-engagement email |
| Conversion window | 30 days |
| Primary metric | Re-activation rate |
| Guardrail metric | Net margin after discount must remain positive |
| AOV reference | $152.89 (calculated from segment transaction data) |
| Strategic implication | Despite smaller population size, the segment's higher AOV increases the value of each successful re-activation |
| Exit criteria | If net margin after campaign goes negative, reduce incentive or pause campaign |
 
---

### 8.5 Pillar 3 — Retention: Phase 2 (Preventive & Growth)

> Phase 2 runs in parallel after Phase 1A is launched. These are automated triggers — near-zero ongoing effort after initial setup.
>
> These interventions prioritize low-cost CRM automation as an initial experimentation layer. Additional channels (e.g., push notifications, onsite personalization, or paid retargeting) may be evaluated after baseline effectiveness is established.

---

#### Phase 2A — Loyal Customers: Pre-gap Triggered Email (Month 2, ongoing)
 
**Rationale:** This segment remains active (recency 92 days) and contributes $226K (20.4% of total revenue). Their average purchase gap is 188 days, making day 150 a potential intervention point to test whether early re-engagement can influence purchase behavior before the segment's historical average repurchase interval is reached.
 
| Element | Detail |
|---|---|
| Trigger | Automated email at day 150 post-last-purchase (38 days before the 188-day avg threshold) |
| Content | New arrivals in Jeans or Outerwear — initial test avoids discounting to evaluate whether reminder-based re-engagement alone influences purchase timing |
| Design | A/B test: Group A (no trigger) vs Group B (receives day-150 email) |
| Primary metric | Purchase rate before day 188 |
| Guardrail metric | Unsubscribe rate |
| Success threshold | Higher purchase rate in treatment group vs control |
| AOV reference | $128.88 (calculated from segment transaction data) |
| Revenue implication | This is a preventive intervention — the goal is to learn whether early re-engagement can influence purchase timing. Any reduction in revenue loss would need to be measured post-experiment. |
| Ongoing effort | Near-zero after initial automation setup |
 
> *Note: "Revenue defended" is not projected here because the natural churn rate for this segment without intervention cannot be determined from available data. The experiment is designed to measure whether the trigger has any detectable effect on purchase timing.*

---
 
#### Phase 2B — Potential Loyalist: Second Purchase Activation (Month 2–3)
 
**Rationale:** The 672-day avg_gap for this segment is a measurement artifact — it reflects the gap calculation across a multi-year dataset for users who have largely made only one purchase. The operative signal is their **recency of 36 days**. The segment size (2,866 users, $205K revenue) makes it a meaningful population for testing second-purchase activation strategies.
 
| Element | Detail |
|---|---|
| Trigger | Automated email at day 30 post-first-purchase |
| Content | Second-purchase voucher, personalized to first-purchase category (Intimates / Sleep & Lounge / Tops & Tees) |
| Design | This experiment primarily evaluates timing effectiveness rather than absolute incremental lift, since both groups receive an intervention. |
| Primary metric | Second purchase rate within 60 days |
| Guardrail metric | Voucher redemption rate |
| Success threshold | Positive lift in second purchase rate vs control (or between timing groups) |
| AOV reference | $71.39 (calculated from segment transaction data) |
| Revenue implication | This segment represents one-time buyers with recent activity. Even modest improvements in second purchase conversion could meaningfully affect long-term customer value trajectories. |
| Ongoing effort | Near-zero after automation setup |

> *Note on benchmarks: Industry second-purchase rates for one-time buyers vary widely (5-15% depending on category and incentive). Actual lift will be measured from the A/B test.*

---
 
#### Phase 2C — Champions: Value Maximization (Month 2–3, parallel)
 
**Rationale:** Champions are the healthiest segment — no rescue required. This intervention is opportunistic: test whether cross-sell recommendations can increase AOV without negatively affecting cart abandonment.

| Element | Detail |
|---|---|
| Strategy | Automated cross-sell recommendations at checkout |
| Recommendation logic | Jeans purchasers shown Outerwear & Coats / Sweaters (based on observed category affinity in this segment) |
| Design | A/B test — Group A (standard cart) vs Group B (cart + cross-sell) |
| Primary metric | Average Order Value (AOV) |
| Guardrail metric | Cart abandonment rate |
| Success threshold | Higher AOV in treatment group without material increase in cart abandonment |
| AOV reference | $121.94 (calculated from segment transaction data) |
| Revenue implication | If successful, this could increase per-transaction value for the platform's healthiest segment without additional acquisition cost. |
| Exit criteria | If cart abandonment increases meaningfully in treatment group, reduce recommendation prominence or pause |

> *Note: No AOV lift is projected here because the effect size cannot be known before the experiment. The test is designed to measure whether cross-sell recommendations have a detectable impact on transaction value.*

---
 
### 8.6 What We Won't Do (and Why)
 
**Hibernating & About to Sleep are not active win-back targets.** AOV of $42–$44 and CLV of ~$38, combined with purchase gaps exceeding 600 days, make the ROI case difficult to justify against higher-value opportunities. These segments are placed into an **automated low-touch email sequence every 3 months** — preserving optionality at negligible cost without committing resources better allocated elsewhere.
 
---
 
### 8.7 Exit Criteria
 
A recommendation without exit criteria is a commitment without conditions.
 
| Phase | Continue if | Adjust if | Stop if |
|---|---|---|---|
| At Risk win-back | Meaningful positive lift vs control | Positive but modest lift | No detectable lift after test window |
| Cant Lose Them | Margin remains positive | Margin compression observed | Margin turns consistently negative |
| Loyal Customers trigger | Earlier repurchase behavior improves | Engagement low but directional improvement exists | Unsubscribe or disengagement materially increases |
| Potential Loyalist trigger | Second purchase conversion improves vs baseline | Timing effect unclear | No meaningful behavioral difference observed |
| Champions cross-sell | AOV improves without material abandonment increase | Slight abandonment increase observed | Abandonment materially worsens |
| Acquisition Phase 1 | Product-to-cart conversion improves | Positive but inconclusive result | No detectable conversion improvement |
 
---
 
## Limitations & Methodology Notes
 
1. **Synthetic dataset:** TheLook is a generated dataset. `cart_to_purchase = 0%` for Anonymous and uniformly low `avg_orders` are by-design artifacts, not real business signals. Findings are directionally valid — not operationally prescriptive without real-data calibration.
2. **RFM trailing window vs. full history:** RFM scoring uses a 1-year trailing window. Large avg_gap values in At Risk (480 days) draw on multi-year purchase history beyond this window — inactivity severity should be validated against real business baselines before operational use.
3. **Potential Loyalist avg_gap:** The 672-day figure is a measurement artifact for largely single-purchase users. Recency (36 days) is the operative signal for this segment.
4. **AOV over CLV:** All financial projections use AOV as the multiplier — a deliberate choice to avoid amplifying the low-frequency artifact in this dataset. Champions average only 1.5 orders; real-world Champions would show 4–8+. CLV projections would silently overstate returns.
5. **A/B tests are forward-looking:** Historical data cannot be retroactively randomized. All experiment designs are recommendations to execute going forward.
6. **RFM as a relative ranking tool:** Segmentation remains valid for comparing value between segments within this dataset. Absolute frequency thresholds require recalibration against real business data before deployment.

---

*Dataset: [TheLook Ecommerce — Google BigQuery Public Data](https://console.cloud.google.com/marketplace/product/bigquery-public-data/thelook-ecommerce)*

*SQL: [SQL for Data Cleaning & Feature Engineering](https://github.com/nafidza/TheLook-Project/blob/main/sql-queries.sql)*

*EDA: [Python for EDA — Google Colab](https://colab.research.google.com/drive/1YXuW8Oy3rV-GknxEYwetqXd3Xl7fZ15n?usp=sharing)*

*Dashboard: [Looker Studio](https://datastudio.google.com/reporting/fe05a7e8-44a2-4b7b-b4dd-2d945c90b409)*
