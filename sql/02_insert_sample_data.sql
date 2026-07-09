USE Insurance_Reconcile_Portfolio;
GO

/*============================================================
02_generate_sample_data.sql

Purpose:
Generate a richer simulated dataset for the Insurance Accounting
Reconciliation portfolio.

Output:
- m_fee_type
- t_core_gl_detail: 10,000 Core GL detail rows
- t_s3_interface_file: S3 summarized interface rows
============================================================*/

SET NOCOUNT ON;

DELETE FROM t_s3_interface_file;
DELETE FROM t_core_gl_detail;
DELETE FROM m_fee_type;

INSERT INTO m_fee_type
(
    fee_type,
    fee_type_name,
    source_code,
    generated_by,
    default_fund
)
VALUES
('RECEIPT_COLLECTION',      'Receipt Collection',                'CASH',       'Inforce',        'NPF0Z'),
('PREMIUM_APPLICATION',     'Premium Application',               'ARAP',       'Process Fund',   'UL-G'),
('TRANSFER_NPF_TO_ULG',     'Transfer NPF to UL General',        'NON_UNIT',   'Process Fund',   'NPF0Z'),
('IMPLICIT_EXPENSE',        'Implicit Expense',                  'NON_UNIT',   'Process Fund',   'UL-G'),
('COMMISSION',              'Commission',                        'COMMISSION', 'Process Fund',   'UL-G'),
('NET_INVESTMENT_PREMIUM',  'Net Investment Premium',            'UNIT',       'Process Fund',   'UL-I'),
('TRANSFER_ULG_TO_ULI',     'Transfer UL General to UL Invest',  'UNIT',       'Process Fund',   'UL-G'),
('POLICY_FEE',              'Policy Fee',                        'NON_UNIT',   'Process Charge', 'UL-I'),
('WD_POLICY_FEE',           'Withdraw Policy Fee',               'UNIT',       'Process Charge', 'UL-I'),
('INSURANCE_CHARGE',        'Insurance Charge',                  'NON_UNIT',   'Process Charge', 'UL-I'),
('WD_INSURANCE_CHARGE',     'Withdraw Insurance Charge',         'UNIT',       'Process Charge', 'UL-I');

DROP TABLE IF EXISTS #fee_config;
CREATE TABLE #fee_config
(
    fee_type VARCHAR(50),
    source_code VARCHAR(30),
    fund_code VARCHAR(30),
    debit_account VARCHAR(30),
    credit_account VARCHAR(30),
    fee_weight INT
);

INSERT INTO #fee_config
VALUES
('RECEIPT_COLLECTION',      'CASH',       'NPF0Z', '11210101', '33880101', 14),
('PREMIUM_APPLICATION',     'ARAP',       'UL-G',  '33880101', '33728101', 16),
('TRANSFER_NPF_TO_ULG',     'NON_UNIT',   'NPF0Z', '33728102', '33728202', 8),
('IMPLICIT_EXPENSE',        'NON_UNIT',   'UL-G',  '64110101', '33728202', 10),
('COMMISSION',              'COMMISSION', 'UL-G',  '64210101', '33180101', 8),
('NET_INVESTMENT_PREMIUM',  'UNIT',       'UL-I',  '33728202', '33728203', 14),
('TRANSFER_ULG_TO_ULI',     'UNIT',       'UL-G',  '33728202', '33728203', 8),
('POLICY_FEE',              'NON_UNIT',   'UL-I',  '33728203', '51112001', 8),
('WD_POLICY_FEE',           'UNIT',       'UL-I',  '33728203', '33728204', 4),
('INSURANCE_CHARGE',        'NON_UNIT',   'UL-I',  '33728203', '51113001', 7),
('WD_INSURANCE_CHARGE',     'UNIT',       'UL-I',  '33728203', '33728205', 3);

DROP TABLE IF EXISTS #fee_pick;
CREATE TABLE #fee_pick
(
    pick_no INT,
    fee_type VARCHAR(50),
    source_code VARCHAR(30),
    fund_code VARCHAR(30),
    debit_account VARCHAR(30),
    credit_account VARCHAR(30)
);

;WITH expanded_fee AS
(
    SELECT fee_type, source_code, fund_code, debit_account, credit_account, n = 1, fee_weight
    FROM #fee_config
    UNION ALL
    SELECT fee_type, source_code, fund_code, debit_account, credit_account, n + 1, fee_weight
    FROM expanded_fee
    WHERE n < fee_weight
)
INSERT INTO #fee_pick
SELECT
    ROW_NUMBER() OVER (ORDER BY fee_type, n),
    fee_type, source_code, fund_code, debit_account, credit_account
