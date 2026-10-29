/* =========================================================
   BusRD - E1: Integridad del modelo
   ---------------------------------------------------------
   Incluye:
   1. Deteccion de boletos activos duplicados y pagos huerfanos.
   2. Limpieza con auditoria:
      - conserva el boleto mas antiguo de cada asiento/viaje;
      - anula el duplicado mas reciente;
      - registra el reverso negativo de su pago;
      - archiva y elimina los pagos huerfanos.
   3. Llaves foraneas, CHECKs y unicidad.
   4. Indice unico filtrado para impedir doble venta activa.
   ========================================================= */

USE BusRD;
GO

/* Opciones requeridas para indices filtrados */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   1. DETECCION (evidencia antes de limpiar)
   ========================================================= */
PRINT '=== E1.1 Boletos activos duplicados ===';
SELECT b.ViajeID, b.NumeroAsiento,
       COUNT(*)        AS BoletosActivos,
       MIN(b.BoletoID) AS BoletoMasAntiguo,
       MAX(b.BoletoID) AS BoletoMasReciente
FROM dbo.Boletos b
WHERE b.Estado = 'Activo'
GROUP BY b.ViajeID, b.NumeroAsiento
HAVING COUNT(*) > 1
ORDER BY b.ViajeID, b.NumeroAsiento;

PRINT '=== E1.1 Pagos huerfanos ===';
SELECT p.PagoID, p.BoletoID, p.Monto, p.Metodo, p.FechaPago
FROM dbo.Pagos p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID)
ORDER BY p.PagoID;
GO

/* =========================================================
   2. TABLAS DE AUDITORIA
   ========================================================= */
IF OBJECT_ID('dbo.Auditoria_BoletosDuplicados', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Auditoria_BoletosDuplicados (
        AuditoriaID    INT IDENTITY(1,1) PRIMARY KEY,
        ViajeID        INT           NOT NULL,
        NumeroAsiento  INT           NOT NULL,
        BoletoID       INT           NOT NULL,
        FechaVenta     DATETIME2(0)  NOT NULL,
        ClienteID      INT           NOT NULL,
        Canal          VARCHAR(10)   NOT NULL,
        Precio         DECIMAL(10,2) NOT NULL,
        Accion         VARCHAR(60)   NOT NULL,
        FechaProceso   DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
    );
END;

IF OBJECT_ID('dbo.Auditoria_PagosHuerfanos', 'U') IS NULL
BEGIN
    CREATE TABLE dbo.Auditoria_PagosHuerfanos (
        AuditoriaID  INT IDENTITY(1,1) PRIMARY KEY,
        PagoID       INT           NOT NULL,
        BoletoID     INT           NOT NULL,
        Monto        DECIMAL(10,2) NOT NULL,
        Metodo       VARCHAR(15)   NOT NULL,
        FechaPago    DATETIME2(0)  NOT NULL,
        Accion       VARCHAR(60)   NOT NULL,
        FechaProceso DATETIME2(0)  NOT NULL DEFAULT SYSDATETIME()
    );
END;
GO

/* =========================================================
   3. LIMPIEZA TRANSACCIONAL
   ---------------------------------------------------------
   Regla:
   - Se conserva el boleto activo mas antiguo de cada
     (ViajeID, NumeroAsiento).
   - Los duplicados posteriores se anulan.
   - A cada duplicado se le registra un pago negativo por
     el monto de su pago original (reverso auditable).
   - Los pagos sin boleto se archivan y se eliminan.
   ========================================================= */
BEGIN TRY
    BEGIN TRANSACTION;

    ;WITH Dup AS (
        SELECT b.BoletoID, b.ViajeID, b.NumeroAsiento, b.FechaVenta,
               b.ClienteID, b.Canal, b.Precio,
               ROW_NUMBER() OVER (
                   PARTITION BY b.ViajeID, b.NumeroAsiento
                   ORDER BY b.FechaVenta, b.BoletoID
               ) AS rn
        FROM dbo.Boletos b
        WHERE b.Estado = 'Activo'
    )
    SELECT BoletoID, ViajeID, NumeroAsiento, FechaVenta, ClienteID, Canal, Precio
    INTO #Dup
    FROM Dup
    WHERE rn > 1;

    INSERT INTO dbo.Auditoria_BoletosDuplicados
        (ViajeID, NumeroAsiento, BoletoID, FechaVenta, ClienteID, Canal, Precio, Accion)
    SELECT d.ViajeID, d.NumeroAsiento, d.BoletoID, d.FechaVenta, d.ClienteID,
           d.Canal, d.Precio, 'Anulado: duplicado vendido despues'
    FROM #Dup d
    WHERE NOT EXISTS (
        SELECT 1 FROM dbo.Auditoria_BoletosDuplicados a
        WHERE a.BoletoID = d.BoletoID
    );

    INSERT INTO dbo.Pagos (BoletoID, Monto, Metodo, FechaPago)
    SELECT d.BoletoID, -p.Monto, p.Metodo, SYSDATETIME()
    FROM #Dup d
    JOIN dbo.Pagos p ON p.BoletoID = d.BoletoID
    WHERE p.Monto > 0
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Pagos r
          WHERE r.BoletoID = d.BoletoID AND r.Monto < 0
      );

    UPDATE b
    SET b.Estado = 'Anulado'
    FROM dbo.Boletos b
    JOIN #Dup d ON d.BoletoID = b.BoletoID
    WHERE b.Estado = 'Activo';

    INSERT INTO dbo.Auditoria_PagosHuerfanos
        (PagoID, BoletoID, Monto, Metodo, FechaPago, Accion)
    SELECT p.PagoID, p.BoletoID, p.Monto, p.Metodo, p.FechaPago,
           'Eliminado: pago sin boleto'
    FROM dbo.Pagos p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID)
      AND NOT EXISTS (
          SELECT 1 FROM dbo.Auditoria_PagosHuerfanos a WHERE a.PagoID = p.PagoID
      );

    DELETE p
    FROM dbo.Pagos p
    WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID);

    COMMIT TRANSACTION;
    PRINT 'Limpieza completada correctamente.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* =========================================================
   4. VERIFICACION POST-LIMPIEZA
   ========================================================= */
