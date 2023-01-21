"""
Reconstruct the plots from "Scaling Behavior for Electric Vehicle Chargers
and Road Map to Addressing the Infrastructure Gap"
"""

using DataFrames
using CSV
using GLM
using Printf
using CairoMakie
using Statistics
using StatsBase
using HypothesisTests
using ChargerScale
using ChargerScale: where
using ChargerScale.Plots: scalingplot!, blue, lightblue, red, lightred, subplot_label!, predictglm!
using ChargerScale.Models: model_report, prefactor_ratio


function population_scaling(df = ChargerScale.Dataset.load_dataset())
    # Fit Models
    models = ChargerScale.Models.fit_models(df;
        X=:population,
        Y=[:n_gas_station, :station_count],
        formulas=ChargerScale.Models.population()
    )

    # Select model
    gas_model = where(models, :formula => "power", :dist => "nb", :response => "n_gas_station")[1, :model]
    ev_model = where(models, :formula => "power", :dist => "nb", :response => "station_count")[1, :model]

    return models, gas_model, ev_model
end

function registration_scaling(df)
    gas_models = ChargerScale.Models.fit_models(
        dropmissing(df[!, [:passenger_vehicles, :n_gas_station]]),
        X=:passenger_vehicles,
        Y=[:n_gas_station],
        formulas=ChargerScale.Models.passenger_vehicles()
    )
    ev_models = ChargerScale.Models.fit_models(
        dropmissing(df[!, [:ev_registrations, :station_count]]),
        X=:ev_registrations,
        Y=[:station_count],
        formulas=ChargerScale.Models.ev_registrations()
    )
    gas_model = where(gas_models, :formula => "power", "dist" => "nb")[1, :model]
    ev_model = where(ev_models, :formula => "power", :dist => "nb")[1, :model]
    models = vcat(gas_models, ev_models)
    return models, gas_model, ev_model
end

function registration_population_scaling(df)
    gas_models = ChargerScale.Models.fit_models(
        dropmissing(df[!, [:population, :passenger_vehicles]]),
        X=:population,
        Y=[:passenger_vehicles],
        formulas=ChargerScale.Models.population()
    )
    df_ev = transform!(
        dropmissing(df[!, [:population, :ev_registrations]]),
        :ev_registrations => ByRow(floor) => :ev_registrations
    )
    ev_models = ChargerScale.Models.fit_models(
        df_ev,
        X=:population,
        Y=[:ev_registrations],
        formulas=ChargerScale.Models.population()
    )
    gas_model = where(gas_models, :formula => "power", "dist" => "nb")[1, :model]
    ev_model = where(ev_models, :formula => "power", :dist => "nb")[1, :model]
    models = vcat(gas_models, ev_models)
    return models, gas_model, ev_model
end

function gas_ev_ratio(ev_power)
    # Gallons per minute Source: https://en.wikipedia.org/wiki/Gasoline_pump
    gas_pump_rate = 10

    # kWh/gallon MPGe Conversion factor: https://en.wikipedia.org/wiki/Miles_per_gallon_gasoline_equivalent
    gas_ev_factor = 33.7

    # On Average EV's are ~ 3x more efficient than cars
    ev_eff = 3
    gas_power = (60*gas_pump_rate) * gas_ev_factor
    return gas_power / (ev_power * ev_eff)
end

function evse_expected_model(gas_pop, ev_power)
    evse_expected = deepcopy(gas_pop)
    coef(evse_expected)[1] += log(gas_ev_ratio(ev_power))
    return evse_expected
end


function charger_gap!(df, gas_model; ev_power=400)
    charger_factor = gas_ev_ratio(ev_power)
    df.req_chargers = charger_factor * predict(gas_model)
	df.charger_gap = df.req_chargers .- df.station_count
    return nothing
end

function plot_station_gap(df)
    county_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_20m/cb_2020_us_county_20m.shp");

    states_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_states/cb_2020_us_state_20m.shp");
    fig = with_theme(ChargerScale.Plots.pnas_theme()) do
        ChargerScale.Plots.charger_gap_choropleth(df, county_shp, states_shp)
    end
    mkpath("img"); save(joinpath("img", "us_charger_gap.pdf"), fig);
    return fig
end

function plot_station_rollout(df)
    county_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_20m/cb_2020_us_county_20m.shp");
    states_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_states/cb_2020_us_state_20m.shp");
    df.scale_adjusted_charger_gap = df.req_chargers ./ df.station_count
    fig = with_theme(ChargerScale.Plots.pnas_theme()) do
        ChargerScale.Plots.charger_rollout_choropleth(df, county_shp, states_shp;
            title=L"Relative increase in EVSE Stations: $\hat{Y}_{EVSE}/Y_{EVSE}$",
            color_field=:scale_adjusted_charger_gap,
            scale=log10,
            colormap=Reverse(:roma),
            tickvalues=Int[5, 10, 100, 1000],
            minorticks=Int[5:10..., 20:10:100..., 200:100:1000...],
            ticklabels=Base.Fix1(map, x -> L"%$x\times"),
            highclip=:white,
        )
    end
    mkpath("img"); save(joinpath("img", "ev_pop_residuals.pdf"), fig);
    return fig
