module Dataset

using DataFrames
using Shapefile
using CSV
using XLSX
using Statistics: median
using ChargerScale
using ChargerScale: PKG_DIR
using ChargerScale: where!
using ..Geo: RevGeocoder
using ..Parsers:
    BLS,
    charge_timeseries,
    fips,
    join_registration,
    load_ev_registrations,
    process_station_data,
    charge_timeseries,
    select_latest,
    select_year


function import_passenger_vehicles()
    df = DataFrame(CSV.File(joinpath("data", "state_registration", "passenger_vehicle.csv")))
    rename!(df, :count => "passenger_vehicles")
    return df
end

function _get_rev_geocoder()
    geocoder_path = joinpath(PKG_DIR, "data", "census", "2010", "geography", "tl_2020_us_county.shp")
    return RevGeocoder(geocoder_path)
end

function import_ev_stations(rev_geocoder = _get_rev_geocoder())
    # Load Station Data
    path = joinpath("data", "nrel_ev_stations.csv")
    df_stations = process_station_data(path, rev_geocoder)
    df_stations_ts = charge_timeseries(df_stations)
    return select!(
        select_latest(df_stations_ts, 2020),
        :fips, :station_count, :station_power, :median_power
    )
end

function import_ev_registrations()
    df_registration = load_ev_registrations()
    geocoder_path = joinpath("data", "census", "2010", "geography", "tl_2020_us_county.shp")
    rev_geocoder = RevGeocoder(geocoder_path);

    # Load Station Data from NREL
    df_stations = process_station_data(joinpath("data", "nrel_ev_stations.csv"), rev_geocoder)
    df_station_ts = charge_timeseries(df_stations)

    # Combine Station and Registration datasets
    df = select_latest(join_registration(df_station_ts, df_registration))
    select!(df, [:fips, :ev_registrations])
    disallowmissing!(df)
    return df
end

function import_census()
    df = DataFrame(CSV.File(joinpath(PKG_DIR, "data", "census", "2020", "co-est2021-alldata.csv")))
    subset!(df, :SUMLEV => ByRow(==(50)))
    select!(df,
        [:STATE, :COUNTY] => fips => :fips,
        :STNAME => :state,
        :CTYNAME => :county,
        :POPESTIMATE2020 => :population,
    )
    return df
end

function import_gas_stations()
    df = BLS.reduce_file(joinpath("data", "bls_qcew", "naics", "2020.csv"))
    where!(df, :qtr => 4, :year => 2020)
    return select!(df, :fips, :establishments => :n_gas_station)
end

function import_county_area()
    file = joinpath(PKG_DIR, "data", "census", "2010", "geography", "tl_2020_us_county.shp")
    df = DataFrame(Shapefile.Table(file))
    return select(df,
        [:STATEFP, :COUNTYFP] => ByRow(fips) => :fips,
        :ALAND => :land_area_sq_m,
    )
end

function dataset()
    df = import_census()
    leftjoin!(df, import_county_area(); on=:fips)
    disallowmissing!(df)

    # Compute Population Density (People Per Sq. Meter)
    transform!(df, [:population, :land_area_sq_m] => ByRow(/) => :pop_density)

    # Import Station Data
    rev_geocoder = _get_rev_geocoder()
    leftjoin!(df, import_gas_stations(); on=:fips)
    leftjoin!(df, import_ev_stations(rev_geocoder); on=:fips)
    for f in [:n_gas_station, :station_count, :station_power]
        transform!(df, f => ByRow(Base.Fix2(coalesce, 0)) => f)
    end

    # Import registrations
    leftjoin!(df, import_passenger_vehicles(); on=:fips)
    leftjoin!(df, import_ev_registrations(); on=:fips)

    return df
end

function load_dataset()
    dataset_path = joinpath(PKG_DIR, "data", "dataset.csv")
    if !(isfile(dataset_path) || islink(dataset_path))
        df = ChargerScale.Dataset.dataset()
        try
            CSV.write(dataset_path, df)
        catch
            @warn "unable to cache dataset to $dataset_path"
        end
    else
        df = DataFrame(CSV.File(dataset_path))
    end
    return df
end

"""
    collate_cbsa(df)

Collate county level data into core-based-statical
"""
function collate_cbsa(df, file=joinpath(PKG_DIR, "data", "census", "cbsa_delineation.xlsx"))
    cbsa = DataFrame(XLSX.readtable(file, "List 1", "A:L";
        first_row=3, stop_in_empty_row=true, infer_eltypes=true)
    )
    transform!(cbsa, ["FIPS State Code", "FIPS County Code"] => fips => :fips)
    subset!(cbsa, "CBSA Code" => ByRow(!ismissing))
    select!(cbsa,
        "CBSA Code" => :cbsa,
        "CBSA Title" => :cbsa_name,
        :fips,
    )
    cbsa_county_count = combine(groupby(cbsa, :cbsa), nrow => :n_counties_expected)

    # Map counties to CBSA
    df_cbsa = combine(groupby(innerjoin(cbsa, df; on=:fips), :cbsa),
        nrow => :n_counties,
        :cbsa => first,
        :cbsa_name => first,
        :population => sum,
        :land_area_sq_m => sum,
        :station_count => sum,
        :station_power => sum,
        :median_power => median,
        :n_gas_station => sum,
        :passenger_vehicles => sum,
        :ev_registrations => sum;
        renamecols=false,
    )

    # Drop CBSA missing counties
    df_cbsa = leftjoin(df_cbsa, cbsa_county_count; on=:cbsa)
    subset!(df_cbsa, [:n_counties, :n_counties_expected] => (ByRow(==)))
    select!(df_cbsa, Not(:n_counties))
    select!(df_cbsa, Not(:n_counties_expected))

    return df_cbsa
end

end # MODULE
