Makie.@recipe(PredictGLM, model) do scene
    Attributes(;
        linewidth = theme(scene, :linewidth),
        linestyle = theme(scene, :linestyle),
        color = :black,
        npoints = 100,
    )
end

function Makie.plot!(plt::PredictGLM)

    # Get Limits
    scene = Makie.parent_scene(plt)
    limits = lift(Makie.projview_to_2d_limits, scene.camera.projectionview)

    # Regenerate points when the view / model updates
    points = Observable(Point2f[])
    onany(limits, plt[:model], plt[:npoints]) do limits, model, npoints
        # Sample x over the full plot width, plus a bit extra to avoid
        # clipping artifacts at the plot limits
        xmin = first(minimum(limits))
        xmax = first(maximum(limits))
        chrome = 2 * (xmax - xmin) / (npoints)
        inv = (Makie.inverse_transform∘Makie.transform_func)(scene)
        x = first(inv).(range(xmin-chrome, xmax+chrome; length=npoints))

        # Predict response
        xvar = independent_name(model)
        mm = GLM.modelmatrix(model.mf; data=DataFrame(xvar => x))
        y_linear = predict(model.model, mm)
        y = map(invfun(model), y_linear)

        # Update points
        empty!(points[])
        append!(points[], Point2.(x, y))
        notify(points)
    end

    # Generate points to plot
    notify(limits)

    # Plot response, and translate it forward
    lines!(plt, points;
        linewidth=plt[:linewidth],
        linestyle=plt[:linestyle],
        color=plt[:color],
    ) |> h -> translate!(h, 0, 0, 5)

    return plt
end


response_name(model::RegressionModel) = response_name(formula(model))
response_name(f::FormulaTerm) = sym_name(f.lhs)
independent_name(model::RegressionModel) = first(unique(dependent_names(formula(model))))

sym_name(t::ContinuousTerm) = t.sym
sym_name(t::FunctionTerm) = first(t.args_parsed).sym

invfun(model::RegressionModel) = invfun(formula(model).lhs)
invfun(::ContinuousTerm) = identity
invfun(f::FunctionTerm) = Makie.inverse_transform(f.forig)

function scalingplot!(ax, model::RegressionModel;
    marker = theme(nothing, :marker),
    data_color = :blue,
    model_color = :red,
    linestyle = theme(nothing, :linestyle),
    label = "",
)

    # Plot the data
    xvar  = independent_name(model)
    yvar = response_name(model)
    data_label = @sprintf "%s, n=%d" label nobs(model)
    h = scatter!(ax, model.mf.data[xvar], model.mf.data[yvar];
       marker, color=data_color, label=data_label
    )
    translate!(h, 0, 0, -10)

    # Plot the model
    predictglm!(ax, model; color=model_color, linestyle, label=model_label(model))

    return nothing
end
