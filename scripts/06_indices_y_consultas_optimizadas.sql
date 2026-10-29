/* =========================================================
   BusRD - E3: Optimizacion de consultas
   ---------------------------------------------------------
   Indices creados:
     IX_Boletos_Cliente          -> C2 (historial por cliente)
     IX_Boletos_Activo_Boleto    -> C3 (reporte mensual)
     IX_Pagos_Boleto_Monto       -> C3 y anulacion de pagos

   C1 se apoya en el indice unico filtrado creado en E1:
     UX_Boletos_Viaje_Asiento_Activo

   Reescrituras sargables:
     C1: NOT IN  -> NOT EXISTS
     C2: LTRIM(RTRIM(Cedula)) -> Cedula = @Cedula
     C3: YEAR(FechaVenta)=2025 -> rango de fechas
   ========================================================= */

USE BusRD;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
GO

SET NOCOUNT ON;
GO

PRINT '=== E3.1 Creacion de indices ===';
GO

/* C2: buscar los boletos de un cliente por ClienteID.
   INCLUDE cubre todas las columnas que devuelve la consulta
   para evitar key lookups al clustered index. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Boletos_Cliente'
      AND object_id = OBJECT_ID('dbo.Boletos')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Boletos_Cliente
        ON dbo.Boletos (ClienteID)
        INCLUDE (ViajeID, NumeroAsiento, Precio, Estado, FechaVenta);
END;
GO

/* C3: recorrer solo boletos activos en orden de BoletoID.
   Ese orden permite el merge join con Pagos y evita leer
   las columnas anchas del clustered index de Boletos.
   FechaVenta va incluida para aplicar el rango de fechas. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Boletos_Activo_Boleto'
      AND object_id = OBJECT_ID('dbo.Boletos')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Boletos_Activo_Boleto
        ON dbo.Boletos (BoletoID)
        INCLUDE (FechaVenta, ViajeID)
        WHERE Estado = 'Activo';
END;
GO

/* C3 y sp_AnularBoleto: localizar los pagos de un boleto.
   Monto y Metodo se incluyen para el reporte y el reverso. */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = 'IX_Pagos_Boleto_Monto'
      AND object_id = OBJECT_ID('dbo.Pagos')
)
BEGIN
    CREATE NONCLUSTERED INDEX IX_Pagos_Boleto_Monto
        ON dbo.Pagos (BoletoID)
        INCLUDE (Monto, Metodo);
END;
GO

PRINT '=== E3.2 C1: asientos disponibles (viaje 15541) ===';
GO

SET STATISTICS IO ON;
SET STATISTICS TIME ON;
GO

DECLARE @ViajeID INT = 15541;

SELECT s.NumeroAsiento, s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = v.ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  )
ORDER BY s.NumeroAsiento
OPTION (RECOMPILE);
GO

PRINT '=== E3.2 C2: historial del cliente 1000 ===';
GO

DECLARE @Cedula CHAR(11) = '40200001000';

SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula
ORDER BY v.FechaSalida DESC
OPTION (RECOMPILE);
GO

PRINT '=== E3.2 C3: reporte mensual de ventas 2025 ===';
GO

SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.FechaVenta >= '2025-01-01'
  AND b.FechaVenta <  '2026-01-01'
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta)
ORDER BY r.Origen, r.Destino, Mes
OPTION (RECOMPILE);
GO

SET STATISTICS IO OFF;
SET STATISTICS TIME OFF;
GO

/* =========================================================
   E3.3 Comprobacion de equivalencia
   ---------------------------------------------------------
   Compara el resultado de la consulta original contra la
   optimizada. Las columnas SoloOriginal y SoloOptimizada
   deben ser 0 en las tres consultas.
   ========================================================= */
PRINT '=== E3.3 Equivalencia original vs optimizada ===';
GO

SET NOCOUNT ON;
GO

DECLARE @ViajeID INT = 15541;
DECLARE @Cedula CHAR(11) = '40200001000';

/* C1 original */
SELECT s.NumeroAsiento, s.Ubicacion
INTO #C1o
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND s.NumeroAsiento NOT IN (
      SELECT b.NumeroAsiento
      FROM dbo.Boletos b
      WHERE b.ViajeID = @ViajeID
        AND b.Estado = 'Activo'
  );

/* C1 optimizada */
SELECT s.NumeroAsiento, s.Ubicacion
INTO #C1n
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
WHERE v.ViajeID = @ViajeID
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = v.ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  );

/* C2 original */
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
INTO #C2o
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE LTRIM(RTRIM(c.Cedula)) = @Cedula;

/* C2 optimizada */
SELECT c.Nombre, c.Apellido, r.Origen, r.Destino,
       v.FechaSalida, b.NumeroAsiento, b.Precio, b.Estado
INTO #C2n
FROM dbo.Clientes c
JOIN dbo.Boletos b ON b.ClienteID = c.ClienteID
JOIN dbo.Viajes  v ON v.ViajeID   = b.ViajeID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE c.Cedula = @Cedula;

/* C3 original */
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
INTO #C3o
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE YEAR(b.FechaVenta) = 2025
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

/* C3 optimizada */
SELECT r.Origen, r.Destino, MONTH(b.FechaVenta) AS Mes,
       COUNT(*) AS Boletos, SUM(p.Monto) AS Ingresos
INTO #C3n
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.FechaVenta >= '2025-01-01'
  AND b.FechaVenta <  '2026-01-01'
  AND b.Estado = 'Activo'
GROUP BY r.Origen, r.Destino, MONTH(b.FechaVenta);

SELECT 'C1' AS Consulta,
       (SELECT COUNT(*) FROM #C1o) AS FilasOriginal,
       (SELECT COUNT(*) FROM #C1n) AS FilasOptimizada,
       (SELECT COUNT(*) FROM (SELECT * FROM #C1o EXCEPT SELECT * FROM #C1n) d) AS SoloOriginal,
       (SELECT COUNT(*) FROM (SELECT * FROM #C1n EXCEPT SELECT * FROM #C1o) d) AS SoloOptimizada
UNION ALL
SELECT 'C2',
       (SELECT COUNT(*) FROM #C2o),
       (SELECT COUNT(*) FROM #C2n),
       (SELECT COUNT(*) FROM (SELECT * FROM #C2o EXCEPT SELECT * FROM #C2n) d),
       (SELECT COUNT(*) FROM (SELECT * FROM #C2n EXCEPT SELECT * FROM #C2o) d)
UNION ALL
SELECT 'C3',
       (SELECT COUNT(*) FROM #C3o),
       (SELECT COUNT(*) FROM #C3n),
       (SELECT COUNT(*) FROM (SELECT * FROM #C3o EXCEPT SELECT * FROM #C3n) d),
       (SELECT COUNT(*) FROM (SELECT * FROM #C3n EXCEPT SELECT * FROM #C3o) d);

DROP TABLE #C1o, #C1n, #C2o, #C2n, #C3o, #C3n;
GO
