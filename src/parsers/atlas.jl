
function load_ev_registrations(;
    dirname=joinpath(@__DIR__, "..", "..", "data", "ev_registration"),
    zip_crosswalk_path=joinpath(@__DIR__, "..", "..", "data", "zcta_county_crosswalk_2020.csv")
)

    # Snapshot level data of EV registrations
    ev_reg = DataFrame(
        fips=Int[],
        origin_state_fips=Int[],
        snapshot=Date[],
        count=Float64[],
    )

    # Load dataframe for converting zip-level data to county level data

    zip_crosswalk = _import_zip_crosswalk(zip_crosswalk_path)

    # Load the dataframe for mapping county names onto FIPS codes
    county_lookup, state_lookup = _fips_lookup()

    # Build dataframe of states with EV Registrations
    state_abv = ["ca", "co", "ct", "fl", "mt", "mi", "mn", "nj", "ny", "or", "tn", "tx", "vt", "va", "wa", "wi"]
    #state_abv = ["fl"]
    states = DataFrame(state=uppercase.(state_abv))
    states = leftjoin(states, state_lookup; on=:state) |> disallowmissing
    rename!(states, :state => :abv, :state_name=>:name, :state_fips => :fips)

    # Load registration data sets in parallel using threads
    # lock access to shared dataframe before appending to prevent dropped rows
    l = ReentrantLock()
    Threads.@threads  for state in eachrow(states)
        path = joinpath(dirname, "$(lowercase(state.abv)).csv")
        local df_state
        try
            df_state = import_state_registrations(path, state.abv, zip_crosswalk, county_lookup)
            df_state[!, :origin_state_fips] .= state.fips
        catch
            @warn "Failed to load $(state.name)"
            rethrow()
        end

        # Append the state's registration data to the national dataframe
        @lock l append!(ev_reg, df_state; cols=:intersect)
    end

    # Drop rows for states which do not report EV registration data to Atlas
    # Otherwise, do count out of state registrations towards a county's total
    _remove_unknown_states!(ev_reg, states)

    # Split fips into state and county
    transform!(ev_reg, :fips => ByRow(fips_split) => [:state_fips, :county_fips])

    # Interpolate out-of-state registrations onto in-state date
    _interpolate_results!(ev_reg)

    # Consolidate registrations by state and county
    return _collect_out_of_state(ev_reg)
end

# Return true if state is a state with EV registration data or
function _out_of_state(state, origin, reporting_states)
    return state in reporting_states || state == origin
end

function _import_zip_crosswalk(filename)
    df = DataFrame(CSV.File(filename))

    # Limit to relevant info
    select!(df, ["GEOID_ZCTA5_20", "GEOID_COUNTY_20", "AREALAND_PART", "AREALAND_ZCTA5_20"])
    subset!(df, "GEOID_ZCTA5_20" => ByRow(!ismissing))

    # Compute area ratio
    transform!(df, ["AREALAND_PART", "AREALAND_ZCTA5_20"] => ByRow(/) => :area_ratio)

    # Clean up table
    rename!(df, "GEOID_ZCTA5_20" => :zcta, "GEOID_COUNTY_20"=>:fips)
    select!(df, [:zcta, :fips, :area_ratio])
    disallowmissing!(df)

    # Sanity check: Area Ratios sum to 1
    min, max = combine(groupby(df, "zcta"), "area_ratio" => sum).area_ratio_sum |> extrema
    @assert max - min < 1e-10

    return df
end

function _remove_unknown_states!(df, known_states)
    # Mark states as known / unknown if their state fips code is in known_states
    transform!(df, :fips => ByRow(in(known_states.fips)∘Base.Fix2(fld, 1000)) => :known)

    # Report the number of rows that we're dropping, and double check that it's resonable
    n_unknown = count(!, df.known)
    if n_unknown > 0
        dropped = subset(df, :known => ByRow(!))
        sort!(dropped, [:count, :snapshot]; rev=true)
        @warn "Dropped $n_unknown rows as state does not report EV registrations" dropped
    end
    n_unknown > nrow(df)/2 && @error "Dropped more than half of EV registrations"

    # Actually drop the data
    subset!(df, :known => identity)
    select!(df, Not(:known))
    return nothing
end

