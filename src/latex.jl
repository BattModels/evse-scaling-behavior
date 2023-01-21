module Latex

using Makie
using LaTeXTabulars
using Latexify
using HypothesisTests
using StatsBase
using Distributions

FORMULA_LATEX = Dict(
    "power" => L"Y_0 N ^\beta",
    "log-cubic" => L"\exp \left ( a N ^3 + bN^3 + cN + d \right )",
    "linear" => L"a N + b",
    "log-linear" => L"\exp \left ( a N + b \right )",
    "quadratic" => L"a N^2 + bN + c",
    "log-quadratic" => L"\exp \left ( a N^2 + bN + c \right )",
    "cubic" => L"a N ^3 + bN^3 + cN + d",
    "null" => L"a",
)

RESPONSE_LATEX = Dict(
    "n_gas_station" => "Gasoline",
    "ncharger" => "EVSE"
)

DIST_LATEX = Dict(
    "nb" => f -> L"$NB \left (r, \mu = %$f \right)$",
    "nb1" => f -> L"$NB \left (r = 1, \mu = %$f \right )$",
    "poisson" => f -> L"$Pois(%$f)$",
    "normal" => f -> L"$\mathcal{N}(%$f, \sigma^2)$",
)

function summary_row(model_row)
    f = FORMULA_LATEX[model_row.formula][2:end-1]
    [
        RESPONSE_LATEX[model_row.response],
        DIST_LATEX[model_row.dist](f),
        latexify(model_row.RMSD; fmt="%2.1f"),
        latexify(model_row.r2McFadden; fmt="%.3f"),
        latexify(model_row.lambda_lr/1e3; fmt=FancyNumberFormatter("%.3g")),
        latexify(model_row.BIC/1e3; fmt="%.1f"),
    ]
end
shortstack(s1, s2) = "\\shortstack{$s1 \\\\ $s2}"

function model_zoo(filename, df_models)
    rows = [
        [
            "",
            "Model",
            "RMSD",
            L"R^2_{McF}",
            shortstack(L"\lambda_{LR}", L"\times 10^{3}"),
            shortstack("BIC", L"\times 10^{3}"),
        ],
        Rule(:mid),
    ]
    sort!(df_models, :BIC)
    for gdf in groupby(df_models, :response)
        cur_row = map(summary_row, eachrow(gdf))

        # Replace with rotated multirow
        rstr = cur_row[1][1]
        nr = length(cur_row)
        cur_row[1][1] = "\\multirow{$nr}{*}{\\rotatebox[origin=c]{90}{$rstr}}"
        for r in cur_row[2:end]
            r[1] = ""
        end

        append!(rows, cur_row)
        push!(rows, Rule(:mid))
    end
    rows[end] = Rule(:bottom)
    latex_tabular(filename, Tabular("llccccc"), rows)
end

function report_test(h::HypothesisTests.OneSampleZTest; tail=:both)
    se_str = latexify(h.stderr; fmt=FancyNumberFormatter("%.2g")) |> latex_clean
    p_str = pvalue(h; tail) |> latex_pvalue |> latex_clean
    z_str = latexify(h.z; fmt=FancyNumberFormatter("%.1f")) |> latex_clean
    str = "SE = $se_str, W = $z_str, p $p_str"
    replace(str, r"(,? *\w*) ?([=<>])" => s"\\mbox{\1} \2")
end

function report_beta(m; level = 0.95)
    beta_str = latexify(coef(m)[2]; fmt="%.2f") |> latex_clean
    ci = stderror(m)[2] * quantile(Normal(), (1 - level)/2) |> abs
    ci_str = latexify(ci; fmt=FancyNumberFormatter("%.2f")) |> latex_clean
    L"\beta = %$beta_str \pm %$ci_str" |> latex_clean
end

latex_clean(str) = str[2:end-1]
function latex_pvalue(p)
    StatsBase.PValue
    if p >= 1e-4
        return latexify(p; fmt="= %.4f")
    else
        p_mag = ceil(Integer, max(nextfloat(log10(p)), -99))
        return L"< 10^{%$p_mag}"
    end
end

end
