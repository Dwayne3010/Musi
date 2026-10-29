/* =========================================================
   BusRD - E4: Seguridad y minimo privilegio
   ---------------------------------------------------------
   Roles:
     rol_taquilla  -> EXECUTE sp_VenderBoleto / sp_AnularBoleto
                      SELECT vw_AsientosDisponibles
     rol_reportes  -> SELECT vw_VentasMensuales
     rol_admin     -> CONTROL de la base

   Usuarios de prueba sin login:
     usr_taquilla, usr_reportes, usr_admin

   Las vistas y los procedimientos son propiedad de dbo; el
   encadenamiento de propiedad (ownership chaining) permite
   operar sin conceder permisos directos sobre las tablas.
   ========================================================= */

USE BusRD;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   1. VISTAS
   ========================================================= */

/* Disponibilidad de asientos: no expone clientes ni pagos. */
CREATE OR ALTER VIEW dbo.vw_AsientosDisponibles
AS
SELECT v.ViajeID,
       v.FechaSalida,
       r.Origen,
       r.Destino,
       s.NumeroAsiento,
       s.Ubicacion
FROM dbo.Viajes v
JOIN dbo.Asientos s ON s.AutobusID = v.AutobusID
JOIN dbo.Rutas   r ON r.RutaID    = v.RutaID
WHERE v.Estado = 'Programado'
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = v.ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  );
GO

/* Reporte mensual agregado: no expone Email ni Telefono. */
CREATE OR ALTER VIEW dbo.vw_VentasMensuales
AS
SELECT YEAR(b.FechaVenta)  AS Anio,
       MONTH(b.FechaVenta) AS Mes,
       r.Origen,
       r.Destino,
       COUNT(*)            AS Boletos,
       SUM(p.Monto)        AS Ingresos
FROM dbo.Boletos b
JOIN dbo.Pagos  p ON p.BoletoID = b.BoletoID
JOIN dbo.Viajes v ON v.ViajeID  = b.ViajeID
JOIN dbo.Rutas  r ON r.RutaID   = v.RutaID
WHERE b.Estado = 'Activo'
GROUP BY YEAR(b.FechaVenta), MONTH(b.FechaVenta), r.Origen, r.Destino;
GO

/* =========================================================
   2. ROLES
   ========================================================= */
IF DATABASE_PRINCIPAL_ID('rol_taquilla') IS NULL
    CREATE ROLE rol_taquilla;

IF DATABASE_PRINCIPAL_ID('rol_reportes') IS NULL
    CREATE ROLE rol_reportes;

IF DATABASE_PRINCIPAL_ID('rol_admin') IS NULL
    CREATE ROLE rol_admin;
GO

/* =========================================================
   3. PERMISOS
   ========================================================= */

/* Taquilla: solo lo estrictamente necesario. */
GRANT SELECT  ON dbo.vw_AsientosDisponibles TO rol_taquilla;
GRANT EXECUTE ON dbo.sp_VenderBoleto          TO rol_taquilla;
GRANT EXECUTE ON dbo.sp_AnularBoleto          TO rol_taquilla;

/* Reportes: solo la vista agregada. */
GRANT SELECT ON dbo.vw_VentasMensuales TO rol_reportes;

/* Administracion completa de la base. */
GRANT CONTROL ON DATABASE::BusRD TO rol_admin;
GO

/* =========================================================
   4. USUARIOS DE PRUEBA
   ========================================================= */
IF DATABASE_PRINCIPAL_ID('usr_taquilla') IS NULL
    CREATE USER usr_taquilla WITHOUT LOGIN;

IF DATABASE_PRINCIPAL_ID('usr_reportes') IS NULL
    CREATE USER usr_reportes WITHOUT LOGIN;

IF DATABASE_PRINCIPAL_ID('usr_admin') IS NULL
    CREATE USER usr_admin WITHOUT LOGIN;
GO

IF IS_ROLEMEMBER('rol_taquilla', 'usr_taquilla') = 0
    ALTER ROLE rol_taquilla ADD MEMBER usr_taquilla;

IF IS_ROLEMEMBER('rol_reportes', 'usr_reportes') = 0
    ALTER ROLE rol_reportes ADD MEMBER usr_reportes;

IF IS_ROLEMEMBER('rol_admin', 'usr_admin') = 0
    ALTER ROLE rol_admin ADD MEMBER usr_admin;
GO

PRINT '=== E4: roles, usuarios, vistas y permisos creados ===';
GO
