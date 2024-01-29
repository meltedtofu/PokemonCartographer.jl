using PokemonCartographer.Nav

@testset "Navmesh" begin
    @testset "Basic" begin
        n = Navmesh()

        p1 = Position(0x01, 0x01, 0x01)
        p2 = Position(0x01, 0x01, 0x02)
        p3 = Position(0x01, 0x02, 0x02)
        Navmesh!(n, p1, p2, Down)
        Navmesh!(n, p2, p3, Right)

        @test [Down, Right] == route(n, p1, p3)

    end
end