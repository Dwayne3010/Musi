Trabajo Final de Taller de Base de Datos III. Diagnóstico y corrección de la base de datos de **BusRD**.

---

## Integrantes

| Nombre | Matrícula |
| :--- | :--- |
| **Dwayne Alcequiez Montan** | A00148694 |
| **Fraybel Johan Beltre De Los Santos** | A00150546 |
| **Reymond Jimenez** | A00143872 |
| **Saul Ozuna Gerardo** | A00162333 |

---

## Datos asignados al grupo

| Dato | Valor |
| :--- | :--- |
| **Número de grupo** | 1 |
| **Cliente para la consulta C2 (grupo × 1000)** | 1000 |
| **Cédula del cliente 1000** | `40200001000` |
| **Viaje asignado (C1 y borrado de E5)** | `15541` |

---

## Entorno

- **Motor y cliente:** SQL Server 2022 (Developer o Express) y SQL Server Management Studio (SSMS).
- **Carpeta de respaldos:** `C:\Backups\BusRD\` (SQL Server corre en la misma máquina).

---

## Orden de Ejecución

Cada script está enumerado de acuerdo a su orden de ejecución:

1. **`00_setup_BusRD.sql`** — Creación de la base de datos y carga inicial (con corrección del literal `DATETIME2`).
2. **`01_integridad_E1.sql`** — Detección y limpieza de datos sucios, creación de llaves foráneas, `CHECK` e índice único filtrado `UX_Boletos_Viaje_Asiento_Activo`.
3. **`02_sp_VenderBoleto_E2.sql`** — Creación del procedimiento transaccional `dbo.sp_VenderBoleto` con `UPDLOCK, HOLDLOCK`.
4. **`03_sp_AnularBoleto_E2.sql`** — Creación del procedimiento `dbo.sp_AnularBoleto` con reverso contable.
5. **`04_demo_concurrencia_sesionA.sql`** y **`05_demo_concurrencia_sesionB.sql`** — Demostración de concurrencia en dos ventanas de SSMS (`@SimularDemora = 1`).
6. **`06_indices_y_consultas_E3.sql`** — Creación de índices secundarios y consultas optimizadas (`C1`, `C2`, `C3`).
7. **`07_seguridad_roles_E4.sql`** — Creación de roles (`rol_taquilla`, `rol_reportes`, `rol_admin`), vistas y pruebas de permisos con `EXECUTE AS USER`.
8. **`08_respaldo_y_recuperacion_E5.sql`** — Secuencia de respaldos (`FULL`, `DIFF`, `LOG1`, `TAIL`) y restauración `STOPAT` en `BusRD_Recuperada`.

> **Importante:** El script `(01_x2venta_sp_VenderBoleto_ejecutar_al_final_como_demo.sql)` solo se ejecuta correctamente como demo luego de correr todos los scripts. Igual aquellos que tienen `(test)` en el nombre deben ser ejecutados luego del *main script* correspondiente a su número.

---

## Estructura del Repositorio

```text
BusRD-Grupo-1/
├── README.md
├── scripts/
│   ├── 00_setup_BusRD.sql
│   ├── 01_integridad_E1.sql
│   ├── 01_x2venta_sp_VenderBoleto_ejecutar_al_final_como_demo.sql
│   ├── 02_sp_VenderBoleto_E2.sql
│   ├── 03_sp_AnularBoleto_E2.sql
│   ├── 04_demo_concurrencia_sesionA.sql
│   ├── 05_demo_concurrencia_sesionB.sql
│   ├── 06_indices_y_consultas_E3.sql
│   ├── 07_seguridad_roles_E4.sql
│   └── 08_respaldo_y_recuperacion_E5.sql
└── evidencias/
    ├── 06_e2_demo_sesionA.png
    ├── 07_e2_demo_sesionB.png
    ├── 08_e3_baseline_C1.png
    ├── 09_e3_optimizado_C1.png
    ├── 15_e5_stopat.png
    ├── 16_e2_v0_asiento_ocupado.png
    ├── prueba_de_procedimientos_nuevo.png
    └── verificacion_respaldo_restauracion.png
```readme_busrd_grupo_1.md…]()
