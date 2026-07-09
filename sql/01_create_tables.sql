USE Insurance_Reconcile_Portfolio;
GO

CREATE TABLE m_fee_type (
    fee_type VARCHAR(50) NOT NULL PRIMARY KEY,
    fee_type_name VARCHAR(100) NOT NULL,
    source_code VARCHAR(20) NOT NULL,
    generated_by VARCHAR(30) NOT NULL,
    default_fund VARCHAR(20) NOT NULL,
    description NVARCHAR(255) NULL
);

CREATE TABLE t_core_gl_detail (
    gl_detail_id BIGINT NOT NULL PRIMARY KEY,
    source_transaction_id VARCHAR(30) NOT NULL,
    policy_number VARCHAR(30) NOT NULL,
    accounting_date DATE NOT NULL,
    account_gl_date DATE NOT NULL,
    transaction_date DATE NOT NULL,
    source_code VARCHAR(20) NOT NULL,
    fee_type VARCHAR(50) NOT NULL,
    product_code VARCHAR(30) NOT NULL,
    channel_code VARCHAR(20) NOT NULL,
    fund_code VARCHAR(20) NOT NULL,
    account_code VARCHAR(30) NOT NULL,
    dr_cr CHAR(2) NOT NULL CHECK (dr_cr IN ('DR', 'CR')),
    amount DECIMAL(18,2) NOT NULL,
    CONSTRAINT fk_core_fee_type FOREIGN KEY (fee_type) REFERENCES m_fee_type(fee_type)
);

CREATE TABLE t_s3_interface_file (
    s3_file_id BIGINT NOT NULL PRIMARY KEY,
    file_name VARCHAR(100) NOT NULL,
    accounting_date DATE NOT NULL,
    fee_type VARCHAR(50) NOT NULL,
    product_code VARCHAR(30) NOT NULL,
    channel_code VARCHAR(20) NOT NULL,
    fund_code VARCHAR(20) NOT NULL,
    account_code VARCHAR(30) NOT NULL,
    amount DECIMAL(18,2) NOT NULL,
    record_count INT NOT NULL,
    CONSTRAINT fk_s3_fee_type FOREIGN KEY (fee_type) REFERENCES m_fee_type(fee_type)
);
GO