end

function plot_station_rollout_all(df, ev_reg, ev_pop_reg)
    county_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_20m/cb_2020_us_county_20m.shp");
    states_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_states/cb_2020_us_state_20m.shp");
    df_fake = select(df, [:fips, :population, :station_count], copycols=true)
    df_fake.ev_registrations = predict(ev_pop_reg, df_fake)
    df_fake.evse_expected = predict(ev_reg, df_fake)
    df_fake.scale_adjusted_charger_gap = df_fake.station_count .- df_fake.evse_expected
    fig = with_theme(ChargerScale.Plots.pnas_theme()) do
        ChargerScale.Plots.charger_rollout_choropleth(df_fake, county_shp, states_shp; color_field=:scale_adjusted_charger_gap, scale=asinh)
    end
    mkpath("img"); save(joinpath("img", "us_charger_rel_gap.pdf"), fig);
    return fig, df_fake
end

function plot_main_fig(ev_pop, gas_pop, ev_reg, gas_reg, ev_pop_reg, gas_pop_reg; spatial_unit="County")
    fig = Figure(;
        resolution = 72 .* (7, 2.11),
    )
    gl = GridLayout(fig[1, 1])
    Q = [(1, 2), (2, 2), (3, 1), (4, 0.5)]
    ax_reg = Axis(gl[1, 1],
        xscale=log10, yscale=log10,
        limits=((1, 2e7), (1, 1e4)),
        xlabel="Vehicle Registrations",
        ylabel="Stations",
        xticks=LogTicks(WilkinsonTicks(3; Q)),
        yticks=LogTicks([0, 1, 2, 3]),
    )
    ax_reg_pop = Axis(gl[1, 2],
        xscale=log10, yscale=log10,
        limits=((1, 2e7), (1, 2e7)),
        xlabel="$spatial_unit Population",
        ylabel="Vehicle Registrations",
        xticks=LogTicks(WilkinsonTicks(3; Q)),
        yticks=LogTicks(WilkinsonTicks(3; Q)),
    )
    ax_pop = Axis(gl[1, 3],
        xscale=log10, yscale=log10,
        limits=((1, 2e7), (1, 1e4)),
        xlabel="$spatial_unit Population",
        ylabel="Stations",
        xticks=LogTicks(WilkinsonTicks(3; Q)),
        yticks=LogTicks([0, 1, 2, 3]),
    )

    # Subplot Labels
    subplot_label!(gl[1, 1], "a")
    subplot_label!(gl[1, 2], "b")
    subplot_label!(gl[1, 3], "c")

    # EV Plots
    ev_opts = (;
        data_color = lightblue,
        model_color = blue,
        marker = :x,
    )
    gas_opts = (;
        data_color = lightred,
        model_color = red,
        marker = :+,
        linestyle = :dash,
    )

    # Stations vs. Registrations
    scalingplot!(ax_reg, gas_reg; label="Gasoline Stations", gas_opts...)
    scalingplot!(ax_reg, ev_reg; label="EVSE Stations", ev_opts...)

    # Stations vs. Population
    scalingplot!(ax_pop, gas_pop; label="Gasoline Stations", gas_opts...)
    scalingplot!(ax_pop, ev_pop; label="EVSE Stations", ev_opts...)

    # Expected EVSE Stations
    evse_expect = evse_expected_model(gas_pop, 400)
    predictglm!(ax_pop, evse_expect; label="EVSE Stations to reach parity (Eq. 2)", color=:black, linestyle=:dot)

    # Registrations vs. Population
    scalingplot!(ax_reg_pop, gas_pop_reg; label = "Passenger Vehicles", gas_opts...)
    scalingplot!(ax_reg_pop, ev_pop_reg; label="Electric Vehicles", ev_opts...)

    # Add legends
    Legend(gl[1,1], ax_reg; valign=:top, halign=:left)
    Legend(gl[1,2], ax_reg_pop; valign=:top, halign=:left)
    Legend(gl[1,3], ax_pop; valign=:top, halign=:left)

    mkpath("img"); save(joinpath("img", "charger_scaling.pdf"), fig);
    return fig
end

function compare_beta(a, b, f)
    if f in ["power", "log-log"]
        return ChargerScale.Models.coefficient_z_test(a, b, 2)
    else
        return nothing
    end
