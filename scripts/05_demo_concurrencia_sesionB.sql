/* =========================================================
   BusRD - E2.4 Demo de concurrencia - SESION B
   ---------------------------------------------------------
   Ejecutar en la ventana B de SSMS, despues de iniciar
   la sesion A (04_demo_concurrencia_sesionA.sql).

   La sesion B intenta vender el mismo asiento. El
   procedimiento espera el bloqueo de A y luego rechaza
   la venta porque el asiento ya quedo vendido.

   Datos de trabajo: viaje 15541, asiento 29, cliente 1000.
   Reemplazar por el viaje/cliente asignado al grupo.
   ========================================================= */

USE BusRD;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

DECLARE @ViajeID       INT = 15541;
DECLARE @NumeroAsiento INT = 29;
DECLARE @ClienteID     INT = 1000;
DECLARE @BoletoID      INT;

SELECT 'SESION B - inicio' AS Evento, SYSDATETIME() AS Hora;

BEGIN TRY
    EXEC dbo.sp_VenderBoleto
        @ViajeID       = @ViajeID,
        @NumeroAsiento = @NumeroAsiento,
        @ClienteID     = @ClienteID,
        @Canal         = 'Taquilla',
        @Metodo        = 'Efectivo',
        @BoletoID      = @BoletoID OUTPUT,
        @SimularDemora = 0;

    SELECT 'SESION B - exito (ERROR: no deberia ocurrir)' AS Evento,
           @BoletoID AS BoletoID,
           SYSDATETIME() AS Hora;
END TRY
BEGIN CATCH
    SELECT 'SESION B - rechazada' AS Evento,
           ERROR_NUMBER() AS Numero,
           ERROR_MESSAGE() AS Mensaje,
           SYSDATETIME() AS Hora;
END CATCH;

/* Verificacion final: debe existir un solo boleto activo
   para el viaje/asiento de la demo. */
SELECT ViajeID, NumeroAsiento, COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE ViajeID = @ViajeID
  AND NumeroAsiento = @NumeroAsiento
  AND Estado = 'Activo'
GROUP BY ViajeID, NumeroAsiento;
GO

