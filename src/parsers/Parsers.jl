module Parsers

using ChargerScale
using CSV
using DataFrames
using Dates
using ..Geo
using Polyester
using Impute
using Shapefile
using StringDistances
using Interpolations
using Statistics

""" Parse FIPS codes as Strings or `(Int, Int)` to `Int`` """
fips(state::Vector, county::Vector) = fips.(state, county)
fips(state::Real, county::Real) = Int(1000*state + county)
function fips(state::AbstractString, county::AbstractString)
    fips(Base.parse(Int, state), Base.parse(Int, county))
end
fips(s::S) where {S <: AbstractString} = fips(Base.tryparse(Int, s))
fips(s::Union{Integer, Nothing, Missing}) = s

""" Split FIPS codes into State and County codes """
fips_split(x::Integer) = divrem(x, 1000)

include(joinpath(@__DIR__, "FixedWidthData.jl"))
using .FixedWidthData

include("bls.jl")
include("census.jl")
include("nrel.jl")
include("atlas.jl")
include("registration.jl")

end
