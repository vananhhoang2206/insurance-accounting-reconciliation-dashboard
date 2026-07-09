USE Insurance_Reconcile_Portfolio;
GO

CREATE OR ALTER VIEW vw_reconciliation_result
AS

WITH core_summary AS
(
SELECT
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code,
    SUM(amount) AS core_amount,
    COUNT(*) AS core_record_count
FROM t_core_gl_detail
GROUP BY
    accounting_date,
    fee_type,
    product_code,
    channel_code,
    fund_code,
    account_code
)

SELECT
COALESCE(c.accounting_date,s.accounting_date) AS accounting_date,
COALESCE(c.fee_type,s.fee_type) AS fee_type,
COALESCE(c.product_code,s.product_code) AS product_code,
COALESCE(c.channel_code,s.channel_code) AS channel_code,
COALESCE(c.fund_code,s.fund_code) AS fund_code,
COALESCE(c.account_code,s.account_code) AS account_code,
ft.fee_type_name,
ft.source_code,
ft.generated_by,
c.core_amount,
s.amount AS s3_amount,
ISNULL(c.core_amount,0)-ISNULL(s.amount,0) AS amount_difference,
c.core_record_count,
s.record_count AS s3_record_count,
ISNULL(c.core_record_count,0)-ISNULL(s.record_count,0) AS record_count_difference,
CASE
WHEN c.accounting_date IS NULL THEN 'ONLY_IN_S3'
WHEN s.accounting_date IS NULL THEN 'ONLY_IN_CORE'
WHEN ABS(ISNULL(c.core_amount,0)-ISNULL(s.amount,0))>0 THEN 'AMOUNT_MISMATCH'
WHEN ISNULL(c.core_record_count,0)<>ISNULL(s.record_count,0) THEN 'COUNT_MISMATCH'
ELSE 'MATCHED'
END AS reconciliation_status,
CASE
WHEN c.accounting_date IS NULL THEN 'Data exists in S3 only. Possible wrong interface file or incorrect interface key.'
WHEN s.accounting_date IS NULL THEN 'Data exists in Core only. Possible late batch, failed export or interface cut-off.'
WHEN ABS(ISNULL(c.core_amount,0)-ISNULL(s.amount,0))>0 THEN 'Amount mismatch between Core and S3.'
WHEN ISNULL(c.core_record_count,0)<>ISNULL(s.record_count,0) THEN 'Record count mismatch.'
ELSE 'Matched'
END AS possible_root_cause
FROM core_summary c
FULL OUTER JOIN t_s3_interface_file s
ON c.accounting_date=s.accounting_date
AND c.fee_type=s.fee_type
AND c.product_code=s.product_code
AND c.channel_code=s.channel_code
AND c.fund_code=s.fund_code
AND c.account_code=s.account_code
LEFT JOIN m_fee_type ft
ON ft.fee_type=COALESCE(c.fee_type,s.fee_type);
GO
