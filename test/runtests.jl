using Test
using PowerSystems
using SeniSienna

raw_dir = joinpath(@__DIR__, "..", "data", "raw")

@testset "SeniSienna" begin
    @test isdefined(SeniSienna, :build_seni_dispatch_system)

    if isdir(joinpath(raw_dir, "processed"))
        sys = build_seni_dispatch_system(raw_dir)

        @testset "conteos vs capa canónica" begin
            @test length(get_components(ACBus, sys)) == 717
            n_gens = length(get_components(ThermalStandard, sys)) +
                     length(get_components(HydroDispatch, sys)) +
                     length(get_components(RenewableDispatch, sys))
            @test n_gens >= 130   # 140 canónicos menos omitidos por bus faltante
            @test length(get_components(PowerLoad, sys)) > 100
            @test length(get_components(TransmissionInterface, sys)) >= 2
        end

        @testset "referencia y series" begin
            refs = [b for b in get_components(ACBus, sys) if get_bustype(b) == ACBusTypes.REF]
            @test length(refs) == 1
            loads = collect(get_components(PowerLoad, sys))
            @test has_time_series(first(loads))
        end
    else
        @info "data/raw/processed no disponible; solo tests estructurales"
    end
end