end

function scaling_cbsa(df_county, models_counties)
    vars = [:population, :n_gas_station, :station_count, :passenger_vehicles, :ev_registrations, :land_area_sq_m]
    df_cbsa = select(ChargerScale.Dataset.collate_cbsa(df_county), :cbsa => :fips, vars...)
    models = Dict(
        "population" => first(population_scaling(df_cbsa)),
        "registration" => first(registration_scaling(df_cbsa)),
        "registration vs. population" => first(registration_population_scaling(df_cbsa)),
    )
    df_cbsa[!, :spatial_unit] .= "cbsa"
    df = select(df_county, :fips, vars...)
    df[!, :spatial_unit] .= "county"
    df = vcat(df, df_cbsa)

    # Run stats on models
    model_comparisons = Dict{keytype(models), Any}()
    for key in keys(models)
        # Check if coefficients are different
        model_compare = innerjoin(
            select(models_counties[key], :model => :county_model, :formula, :dist, :response),
            select(models[key], :model => :cbsa_model, :formula, :dist, :response);
            on=[:formula, :dist, :response]
        )

        transform!(model_compare,
            [:county_model, :cbsa_model, :formula] =>
            ByRow((a, b, f) -> compare_beta(a, b, f))
            => :z_test,
            :county_model => ByRow(bic) => :county_bic,
            :cbsa_model => ByRow(bic) => :cbsa_bic,
            :county_model => ByRow(last∘coef) => :county_beta,
            :cbsa_model => ByRow(last∘coef) => :cbsa_beta,
        )
        subset!(model_compare, :z_test => ByRow(!isnothing))
        disallowmissing!(model_compare, :z_test)
        transform!(model_compare,
            :cbsa_model => ByRow(pvalue∘last∘Base.Fix2(OneSampleZTest, [0, 1])) => :pvalue_linear,
            :z_test => ByRow(pvalue) => :pvalue_clogg
        )

        model_comparisons[key] = select(model_compare, Not([:county_model, :cbsa_model, :z_test]))
    end

    # Print out model statistics
    for (name, m) in models
        println("Model Report - CBSA: $name")
        display(ChargerScale.Models.model_report(m))
        println("Comparison to County: $name")
        display(model_comparisons[name])
    end

    return model_comparisons, models
end

