/* =========================================================
   BusRD - E2.3: Procedimiento de venta transaccional
   ---------------------------------------------------------
   - Valida viaje Programado, asiento del autobus, cliente,
     canal y metodo.
   - Boleto + pago en una sola transaccion.
   - Usa UPDLOCK + HOLDLOCK sobre el indice unico filtrado
     para bloquear el rango del asiento y evitar la doble venta.
   - TRY/CATCH con ROLLBACK y THROW.
   - Devuelve el BoletoID por parametro OUTPUT.
   - @SimularDemora = 1 ejecuta WAITFOR 10 s dentro de la
     transaccion para la demo de concurrencia.
   ========================================================= */

USE BusRD;
GO
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE dbo.sp_VenderBoleto
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
    SET XACT_ABORT ON;

    /* Validaciones de parametros */
    IF @Canal NOT IN ('Taquilla', 'Web')
        THROW 51001, 'Canal no valido. Use Taquilla o Web.', 1;

    IF @Metodo NOT IN ('Efectivo', 'Tarjeta', 'Transferencia')
        THROW 51002, 'Metodo de pago no valido.', 1;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* El viaje debe existir y estar Programado */
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Viajes
            WHERE ViajeID = @ViajeID
              AND Estado = 'Programado'
        )
            THROW 51003, 'El viaje no existe o no esta Programado.', 1;

        /* El asiento debe existir en el autobus de ese viaje */
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Viajes v
            JOIN dbo.Asientos a ON a.AutobusID = v.AutobusID
            WHERE v.ViajeID = @ViajeID
              AND a.NumeroAsiento = @NumeroAsiento
        )
            THROW 51004, 'El asiento no existe en el autobus de este viaje.', 1;

        /* El cliente debe existir */
        IF NOT EXISTS (
            SELECT 1
            FROM dbo.Clientes
            WHERE ClienteID = @ClienteID
        )
            THROW 51005, 'El cliente no existe.', 1;

        /* Bloqueo de rango sobre el asiento activo.
           UPDLOCK evita que otro proceso lo tome;
           HOLDLOCK mantiene el bloqueo hasta el COMMIT.
           El indice filtrado solo contiene boletos activos. */
        IF EXISTS (
            SELECT 1
            FROM dbo.Boletos WITH (
                UPDLOCK,
                HOLDLOCK,
                INDEX(UX_Boletos_Viaje_Asiento_Activo)
            )
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

        /* Demora dentro de la transaccion para evidenciar el bloqueo */
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
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
            ROLLBACK TRANSACTION;

        /* Mensaje amigable si la restriccion unica gana la carrera */
        IF ERROR_NUMBER() IN (2601, 2627)
            THROW 51007, 'El asiento ya esta vendido (conflicto de unicidad).', 1;

        THROW;
    END CATCH;
END;
GO
