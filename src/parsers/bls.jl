module BLS
using CSV
using DataFrames
using Dates
using ..Parsers: fips

function reduce_file(filename)
    # Read in CSV File
    rows = Dict[]
    is_sic = occursin("sic", filename)
    for row in CSV.File(filename)
        if row.agglvl_code in [22, 30, 75]
            row_data = Dict(
                :year => row.year,
                :qtr => row.qtr,
                :fips => fips(row.area_fips),
                :establishments => is_sic ? row.qtrly_estabs_count : row.qtrly_estabs
            )
            push!(rows, row_data)
        end
    end

    # Construct DataFrame
    df = DataFrame(rows)

    # Combine counts over disclosed and undisclosed entries
    # See: https://www.bls.gov/cew/questions-and-answers.htm
    combine(
        groupby(df, [:year, :qtr, :fips]),
        :establishments => sum;
        renamecols=false
    )
end

function reduce_dir(dir)
    dfs = map(readdir(dir; join=true, sort=false)) do f
        @info f
        reduce_file(f)
    end
    df = vcat(dfs...)

    # Roll up states
    df_state = combine(groupby(df, [:state_fips, :year, :qtr]), :establishments => sum; renamecols=false)
    df_state[!, :county_fips] .= 0
    df = vcat(df, antijoin(df_state, df; on=[:state_fips, :county_fips, :year, :qtr]))

    # Roll up National
    df_national = combine(groupby(df, [:year, :qtr]), :establishments => sum; renamecols=false)
    df_national[!, :state_fips] .= 0
    df_national[!, :county_fips] .= 0
    vcat(df, antijoin(df_national, df; on=[:state_fips, :county_fips, :year, :qtr]))
end

function consolidate()
    # Reduce NAICS and SIC Counts
    df_naics = reduce_dir("data/bls_qcew/naics")
    df_sic = reduce_dir("data/bls_qcew/sic")

    # Add source label and join
    df_naics[!, :source] .= :naics
    df_sic[!, :source] .= :sic
    df = vcat(df_naics, df_sic)

    # Add Time Stamp
    function date(year, qtr)
        qtr_month = [1, 4, 7, 10]
        Date(year, qtr_month[qtr], 1)
    end
    transform!(df, [:year, :qtr] => ByRow(date) => :date)

    return df
end

end
