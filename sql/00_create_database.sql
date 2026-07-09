IF DB_ID('Insurance_Reconcile_Portfolio') IS NOT NULL
BEGIN
    ALTER DATABASE Insurance_Reconcile_Portfolio SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Insurance_Reconcile_Portfolio;
END;
GO

CREATE DATABASE Insurance_Reconcile_Portfolio;
GO

USE Insurance_Reconcile_Portfolio;
GO
