module Geo

using ArchGDAL
using LibGEOS
using Distances
using DataFrames
using StaticArrays
import Shapefile
using NearestNeighbors
import GeoInterface
import GeoJSON

include("geocode.jl")

end
