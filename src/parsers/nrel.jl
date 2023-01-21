function process_station_data(filename, rev_geocoder)
    df = DataFrame(CSV.File(filename))

    # Drop Ontario Rows
    subset!(df, :State => ByRow(!=("ON")))

    # Estimate the total power output of the station
    df[!, :station_ports] = count_station_ports(df)
    df[!, :station_power] = estimate_station_power(df)

    # Apply Manual Fixes
    fix_station!(df, "Hawaii Prince Golf Club"; long=-158.009171, lat=21.328434)
    fix_station!(df, "Stadium Marketplace"; long=-157.928437, lat=21.363734)
    fix_station!(df, "Four Seasons Resort Hualalai"; long=-155.991648, lat=19.8278417)
    fix_station!(df, "7-Eleven Hawaii Kai provided by Hawaiian Electric"; long=-157.71057, lat=21.293919)
    fix_station!(df, "Maine Maritime Academy"; long=-68.802641, lat=44.389198)
    fix_station!(df, "PH Urban Renewal, LLC"; long=-74.038117, lat=40.717515)
    fix_station!(df, "PTC Garage"; long=-79.959539, lat=40.430789)

    # Reverse Geocode Stations to counties
    fips_code, error = rev_geocoder(df[!, :Longitude], df[!, :Latitude])
    df[!, :fips] = fips_code
    df[!, :geocode_error] = error

    # Check that the geocoding worked
    row_errors = subset(df, :geocode_error => ByRow(>(0)))
    if nrow(row_errors) > 0
        @warn "Possible Reverse Geocoding Errors" row_errors[!, ["Station Name", "Street Address", "Longitude", "Latitude", "fips"]]
    end
    disallowmissing!(df, :fips)

    return df
end

function fix_station!(df, station_name; lat, long)
    # Check that only one station matches
    station = subset(df, "Station Name" => ByRow(==(station_name)), view=true)
    @assert nrow(station) == 1 "Error correcting $station_name. Found $(nrow(station)) ≠ 1 stations"

    # Correct the coordinates
    station[!, :Longitude] .= long
    station[!, :Latitude] .= lat
    return nothing
end

function charge_timeseries(df, date_col="Open Date")
    _grouped_impute!(df, :station_power, :fips)
    disallowmissing!(df, [:station_power, :fips])
    sort!(df, date_col)
    df_known = subset(df, date_col => ByRow(!ismissing); view=true)
    gdf = groupby(df_known, :fips; sort=false)
    dfo = DataFrame(
        fips=Int[],
        date=Date[],
        station_count=Int[],
        station_power=Float64[],
        median_power=Float64[],
    )
    l = ReentrantLock()
    Threads.@threads for g in gdf
        #sort!(g, date_col)
        g_fips = first(g.fips)
        dates = g[!, date_col]
        station_power = g[!, :station_power]
        g_out = DataFrame(
            fips=Int[],
            date=Date[],
            station_count=Int[],
            station_power=Float64[],
            median_power=Float64[],
        )

        # Accumulate total power and station count
        count = 0
        power = 0.0
        date = first(dates)
        n = length(dates)
        np = 0
        for i in 1:n
            # If the data changes, push the current stats
            if dates[i] != date
                push!(g_out, (g_fips, date, count, power, median(station_power[1:i])))
                date = dates[i]
                np += 1
            end

            # Accumulate the current station
            count += 1
            power += station_power[i]
        end
        # Push the final stats
        push!(g_out, (g_fips, date, count, power, median(station_power)))
        np += 1

        # Append County stats to the cumulative dataframe
        @lock l append!(dfo, g_out)
    end
    return dfo
end

function estimate_station_power(df::DataFrame)
    n = nrow(df)
    power = Vector{Union{Float64, Missing}}(undef, n)
    @batch for i in 1:n
        power[i] = estimate_station_power(df[i, :])
    end
    return power
end

function estimate_station_power(row::DataFrameRow)
    power = coalesce(row["EV Level1 EVSE Num"], 0.0) * 1.4e3
    power += coalesce(row["EV Level2 EVSE Num"], 0.0) * 7.2e3
    power += coalesce(row["EV DC Fast Count"], 0.0) * 50.0e3
    return power == 0 ? missing : power
end

function count_station_ports(df::DataFrame)
    n = nrow(df)
    power = Vector{Union{Float64, Missing}}(undef, n)
    @batch for i in 1:n
        power[i] = count_station_ports(df[i, :])
    end
    return power
end

function count_station_ports(row::DataFrameRow)
    ports = coalesce(row["EV Level1 EVSE Num"], 0.0)
    ports += coalesce(row["EV Level2 EVSE Num"], 0.0)
    ports += coalesce(row["EV DC Fast Count"], 0.0)
    return ports == 0 ? missing : ports
end

"""
Select the latest row for each group that occurs before date
"""
function select_latest(df, date::Date=Date(2021); datecol=:date, group=(:fips,))
    df_year = subset(df, datecol => ByRow(<(date)))
    return combine(groupby(df_year, group...)) do gdf
        sort(gdf, datecol; rev=true)[1, :]
    end
end
select_latest(df, year::Int; kwargs...) = select_latest(df, Date(year+1); kwargs...)

function select_year(df, year=2020)
    df_year = subset(df, :date => ByRow(x -> Date(year) <= x < (Date(year+1))))
    return combine(groupby(df_year, :fips)) do gdf
        sort(gdf, :date; rev=true)[1, Not(:date)]
    end
end