FROM expanded_fee
OPTION (MAXRECURSION 200);

DECLARE @fee_pick_count INT;
SELECT @fee_pick_count = COUNT(*) FROM #fee_pick;

DROP TABLE IF EXISTS #events;

;WITH n AS
(
    SELECT TOP (5000)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS event_no
    FROM sys.all_objects a
    CROSS JOIN sys.all_objects b
)
SELECT
    event_no,
    source_transaction_id = 'TRX' + RIGHT('000000' + CAST(event_no AS VARCHAR(6)), 6),
    policy_number = 'POL' + RIGHT('0000000' + CAST(event_no AS VARCHAR(7)), 7),
    accounting_date = DATEADD(DAY, (event_no * 7) % 45, CAST('2025-11-01' AS DATE)),
    account_gl_date = DATEADD(DAY, ((event_no * 7) % 45) + 1, CAST('2025-11-01' AS DATE)),
    transaction_date = DATEADD(DAY, (event_no * 7) % 45, CAST('2025-11-01' AS DATE)),
    product_code =
        CASE event_no % 4
            WHEN 0 THEN 'UL_WEALTH'
            WHEN 1 THEN 'UL_PROTECT'
            WHEN 2 THEN 'UL_PLUS'
            ELSE 'UL_ELITE'
        END,
    channel_code =
        CASE event_no % 3
            WHEN 0 THEN 'AGENCY'
            WHEN 1 THEN 'BANCA'
            ELSE 'DIRECT'
        END,
    fee_pick_no = ((event_no * 13) % @fee_pick_count) + 1,
    premium_base =
        CASE event_no % 6
            WHEN 0 THEN 8000000
            WHEN 1 THEN 10000000
            WHEN 2 THEN 12000000
            WHEN 3 THEN 15000000
            WHEN 4 THEN 18000000
            ELSE 20000000
        END
INTO #events
FROM n;

DROP TABLE IF EXISTS #event_fee;

SELECT
    e.event_no,
    e.source_transaction_id,
    e.policy_number,
    e.accounting_date,
    e.account_gl_date,
    e.transaction_date,
    fp.source_code,
    fp.fee_type,
    e.product_code,
    e.channel_code,
    fp.fund_code,
    fp.debit_account,
    fp.credit_account,
    amount =
        CAST(
        CASE
            WHEN fp.fee_type IN ('POLICY_FEE','WD_POLICY_FEE')
                THEN CASE e.event_no % 4 WHEN 0 THEN 100000 WHEN 1 THEN 150000 WHEN 2 THEN 200000 ELSE 250000 END
            WHEN fp.fee_type IN ('INSURANCE_CHARGE','WD_INSURANCE_CHARGE')
                THEN CASE e.event_no % 4 WHEN 0 THEN 350000 WHEN 1 THEN 500000 WHEN 2 THEN 650000 ELSE 800000 END
            WHEN fp.fee_type = 'COMMISSION'
                THEN e.premium_base * CASE e.event_no % 3 WHEN 0 THEN 0.08 WHEN 1 THEN 0.10 ELSE 0.12 END
            WHEN fp.fee_type = 'IMPLICIT_EXPENSE'
                THEN e.premium_base * CASE e.event_no % 4 WHEN 0 THEN 0.25 WHEN 1 THEN 0.30 WHEN 2 THEN 0.35 ELSE 0.40 END
            WHEN fp.fee_type IN ('NET_INVESTMENT_PREMIUM','TRANSFER_ULG_TO_ULI')
                THEN e.premium_base * CASE e.event_no % 4 WHEN 0 THEN 0.55 WHEN 1 THEN 0.60 WHEN 2 THEN 0.65 ELSE 0.70 END
            ELSE e.premium_base
        END AS DECIMAL(18,2))
INTO #event_fee
FROM #events e
INNER JOIN #fee_pick fp
    ON e.fee_pick_no = fp.pick_no;

INSERT INTO t_core_gl_detail
(
    gl_detail_id,
    source_transaction_id,
    policy_number,
    accounting_date,
    account_gl_date,
    transaction_date,
    source_code,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    dr_cr,
    amount
)
SELECT
    ROW_NUMBER() OVER (ORDER BY ef.event_no, dc.dr_cr),
    ef.source_transaction_id,
    ef.policy_number,
    ef.accounting_date,
    ef.account_gl_date,
    ef.transaction_date,
    ef.source_code,
    ef.fee_type,
    ef.product_code,
    ef.channel_code,
    ef.fund_code,
    CASE WHEN dc.dr_cr = 'DR' THEN ef.debit_account ELSE ef.credit_account END,
    dc.dr_cr,
    ef.amount
