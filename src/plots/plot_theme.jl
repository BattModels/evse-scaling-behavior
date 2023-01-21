using Makie

# Get fonts
const font_bold = "cmu.serif-bold.ttf"
const font_normal = "cmu.serif-roman.tff"

# Et colors
const red = "rgb(220,50,32)"
const lightred = "rgb(219, 111, 99)"
const blue = "rgb(0,90,181)"
const lightblue = "rgb(54, 117, 181)"

function pnas_theme(;figsize=(3.42, 2.11))
    font_size = 6
    Theme(
        resolution = 72 .* figsize,
        font = font_normal,
        fontsize = font_size,
        figure_padding = (1, 1, 1, 1),
        rowgap = 3,
        colgap = 4,
        linewidth = 1.5,
        markersize = 3,
        Axis = (
            spinewidth = 0.5,
            xlabelpadding = 1,
            ylabelpadding = 1,
            xticksize = 2,
            yticksize = 2,
            xtickwidth = 0.5,
            ytickwidth = 0.5,
            xgridwidth = 0.25,
            ygridwidth = 0.25,
            xminorticksize = 1.5,
            yminorticksize = 1.5,
            xminortickwidth = 0.5,
            yminortickwidth = 0.5,
            xminorgridwidth = 0.25,
            yminorgridwidth = 0.25,
        ),
        Legend = (
            titlegap = 0,
            patchsize = (13, 6),
            patchlabelgap = 2,
            rowgap = 0,
            padding = 2,
            framewidth = 0.5,
            margin = (2, 2, 2, 2),
            tellheight = false,
            tellwidth = false,
        ),
        Colorbar = (
            spinewidth = 0.5,
            tickwidth = 0.5,
            ticksize = 2,
            minortickwidth = 0.25,
            minorticksize = 1.5,
            labelpadding = 0,
            ticklabelpad = 0,
        ),
        Text = (
            font = font_normal,
            fontsize = font_size,
        ),
    )
end

function subplot_label!(gp::Makie.GridPosition, label::String)
    layout = gp.layout
    loc = layout[gp.span.rows, gp.span.cols, TopLeft()]
    Label(loc, "$label)";
        font = font_bold,
        fontsize = 8,
        padding = (0, 6, 0, 0),
        halign = :right,
        valign = :top,
        tellheight = false,
        tellwidth = false,
    )
end
