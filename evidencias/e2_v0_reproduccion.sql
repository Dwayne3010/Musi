/* =========================================================
   BusRD - E2.1 Reproduccion de la doble venta (soporte)
   ---------------------------------------------------------
   Este script NO forma parte de la secuencia 01-08.
   Se ejecuta sobre una COPIA desechable para demostrar que el
   procedimiento original v0 permite vender dos veces el mismo
   asiento. La base final BusRD NO se modifica.

   Resultado obtenido: boletos 232149 (Taquilla) y 232150 (Web)
   activos para el viaje 15541, asiento 30, con dos pagos de
   $420.00. Ver e2_v0_demo_sesionA.log, e2_v0_demo_sesionB.log
   y e2_v0_resultado.log.

   Para reproducirlo:
   1) Crear la copia:
        BACKUP DATABASE BusRD TO DISK='C:\Backups\BusRD\E2Demo_source.bak'
          WITH INIT, COPY_ONLY;
        RESTORE DATABASE BusRD_E2Demo FROM DISK='C:\Backups\BusRD\E2Demo_source.bak'
          WITH MOVE 'BusRD'     TO '...\BusRD_E2Demo.mdf',
               MOVE 'BusRD_log' TO '...\BusRD_E2Demo_log.ldf',
               RECOVERY, REPLACE;
   2) Ejecutar este script en BusRD_E2Demo.
   3) Abrir dos ventanas: ejecutar la SESION A y, 2 segundos
      despues, la SESION B.
   4) Verificar el resultado con la consulta final.
   ========================================================= */

USE BusRD_E2Demo;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* Estado previo a E1.4: sin indice unico filtrado */
IF EXISTS (SELECT 1 FROM sys.indexes
           WHERE object_id = OBJECT_ID('dbo.Boletos')
             AND name = 'UX_Boletos_Viaje_Asiento_Activo')
    DROP INDEX UX_Boletos_Viaje_Asiento_Activo ON dbo.Boletos;
GO

/* Procedimiento original v0: check-then-act sin bloqueo */
CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto_v0
    @ViajeID       INT,
    @NumeroAsiento INT,
    @ClienteID     INT,
    @Canal         VARCHAR(10),
    @Metodo        VARCHAR(15),
    @BoletoID      INT OUTPUT,
    @SimularDemora BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (
        SELECT 1
        FROM dbo.Boletos
        WHERE ViajeID = @ViajeID
          AND NumeroAsiento = @NumeroAsiento
          AND Estado = 'Activo'
    )
        THROW 51006, 'El asiento ya esta vendido.', 1;

    DECLARE @Precio DECIMAL(10,2);

    SELECT @Precio = r.PrecioBase
    FROM dbo.Viajes v
    JOIN dbo.Rutas r ON r.RutaID = v.RutaID
    WHERE v.ViajeID = @ViajeID;

    BEGIN TRANSACTION;

    IF @SimularDemora = 1
        WAITFOR DELAY '00:00:10';

    INSERT INTO dbo.Boletos
        (ViajeID, NumeroAsiento, ClienteID, FechaVenta, Canal, Precio, Estado)
    VALUES
        (@ViajeID, @NumeroAsiento, @ClienteID, SYSDATETIME(), @Canal, @Precio, 'Activo');

    SET @BoletoID = CAST(SCOPE_IDENTITY() AS INT);

    INSERT INTO dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
    VALUES (@BoletoID, @Precio, @Metodo, SYSDATETIME());

    COMMIT TRANSACTION;
END;
GO

/* ================= SESION A (ventana A) ================= */
/*
DECLARE @ViajeID INT = 15541, @NumeroAsiento INT = 30;
DECLARE @ClienteID INT = 1000, @BoletoID INT;
SELECT 'SESION A - inicio' AS Evento, SYSDATETIME() AS Hora;
EXEC dbo.sp_VenderBoleto_v0
    @ViajeID=@ViajeID, @NumeroAsiento=@NumeroAsiento, @ClienteID=@ClienteID,
    @Canal='Web', @Metodo='Tarjeta', @BoletoID=@BoletoID OUTPUT, @SimularDemora=1;
SELECT 'SESION A - fin' AS Evento, @BoletoID AS BoletoID, SYSDATETIME() AS Hora;
*/

/* ================= SESION B (ventana B) ================= */
/*
DECLARE @ViajeID INT = 15541, @NumeroAsiento INT = 30;
DECLARE @ClienteID INT = 1000, @BoletoID INT;
SELECT 'SESION B - inicio' AS Evento, SYSDATETIME() AS Hora;
EXEC dbo.sp_VenderBoleto_v0
    @ViajeID=@ViajeID, @NumeroAsiento=@NumeroAsiento, @ClienteID=@ClienteID,
    @Canal='Taquilla', @Metodo='Efectivo', @BoletoID=@BoletoID OUTPUT, @SimularDemora=0;
SELECT 'SESION B - fin (VENTA INDEBIDA)' AS Evento, @BoletoID AS BoletoID, SYSDATETIME() AS Hora;
*/

/* ================= Verificacion final ================= */
SELECT b.BoletoID, b.NumeroAsiento, b.Canal, b.Estado, b.Precio,
       p.PagoID, p.Monto, p.Metodo
FROM dbo.Boletos b
LEFT JOIN dbo.Pagos p ON p.BoletoID = b.BoletoID
WHERE b.ViajeID = 15541 AND b.NumeroAsiento = 30
ORDER BY b.BoletoID;

SELECT COUNT(*) AS BoletosActivos
FROM dbo.Boletos
WHERE ViajeID = 15541 AND NumeroAsiento = 30 AND Estado = 'Activo';
GO