FROM #event_fee ef
CROSS JOIN
(
    SELECT 'DR' AS dr_cr
    UNION ALL
    SELECT 'CR'
) dc;

DROP TABLE IF EXISTS #s3_summary;

SELECT
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    amount = SUM(amount),
    record_count = COUNT(*)
INTO #s3_summary
FROM t_core_gl_detail
GROUP BY
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code;

ALTER TABLE #s3_summary ADD rn INT NULL;

;WITH ranked AS
(
    SELECT *,
           ROW_NUMBER() OVER (
               ORDER BY accounting_date, fee_type, product_code, channel_code, fund_code, account_code
           ) AS new_rn
    FROM #s3_summary
)
UPDATE ranked
SET rn = new_rn;

-- AMOUNT_MISMATCH
UPDATE #s3_summary
SET amount = amount -
    CASE rn % 4
        WHEN 0 THEN 100000
        WHEN 1 THEN 250000
        WHEN 2 THEN 500000
        ELSE 750000
    END
WHERE rn % 37 = 0;

-- COUNT_MISMATCH
UPDATE #s3_summary
SET record_count =
    CASE
        WHEN record_count > 1 THEN record_count - 1
        ELSE record_count + 1
    END
WHERE rn % 53 = 0
  AND rn % 37 <> 0;

-- ONLY_IN_CORE
DELETE FROM #s3_summary
WHERE rn % 30 = 0;

-- ONLY_IN_S3
DECLARE @max_rn INT;
SELECT @max_rn = ISNULL(MAX(rn), 0) FROM #s3_summary;

;WITH n AS
(
    SELECT TOP (35)
        ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS extra_no
    FROM sys.all_objects
)
INSERT INTO #s3_summary
(
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    amount,
    record_count,
    rn
)
SELECT
    DATEADD(DAY, (extra_no * 5) % 45, CAST('2025-11-01' AS DATE)),
    CASE extra_no % 5
        WHEN 0 THEN 'PREMIUM_APPLICATION'
        WHEN 1 THEN 'IMPLICIT_EXPENSE'
        WHEN 2 THEN 'COMMISSION'
        WHEN 3 THEN 'POLICY_FEE'
        ELSE 'INSURANCE_CHARGE'
    END,
    CASE extra_no % 4
        WHEN 0 THEN 'UL_WEALTH'
        WHEN 1 THEN 'UL_PROTECT'
        WHEN 2 THEN 'UL_PLUS'
        ELSE 'UL_ELITE'
    END,
    CASE extra_no % 3
        WHEN 0 THEN 'AGENCY'
        WHEN 1 THEN 'BANCA'
        ELSE 'DIRECT'
    END,
    CASE extra_no % 3
        WHEN 0 THEN 'UL-G'
        WHEN 1 THEN 'UL-I'
        ELSE 'NPF0Z'
    END,
    CASE extra_no % 4
        WHEN 0 THEN '33728101'
        WHEN 1 THEN '33728202'
        WHEN 2 THEN '51112001'
        ELSE '51113001'
    END,
    CAST(CASE extra_no % 4 WHEN 0 THEN 99999 WHEN 1 THEN 199999 WHEN 2 THEN 299999 ELSE 499999 END AS DECIMAL(18,2)),
    1,
    @max_rn + extra_no
FROM n;

INSERT INTO t_s3_interface_file
(
    s3_file_id,
    file_name,
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    amount,
    record_count
)
SELECT
    ROW_NUMBER() OVER (
        ORDER BY accounting_date, fee_type, product_code, channel_code, fund_code, account_code
    ),
    'GL_' + CONVERT(CHAR(8), accounting_date, 112) + '.txt',
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    amount,
    record_count
FROM #s3_summary;

SELECT 'm_fee_type' AS table_name, COUNT(*) AS row_count FROM m_fee_type
UNION ALL
SELECT 't_core_gl_detail', COUNT(*) FROM t_core_gl_detail
UNION ALL
SELECT 't_s3_interface_file', COUNT(*) FROM t_s3_interface_file;

IF OBJECT_ID('dbo.vw_reconciliation_result', 'V') IS NOT NULL
BEGIN
    SELECT
        reconciliation_status,
        COUNT(*) AS group_count,
        SUM(ABS(amount_difference)) AS total_abs_difference
    FROM vw_reconciliation_result
    GROUP BY reconciliation_status
    ORDER BY reconciliation_status;
END;

PRINT 'Sample data generated successfully.';
GO
