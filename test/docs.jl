using Documenter

@testset "Doctests" begin
    DocMeta.setdocmeta!(PokemonCartographer, :DocTestSetup, :(using PokemonCartographer, PokemonCartographer.Nav, GameBoy); recursive=true)
    doctest(PokemonCartographer; manual=false)
end