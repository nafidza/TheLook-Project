\sql

-- User Cleaning --------------------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.users_cleaned` AS
SELECT 
    CAST(id AS INT64) AS user_id,
    CAST(first_name AS STRING) AS first_name,
    CAST(last_name AS STRING) AS last_name,
    CAST(email AS STRING) AS email,
    CAST(age AS INT64) AS age,
    CAST(gender AS STRING) AS gender,
    CAST(state AS STRING) AS state,
    CAST(street_address AS STRING) AS street_address,
    CAST(postal_code AS STRING) AS postal_code,
    CAST(city AS STRING) AS city,
    CAST(country AS STRING) AS country,
    CAST(latitude AS FLOAT64) AS latitude,
    CAST(longitude AS FLOAT64) AS longitude,
    CAST(traffic_source AS STRING) AS traffic_source,
    CAST(created_at AS TIMESTAMP) AS created_at,
    -- Audit Column
    CASE 
      WHEN id IS NOT NULL AND created_at IS NOT NULL THEN TRUE 
      ELSE FALSE 
    END AS is_clean
FROM `bigquery-public-data.thelook_ecommerce.users`
WHERE id IS NOT NULL;


-- Order Cleaning ------------------------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned` AS
-- Langkah awal: Ambil data dari source dan cek keberadaan user di master user
WITH order_with_user_check AS (
  SELECT 
    o.*,
    u.user_id AS master_user_id -- Jika NULL, berarti user tidak ada di master user
  FROM `bigquery-public-data.thelook_ecommerce.orders` AS o
  LEFT JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.users_cleaned` AS u 
    ON o.user_id = u.user_id
)
SELECT 
    CAST(order_id AS INT64) AS order_id,
    CAST(user_id AS INT64) AS user_id,
    CAST(status AS STRING) AS status,
    CAST(gender AS STRING) AS gender,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(returned_at AS TIMESTAMP) AS returned_at,
    CAST(shipped_at AS TIMESTAMP) AS shipped_at,
    CAST(delivered_at AS TIMESTAMP) AS delivered_at,
    CAST(num_of_item AS INT64) AS num_of_item,
    CASE 
      WHEN order_id IS NOT NULL 
           AND user_id IS NOT NULL 
           AND master_user_id IS NOT NULL 
           AND created_at IS NOT NULL
           AND (shipped_at IS NULL OR shipped_at >= created_at)
           AND (delivered_at IS NULL OR delivered_at >= shipped_at)
           AND (returned_at IS NULL OR returned_at >= delivered_at)
      THEN TRUE 
      ELSE FALSE 
    END AS is_clean
FROM order_with_user_check
WHERE order_id IS NOT NULL;


-- Order Item Clean ------------------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.order_items_cleaned` AS
WITH validation_check AS (
  SELECT 
    oi.*,
    oc.order_id AS master_order_id,
    p.id AS master_product_id
  FROM `bigquery-public-data.thelook_ecommerce.order_items` AS oi
  LEFT JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned` AS oc 
    ON oi.order_id = oc.order_id
  LEFT JOIN `bigquery-public-data.thelook_ecommerce.products` AS p 
    ON oi.product_id = p.id
)
SELECT 
    CAST(id AS INT64) AS item_id,
    CAST(order_id AS INT64) AS order_id,
    CAST(user_id AS INT64) AS user_id,
    CAST(product_id AS INT64) AS product_id,
    CAST(inventory_item_id AS INT64) AS inventory_item_id,
    CAST(status AS STRING) AS status,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(shipped_at AS TIMESTAMP) AS shipped_at,
    CAST(delivered_at AS TIMESTAMP) AS delivered_at,
    CAST(returned_at AS TIMESTAMP) AS returned_at,
    CAST(sale_price AS FLOAT64) AS sale_price,
    CASE 
      WHEN id IS NOT NULL 
           AND sale_price > 0 
           AND master_order_id IS NOT NULL
           AND master_product_id IS NOT NULL
           AND created_at IS NOT NULL
      THEN TRUE 
      ELSE FALSE 
    END AS is_clean
FROM validation_check
WHERE id IS NOT NULL;


-- Events Cleaned --------------------------------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.events_cleaned` AS
WITH deduplicated_events AS (
  SELECT 
    *,
    ROW_NUMBER() OVER (
      PARTITION BY session_id, user_id, sequence_number 
      ORDER BY created_at ASC, id ASC
    ) as row_num
  FROM `bigquery-public-data.thelook_ecommerce.events`
),
joined_events AS (
  SELECT 
    e.*,
    u.user_id AS master_user_id
  FROM deduplicated_events AS e
  LEFT JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.users_cleaned` AS u 
    ON e.user_id = u.user_id
  WHERE e.row_num = 1
)
SELECT 
    CAST(id AS INT64) AS event_id,
    CAST(user_id AS INT64) AS user_id,
    CAST(sequence_number AS INT64) AS sequence_number,
    CAST(session_id AS STRING) AS session_id,
    CAST(created_at AS TIMESTAMP) AS created_at,
    CAST(ip_address AS STRING) AS ip_address,
    CAST(city AS STRING) AS city,
    CAST(state AS STRING) AS state,
    CAST(postal_code AS STRING) AS postal_code,
    CAST(browser AS STRING) AS browser,
    COALESCE(CAST(traffic_source AS STRING), 'Other') AS traffic_source,
    CAST(uri AS STRING) AS uri,
    CAST(event_type AS STRING) AS event_type,
    CASE WHEN user_id IS NULL THEN 'Anonymous' ELSE 'Known' END AS user_behavior_type,
    CASE 
      WHEN id IS NOT NULL 
           AND session_id IS NOT NULL 
           AND event_type IS NOT NULL 
           AND uri IS NOT NULL
           AND (
             user_id IS NULL OR (user_id IS NOT NULL AND master_user_id IS NOT NULL)
           )
      THEN TRUE 
      ELSE FALSE 
    END AS is_clean
FROM joined_events
WHERE id IS NOT NULL;

-- Product Cleaned-----------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.products_cleaned` AS
WITH ranked_products AS (
  SELECT 
    id AS product_id,
    cost,
    -- Merapikan teks kategori dan department agar seragam (huruf kecil/kapital tidak berantakan)
    TRIM(category) AS category,
    TRIM(name) AS product_name,
    TRIM(brand) AS brand,
    retail_price,
    TRIM(department) AS department,
    sku,
    distribution_center_id,
    -- Mengidentifikasi duplikat berdasarkan product_id
    ROW_NUMBER() OVER (PARTITION BY id ORDER BY cost DESC) AS rn
  FROM `bigquery-public-data.thelook_ecommerce.products` -- sesuaikan dengan nama tabel mentahmu
  WHERE id IS NOT NULL 
    AND category IS NOT NULL 
    AND department IS NOT NULL
    AND retail_price >= 0
    AND cost >= 0
)
SELECT 
  product_id,
  cost,
  category,
  product_name,
  brand,
  retail_price,
  department,
  sku,
  distribution_center_id
FROM ranked_products
WHERE rn = 1; -- Hanya mengambil 1 data unik, duplikat otomatis terbuang


-- RFM ANALYSIS -------------------------------------------

-- 1. determining today's date 
SELECT
    MIN(DATE(created_at)) AS min_order_date,
    MAX(DATE(created_at)) AS max_order_date
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned`
WHERE is_clean IS TRUE
  AND status   = 'Complete';
-- max date 14-05-2026, so today = max+1


-- 2. create rfm database (1 year)
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_base` AS
WITH ltm_orders AS (
  SELECT 
    user_id,
    order_id,
    created_at
  FROM `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned`
  WHERE is_clean IS TRUE 
    AND status = 'Complete'
    AND created_at >= '2025-05-15' 
)
SELECT 
    o.user_id,
    DATE_DIFF(
        DATE('2026-05-15'),
        DATE(MAX(o.created_at)),
        DAY
    ) AS recency,
    COUNT(DISTINCT o.order_id) AS frequency,
    SUM(oi.sale_price) AS monetary
FROM ltm_orders o
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.order_items_cleaned` oi 
  ON o.order_id = oi.order_id
WHERE oi.is_clean IS TRUE
   AND oi.status   = 'Complete'
GROUP BY 1;

-- 3. Create Segment for Each Customer--------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores` AS
WITH rfm_base AS (
    -- Tahap 1: Ambil data dasar RFM dari tabel yang kita buat sebelumnya
    SELECT 
        user_id,
        recency,
        frequency,
        monetary,
        -- Recency: Semakin KECIL hari, semakin BAIK (skor 5)
        -- Maka kita urutkan DESC agar nilai terkecil (terbaru) dapat NTILE 1, lalu kita balik
        NTILE(5) OVER (ORDER BY recency DESC) AS r_score,
        
        -- Frequency: Semakin BESAR kali, semakin BAIK (skor 5)
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        
        -- Monetary: Semakin BESAR nilai, semakin BAIK (skor 5)
        NTILE(5) OVER (ORDER BY monetary ASC) AS m_score
    FROM `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_base`
),
scoring_base AS (
  SELECT 
      *,
      -- Membuat RFM String untuk memudahkan segmentasi (Contoh: "554")
      CONCAT(CAST(r_score AS STRING), CAST(f_score AS STRING), CAST(m_score AS STRING)) AS rfm_cell,
      ROUND((f_score + m_score) / 2.0, 1) AS avg_fm
  FROM rfm_base
)
SELECT 
    *,
    CASE 
        -- CHAMPIONS: Baru beli, sering beli, dan belanja banyak
        WHEN r_score = 5 AND avg_fm >= 4 THEN 'Champions'
        -- LOYAL CUSTOMERS: Belanja rutin, tidak harus hari ini tapi masih baru
        WHEN r_score >= 3 AND avg_fm >= 4 THEN 'Loyal Customers'
        -- POTENTIAL LOYALIST: Pembeli baru tapi frekuensi/monetary lumayan
        WHEN r_score >= 4 AND avg_fm >= 2 THEN 'Potential Loyalist'
        -- NEW CUSTOMERS: Skor Recency tinggi, tapi Freq/Mon rendah (karena baru sekali)
        WHEN r_score = 5 AND avg_fm < 2 THEN 'New Customers'
        -- PROMISING: Baru beli tapi belum banyak belanja
        WHEN r_score = 4 AND avg_fm < 2 THEN 'Promising'
        -- NEED ATTENTION: Di tengah-tengah, mulai agak lama tidak belanja
        WHEN r_score = 3 AND avg_fm >= 3 THEN 'Need Attention'
        -- ABOUT TO SLEEP: Recency mulai rendah, Freq/Mon juga rendah
        WHEN r_score = 3 AND avg_fm < 3 THEN 'About to Sleep'
        -- CAN'T LOSE THEM: Dulu pembeli besar, sekarang sudah lama tidak ada kabar
        WHEN r_score <= 1 AND avg_fm >= 4 THEN 'Cant Lose Them'
        -- AT RISK: Dulu sering belanja banyak, tapi sudah lama tidak kembali
        WHEN r_score <= 2 AND avg_fm >= 3 THEN 'At Risk'
        -- HIBERNATING: Jarang beli, belanja sedikit, dan sudah lama sekali
        WHEN r_score <= 2 AND avg_fm < 3 THEN 'Hibernating'
        ELSE 'Lost/Others'
    END AS segment
FROM scoring_base
ORDER BY r_score DESC, avg_fm DESC;


-- 4. Distribution of Customers per Segment
SELECT
    segment,
    COUNT(*)                                           AS jumlah_customer,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 1) AS pct_customer,
    ROUND(AVG(recency),   1)                           AS avg_recency_hari,
    ROUND(AVG(frequency), 1)                           AS avg_frequency,
    ROUND(AVG(monetary),  0)                           AS avg_monetary
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores`
GROUP BY segment
ORDER BY
    CASE segment
        WHEN 'Champions'        THEN 1
        WHEN 'Loyal Customers'  THEN 2
        WHEN 'Potential Loyalist' THEN 3
        WHEN 'New Customers'    THEN 4
        WHEN 'Promising'        THEN 5
        WHEN 'Need Attention'   THEN 6
        WHEN 'About to Sleep'   THEN 7
        WHEN 'Cant Lose Them'   THEN 8
        WHEN 'At Risk'          THEN 9
        WHEN 'Hibernating'      THEN 10
        ELSE 11
    END;




-- Customer Conversion Rate Funnel-----------------------
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.funnel_base_summary` AS
WITH user_segments AS (
  SELECT 
    user_id, 
    segment,
    CASE WHEN frequency > 1 THEN 'Repeat Customer' ELSE 'New Customer' END AS customer_type
  FROM `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores`
),
event_funnel AS (
  SELECT 
    e.session_id,
    e.traffic_source,
    COALESCE(u.segment, 'Non-Purchaser/Anonymous') AS rfm_segment,
    CASE 
            WHEN e.user_id IS NULL THEN 'Pure Guest (Anonymous)'
            WHEN e.user_id IS NOT NULL AND u.user_id IS NULL THEN 'Registered Lead (Has Account, No Purchase)'
            ELSE 'Existing Customer (Buyer)'
    END AS user_status,
    MAX(CASE WHEN e.event_type = 'home' THEN 1 ELSE 0 END) AS has_home,
    MAX(CASE WHEN e.event_type = 'product' THEN 1 ELSE 0 END) AS has_product,
    MAX(CASE WHEN e.event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
    MAX(CASE WHEN e.event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
  FROM `portfolio-analytics-nafidza.thelook_clean_analysis.events_cleaned` e
  LEFT JOIN user_segments u ON e.user_id = u.user_id
  WHERE e.is_clean IS TRUE
  GROUP BY 1, 2, 3, 4
)
SELECT 
  traffic_source,
  rfm_segment,
  user_status,
  COUNT(session_id) AS total_sessions,
  SUM(has_home) AS total_home,
  SUM(has_product) AS total_product,
  SUM(has_cart) AS total_cart,
  SUM(has_purchase) AS total_purchase
FROM event_funnel
GROUP BY 1, 2, 3;


-- CR for Each Traffic Source and User_Type -------------------------
SELECT
    traffic_source,
    CASE 
        WHEN user_status = 'Pure Guest (Anonymous)' THEN 'Anonymous'
        WHEN user_status = 'Registered Lead (Has Account, No Purchase)' THEN 'Registered Lead'
        ELSE 'Existing Buyer'
    END AS user_type,
    SUM(total_sessions) AS total_sessions,
    ROUND(SAFE_DIVIDE(SUM(total_home),     SUM(total_sessions)) * 100, 1) AS pct_reached_home,
    ROUND(SAFE_DIVIDE(SUM(total_product),  SUM(total_sessions)) * 100, 1) AS pct_reached_product,
    ROUND(SAFE_DIVIDE(SUM(total_cart),     SUM(total_product))  * 100, 1) AS product_to_cart_pct,
    ROUND(SAFE_DIVIDE(SUM(total_purchase), SUM(total_cart))     * 100, 1) AS cart_to_purchase_pct,
    ROUND(SAFE_DIVIDE(SUM(total_purchase), SUM(total_sessions)) * 100, 1) AS overall_cvr
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.funnel_base_summary`
GROUP BY 1, 2
ORDER BY traffic_source, total_sessions DESC;


-- RFM Segment Behaviour ------------------

-- 1. when
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.order_gap_summary` AS
WITH order_gaps AS (
    SELECT
        o.user_id,
        r.segment,
        o.created_at,
        LAG(o.created_at) OVER (
            PARTITION BY o.user_id ORDER BY o.created_at
        ) AS prev_order_at
    FROM `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned` AS o
    JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores` AS r
        ON o.user_id = r.user_id
    WHERE o.is_clean IS TRUE
      AND o.status   = 'Complete'
)
SELECT
    segment,
    COUNT(DISTINCT user_id) AS unique_users,
    ROUND(AVG(DATE_DIFF(DATE(created_at), DATE(prev_order_at), DAY)), 1) AS avg_days_between_orders,
    ROUND(MIN(DATE_DIFF(DATE(created_at), DATE(prev_order_at), DAY)), 1) AS min_gap,
    ROUND(MAX(DATE_DIFF(DATE(created_at), DATE(prev_order_at), DAY)), 1) AS max_gap
FROM order_gaps
WHERE prev_order_at IS NOT NULL   -- hanya repeat order
GROUP BY segment
ORDER BY avg_days_between_orders;

-- 2. what product
CREATE OR REPLACE TABLE `portfolio-analytics-nafidza.thelook_clean_analysis.top_product_summary` AS
SELECT
    r.segment,
    p.category,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.sale_price), 0) AS total_revenue,
    ROUND(AVG(oi.sale_price), 0) AS avg_item_price,
    ROUND(SAFE_DIVIDE(
        SUM(oi.sale_price),
        SUM(SUM(oi.sale_price)) OVER (PARTITION BY r.segment)
    ) * 100, 1) AS pct_of_segment_revenue
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.order_items_cleaned` AS oi
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned`      AS o
    ON oi.order_id = o.order_id
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores`          AS r
    ON o.user_id   = r.user_id
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.products_cleaned`    AS p
    ON oi.product_id = p.product_id
WHERE oi.is_clean IS TRUE
  AND oi.status   = 'Complete'
  AND o.is_clean  IS TRUE
  AND o.status    = 'Complete'
GROUP BY r.segment, p.category
QUALIFY RANK() OVER (PARTITION BY r.segment ORDER BY total_orders DESC) <= 3
ORDER BY r.segment, total_orders DESC;

-- 3. how much
SELECT
    segment,
    COUNT(DISTINCT user_id) AS unique_users,
    ROUND(SUM(monetary), 0) AS total_revenue,
    ROUND(AVG(monetary), 0) AS avg_clv,
    ROUND(SAFE_DIVIDE(
        SUM(monetary),
        SUM(SUM(monetary)) OVER ()
    ) * 100, 1) AS pct_total_revenue,
    ROUND(AVG(frequency), 1) AS avg_orders,
    ROUND(AVG(recency), 0) AS avg_recency_days
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores`
GROUP BY segment
ORDER BY total_revenue DESC;



-- AOV per segment (used for financial projection)
SELECT
    r.segment,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    ROUND(SUM(oi.sale_price), 0) AS total_revenue,
    ROUND(SAFE_DIVIDE(
        SUM(oi.sale_price),
        COUNT(DISTINCT oi.order_id)
    ), 2) AS avg_order_value
FROM `portfolio-analytics-nafidza.thelook_clean_analysis.order_items_cleaned` AS oi
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.orders_cleaned`      AS o  ON oi.order_id = o.order_id
JOIN `portfolio-analytics-nafidza.thelook_clean_analysis.rfm_scores`          AS r  ON o.user_id   = r.user_id
WHERE oi.is_clean IS TRUE AND oi.status = 'Complete'
  AND o.is_clean  IS TRUE AND o.status  = 'Complete'
GROUP BY r.segment
ORDER BY total_revenue DESC;

\\
