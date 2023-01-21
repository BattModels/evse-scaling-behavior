module Models

using StatsBase
using Statistics
using Distributions
using DataFrames
using GLM
using LsqFit
using HypothesisTests
using DataInterpolations
using Random
using ..Plots: independent_name

import ChargerScale.Latex: report_beta

include("functions.jl")

function fit_models(df::DataFrame; X, Y::Array{Symbol}, formulas=passenger_models())
    distributions = Dict(
        "nb" => (f, link, df) -> negbin(f, df, link; maxiter=120),
        "poisson" => (f, link, df) -> glm(f, df, Poisson(), link; maxiter=120),
        "normal" => (f, link, df) -> glm(f, df, Normal(), link; maxiter=120),
    );

    # Build and fit the model
    df_models = build_models(formulas, distributions, df; X, Y);
    sort!(df_models, :BIC)
    return df_models
end

distribution(d::String) = distribution(Val(Symbol(d)))
distribution(::Val{:nb}) = NegativeBinomial()
distribution(::Val{:poisson}) = Poisson()
distribution(::Val{:normal}) = Normal()

function build_models(formulas, dist, df; X = :population, Y = [:ncharger, :n_gas_station])
    model_df = DataFrame(model = [], formula=String[], dist=String[], response=String[])
    df_lock = Threads.SpinLock()
    Threads.@threads for (f_name, (formula, link)) in collect(formulas)
        Threads.@threads for (dist_name, fitter) in collect(dist)
            if link === nothing
                cur_link = dist_name == "normal" ? IdentityLink() : LogLink()
            else
                cur_link = link
            end
            if link isa IdentityLink && dist_name in ["poisson", "nb", "nb1"]
                continue
            elseif f_name in ["log-quadratic", "log-cubic"] && dist_name == "nb"
                continue
            end

            # Fit Models
            Threads.@threads for y in Y
                if formula.lhs isa FunctionTerm
                    exorig = copy(formula.lhs.exorig)
                    exorig.args[2] = y
                    lhs = FunctionTerm(formula.lhs.forig, formula.lhs.fanon, (y,), exorig, [term(y)])
                else
                    lhs = term(y)
                end
                f = FormulaTerm(lhs, formula.rhs)

                # For Log-Log Formula, only fit to positive values
                if f_name in ["log-log", "log-null"] || (link isa LogLink && dist_name in ["normal", "lognormal", "gamma"])
                    df_model = subset(df, X => ByRow(>(0)), y => ByRow(>(0)); skipmissing=true)
                else
                    df_model = subset(df, X => ByRow(>(0)); skipmissing=true)
                end
                subset!(df_model, X => ByRow(!ismissing), y => ByRow(!ismissing))
                if !all(insupport(distribution(dist_name), df_model[:, y]))
                    @warn "$y not in support of $dist_name, skipping"
                    continue
                end
                try
                    model = fitter(f, cur_link, df_model)
                    row = (model=model, formula=f_name, dist=dist_name, response=string(y))
                    @lock df_lock push!(model_df, row)
                catch
                    @error "failed to fit $y for $f_name and $dist_name"
                end
            end
        end
    end

    # Add Summary Statistics
    transform!(model_df,
        :model => ByRow(nobs) => :nobs,
        :model => ByRow(r2) => :r2,
        :model => ByRow(deviance) => :D,
        :model => ByRow(nbic) => :BIC,
        :model => ByRow(mean_deviation) => :MAD,
        :model => ByRow(rmsd) => :RMSD,
        :model => ByRow(loglikelihood) => :logL,
    )

    # Compute R2_likelihood
    r2L = Float64[]
    r2McFadden = Float64[]
    lambda_lr = Float64[]
    for r in eachrow(model_df)
        null_formula = r.formula == "log-log" ? "log-null" : "null"
        sdx = (model_df.response .== r.response) .&
              (model_df.formula .== null_formula) .&
              (model_df.dist .== r.dist)
        null_model = model_df[sdx, :]

        push!(r2L, 1 - r.D / null_model.D[])
        push!(r2McFadden, 1 - r.logL / null_model.logL[])
        push!(lambda_lr, likelihood_ratio(null_model.model[], r.model))
    end
    model_df.r2L = r2L
    model_df.r2McFadden = r2McFadden
    model_df.lambda_lr = lambda_lr

    return model_df
