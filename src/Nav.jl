module Nav

using Graphs
using MetaGraphsNext
using GameBoy: Button, ButtonUp, ButtonRight, ButtonDown, ButtonLeft

struct Position
    location::UInt8
    x::UInt8
    y::UInt8

    Position(l, x, y) = new(l, x, y)
    Position(p) = new(p...)
end

@enum Direction Up Right Down Left

function asbutton(d::Direction)::Button
    if d == Up
        ButtonUp
    elseif d == Right
        ButtonRight
    elseif d == Down
        ButtonDown
    elseif d == Left
        ButtonLeft
    end
end

function asdirection(b::Button)::Direction
    if b == ButtonUp
        Up
    elseif b == ButtonRight
        Right
    elseif b == ButtonDown
        Down
    elseif b == ButtonLeft
        Left
    end
end

export Up, Right, Down, Left, asbutton, asdirection

# Using type parameters to elide the unimportant implementation details of MetaGraphNext.
# Vertex representation in DiGraph (aka "Code"), Weight Function, Weight.
const Navmesh{C, Wf, W} = MetaGraph{C, Graphs.SimpleGraphs.SimpleDiGraph{C}, Position, Nothing, Direction, Nothing, Wf, W}

function Navmesh()::Navmesh
    MetaGraph(DiGraph();
              vertex_data_type=Nothing,
              label_type=Position,
              edge_data_type=Direction)
end

function Navmesh!(n::Navmesh, from::Position, to::Position, d::Direction)::Nothing
    n[from] = nothing
    n[to] = nothing
    n[from, to] = d

    nothing
end

function Navmesh(a::Navmesh, b::Navmesh)::Navmesh
    n = Navmesh()

    for x in [a, b]
        for l in labels(x)
            n[l] = nothing
        end

        for el in edge_labels(x)
            n[el...] = x[el...]
        end
    end

    n
end

function route(n::Navmesh, from::Position, to::Position)::Vector{Direction}
    try
        Graphs.a_star(n,
                      code_for(n, from),
                      code_for(n, to)) |>
                          Base.Fix1(map, e -> n[label_for(n, e.src), label_for(n, e.dst)])
    catch e
        if isa(e, KeyError)
            return []
        else
            rethrow(e)
        end
    end
end

connected(n::Navmesh, from::Position, to::Position)::Bool = from == to || route(n, from, to) |> length > 0

# TODO: Render Navmesh as Matrix
# TODO: Render Navmesh as Ascii

export Navmesh, Direction, Position, route, connected, Navmesh!

end # module Nav