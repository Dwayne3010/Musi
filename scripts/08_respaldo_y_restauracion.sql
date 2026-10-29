/* =========================================================
   BusRD - E5: Respaldo y recuperacion
   ---------------------------------------------------------
   Secuencia:
     1. Modelo FULL.
     2. Backup FULL.
     3. Vender 5 boletos.
     4. Backup DIFERENCIAL.
     5. Vender 3 boletos.
     6. Backup de LOG y hora exacta de corte.
     7. DELETE de todos los boletos del viaje asignado.
     8. Backup de LOG de cola (NO_TRUNCATE).
     9. Restaurar BusRD_Recuperada con STOPAT antes del DELETE.
    10. Restaurar BusRD al mismo punto para dejar la base operable.
    11. Politica de respaldos propuesta.

   Los archivos se guardan en C:\Backups\BusRD\.
   ========================================================= */

USE master;
GO

/* Opciones requeridas por los indices filtrados de BusRD */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
GO

/* Carpeta de respaldos */
EXEC master.dbo.xp_create_subdir 'C:\Backups\BusRD';
GO

/* Modelo FULL: permite backups de log y recuperacion a un punto
   en el tiempo (STOPAT). SIMPLE trunca el log y no lo permite. */
ALTER DATABASE BusRD SET RECOVERY FULL;
GO

USE BusRD;
GO

/* Limpieza de tablas auxiliares de la demo */
IF OBJECT_ID('dbo.E5_BoletosVendidos', 'U') IS NOT NULL DROP TABLE dbo.E5_BoletosVendidos;
IF OBJECT_ID('dbo.E5_Control', 'U') IS NOT NULL DROP TABLE dbo.E5_Control;

CREATE TABLE dbo.E5_BoletosVendidos (
    BoletoID    INT PRIMARY KEY,
    Fase        VARCHAR(10) NOT NULL,
    FechaVenta  DATETIME2(0) NOT NULL DEFAULT SYSDATETIME()
);

CREATE TABLE dbo.E5_Control (
    Id             INT PRIMARY KEY,
    BoletosAntes   INT NULL,
    PagosAntes     INT NULL,
    FechaCorte     DATETIME2(3) NULL
);

INSERT INTO dbo.E5_Control (Id) VALUES (1);
GO

/* =========================================================
   1. BACKUP FULL
   ========================================================= */
BACKUP DATABASE BusRD
TO DISK = 'C:\Backups\BusRD\E5_FULL.bak'
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
GO

/* =========================================================
   2. VENDER 5 BOLETOS
   ========================================================= */
USE BusRD;
GO

DECLARE @ViajeID INT = 15541;
DECLARE @ClienteID INT = 1000;
DECLARE @i INT = 1;
DECLARE @Asiento INT;
DECLARE @BoletoID INT;

IF OBJECT_ID('tempdb..#AsientosLibres') IS NOT NULL DROP TABLE #AsientosLibres;

SELECT TOP (8)
       ROW_NUMBER() OVER (ORDER BY s.NumeroAsiento) AS rn,
       s.NumeroAsiento
INTO #AsientosLibres
FROM dbo.Asientos s
WHERE s.AutobusID = (SELECT AutobusID FROM dbo.Viajes WHERE ViajeID = @ViajeID)
  AND NOT EXISTS (
      SELECT 1
      FROM dbo.Boletos b
      WHERE b.ViajeID = @ViajeID
        AND b.NumeroAsiento = s.NumeroAsiento
        AND b.Estado = 'Activo'
  )
ORDER BY s.NumeroAsiento;

WHILE @i <= 5
BEGIN
    SELECT @Asiento = NumeroAsiento FROM #AsientosLibres WHERE rn = @i;

    EXEC dbo.sp_VenderBoleto
        @ViajeID = @ViajeID,
        @NumeroAsiento = @Asiento,
        @ClienteID = @ClienteID,
        @Canal = 'Web',
        @Metodo = 'Tarjeta',
        @BoletoID = @BoletoID OUTPUT,
        @SimularDemora = 0;

    INSERT INTO dbo.E5_BoletosVendidos (BoletoID, Fase)
    VALUES (@BoletoID, 'Fase1');

    SET @i = @i + 1;
END;

SELECT BoletoID, Fase, FechaVenta
FROM dbo.E5_BoletosVendidos
ORDER BY BoletoID;
GO

/* =========================================================
   3. BACKUP DIFERENCIAL
   ========================================================= */
BACKUP DATABASE BusRD
TO DISK = 'C:\Backups\BusRD\E5_DIFF.bak'
WITH DIFFERENTIAL, INIT, COMPRESSION, CHECKSUM, STATS = 10;
GO

/* =========================================================
   4. VENDER 3 BOLETOS
   ========================================================= */
USE BusRD;
GO

DECLARE @ViajeID INT = 15541;
DECLARE @ClienteID INT = 1000;
DECLARE @i INT = 6;
DECLARE @Asiento INT;
DECLARE @BoletoID INT;

