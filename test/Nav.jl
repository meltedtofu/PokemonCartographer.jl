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
        @test [] == route(n, p3, p1)
    end

    @testset "Fully Connected Merged" begin
        n1 = Navmesh()
        n2 = Navmesh()

        p1 = Position(0x01, 0x01, 0x01)
        p2 = Position(0x01, 0x01, 0x02)
        p3 = Position(0x01, 0x02, 0x02)
        Navmesh!(n1, p1, p2, Down)
        Navmesh!(n1, p2, p3, Right)

        @test [Down, Right] == route(n1, p1, p3)

        p4 = Position(0x02, 0x01, 0x01)
        p5 = Position(0x02, 0x01, 0x02)
        p6 = Position(0x02, 0x02, 0x02)
        Navmesh!(n2, p4, p5, Down)
        Navmesh!(n2, p5, p6, Right)
        Navmesh!(n2, p3, p4, Up)

        @test [Down, Right] == route(n2, p4, p6)

        n = Navmesh(n1, n2)

        @test [] == route(n1, p1, p6)
        @test [] == route(n2, p1, p6)
        @test [Down, Right, Up, Down, Right] == route(n, p1, p6)
    end
end