end

function nbic(model)
    dist = model.model.rr.d
    if dist isa NegativeBinomial
        return bic(model)
    else
        # Account for free r
        return -2 * loglikelihood(model) + (dof(model) + 1) * log(nobs(model))
    end
end

"""
    CloggTest(μ₁, σ₁, μ₂, σ₂)

Compare the regression coefficient μ₁ and μ₂ using a Z-Test under the
null-hypothesis that difference between the coefficient is zero.

See: https://www.jstor.org/stable/2782277
"""
function CloggTest(c1, se1, c2, se2)
	se = hypot(se1, se2)
	z = c1 - c2
	OneSampleZTest(z, se, 2)
end

function mean_deviation(m::RegressionModel)
    abs_deviation = Iterators.map((abs∘-), predict(m), response(m))
    mean(abs_deviation)
end

function likelihood_ratio(null::StatisticalModel, m::StatisticalModel)
    -2 * (loglikelihood(null) - loglikelihood(m))
end

function StatsBase.mss(m::GLM.GeneralizedLinearModel)
    Y = response(m)
    ȳ = sum(Y) / length(Y)
    ŷ = predict(m)
    Iterators.map(y -> abs2(y - ȳ), ŷ) |> sum
end

"""
    tss(m::GLM.GeneralizedLinearModel)

Returns the total sum of squares of the data
"""
function tss(m::GLM.GeneralizedLinearModel)
    Y = response(m)
    ȳ = sum(Y) / length(Y)
    Iterators.map(y -> abs2(y - ȳ), Y) |> sum
end

"""
    rss(m::GLM.GeneralizedLinearModel)

Returns the residual sum of squares of the data
"""
function rss(m::RegressionModel)
    Iterators.map((abs2∘-), predict(m), response(m)) |> sum
end

StatsBase.rmsd(m::RegressionModel) = rmsd(predict(m), response(m))
StatsBase.residuals(m::GLM.GeneralizedLinearModel) = response(m) .- predict(m)

"""
    r2(m::GLM.GeneralizedLinearModel)

Returns the Pearson correlation coefficient
"""
StatsBase.r2(m::GLM.GeneralizedLinearModel) = 1 - rss(m) / tss(m)

function HypothesisTests.OneSampleTTest(m::StatsBase.RegressionModel, μ0=0)
    n = nobs(m)
    xbar = coef(m)
    df = dof(m)
    μ0 = fill(μ0, length(xbar))
    std_error = stderror(m)
    t = (xbar .- μ0) ./ std_error
    OneSampleTTest.(n, Float64.(xbar), df, Float64.(std_error), Float64.(t), μ0)
end

function HypothesisTests.OneSampleZTest(m::StatsBase.RegressionModel, μ0::Real=0)
    μ0 = fill(μ0, length(coef(m)))
    OneSampleZTest(m, μ0)
end
function HypothesisTests.OneSampleZTest(m::StatsBase.RegressionModel, μ0::Vector)
    n = nobs(m)
    xbar = coef(m)
    stddev = stderror(m) * sqrt(n)
    OneSampleZTest.(Float64.(xbar), Float64.(stddev), Int64(n), Float64.(μ0))
end

function coefficient_z_test(m::StatsBase.RegressionModel, a::Int, b::Int; μ0=0)
    n = nobs(m)
    xbar = coef(m)[a] - coef(m)[b]
    se = stderror(m)
    stderr = hypot(se[a], se[b])
    z = (xbar - μ0)/stderr
    UnequalVarianceZTest(n, n, xbar, stderr, z, μ0)
end

function coefficient_z_test(a::StatsBase.RegressionModel, b::StatsBase.RegressionModel, p::Int; μ0=0)
    na, nb = nobs(a), nobs(b)
    xbar = coef(a)[p] - coef(b)[p]
    stderr = hypot(stderror(a)[p], stderror(b)[p])
    z = (xbar - μ0)/stderr
    UnequalVarianceZTest(nobs(a), nobs(b), xbar, stderr, z, μ0)
