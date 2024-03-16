using Documenter

@testset "Doctests" begin
    DocMeta.setdocmeta!(PokemonCartographer, :DocTestSetup, :(using PokemonCartographer, PokemonCartographer.Nav); recursive=true)
    doctest(PokemonCartographer; manual=false)
end