USE BusRD;
GO
/* E2.1 - sp_VenderBoleto_v0 sobre un asiento ya ocupado (viaje 15541, asiento 1) */
GO
EXEC dbo.sp_VenderBoleto_v0
     @ViajeID       = 15541,
     @NumeroAsiento = 1,
     @ClienteID     = 6000,
     @Canal         = 'Taquilla',
     @Metodo        = 'Efectivo';
GO
