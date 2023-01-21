module Plots

using ..ChargerScale
using DataFrames
using Dates
using GeoMakie
using Makie
using StatsBase
using GLM
using Printf
using ColorSchemes
using LibGEOS

import Makie: Axis, Point2f0, linesegments!

Makie.inverse_transform(::typeof(asinh)) = sinh
Makie.inverse_transform(::typeof(sinh)) = asinh

include("plot_recipes.jl")
include("plot_theme.jl")
include("power_model.jl")

end