function _interpolate_results!(df)
    # Get the timestamps at which each state self-reported registrations
    state_snapshot = combine(
        groupby(df, [:origin_state_fips, :snapshot]),
        :snapshot => unique => :snapshot
    )
    sort!(state_snapshot, :snapshot)

    # Get the entries for out of state registrations
    out_of_state = subset(df, [:state_fips, :origin_state_fips] => ByRow(!=); view=true)

    # Interpolate out of state registrations onto the destination state's snapshots
    gdf_origin = groupby(out_of_state, [:origin_state_fips, :state_fips, :county_fips]; sort=false)
    df_oos_reg = combine(x -> _interpolate_group!(x, state_snapshot), gdf_origin)
    transform!(df_oos_reg,
		[:state_fips, :county_fips] => ByRow((s,c) -> 1000*s + c) => :fips
	)
    append!(df, df_oos_reg)
    return nothing
end

_state_snapshots(df, fips) = subset(df, :origin_state_fips => ByRow(==(fips)); view=true)

function _interpolate_group!(df, state_snapshot)
    # Check that df is not empty
    nrow(df) == 0 && return DataFrame(snapshot=Date[], count=Float64[])

    # Get the snapshot timestamps for the origin state
    origin_fips = first(df[!, :origin_state_fips])
    origin_snapshot = _state_snapshots(state_snapshot, origin_fips)

    # Get the source data
    df_src = rightjoin(
        select(df, [:snapshot, :count]; copycols=false),
        select(origin_snapshot, :snapshot; copycols=false);
        on=:snapshot
    )
    replace!(df_src[!, :count], missing => 0)
    sort!(df_src, :snapshot)

    # Build Cubic Spline Interplant
    t = (float∘Dates.date2epochdays).(df_src.snapshot)
    intp = LinearInterpolation(t, df_src[!, :count])

    # Interpolate onto the destination state's snapshots
    dst_fips = first(df[!, :state_fips])
    dst_snapshot = _state_snapshots(state_snapshot, dst_fips)
    if nrow(dst_snapshot) == 0
        @warn "No destination snapshots for $(dst_fips)"
        return DataFrame(snapshot=Date[], count=Float64[])
    end

    # Restring to the domain of the origin's data and only interpolate the missing values
    start = minimum(origin_snapshot.snapshot)
    stop = maximum(origin_snapshot.snapshot)
    dst_snapshot = subset(dst_snapshot, :snapshot => ByRow(x -> start <= x <= stop); view=true)
    dst_snapshot = antijoin(dst_snapshot, origin_snapshot; on=:snapshot)

    # Interpolate the missing values
    dst_y = map((intp∘Dates.date2epochdays), dst_snapshot[!, :snapshot])

    return DataFrame(snapshot=dst_snapshot.snapshot, count=dst_y)
end

#using Infiltrator
function _collect_out_of_state(df)
    transform!(df, [:state_fips, :origin_state_fips] => ByRow(!=) => :oos)
    df_out = DataFrame(
        fips=Int[],
        snapshot=Date[],
        count=Float64[],
        out_of_state_count=Float64[],
    )
    l = ReentrantLock()
    for t in groupby(df, [:state_fips, :county_fips, :snapshot])
        oos_reg = sum(subset(t, :oos).count)
        is_reg = sum(subset(t, :oos => ByRow(!)).count)
        state_fips = first(t.state_fips)
        county_fips = first(t.county_fips)
        fips = state_fips * 1000 + county_fips
        snapshot = first(t.snapshot)
        if !all(t.oos)
            @lock l push!(df_out, (fips, snapshot, is_reg+oos_reg, oos_reg))
        end
    end
    sort!(df_out, [:fips, :snapshot])
    select!(df, Not(:oos))
    return df_out
end

function import_state_registrations(f, state_abv, zip_crosswalk, county_lookup)
    df = DataFrame(CSV.File(f; ntasks=1))
    hasproperty(df, "DMV Snapshot (Date)") && rename!(df, "DMV Snapshot (Date)" => "DMV Snapshot")

    # Fill in state
    hasproperty(df, "State") && rename!(df, "State" => :state_abv)
    hasproperty(df, "State Abbreviation") && rename!(df, "State Abbreviation" => :state_abv)
    if !hasproperty(df, :state_abv)
        df[!, :state_abv] .= state_abv
    end

    # Impute missing data and code registration data to fips codes
    transform!(df, "DMV Snapshot" => ByRow(_snapshot_date) => :snapshot)
    if hasproperty(df, "County GEOID") || hasproperty(df, "County")
        df_state = _county_level_registration!(df, county_lookup)
    else
        df_state = _zip_level_registration!(df, zip_crosswalk)
    end
    disallowmissing!(df_state, [:fips])

    # Add in zeros to in-state registrations
    zero_counties = subset(county_lookup, :state => ByRow(==(state_abv)))[!, [:fips]]
    date_ts = DataFrame(snapshot=unique(df_state[!, :snapshot]))
    zero_counties = crossjoin(zero_counties, date_ts)
    df_state = outerjoin(df_state, zero_counties; on=[:fips, :snapshot])

    # Fill in the state/county fips codes
    disallowmissing!(df_state, [:fips, :snapshot])

    # If an in-state county lacks registrations -> There are zero evs there
    replace!(df_state[!, :count], missing => 0)
    disallowmissing!(df_state, :count)
    return df_state
