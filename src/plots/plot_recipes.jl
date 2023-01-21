
dependent_names(f::AbstractTerm) = filter(x -> !(x isa InterceptTerm), terms(f.rhs)) .|> x -> x.sym

unzip(a) = [getindex.(a, i) for i in 1:length(a[1])]
function poly_flatten(g::Vector, args...)
    out = Tuple[]
    for (i, a...) in zip(g, args...)
        if i isa LibGEOS.Polygon
            push!(out, (__convert_cords(i), a...))
        else
            for sp in map(__convert_cords, GeoInterface.coordinates(i))
                push!(out, (sp, a...))
            end
        end
    end
    return unzip(out)
end
function poly_flatten(g::Vector)
    out = Makie.GeometryBasics.Polygon[]
    for i in g
        if i isa LibGEOS.Polygon
            push!(out, __convert_cords(i))
        else
            append!(out,  map(__convert_cords, GeoInterface.coordinates(i)))
        end
    end
    return out
end

__convert_cords(p::LibGEOS.Polygon) = __convert_cords(GeoInterface.coordinates(p))
function __convert_cords(cords)
    length(cords) == 1
    return Makie.GeometryBasics.Polygon(Makie.Point2.(first(cords)))
end

function Makie.convert_arguments(P::Type{<:Makie.Poly}, x::LibGEOS.Polygon)
    cords = GeoInterface.coordinates(x)
    Makie.convert_arguments(P, __convert_cords(cords))
end

function Makie.convert_arguments(P::Type{<:Makie.Poly}, x::LibGEOS.MultiPolygon)
    polygons = map(__convert_cords, GeoInterface.coordinates(x))
    Makie.convert_arguments(P, polygons)
end

function charger_gap_choropleth(df, counties, states; color_field = :charger_gap)
    # Setup Figure
    fig = Figure(resolution = 72 .* (3.42, 2.))
    scale = log10

    # Filter to continental usa
    transform!(counties,
		[:STATEFP, :COUNTYFP] => ByRow((s,c) -> 1000*s + c) => :fips,
	)
    df_plot = innerjoin(df, counties; on=:fips)

    # Hide borders
    hide_spline = (
        topspinevisible=false,
        bottomspinevisible=false,
        leftspinevisible=false,
        rightspinevisible=false
    )

    # Plot choropleth for counties
    ax = Axis(fig[1,1]; hide_spline...)
    hidedecorations!(ax)

    # Color levels
    levels = Float64[1, 10, 100, 1000, 10_000, 100_000]
    level_str = [L"1", L"10", L"10^2", L"10^3", L"10^4", L"10^5"]
    scaled_levels = scale.(levels)

    # Add Colorbar
    cbar = Colorbar(fig[2, 1],
        vertical = false,
        flipaxis = false,
        width = Relative(0.95),
        size = 5,
        ticks = (scaled_levels, level_str),
        colormap = :YlGnBu_9,
        colorrange = scale.(extrema(df_plot[!, color_field])),
    )
    rowgap!(fig.layout, 1)

    # Contiguous States
    plot_choropleth!(ax,
        filter(:fips => x -> floor(x/1000) ∉ [2, 15], df_plot), states, color_field;
        state_color = :white,
        cbar,
        scale,
    )

    # Add hawaii Inset Plot
    hawaii_len = 50
    inset_hawaii = Axis(fig[1,1];
        alignmode = Outside(1),
        tellheight = false, tellwidth = false,
        height = hawaii_len, width = hawaii_len,
        valign = :bottom,
        halign = :left,
        hide_spline...
    )
    hidedecorations!(inset_hawaii)
    plot_choropleth!(inset_hawaii,
        filter(:fips => x -> floor(x/1000) == 15, df_plot), states, color_field;
        state_border = 0.25,
        state_color = :white,
        cbar,
        scale,
    )

    # Add akaska Inset Plot
    akaska_len = 60
    inset_akaska = Axis(fig[1,1];
        alignmode = Outside(1),
        tellheight = false, tellwidth = false,
        height = akaska_len, width = akaska_len,
        valign = :bottom,
        halign = :right,
        hide_spline...
    )
    hidedecorations!(inset_akaska)
    plot_choropleth!(inset_akaska,
        filter(:fips => x -> floor(x/1000) == 2, df_plot), states, color_field;
        state_border = 0.25,
        state_color = :white,
        cbar,
        scale,
    )
    xlims!(inset_akaska, (-180, -130))

    # Add Label for Colorbar
    Label(fig[1,1], L"EVSE Station Gap: $\Delta Y_{EVSE}$";
        tellheight = false, tellwidth = false,
        valign = :bottom, halign = :center,
    )

    return fig