WHILE @i <= 8
BEGIN
    SELECT @Asiento = NumeroAsiento FROM #AsientosLibres WHERE rn = @i;

    EXEC dbo.sp_VenderBoleto
        @ViajeID = @ViajeID,
        @NumeroAsiento = @Asiento,
        @ClienteID = @ClienteID,
        @Canal = 'Taquilla',
        @Metodo = 'Efectivo',
        @BoletoID = @BoletoID OUTPUT,
        @SimularDemora = 0;

    INSERT INTO dbo.E5_BoletosVendidos (BoletoID, Fase)
    VALUES (@BoletoID, 'Fase2');

    SET @i = @i + 1;
END;

SELECT BoletoID, Fase, FechaVenta
FROM dbo.E5_BoletosVendidos
ORDER BY BoletoID;
GO

/* =========================================================
   5. BACKUP DE LOG Y HORA DE CORTE
   ========================================================= */
USE BusRD;
GO

UPDATE dbo.E5_Control
SET BoletosAntes = (SELECT COUNT(*) FROM dbo.Boletos WHERE ViajeID = 15541),
    PagosAntes   = (SELECT COUNT(*) FROM dbo.Pagos p
                    JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
                    WHERE b.ViajeID = 15541)
WHERE Id = 1;

BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD\E5_LOG1.trn'
WITH INIT, COMPRESSION, CHECKSUM, STATS = 10;
GO

USE BusRD;
GO

/* La hora de corte se toma DESPUES del backup de log y ANTES
   del DELETE. El log de cola contendra el DELETE. */
UPDATE dbo.E5_Control SET FechaCorte = SYSDATETIME() WHERE Id = 1;

DECLARE @FechaCorte DATETIME2(3) = (SELECT FechaCorte FROM dbo.E5_Control WHERE Id = 1);
SELECT @FechaCorte AS HoraCorte,
       (SELECT BoletosAntes FROM dbo.E5_Control WHERE Id = 1) AS BoletosAntes,
       (SELECT PagosAntes   FROM dbo.E5_Control WHERE Id = 1) AS PagosAntes;

WAITFOR DELAY '00:00:02';

/* Error simulado: se borran todos los boletos del viaje asignado.
   Primero los pagos por la llave foranea FK_Pagos_Boletos. */
DELETE p
FROM dbo.Pagos p
JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.ViajeID = 15541;

DELETE FROM dbo.Boletos WHERE ViajeID = 15541;

SELECT COUNT(*) AS BoletosDespuesDelDelete FROM dbo.Boletos WHERE ViajeID = 15541;
GO

/* =========================================================
   6. BACKUP DE LOG DE COLA
   ========================================================= */
BACKUP LOG BusRD
TO DISK = 'C:\Backups\BusRD\E5_TAIL.trn'
WITH NO_TRUNCATE, INIT, COMPRESSION, CHECKSUM, STATS = 10;
GO

/* =========================================================
   7. RESTAURAR BusRD_Recuperada CON STOPAT
   ========================================================= */
USE master;
GO

DECLARE @FechaCorte DATETIME2(3) = (SELECT FechaCorte FROM BusRD.dbo.E5_Control WHERE Id = 1);
/* STOPAT 1 s despues de la actualizacion: incluye FechaCorte y
   excluye el DELETE, que ocurre 2 s despues. */
DECLARE @StopTime DATETIME2(3) = DATEADD(SECOND, 1, @FechaCorte);
DECLARE @StopStr VARCHAR(30) = CONVERT(VARCHAR(23), @StopTime, 126);
DECLARE @Sql NVARCHAR(MAX);

PRINT 'Restaurando BusRD_Recuperada hasta: ' + @StopStr;

IF DB_ID('BusRD_Recuperada') IS NOT NULL
BEGIN
    ALTER DATABASE BusRD_Recuperada SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE BusRD_Recuperada;
END;

RESTORE DATABASE BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\E5_FULL.bak'
WITH MOVE 'BusRD' TO 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\BusRD_Recuperada.mdf',
     MOVE 'BusRD_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\BusRD_Recuperada_log.ldf',
     NORECOVERY, REPLACE, STATS = 10;

RESTORE DATABASE BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\E5_DIFF.bak'
WITH NORECOVERY, STATS = 10;

RESTORE LOG BusRD_Recuperada
FROM DISK = 'C:\Backups\BusRD\E5_LOG1.trn'
WITH NORECOVERY, STATS = 10;

