using Test
using SeniSienna

@testset "SeniSienna" begin
    # TODO Fase 1: tests del traductor con los datos en data/raw/
    #  - conteos de componentes vs resumen.csv
    #  - balance de capacidad MW por tecnología vs capa canónica MODOM
    #  - impedancias en pu dentro de rangos razonables
    @test isdefined(SeniSienna, :build_seni_system)
end
