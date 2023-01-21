module ChargerScale

using DataFrames

const PKG_DIR = abspath(joinpath(@__DIR__, ".."))

"""
    where(df, col1 => val1, col2 => val2,...; kwargs...)

Return a `subset(df, selectors....; kwargs...)` where `selectors` select rows such that
the value of `col1` is equal to `val1`, etc.
"""
where(df, items::Pair...; kwargs...) = subset(df, _selectors(items)...; kwargs...)

"""
    where!(df, col1 => val1, col2 => val2,...; kwargs...)

In-place version of [`where`](@ref)
"""
where!(df, items::Pair...; kwargs...) = subset!(df, _selectors(items)...; kwargs...)

function _selectors(items::NTuple{N, Pair}) where {N}
    selectors = Pair{String, Base.Callable}[]
    for (col, val) in items
        push!(selectors, string(col) => ByRow(==(val)))
    end
    return selectors
end

# Load Submodules
include("geo/Geo.jl")
include("parsers/Parsers.jl")
include("plots/Plots.jl")
include("latex.jl")
include("models/Models.jl")
include("dataset.jl")

end
