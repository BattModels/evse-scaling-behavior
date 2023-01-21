function join_registration(df_station, df_registration)
    df = outerjoin(df_station, df_registration;
        on=[:fips, :date=>:snapshot],
        renamecols = "_left" => "_right",
    )
    select!(df, [:fips, :date, :station_count_left, :station_power_left, :count_right])
    rename!(df,
        :count_right => :ev_registrations,
        :station_count_left => :station_count,
        :station_power_left => :station_power,
    )
    sort!(df, :date)

    # Fill in station count data for missing dates with the count
    # from the previous date (Or zero if there is no previous date)
    for g in groupby(df, :fips; sort=false)
        count = 0
        power = 0.0
        for r in eachrow(g)
            if ismissing(r.station_count)
                r.station_count = count
                r.station_power = power
            else
                count = r.station_count
                power = r.station_power
            end
        end
    end

    # Restring to dates that have registration data
    df = semijoin(df, df_registration[!, [:fips, :snapshot]]; on=[:fips, :date=>:snapshot])


    sort!(df, [:fips, :date])
    return df
end