PRINT '=== Verificacion: duplicados activos restantes ===';
SELECT COUNT(*) AS DuplicadosActivos
FROM (
    SELECT 1 AS x
    FROM dbo.Boletos
    WHERE Estado = 'Activo'
    GROUP BY ViajeID, NumeroAsiento
    HAVING COUNT(*) > 1
) d;

PRINT '=== Verificacion: pagos huerfanos restantes ===';
SELECT COUNT(*) AS PagosHuerfanos
FROM dbo.Pagos p
WHERE NOT EXISTS (SELECT 1 FROM dbo.Boletos b WHERE b.BoletoID = p.BoletoID);
GO

/* =========================================================
   5. LLAVES FORANEAS
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Asientos_Autobuses')
    ALTER TABLE dbo.Asientos ADD CONSTRAINT FK_Asientos_Autobuses
        FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Viajes_Rutas')
    ALTER TABLE dbo.Viajes ADD CONSTRAINT FK_Viajes_Rutas
        FOREIGN KEY (RutaID) REFERENCES dbo.Rutas(RutaID);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Viajes_Autobuses')
    ALTER TABLE dbo.Viajes ADD CONSTRAINT FK_Viajes_Autobuses
        FOREIGN KEY (AutobusID) REFERENCES dbo.Autobuses(AutobusID);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Boletos_Viajes')
    ALTER TABLE dbo.Boletos ADD CONSTRAINT FK_Boletos_Viajes
        FOREIGN KEY (ViajeID) REFERENCES dbo.Viajes(ViajeID);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Boletos_Clientes')
    ALTER TABLE dbo.Boletos ADD CONSTRAINT FK_Boletos_Clientes
        FOREIGN KEY (ClienteID) REFERENCES dbo.Clientes(ClienteID);

IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = 'FK_Pagos_Boletos')
    ALTER TABLE dbo.Pagos ADD CONSTRAINT FK_Pagos_Boletos
        FOREIGN KEY (BoletoID) REFERENCES dbo.Boletos(BoletoID);
GO

/* =========================================================
   6. RESTRICCIONES CHECK
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Autobuses_Tipo')
    ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Tipo
        CHECK (Tipo IN ('Estandar', 'Ejecutivo'));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Autobuses_Capacidad')
    ALTER TABLE dbo.Autobuses ADD CONSTRAINT CK_Autobuses_Capacidad
        CHECK (Capacidad BETWEEN 1 AND 100);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Viajes_Estado')
    ALTER TABLE dbo.Viajes ADD CONSTRAINT CK_Viajes_Estado
        CHECK (Estado IN ('Programado', 'Completado', 'Cancelado'));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Boletos_Canal')
    ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Canal
        CHECK (Canal IN ('Taquilla', 'Web'));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Boletos_Estado')
    ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Estado
        CHECK (Estado IN ('Activo', 'Anulado'));

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Boletos_Precio')
    ALTER TABLE dbo.Boletos ADD CONSTRAINT CK_Boletos_Precio
        CHECK (Precio > 0);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Pagos_Metodo')
    ALTER TABLE dbo.Pagos ADD CONSTRAINT CK_Pagos_Metodo
        CHECK (Metodo IN ('Efectivo', 'Tarjeta', 'Transferencia'));

/* Monto permite negativos para los reversos de anulacion */
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Pagos_Monto')
    ALTER TABLE dbo.Pagos ADD CONSTRAINT CK_Pagos_Monto
        CHECK (Monto <> 0 AND Monto BETWEEN -1000000 AND 1000000);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Rutas_DistanciaKm')
    ALTER TABLE dbo.Rutas ADD CONSTRAINT CK_Rutas_DistanciaKm
        CHECK (DistanciaKm > 0);

IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Rutas_PrecioBase')
    ALTER TABLE dbo.Rutas ADD CONSTRAINT CK_Rutas_PrecioBase
        CHECK (PrecioBase >= 0);
GO

/* =========================================================
   7. UNICIDAD DE CEDULA Y PLACA
   ========================================================= */
IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Clientes_Cedula')
    ALTER TABLE dbo.Clientes ADD CONSTRAINT UQ_Clientes_Cedula UNIQUE (Cedula);

IF NOT EXISTS (SELECT 1 FROM sys.key_constraints WHERE name = 'UQ_Autobuses_Placa')
    ALTER TABLE dbo.Autobuses ADD CONSTRAINT UQ_Autobuses_Placa UNIQUE (Placa);
GO

/* =========================================================
   8. UN BOLETO ACTIVO POR VIAJE/ASIENTO
   ---------------------------------------------------------
   Indice unico filtrado: los anulados no participan, por lo
   que anular un boleto libera el asiento.
   ========================================================= */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'UX_Boletos_Viaje_Asiento_Activo'
      AND object_id = OBJECT_ID('dbo.Boletos')
)
BEGIN
    CREATE UNIQUE INDEX UX_Boletos_Viaje_Asiento_Activo
        ON dbo.Boletos (ViajeID, NumeroAsiento)
        WHERE Estado = 'Activo';
END;
GO

PRINT '=== E1 completado: integridad aplicada ===';
GO
