using PokemonCartographer.Render: BoundingBox, width, height, expand
using Luxor: Point
using Supposition, Supposition.Data

@testset "Render" begin
    @testset "BoundingBox" begin
        @testset "Size" begin
            bb1 = BoundingBox(0, 1, 3, 7)
            bb2 = BoundingBox(99, 132, 12345, 76543)

            @test width(bb1) == 6
            @test height(bb1) == 3

            @test width(bb2) == 76411
            @test height(bb2) == 12246
        end

        @testset "expand" begin
            numbers = Data.Integers{Int}()
            point = @composed function point_(x=numbers, y=numbers)
                Point(x, y)
            end
            
            points = Data.Vectors(point; min_size=1, max_size=5_678)

            # Theoretically in Julia 1.11 Supposition directly integrates with Test. Doing this dance for now.
            result = Supposition.results(@check function contained(ps=points)
                bb = BoundingBox(0, 0, 0, 0)
                for p in ps
                    bb = expand(bb, p)
                end
                
                c = true
                for p in ps
                    c = c && p.x >= bb.left && p.x <= bb.right && p.y >= bb.top && p.y <= bb.bottom
                end
                c
            end)

            @test result.ispass == true
        end
    end
end