end

function _county_level_registration!(df, county_lookup)
    if hasproperty(df, "County GEOID")
        # Impute the missing County ids from the ones present in the dataset
        _grouped_impute!(df, "County GEOID")

        # Convert County GEOID to FIPS codes
        transform!(df, "County GEOID" => ByRow(fips) => :fips )
    elseif hasproperty(df, "County")
        # Impute the missing County ids from the ones present in the dataset
        _grouped_impute!(df, "County")

        # Fuzzy match county names to FIPS codes
        transform!(df, ["state_abv", "County"] =>
            ByRow((s,c) -> _match_county(s, c, county_lookup)) => :fips
        )
    else
        error("Missing 'County' or 'County GEOID' column")
    end

    # Collate date by county
    return combine(groupby(df, [:fips, :snapshot]), nrow => :count)
end

"""
Declare `values` as missing and imputes missing values using `imp` after
grouping by `group`
"""
function _grouped_impute!(df, col, group=:snapshot; values=("Unknown",), imp=Impute.SRS())
    allowmissing!(df, col)

    # Replace rows matching values with missing
    foreach(v -> replace!(df[!, col], v => missing), values)

    # Group by the specified column, and impute missing values
    gdf = groupby(df, group)
    transform!(gdf, col => x -> Impute.impute!(x, imp); renamecols=false)

    # At this point all values should be imputed
    disallowmissing!(df, col)
    return nothing
end

function _match_county(state, county, county_lookup)
    county_in_state = subset(county_lookup, :state => ByRow(==(state)); view=true)
    (ismissing(state) || ismissing(county)) && error("Missing county name")
    counties = county_in_state[!, :county]
    idx = findfirst(==(county), counties)
    if isnothing(idx)
        _, idx = findnearest(county, counties, Partial(Levenshtein()))
        @assert !isnothing(idx) "No county found for '$(county) in $county_lookup'"
    end
    return county_in_state[idx, :fips]
end

function _zip_level_registration!(df, zip_crosswalk)
    transform!(df, "DMV Snapshot" => ByRow(_snapshot_date) => :snapshot)

    # Impute the missing ZIP codes from the dataset
    _grouped_impute!(df, "ZIP Code")

    # Convert String ZIP Codes to Integers
    if eltype(df[!, "ZIP Code"]) <: AbstractString
        # Convert ZIP Code to Integer
        transform!(df, "ZIP Code" => ByRow(x -> Base.tryparse(Int, x)) => "Parsed ZIP Code")

        # Montana has "L7M4R" and "N1L0A" ZIP codes.
        # Former is a Canadian ZIP code the latter is unknown (Possible data entry)
        df_drop = filter("ZIP Code" => isnothing, df)
        if nrow(df_drop) > 0
            @info "Dropping non-us ZIP codes" filter("ZIP Code" => isnothing, df)
        end

        # Drop rows that have non-us ZIP codes
        filter!("Parsed ZIP Code" => !isnothing, df)
        select!(df, Not("ZIP Code"))

        # Convert Parsed Zip Codes to Ints and drop source column
        df[!, "ZIP Code"] = Int.(df[!, "Parsed ZIP Code"])
        select!(df, Not("Parsed ZIP Code"))
    end
    zip_type = eltype(df[!, "ZIP Code"])
    @assert zip_type <: Int "Got unexpected ZIP code type: $(zip_type)"

    # Convert ZIP Code to FIPS codes
    df_zip = combine(groupby(df, ["ZIP Code", "snapshot"]), nrow)
    df_joined = innerjoin(df_zip, zip_crosswalk; on="ZIP Code" => "zcta")
    transform!(df_joined, [:nrow, :area_ratio] => ByRow(*) => :count)
    select!(df_joined, [:fips, :snapshot, :count])

    return combine(groupby(df_joined, Not(:count)), :count => sum => :count)
end

function _snapshot_date(s)
    m = match(r"\((.*)\)", s)
    isnothing(m) && return missing
    try
        return Date(m[1], dateformat"m/d/yyy")
    catch
        # Try year only
        return Date(m[1], dateformat"yyyy")
        return missing
    end
end