function main(df = ChargerScale.Dataset.load_dataset())
    # Fit models
    model_pop, gas_pop, ev_pop = population_scaling(df)
    model_reg, gas_reg, ev_reg = registration_scaling(df)
    model_pop_reg, gas_pop_reg, ev_pop_reg = registration_population_scaling(df)
    model_county = Dict(
        "population" => model_pop,
        "registration" => model_reg,
        "registration vs. population" => model_pop_reg
    )

    # Generate the main figure
    fig = with_theme(ChargerScale.Plots.pnas_theme()) do
        plot_main_fig(ev_pop, gas_pop, ev_reg, gas_reg, ev_pop_reg, gas_pop_reg)
    end
    mkpath("img"); save(joinpath("img", "charger_scaling.pdf"), fig);

    # Report statistics
    print("Registrations Scaling\n$(model_report(model_reg))\n")
    print("Population Scaling\n$(model_report(model_pop))\n")
    print("Registrations vs. Population Scaling\n$(model_report(model_pop_reg))\n")

    # Report beta
    for m in [gas_pop, ev_pop, gas_reg, ev_reg]
        print("$(formula(m)) - β: $(ChargerScale.Latex.report_beta(m))\n")
    end

    # Interesting ratios of scaling coefficients
    prefactor_ratio = ChargerScale.Models.prefactor_ratio(ev_reg, gas_reg)
    @printf "Gas to EV Empirical Ratio: %.2g - %.2g\n" prefactor_ratio...
    @printf "Expected EV Registration Scaling: %.2f - %.2f\n" ChargerScale.Models.scaling_ratio(ev_pop, ev_pop_reg)...
    @printf "Expected Gasoline Registration Scaling: %.2f - %.2f\n" ChargerScale.Models.scaling_ratio(gas_pop, gas_pop_reg)...

    # Estimate gamma
    med_station_power = median(filter(!ismissing, df.median_power))
    β′ = gas_ev_ratio(med_station_power / 1e3)
    @printf "Median Station Power: %.3g kW\n" med_station_power/1e3
    @printf "Median Gas - EV ratio: %.3g\n" β′
    @printf "γ estimate: %.1g - %.1g\n" minmax((prefactor_ratio ./ β′)...)...

    # Estimate Gap
    charger_gap!(df, gas_pop; ev_power=400)
    @printf "Maxium County Station Gap: %.1f\n" maximum(df[!, :charger_gap])
    @printf "Median County Station Gap: %.1f\n" median(df[!, :charger_gap])
    @printf "EVSE stations for power parity %.1e\n" sum(df[!, :req_chargers])

    # Plot expected releative increase in EVSE stations
    fig2 = with_theme(ChargerScale.Plots.pnas_theme()) do
        plot_station_rollout(df)
    end
    fig3 = with_theme(ChargerScale.Plots.pnas_theme()) do
        plot_station_gap(df)
    end

    # Report stats for Scale Adjusted Charger Gap Caption
    # Compare Alleghany County, PA to
    #   - Similar SACG: Platte County, WY
    #   - Similar Station Gap: Travis County, TX
    df_sacg = subset(df, :fips => ByRow(in((42003, 56031, 48453, 6055, 6003, 41069, 5603, 6037, 32003))))
    sort!(df_sacg, :scale_adjusted_charger_gap)
    show(df_sacg[!, [
        :fips, :county, :state,
        :station_count, :charger_gap, :scale_adjusted_charger_gap,
        :population
    ]], allcols=true)

    median_sacg = median(df.scale_adjusted_charger_gap)
    @printf "Median Expansion of EVSE Infrastructure: %.1e\n" median_sacg
    bottom_gap = sum(subset(df, :scale_adjusted_charger_gap => ByRow(<=(median_sacg)))[!, :charger_gap])
    upper_gap = sum(subset(df, :scale_adjusted_charger_gap => ByRow(>(median_sacg)))[!, :charger_gap])
    @printf "Bottom 50%% need %.1e stations vs. %.1e for upper\n" bottom_gap upper_gap

    # Report Stats for counties lacking EVSE stations
    no_chargers = subset(df, :station_count => ByRow(==(0)))
    @printf "Population of No Station Counties: %.2e\n" sum(no_chargers.population)
    @printf "Counties with no charging stations: %d (%.1f%%)\n" nrow(no_chargers) 100*nrow(no_chargers)/nrow(df)
    @printf "Median Station Gap for Counties with No Stations: %.1f\n" median(no_chargers[!, :req_chargers])
    @printf "Maximum Station Gap for Counties with No Stations: %.1f\n" maximum(no_chargers[!, :req_chargers])
    @printf "Total Stations for Counties with No Stations: %.1f\n" sum(no_chargers[!, :req_chargers])

    # Repat for CBSA
    model_comparisons, model_cbsa = scaling_cbsa(df, model_county)
    cbsa_model_select = (:formula => "power", :dist => "nb")
    fig_cbsa = with_theme(ChargerScale.Plots.pnas_theme()) do
        plot_main_fig(
            where(model_cbsa["population"], :response => "station_count", cbsa_model_select...)[1, :model],
            where(model_cbsa["population"], :response => "n_gas_station", cbsa_model_select...)[1, :model],
            where(model_cbsa["registration"], :response => "station_count", cbsa_model_select...)[1, :model],
            where(model_cbsa["registration"], :response => "n_gas_station", cbsa_model_select...)[1, :model],
            where(model_cbsa["registration vs. population"], :response => "ev_registrations", cbsa_model_select...)[1, :model],
            where(model_cbsa["registration vs. population"], :response => "passenger_vehicles", cbsa_model_select...)[1, :model];
            spatial_unit = "CBSA",
        )
    end
    mkpath("img"); save(joinpath("img", "charger_scaling_cbsa.pdf"), fig_cbsa);

    # Save all models
    models = Dict(
        "county" => model_county,
        "cbsa" => model_cbsa,
    )

    # Save our predictions
    round_prediction = x -> round(x; sigdigits=3)
    df_out = transform(df[!, [:fips, :state, :county, :population, :station_count, :req_chargers, :n_gas_station, :scale_adjusted_charger_gap]],
        :req_chargers => ByRow(round_prediction),
        :scale_adjusted_charger_gap => ByRow(round_prediction);
        renamecols=false,
    )
    select!(df_out,
        :fips,
        :state => "State",
        :county => "County",
        :population => "Population",
        :req_chargers => "EVSE Stations for Parity",
        :station_count => "EVSE Stations (As of 12/31/2020)",
        :n_gas_station => "Gasoline Stations (Q4 2020)",
        :scale_adjusted_charger_gap => "Scale-Adjusted EVSE Station Gap",
    )

    county_shp = ChargerScale.Geo.import_shapefile("data/census/2010/geography_20m/cb_2020_us_county_20m.shp");
    df_out = leftjoin(df_out, county_shp[!, [:GEOID, :geometry]]; on=:fips=>:GEOID)
    CSV.write("charger_scaling_predictions.csv", df_out)

    return fig, models, model_comparisons, df, df_out
end