end

function Distributions.cdf(m::GLM.GeneralizedLinearModel)
    D = m.rr.d
    ϕ = GLM.dispersion(m)
    ŷ = predict(m)
    y = response(m)
    cdf_out = similar(y)
    for (idx, (y, ŷ)) in enumerate(zip(y, ŷ))
        @inbounds cdf_out[idx] = cdf(glm_dist(D, ŷ, ϕ), y)
    end
    cdf_out
end

function Distributions.cdf(m::GLM.GeneralizedLinearModel, x; μ = x, ϕ = GLM.dispersion(m))
    cdf(Distribution(m, μ, ϕ), x)
end

Distribution(m::GLM.GeneralizedLinearModel, μ, ϕ) = glm_dist(m.rr.d, μ, ϕ)
glm_dist(::Poisson, μ, ϕ) = Poisson(μ)
glm_dist(d::NegativeBinomial, μ, ϕ) = NegativeBinomial(d.r, d.r/(μ+d.r))
glm_dist(::Normal, μ, ϕ) = Normal(μ, sqrt(ϕ))

function report_beta(formula::String, model::StatsModels.RegressionModel)
    if formula in ["log-log", "power", "power-linear"]
        return report_beta(model)
    end
    return missing
end

function parameter_significance(formula, model)
    if formula == "linear"
        μ = [0, 0]
    elseif formula in ["power", "log-log"]
        μ = [0, 1]
    elseif formula == "power-linear"
        μ = [0, 1, 0]
    elseif formula == "quadratic"
        μ = [0, 0, 0]
    elseif formula in ["null", "log-null"]
        μ = [0]
    else
        error("Unknown formula: $formula")
    end
    OneSampleZTest(model, μ) .|> pvalue .|> <(0.001)
end

function model_report(models)
    return select(models,
        :response,
        :formula,
        :dist,
        :nobs,
        :BIC,
        :r2McFadden,
        :lambda_lr,
        [:formula, :model] => ByRow(report_beta) => :β,
        [:formula, :model] => ByRow(parameter_significance) => :coef_sig,
    )
end

"""
    prefactor_ratio(m1, m2; level=0.95)

Assuming both m1 and m2 are power models: `ln(E[y]) ~ Yᵢ + β ln(x)`,
compute the lower and upper bounds on Y₁/Y₂ for the given confidence `level`
"""
function prefactor_ratio(m1, m2; level=0.95)
    se1 = first(stderror(m1))
    se2 = first(stderror(m2))
    se = hypot(se1, se2)
    μ1 = first(coef(m1))
    μ2 = first(coef(m2))
    μ = μ1 - μ2
    f = quantile(Normal(), 0.5 + level/2)
    l = exp(μ - f*se)
    u = exp(μ + f*se)
    return l, u
end

"""
    scaling_ratio(m1, m2; level=0.95)

Assuming both m1 and m2 are power models: `ln(E[y]) ~ Yᵢ + β ln(x)`,
estimate the lower and upper bounds on β₁/β₂ for the given confidence `level`
"""
function scaling_ratio(m1, m2; level=0.95, n=2^14)
    x1 = _sample_beta(m1, n)
    x2 = _sample_beta(m2, n)
    r = x1 ./ x2
    return quantile(r, (0.5 - level/2, 0.5 + level/2))
end


function _sample_beta(m, n)
    dist =  Normal(last(coef(m)), last(stderror(m)))
    x = Vector{Float64}(undef, n)
    Random.rand!(dist, x)
    return x
end

predict_distribution(d::NegativeBinomial, ::GeneralizedLinearModel, μ) = NegativeBinomial(d.r, d.r/(μ+d.r))

function predict_interval(m; level=0.95)
    mm = GLM.modelmatrix(m.mf)
    μ = predict(m.model, mm)
    dist = m.model.rr.d
    pred_dists = map(x -> predict_distribution(dist, m.model, x), μ)
    l = map(Base.Fix2(quantile, 0.5 + level/2), pred_dists)
    m = quantile.(pred_dists, 0.5)
    u = quantile.(pred_dists, 0.5 - level/2)
    return sum(l), sum(m), sum(u)
end

end
