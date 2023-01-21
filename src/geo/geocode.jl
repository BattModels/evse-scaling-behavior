
struct RevGeocoder{T,R,K,M}
    regions::Vector{R}
    data::Vector{T}
    tree::K
    metric::M
end

function RevGeocoder(regions, data, internal; metric=Haversine())
    tree = BallTree(internal, metric)
    return RevGeocoder(regions, data, tree, metric)
end

(rg::RevGeocoder)(longitude, latitude; n=100) = rg(longitude, latitude, n)

function (rg::RevGeocoder{T})(longitude::Vector, latitude::Vector, n::Int) where T
    @assert length(longitude) == length(latitude)
    val = Vector{T}(undef, length(longitude))
    error = similar(longitude)
    Threads.@threads for i in eachindex(longitude)
        val[i], error[i] = rg(longitude[i], latitude[i], n)
    end
    return val, error
end

function (rg::RevGeocoder)(longitude::T, latitude::T, n::Int) where {T <: Real}
    loc = SVector{2, T}(longitude, latitude)
    rg(loc, n)
end

function (rg::RevGeocoder)(loc::SVector{2, T}, n) where {T}
    candidates, _ = knn(rg.tree, loc, n, true)

    # Create a point for the query point and unpack RevGeocoder
    pnt = LibGEOS.Point(loc[1], loc[2])
    (; regions, data, metric) = rg

    # Loop over candidate locations until we find one that contains loc
    best_guess = zero(T)
    best_dist = Inf
    i = 0
    for candidate in candidates
        region = regions[candidate]
        if LibGEOS.within(pnt, region)
            # If we found a region that contains loc, return it
            return data[candidate], zero(T)
        else
            # Compute the distance to the region
            nr = first(LibGEOS.nearestPoints(region, pnt))
            ref_point = SVector{2}(GeoInterface.coordinates(nr))
            cur_dist = metric(ref_point, loc)

            # Update the best guess if this is the closest point
            if cur_dist < best_dist
                best_guess = candidate
                best_dist = cur_dist
            end
        end
    end

    # Return the best guess
    @assert best_guess != 0
    return data[best_guess], best_dist
end

function RevGeocoder(filename::String; metric=Haversine())
    df = import_shapefile(filename)

    # Trim to the relevant columns
    select!(df, :geometry, :INTPTLON, :INTPTLAT, :GEOID)

    # Split into Polygons and multipolygons
    transform!(df, :geometry => ByRow(Base.Fix2(isa, MultiPolygon)) => :multi)
    df_multi = subset(df, :multi)
    subset!(df, :multi => ByRow(!))
    select!(df, Not(:multi))

    # Convert multipolygons to polygons
    for i in 1:nrow(df_multi)
        row = df_multi[i, :]
        geom = row.geometry.ptr::Core.Ptr{Core.Nothing}
        n = LibGEOS.numGeometries(geom)
        for j in 1:n
            # Split the multipolygon into individual polygons
            poly = LibGEOS.Polygon(LibGEOS.getGeometry(geom, j))

            # Compute a new internal point for the polygon
            inner = LibGEOS.pointOnSurface(poly)
            inner_cords = GeoInterface.coordinates(inner)

            # Add the polygon to the dataframe
            push!(df, (poly, inner_cords[1], inner_cords[2], row.GEOID))
        end
    end

    # Construct RevGeocoder
    internal = select(df, [:INTPTLON, :INTPTLAT] => ByRow(SVector{2, Float64}))[!, 1]
    data = df[!, :GEOID]::Vector{Int}
    return RevGeocoder(df.geometry, data, internal; metric)
end

_expand_multipolygon(p::Polygon, args...) = (p, args...)
function _expand_multipolygon(p::MultiPolygon, args...)
    n_geom = LibGEOS.numGeometries(p.ptr)
    df = DataFrame(p, args...)
    for i in 1:n_geom
        geom = LibGEOS.getGeometry(p.ptr, i)
    end
    return df
end

function import_shapefile(filename::String)
    # Load boundaries from shapefile
    shp = ArchGDAL.read(filename)
    df_shp = DataFrame(ArchGDAL.getlayer(shp, 0))
    transform!(df_shp, 1 => ByRow(x -> readgeom(ArchGDAL.toWKB(x))), renamecols=false)
    rename!(df_shp, 1 => :geometry)

    colnames = names(df_shp)
    for (field, T) in [("STATEFP", Int), ("COUNTYFP", Int), ("GEOID", Int), ("INTPTLAT", Float64), ("INTPTLON", Float64)]
    if field ∈ colnames
            transform!(df_shp, field => ByRow(x -> parse(T, x)), renamecols=false)
        end
    end

    return df_shp
end
