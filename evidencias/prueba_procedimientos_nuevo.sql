USE BusRD;
GO
SET NOCOUNT ON;
GO

/* =========================================================
   Prueba de los procedimientos nuevos:
   1) sp_VenderBoleto  -> venta correcta
   2) sp_VenderBoleto  -> rechazo de la doble venta (51006)
   3) sp_AnularBoleto  -> anulacion con reverso negativo
   ========================================================= */

DECLARE @ViajeID       INT = 15541;
DECLARE @NumeroAsiento INT = 1;
DECLARE @ClienteID     INT = 6000;

DECLARE @BoletoID      INT = NULL;
DECLARE @Error1        INT = NULL;
DECLARE @Msg1          NVARCHAR(4000) = NULL;
DECLARE @Error2        INT = NULL;
DECLARE @Msg2          NVARCHAR(4000) = NULL;
DECLARE @Error3        INT = NULL;
DECLARE @Msg3          NVARCHAR(4000) = NULL;
DECLARE @Estado        VARCHAR(10) = NULL;
DECLARE @PagosPos      DECIMAL(10,2) = NULL;
DECLARE @PagosNeg      DECIMAL(10,2) = NULL;
DECLARE @ActivosFinal  INT = NULL;

/* 1) Venta normal */
BEGIN TRY
    EXEC dbo.sp_VenderBoleto
         @ViajeID, @NumeroAsiento, @ClienteID,
         'Taquilla', 'Efectivo', @BoletoID OUTPUT;
END TRY
BEGIN CATCH
    SET @Error1 = ERROR_NUMBER();
    SET @Msg1   = ERROR_MESSAGE();
END CATCH;

/* 2) Reintento del mismo asiento: debe rechazarse */
BEGIN TRY
    DECLARE @BoletoID2 INT = NULL;
    EXEC dbo.sp_VenderBoleto
         @ViajeID, @NumeroAsiento, 6001,
         'Taquilla', 'Efectivo', @BoletoID2 OUTPUT;
END TRY
BEGIN CATCH
    SET @Error2 = ERROR_NUMBER();
    SET @Msg2   = ERROR_MESSAGE();
END CATCH;

/* 3) Anulacion del boleto vendido en el paso 1 */
IF @BoletoID IS NOT NULL
BEGIN
    BEGIN TRY
        EXEC dbo.sp_AnularBoleto @BoletoID;
    END TRY
    BEGIN CATCH
        SET @Error3 = ERROR_NUMBER();
        SET @Msg3   = ERROR_MESSAGE();
    END CATCH;
END;

SELECT @Estado = Estado
FROM dbo.Boletos
WHERE BoletoID = @BoletoID;

SELECT @PagosPos = SUM(CASE WHEN Monto > 0 THEN Monto ELSE 0 END),
       @PagosNeg = SUM(CASE WHEN Monto < 0 THEN Monto ELSE 0 END)
FROM dbo.Pagos
WHERE BoletoID = @BoletoID;

SELECT @ActivosFinal = COUNT(*)
FROM dbo.Boletos
WHERE ViajeID = @ViajeID
  AND NumeroAsiento = @NumeroAsiento
  AND Estado = 'Activo';

SELECT CAST('PRUEBA DE PROCEDIMIENTOS NUEVOS - BusRD' AS VARCHAR(60)) AS Prueba,
       CAST('' AS VARCHAR(12)) AS Resultado,
       CAST(CONCAT('Viaje ', @ViajeID, ' / asiento ', @NumeroAsiento,
                   ' / cliente ', @ClienteID) AS VARCHAR(120)) AS Detalle
UNION ALL
SELECT CAST(CONCAT('1. Venta asiento ', @NumeroAsiento) AS VARCHAR(60)),
       CAST(CASE WHEN @Error1 IS NULL THEN 'OK' ELSE 'FALLO' END AS VARCHAR(12)),
       CAST(CASE WHEN @Error1 IS NULL
                 THEN CONCAT('Boleto ', @BoletoID, ' creado')
                 ELSE CONCAT('Error ', @Error1, ': ', @Msg1) END AS VARCHAR(120))
UNION ALL
SELECT CAST('2. Reintento mismo asiento' AS VARCHAR(60)),
       CAST(CASE WHEN @Error2 IS NULL THEN 'FALLO' ELSE 'RECHAZADA' END AS VARCHAR(12)),
       CAST(CASE WHEN @Error2 IS NULL
                 THEN 'Se permitio una segunda venta activa'
                 ELSE CONCAT('Error ', @Error2, ': ', @Msg2) END AS VARCHAR(120))
UNION ALL
SELECT CAST(CONCAT('3. Anulacion boleto ', @BoletoID) AS VARCHAR(60)),
       CAST(CASE WHEN @Error3 IS NOT NULL THEN 'FALLO'
                 WHEN @Estado = 'Anulado' THEN 'OK'
                 ELSE 'FALLO' END AS VARCHAR(12)),
       CAST(CASE WHEN @Error3 IS NOT NULL
                 THEN CONCAT('Error ', @Error3, ': ', @Msg3)
                 ELSE CONCAT('Estado: ', @Estado,
                             '; pagos: +', @PagosPos,
                             ' / ', @PagosNeg) END AS VARCHAR(120))
UNION ALL
SELECT CAST(CONCAT('4. Estado final asiento ', @NumeroAsiento) AS VARCHAR(60)),
       CAST(CASE WHEN @ActivosFinal = 0 THEN 'LIBRE' ELSE 'OCUPADO' END AS VARCHAR(12)),
       CAST(CONCAT(@ActivosFinal, ' boleto(s) activo(s)') AS VARCHAR(120));
GO