SET @Sql = N'RESTORE LOG BusRD_Recuperada FROM DISK = ''C:\Backups\BusRD\E5_TAIL.trn'' '
         + N'WITH STOPAT = ''' + @StopStr + ''', RECOVERY, STATS = 10;';
EXEC sys.sp_executesql @Sql;
GO

/* Verificacion en la base recuperada */
USE BusRD_Recuperada;
GO

SELECT 'BusRD_Recuperada' AS Base,
       COUNT(*) AS BoletosViaje
FROM dbo.Boletos
WHERE ViajeID = 15541;

SELECT COUNT(*) AS PagosViaje
FROM dbo.Pagos p
JOIN dbo.Boletos b ON b.BoletoID = p.BoletoID
WHERE b.ViajeID = 15541;

SELECT c.BoletosAntes, c.PagosAntes, c.FechaCorte
FROM dbo.E5_Control c
WHERE c.Id = 1;

SELECT v.BoletoID, v.Fase, b.NumeroAsiento, b.Estado, b.Precio
FROM dbo.E5_BoletosVendidos v
LEFT JOIN dbo.Boletos b ON b.BoletoID = v.BoletoID
ORDER BY v.BoletoID;
GO

/* =========================================================
   8. RESTAURAR BusRD AL MISMO PUNTO
   ---------------------------------------------------------
   Se deja BusRD operable y sin el DELETE simulado. Esta
   restauracion requiere SINGLE_USER porque reemplaza la base.
   ========================================================= */
USE master;
GO

DECLARE @FechaCorte DATETIME2(3) = (SELECT FechaCorte FROM BusRD.dbo.E5_Control WHERE Id = 1);
/* STOPAT 1 s despues de la actualizacion: incluye FechaCorte y
   excluye el DELETE, que ocurre 2 s despues. */
DECLARE @StopTime DATETIME2(3) = DATEADD(SECOND, 1, @FechaCorte);
DECLARE @StopStr VARCHAR(30) = CONVERT(VARCHAR(23), @StopTime, 126);
DECLARE @Sql NVARCHAR(MAX);

PRINT 'Restaurando BusRD hasta: ' + @StopStr;

ALTER DATABASE BusRD SET SINGLE_USER WITH ROLLBACK IMMEDIATE;

RESTORE DATABASE BusRD
FROM DISK = 'C:\Backups\BusRD\E5_FULL.bak'
WITH MOVE 'BusRD' TO 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\BusRD.mdf',
     MOVE 'BusRD_log' TO 'C:\Program Files\Microsoft SQL Server\MSSQL17.MSSQLSERVER\MSSQL\DATA\BusRD_log.ldf',
     NORECOVERY, REPLACE, STATS = 10;

RESTORE DATABASE BusRD
FROM DISK = 'C:\Backups\BusRD\E5_DIFF.bak'
WITH NORECOVERY, STATS = 10;

RESTORE LOG BusRD
FROM DISK = 'C:\Backups\BusRD\E5_LOG1.trn'
WITH NORECOVERY, STATS = 10;

SET @Sql = N'RESTORE LOG BusRD FROM DISK = ''C:\Backups\BusRD\E5_TAIL.trn'' '
         + N'WITH STOPAT = ''' + @StopStr + ''', RECOVERY, STATS = 10;';
EXEC sys.sp_executesql @Sql;

ALTER DATABASE BusRD SET MULTI_USER;
GO

USE BusRD;
GO

SELECT 'BusRD' AS Base, COUNT(*) AS BoletosViaje
FROM dbo.Boletos
WHERE ViajeID = 15541;

SELECT COUNT(*) AS BoletosVendidosRecuperados
FROM dbo.E5_BoletosVendidos v
JOIN dbo.Boletos b ON b.BoletoID = v.BoletoID
WHERE b.Estado = 'Activo';
GO

/* =========================================================
   9. POLITICA DE RESPALDOS PROPUESTA
   ========================================================= */
IF OBJECT_ID('dbo.PoliticaRespaldo', 'U') IS NOT NULL DROP TABLE dbo.PoliticaRespaldo;

CREATE TABLE dbo.PoliticaRespaldo (
    Tipo          VARCHAR(20)  NOT NULL PRIMARY KEY,
    Frecuencia    VARCHAR(60)  NOT NULL,
    Retencion     VARCHAR(60)  NOT NULL,
    Justificacion VARCHAR(250) NOT NULL
);

INSERT INTO dbo.PoliticaRespaldo (Tipo, Frecuencia, Retencion, Justificacion) VALUES
('FULL',        'Diario a las 02:00',                          '30 dias',  'Base de la cadena; permite recuperar la base completa.'),
('DIFERENCIAL', 'Cada 6 horas (06:00, 12:00, 18:00, 00:00)',   '7 dias',   'Reduce el tiempo de restauracion sin respaldar todo el log.'),
('LOG',         'Cada 15 minutos',                             '7 dias',   'RPO de 15 minutos; permite STOPAT ante borrados o errores.'),
('FULL mensual','Primer dia del mes a las 02:00',              '12 meses', 'Retencion historica y recuperacion ante fallas prolongadas.'),
('LOG de cola', 'Bajo demanda ante un incidente',               'Hasta recuperar', 'Captura los ultimos cambios cuando la base sigue en linea.');

SELECT Tipo, Frecuencia, Retencion, Justificacion
FROM dbo.PoliticaRespaldo
ORDER BY CASE Tipo WHEN 'FULL' THEN 1 WHEN 'DIFERENCIAL' THEN 2 WHEN 'LOG' THEN 3 WHEN 'FULL mensual' THEN 4 ELSE 5 END;
GO
