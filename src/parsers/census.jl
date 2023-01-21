function census(filename)
    raw_census = JSON.parsefile(filename)
    census = DataFrame()
    data_type = Dict(
        "POP" => Int,
        "state" => Int,
        "county" => Int,
    )
    for (fdx, field) in enumerate(raw_census[1])
        col_data = (i[fdx] for i in raw_census[2:end])
        if haskey(data_type, field)
            dtype = data_type[field]
            census[!, field] = Base.parse.(dtype, col_data)
        else
            census[!, field] = col_data |> collect
        end
    end
    census
end

function import_census_popest(filename)
    df = DataFrame(CSV.File(filename;
        select=(i, name) -> name in Symbol.(["SUMLEV", "STATE", "COUNTY", "POPESTIMATE2020"]),
    ))
    subset!(df, :SUMLEV => ByRow(==(50)))
    transform!(df, [:STATE, :COUNTY] => ByRow((s,c) -> 1000*s + c) => :fips)
    rename!(df, :POPESTIMATE2020 => :population)
    select!(df, [:fips, :population])
    return df
end

function import_census_csv(filename::String)
    raw = CSV.File(filename) |> DataFrame

    # Stack Population Estimates
    df = stack(raw, r"POPESTIMATE.*",
        ["SUMLEV", "REGION", "DIVISION", "STATE", "COUNTY", "STNAME", "CTYNAME"]
    )
    rename!(df, Dict(
        :SUMLEV => :summary_level,
        :REGION => :region,
        :DIVISION => :division,
        :STATE => :state_fips,
        :COUNTY => :county_fips,
        :STNAME => :state_name,
        :CTYNAME => :county_name,
        :variable => :year,
        :value => :population
    ))

    # Parse Years to Ints
    transform!(df, :year => ByRow(x -> parse(Int, match(r"\d+", x).match)) => :year)

    df
end

function import_census_block(filename)
    open(filename, "r") do io
        for line in eachline(io)
            if startswith(line, "Block")
                return read_census_block(io)
            end
        end
    end
end

function read_census_block(io)
    format = [
        FixedWidthData.Field(:block_number, Int, 1:2),
        FixedWidthData.Field(:state_fips, Int, 4:5),
        FixedWidthData.Field(:county_fips, Int, 6:8),
        FixedWidthData.Field(:year_1999, Int, 10:21),
        FixedWidthData.Field(:year_1998, Int, 22:33),
        FixedWidthData.Field(:year_1997, Int, 34:45),
        FixedWidthData.Field(:year_1996, Int, 46:57),
        FixedWidthData.Field(:year_1995, Int, 58:69),
        FixedWidthData.Field(:year_1994, Int, 70:81),
        FixedWidthData.Field(:year_1993, Int, 82:93),
        FixedWidthData.Field(:year_1992, Int, 94:105),
        FixedWidthData.Field(:year_1991, Int, 106:117),
        FixedWidthData.Field(:year_1990, Int, 118:129),
        FixedWidthData.Field(:area_name, String, 142:176),
    ]
    line = ""
    while line == ""
        line = readline(io)
    end
    rows = Dict[]
    while line != "" && line != " "
        push!(rows, FixedWidthData.read_row(line, format))
        line = readline(io)
    end

    # Construct Dataframe
    df = stack(DataFrame(rows), r"year_\d+")
    rename!(df, Dict(
        :variable => :year,
        :value => :population
    ))

    # Drop Rows with bytes errors
    # FIXME: Fill in corrupted data from other tables
    df = df[(!isnothing).(df.population), :] .|> coalesce

    # Coalesce missing state / county fips codes
    df.state_fips = coalesce.(df.state_fips, 0)
    df.county_fips = coalesce.(df.county_fips, 0)

    # Parse Years to Ints
    transform!(df, :year => ByRow(x -> parse(Int, match(r"\d+", x).match)) => :year)
end

function import_census_txt(filename)
    @info "Importing $filename"
    format = [
        FixedWidthData.Field(:state_fips, Int, 1:2),
        FixedWidthData.Field(:county_fips, Int, 3:5),
        FixedWidthData.Field(:area_name, String, 6:22),
        FixedWidthData.Field(:year_1, Int, 23:31),
        FixedWidthData.Field(:year_2, Int, 33:41),
        FixedWidthData.Field(:year_3, Int, 43:51),
        FixedWidthData.Field(:year_4, Int, 53:61),
        FixedWidthData.Field(:year_5, Int, 63:71),
    ]

    # Read in File
    dfs = []
    open(filename, "r") do io
        while !eof(io)
            line = readline(io)
            # Scan to start of block
            while !startswith(line, "Code")
                line = readline(io)
            end

            # Read block
            push!(dfs, read_census_txt_table(io, line, format))
        end
    end
    vcat(dfs...)
end

function  read_census_txt_table(io, header, format)
    # Get years
    years = split(header, " "; keepempty=false)[4:end] .|> x -> parse(Int, x)

    # Read in rows
    rows = []
    mark(io)
    line = readline(io)

    # Check for leading blank (Occurs in 1970 File)
    if line == ""
        mark(io)
        line = readline(io)
    end

    # Check we are not still on the Code line
    @assert !startswith(line, "Code") line

    # Loop over rows
    while line != ""
        reset(io)
        mark(io)
        try
            push!(rows, FixedWidthData.read_split_row(io, format))
        catch
            reset(io)
            @error "Was reading: $(readline(io))"
            rethrow()
        end
        mark(io)
        line = readline(io)
    end

    # Convert to Dataframe
    df = stack(DataFrame(rows), r"year_\d")
    transform!(df,
        :variable => ( x -> replace(x, ("year_$i" => years[i] for i in 1:5)...) );
        renamecols=false,
    )
    rename!(df, Dict(:variable => :year, :value => :population))

    return df
end

function import_census()
    cols = [:state_fips, :county_fips, :population, :year]
    vcat(
        import_census_csv("data/census/2010/population.csv")[!, cols],
        import_census_csv("data/census/2000/population.csv")[!, cols],
        import_census_block("data/census/1990/population.txt")[!, cols],
        import_census_txt("data/census/1980/population.txt")[!, cols],
        import_census_txt("data/census/1970/population.txt")[!, cols],
    )
end

function _fips_lookup(;year="2010")
    # Load shapefile of county boundaries provided by US Census
    files = readdir(joinpath("data", "census", year, "geography_20m"); join=true)
    file = filter(endswith(".shp"), files) |> first
    df = DataFrame(Shapefile.Table(file))

    # Select relevant columns and rename for convenience
    select!(df, [:GEOID, :NAME, :STUSPS, :STATE_NAME])
    rename!(df, "NAME" => :county, "STUSPS" => :state, "STATE_NAME" => :state_name)
    transform!(df, "GEOID" => ByRow(fips) => :fips)
    transform!(df, :fips => ByRow(fips_split) => [:state_fips, :county_fips])
    select!(df, Not("GEOID"))
    sort!(df, [:state, :county])

    # Consolidate to state lookup table
    df_state = combine(groupby(df, :state_fips)) do t
        @assert length(unique(t.state)) == 1
        return first(select(t, [:state_fips, :state, :state_name]))
    end

    return df, df_state
end

