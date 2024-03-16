using JET

@testset "Types" begin
   @testset "JET" begin
       test_package("PokemonCartographer"; target_defined_modules=true)
   end
end