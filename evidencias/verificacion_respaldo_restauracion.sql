USE BusRD;
GO
SET NOCOUNT ON;
GO

/* =========================================================
   Verificacion E5: respaldo / restauracion con STOPAT
   Se ejecuta con BusRD en el estado posterior al DELETE
   simulado y BusRD_Recuperada restaurada antes del DELETE.
   ========================================================= */

DECLARE @EsperadoVendidos INT = 8;
DECLARE @ObtenidoVendidos INT;
DECLARE @ObtenidoViaje    INT;
DECLARE @ObtenidoPagos    INT;
DECLARE @ObtenidoBusRD    INT;

SELECT @ObtenidoVendidos = COUNT(*)
FROM BusRD_Recuperada.dbo.Boletos b
JOIN dbo.E5_BoletosVendidos v ON v.BoletoID = b.BoletoID
WHERE b.Estado = 'Activo';

SELECT @ObtenidoViaje = COUNT(*)
FROM BusRD_Recuperada.dbo.Boletos b
JOIN dbo.E5_BoletosVendidos v ON v.BoletoID = b.BoletoID
WHERE b.ViajeID = 15541
  AND b.Estado = 'Activo';

SELECT @ObtenidoPagos = COUNT(*)
FROM BusRD_Recuperada.dbo.Pagos p
JOIN dbo.E5_BoletosVendidos v ON v.BoletoID = p.BoletoID;

SELECT @ObtenidoBusRD = COUNT(*)
FROM dbo.Boletos
WHERE ViajeID = 15541;

SELECT Verificacion, Obtenido, Esperado,
       CASE WHEN Obtenido = Esperado THEN 'OK' ELSE 'FALLO' END AS Resultado
FROM (
    SELECT 1 AS Orden,
           'Boletos vendidos presentes en BusRD_Recuperada (esperado 8)' AS Verificacion,
           @ObtenidoVendidos AS Obtenido,
           @EsperadoVendidos AS Esperado
    UNION ALL
    SELECT 2,
           'Boletos vendidos del viaje asignado en BusRD_Recuperada',
           @ObtenidoViaje,
           @EsperadoVendidos
    UNION ALL
    SELECT 3,
           'Pagos de esos boletos en BusRD_Recuperada',
           @ObtenidoPagos,
           @EsperadoVendidos
    UNION ALL
    SELECT 4,
           'Boletos del viaje asignado en BusRD (siguen borrados)',
           @ObtenidoBusRD,
           0
) t
ORDER BY Orden;
GO