end

function charger_rollout_choropleth(df, counties, states;
    color_field = :charger_gap,
    scale=identity,
    colormap = :vik,
    title="",
    tickvalues=Int[0],
    minorticks=Int[0],
    ticklabels=Makie.Automatic(),
    highclip=nothing, lowclip=nothing,
)
    # Setup Figure
    fig = Figure(resolution = 72 .* (3.42, 2.))

    # Filter to continental usa
    df_plot = innerjoin(df, counties; on=:fips=>:GEOID)

    # Hide borders
    hide_spline = (
        topspinevisible=false,
        bottomspinevisible=false,
        leftspinevisible=false,
        rightspinevisible=false
    )

    # Plot choropleth for counties
    ax = Axis(fig[1,1]; hide_spline...)
    hidedecorations!(ax)

    # Add Colorbar
    scaled_ticks = scale.(tickvalues)
    ticklabels = Makie.get_ticklabels(ticklabels, tickvalues)
    clims = extrema(filter(isfinite, scale.(skipmissing(df_plot[!, color_field]))))
    clims = (prevfloat(clims[1]), nextfloat(clims[2]))
    cbar = Colorbar(fig[3, 1];
        vertical = false,
        flipaxis = false,
        width = Relative(0.95),
        size = 5,
        colormap,
        colorrange=scale.((5, 1500)),
        ticks=(scaled_ticks, ticklabels),
        minorticksvisible=true,
        minorticks=scale.(minorticks),
        lowclip,
        highclip,
        nsteps=500,
    )
    rowgap!(fig.layout, 0)

    # Contiguous States
    plot_choropleth!(ax,
        filter(:fips => x -> floor(x/1000) ∉ [2, 15], df_plot), states, color_field;
        cbar,
        scale
    )

    # Add hawaii Inset Plot
    hawaii_len = 50
    inset_hawaii = Axis(fig[1,1];
        alignmode = Outside(1),
        tellheight = false, tellwidth = false,
        height = hawaii_len, width = hawaii_len,
        valign = :bottom,
        halign = :left,
        hide_spline...
    )
    hidedecorations!(inset_hawaii)
    plot_choropleth!(inset_hawaii,
        filter(:fips => x -> floor(x/1000) == 15, df_plot), states, color_field;
        state_border = 0.25,
        cbar,
        scale,
    )

    # Add akaska Inset Plot
    akaska_len = 60
    inset_akaska = Axis(fig[1,1];
        alignmode = Outside(1),
        tellheight = false, tellwidth = false,
        height = akaska_len, width = akaska_len,
        valign = :bottom,
        halign = :right,
        hide_spline...
    )
    hidedecorations!(inset_akaska)
    plot_choropleth!(inset_akaska,
        filter(:fips => x -> floor(x/1000) == 2, df_plot), states, color_field;
        state_border = 0.25,
        cbar,
        scale,
    )
    xlims!(inset_akaska, (-180, -130))

    # Add Label for Colorbar
    Label(fig[2,1], title,
        tellheight = true, tellwidth = false,
        valign = 1, halign = :center,
    )

    return fig
end

function model_label(m)
    r = confint(m)[2, :] .|> x -> @sprintf("%.2f", x)
    L"$\beta$ %$(r[1]) - %$(r[2])"
    "β $(r[1]) - $(r[2])"
end

function plot_choropleth!(ax, df, states, value; state_border=0.25, state_color = "rgb(109,110,113)", cbar, scale=identity)
    # Plot main choropleth
    df_plot = subset(df, value => ByRow(!ismissing))
    if nrow(df_plot) > 0
        p, color = poly_flatten(df_plot[!, :geometry], df_plot[!, value])
        color = scale.(color)
        poly!(ax, p;
            color,
            strokecolor=state_color,
            strokewidth = 0.1,
            colormap = cbar.colormap,
            colorrange = cbar.colorrange,
            lowclip = cbar.lowclip,
            highclip = cbar.highclip,
        )
    end

    # Add boarder around states
    plotted_states = unique(@. floor(df.fips / 1000))
    borders = subset(states, :STATEFP => ByRow(in(plotted_states))).geometry
    for s in poly_flatten(borders)
        lines!(ax, s, color=:black, linewidth=state_border)
    end
    return nothing
end
