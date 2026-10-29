# Guía de capturas de pantalla - BusRD

Las capturas deben numerarse igual que la tabla de evidencias de `README.md` e
`INFORME.md`. Guardarlas en `evidencias/capturas/` con el nombre sugerido.

| # | Captura sugerida | Qué mostrar |
|---|---|---|
| 01 | `01_e1_deteccion.png` | Resultado de la detección de E1: 61 grupos / 122 boletos (incluye el duplicado 232116/232117 de la demo E2.1; la data original tenía 60/120) y 15 pagos huérfanos; luego 0 duplicados y 0 huérfanos. Abrir `evidencias/e1_deteccion_y_estado.log` o ejecutar la sección de detección de `01_integridad.sql`. |
| 02 | `02_e2_v0_sesionA.png` | `evidencias/e2_v0_demo_sesionA.log`: sesión A inicia 21:27:57.355 y termina 21:28:07.381 con el boleto 232150. |
| 03 | `03_e2_v0_sesionB.png` | `evidencias/e2_v0_demo_sesionB.log`: sesión B inicia 21:27:59.515 y termina 21:27:59.526 con el boleto 232149. |
| 04 | `04_e2_v0_resultado.png` | `evidencias/e2_v0_resultado.log`: dos boletos activos (232149 y 232150), dos pagos de $420.00 y `BoletosActivos = 2`. |
| 05 | `05_e2_v0_script.png` | `evidencias/e2_v0_reproduccion.sql` en SSMS, mostrando el `DROP INDEX` del índice único y el `sp_VenderBoleto_v0` sin bloqueo. |
| 06 | `06_e2_demo_sesionA.png` | Ventana A de SSMS ejecutando `04_demo_concurrencia_sesionA.sql` en la revalidación: inicio 21:44:41.638 y fin 21:44:51.652 con el boleto 232150. La corrida original está en `evidencias/e2_demo_sesionA.log` (boleto 232148). |
| 07 | `07_e2_demo_sesionB.png` | Ventana B ejecutando `05_demo_concurrencia_sesionB.sql`: inicio 21:44:44.353, rechazo con error 51006 "El asiento ya esta vendido." a las 21:44:51.652 y `BoletosActivos = 1`. |
| 08 | `08_e3_baseline_C1.png` | Plan de `evidencias/e3_baseline/sin_indices/baseline_C1.sqlplan` abierto en SSMS con zoom para ajustar: `Clustered Index Scan` sobre `Boletos` (87 %) y advertencia de índice faltante. La salida de `baseline_C1.log` registra 1.774 lecturas lógicas (Boletos 1.677 + Worktable 93 + Asientos 2 + Viajes 2). |
| 09 | `09_e3_optimizado_C1.png` | Plan de `evidencias/e3_optimizado/optimizado_C1.sqlplan` abierto en SSMS con zoom para ajustar: `Index Seek` sobre `UX_Boletos_Viaje_Asiento` y `Merge Join`. La salida de `optimizado_C1.log` registra 7 lecturas lógicas (Boletos 3 + Asientos 2 + Viajes 2). |
| 10 | `10_e3_equivalencia.png` | Salida de `evidencias/e3_script_completo.log`: C1 40/40, C2 11/11, C3 240/240, 0 diferencias. |
| 11 | `11_e4_taquilla.png` | `EXECUTE AS USER = 'usr_taquilla'`: `SELECT` a `vw_AsientosDisponibles` permitido; `SELECT` a `dbo.Boletos` denegado con error 229. |
| 12 | `12_e4_taquilla_anulacion.png` | `EXEC sp_AnularBoleto` permitido y reverso de -$420.00; evidencia `e4_pruebas_taquilla_anulacion.log`. |
| 13 | `13_e4_reportes.png` | `usr_reportes`: `SELECT` a `vw_VentasMensuales` permitido; `SELECT` a `dbo.Clientes` denegado con error 229. |
| 14 | `14_e4_admin.png` | `usr_admin`: `SELECT` a `dbo.Clientes` (incluye Email/Telefono) y `CREATE TABLE`/`DROP TABLE` permitidos. |
| 15 | `15_e5_stopat.png` | Revalidación en SSMS de E5: `BusRD` y `BusRD_Recuperada` con 42 boletos / 48 pagos; `stop_at = 2026-10-27 21:53:04.397` y `FechaCorte = 21:53:03.398`. La evidencia primaria es `evidencias/e5_script_completo.log` (33/38). |
| 16 | `16_e2_v0_asiento_ocupado.png` | Rechazo del `sp_VenderBoleto_v0` original al vender un asiento ya ocupado (error 50000, línea 17). Log: `evidencias/e2_v0_asiento_ocupado.log`. |
| — | `prueba_de_procedimientos_nuevo.png` | Prueba de los procedimientos nuevos: venta OK (boleto 231506), reintento rechazado con 51006, anulación con reverso +550.00 / -550.00 y asiento 1 libre. Log: `evidencias/prueba_procedimientos_nuevo.log`. |
| — | `verificacion_respaldo_restauracion.png` | Verificación E5 de respaldo/restauración: 8/8 boletos vendidos, 8/8 en el viaje 15541, 8/8 pagos y 0/0 boletos en `BusRD` tras el DELETE simulado. Log: `evidencias/verificacion_respaldo_restauracion.log`. |

> Las capturas 06, 07 y 15 corresponden a la revalidación en vivo en SSMS sobre
> el estado previo a la entrega. La corrida original de E2.4 y E5 está documentada
> en los logs `e2_demo_sesion*.log` y `e5_script_completo.log`; las capturas son
> evidencia complementaria.

Las capturas 08 y 09 se generaron el 27/10/2026 desde los archivos `.sqlplan`
con SSMS 22, cerrando el Explorador de objetos y aplicando **Zoom para ajustar**
en el plan. Los porcentajes de costo y las lecturas lógicas provienen de los
respectivos logs de `SET STATISTICS IO`.

## Cómo abrir los planes

En SSMS: **Archivo → Abrir → Archivo**, seleccionar el `.sqlplan`. También se
puede hacer clic derecho sobre el plan guardado y elegir **Abrir**. Para que la
captura muestre el plan completo, hacer clic derecho en un espacio vacío del plan
y elegir **Zoom para ajustar**; también se puede usar **Zoom personalizado** para
ampliar una zona concreta.

## Nota sobre los logs

Los archivos `.log` son texto plano; se pueden abrir en SSMS con **Archivo →
Abrir → Archivo** o en cualquier editor. Para una captura más legible, abrir el
log en SSMS y usar una fuente monoespaciada.
