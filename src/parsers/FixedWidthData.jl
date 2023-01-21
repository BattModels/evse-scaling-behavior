module FixedWidthData

using Base: Symbol
struct Field{S, T}
    label::S
    range::UnitRange
end
function Field(label::S; start::Int, stop::Int) where {S}
    Field(label, Any, start:stop)
end
function Field(label::S, T, range) where {S}
    Field{S,T}(label, range)
end


function read_row(io::IO, format::Vector{F}) where {F <: Field}
    line = readline(io)
    read_row(line, format)
end
function read_row(line::AbstractString, format::Vector{F}) where {F <: Field{S}} where {S}
    row = Dict{S,Any}()
    for field in format
        try
            read_field!(row, field, line)
        catch
            @error "Error reading: $line"
            rethrow()
        end
    end
    row
end

function read_field!(row::Dict, field::Field{S,T}, line::String) where {S, T}
    str = rstrip(line[field.range])
    if str == ""
        row[field.label] = missing
    else
        row[field.label] = field(str)
    end
    return
end
(field::Field{S, T})(str) where {S, T <: AbstractString} = string(str)
(field::Field{S, T})(str) where {S, T <: Int} = tryparse(T, replace(str, "," => ""))

function read_split_row(io::IO, format::Vector{F}) where {F <: Field{S}} where {S}
    line = readline(io)
    @assert !startswith(line, "Code") line
    row = Dict{S, Any}()
    for field in format
        nchars = length(line)
        if nchars <= last(field.range) && typeof(field) <: Field{S, String}
            # Read as much as possible, then read the next line an append it
            row[field.label] = field(line[first(field.range):nchars])
            line = readline(io)
            row[field.label] = row[field.label] * field(line[field.range])
        else
            # Normal read
            read_field!(row, field, line)
        end
    end
    row
end

end
