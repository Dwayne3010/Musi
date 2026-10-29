/* =========================================================
   BusRD - E2.5: Anulacion de boleto
   ---------------------------------------------------------
   - Anula el boleto dentro de una transaccion.
   - Registra el reverso del pago con monto negativo.
   - El indice unico filtrado libera el asiento al quedar
     el boleto en estado Anulado.
   ========================================================= */

USE BusRD;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AnularBoleto
    @BoletoID INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @Estado VARCHAR(10), @Monto DECIMAL(10,2), @Metodo VARCHAR(15);

        SELECT @Estado = Estado
        FROM dbo.Boletos WITH (UPDLOCK, HOLDLOCK)
        WHERE BoletoID = @BoletoID;

        IF @Estado IS NULL
            THROW 52001, 'El boleto no existe.', 1;

        IF @Estado = 'Anulado'
            THROW 52002, 'El boleto ya esta anulado.', 1;

        SELECT @Monto = SUM(Monto)
        FROM dbo.Pagos
        WHERE BoletoID = @BoletoID
          AND Monto > 0;

        IF @Monto IS NULL
            THROW 52003, 'El boleto no tiene pago registrado.', 1;

        SELECT TOP (1) @Metodo = Metodo
        FROM dbo.Pagos
        WHERE BoletoID = @BoletoID
          AND Monto > 0
        ORDER BY PagoID DESC;

        UPDATE dbo.Boletos
        SET Estado = 'Anulado'
        WHERE BoletoID = @BoletoID;

        INSERT INTO dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
        VALUES (@BoletoID, -@Monto, @Metodo, SYSDATETIME());

        COMMIT TRANSACTION;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        THROW;
    END CATCH;
END;
GO
