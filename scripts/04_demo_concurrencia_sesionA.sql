/* =========================================================
   BusRD - E2.4 Demo de concurrencia - SESION A
   ---------------------------------------------------------
   Ejecutar en la ventana A de SSMS.
   Luego, dentro de los siguientes 10 segundos, ejecutar
   05_demo_concurrencia_sesionB.sql en la ventana B.

   La sesion A adquiere el bloqueo del asiento con
   UPDLOCK + HOLDLOCK y despues espera 10 segundos dentro
   de la transaccion (@SimularDemora = 1).

   La sesion B debe esperar ese bloqueo y luego ser
   rechazada con "El asiento ya esta vendido.".

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

/* Verificacion previa: el asiento debe estar libre para iniciar la demo */
IF EXISTS (
    SELECT 1
    FROM dbo.Boletos
    WHERE ViajeID = @ViajeID
      AND NumeroAsiento = @NumeroAsiento
      AND Estado = 'Activo'
)
    THROW 51010, 'El asiento de la demo ya esta ocupado. Elija otro asiento.', 1;

SELECT 'SESION A - inicio' AS Evento, SYSDATETIME() AS Hora;

EXEC dbo.sp_VenderBoleto
    @ViajeID       = @ViajeID,
    @NumeroAsiento = @NumeroAsiento,
    @ClienteID     = @ClienteID,
    @Canal         = 'Web',
    @Metodo        = 'Tarjeta',
    @BoletoID      = @BoletoID OUTPUT,
    @SimularDemora = 1;

SELECT 'SESION A - fin' AS Evento, @BoletoID AS BoletoID, SYSDATETIME() AS Hora;

/* Para repetir la demo, anular el boleto creado por A:
   EXEC dbo.sp_AnularBoleto @BoletoID = <BoletoID>;
*/
GO

