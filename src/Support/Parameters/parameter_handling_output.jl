# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

"""
    check_for_duplicates(filenames)

Check for duplicate filenames.

# Arguments
- `filenames::Vector{String}`: The filenames
"""
function check_for_duplicates(filenames::Vector{String})
    returnfilenames = []
    checked_filenames = []
    for filename in filenames
        if (filename in checked_filenames) == false
            num_same_filenames = length(findall(x -> x == filename, filenames))
            if num_same_filenames > 1
                @error "Filename $filename is used $num_same_filenames times"
            end
        end
    end
end

"""
    get_output_filenames(params::Dict, filedirectory::String)

Gets the output filenames.

# Arguments
- `params::Dict`: The parameters
- `filedirectory::String`: The file directory
# Returns
- `filenames::Vector{String}`: The filenames
"""
function get_output_filenames(params::Dict, filedirectory::String)
    if haskey(params::Dict, "Outputs")
        filenames::Vector{String} = []
        outputs = params["Outputs"]
        for output in keys(outputs)
            output_type = get_output_type(outputs, output)
            if haskey(outputs[output], "Output Filename")
                filename = outputs[output]["Output Filename"]
                if output_type == "CSV"
                    filename = filename * ".csv"
                else
                    filename = filename * ".e"
                end
                push!(filenames, joinpath(filedirectory, filename))
            end
        end
        check_for_duplicates(filenames)

        return filenames
    end
    return []
end

"""
    get_output_type(outputs::Dict, output::String)

Gets the output type.

# Arguments
- `outputs::Dict`: The outputs
- `output::String`: The output
# Returns
- `output_type::String`: The output type
"""
function get_output_type(outputs::Dict, output::String)
    if haskey(outputs[output], "Output File Type")
        return outputs[output]["Output File Type"]
    else
        @warn "No Output File Type defined for $output, defaulting to Exodus"
        return "Exodus"
    end
end

"""
    get_flush_file(outputs::Dict, output::String)

Gets the flush file.

# Arguments
- `outputs::Dict`: The outputs
- `output::String`: The output
# Returns
- `flush_file::Bool`: The flush file
"""
function get_flush_file(outputs::Dict, output::String)
    if haskey(outputs[output], "Flush File")
        return outputs[output]["Flush File"]
    else
        return false
    end
end

"""
    get_output_fieldnames(outputs::Dict, variables::Vector{String}, computes::Vector{String}, output_type::String)

Gets the output fieldnames.

# Arguments
- `outputs::Dict`: The outputs
- `variables::Vector{String}`: The variables
- `computes::Vector{String}`: The computes
- `output_type::String`: The output type
# Returns
- `output_fieldnames::Vector{String}`: The output fieldnames
"""
function get_output_fieldnames(outputs::Dict, variables::Vector{String}, computes::Vector{String}, output_type::String)
    return_outputs = String[]
    for output in keys(outputs)
        if !isa(outputs[output], Bool)
            @error "Output variable $output must be set to True or False"
        end
        if outputs[output]
            if output_type == "CSV"
                if output in computes
                    push!(return_outputs, output)
                else
                    @warn '"' * output * '"' * " is not defined as global variable"
                end
            else
                if output in variables || output in computes
                    push!(return_outputs, output)
                elseif output * "NP1" in variables
                    push!(return_outputs, output * "NP1")
                else
                    @warn '"' * output * '"' * " is not defined as variable"
                end
            end
        end
    end
    return return_outputs
end

"""
    get_outputs(params::Dict, variables::Vector{String}, compute_names::Vector{String})

Gets the outputs.

# Arguments
- `params::Dict`: The parameters
- `variables::Vector{String}`: The variables
- `compute_names::Vector{String}`: The compute names
# Returns
- `outputs::Dict`: The outputs
"""
function get_outputs(params::Dict, variables::Vector{String}, compute_names::Vector{String})
    num = 0
    if haskey(params, "Outputs")
        outputs = params["Outputs"]
        for output in keys(outputs)
            output_type = get_output_type(outputs, output)
            if (haskey(outputs[output], "Output Variables")) && (length(outputs[output]["Output Variables"]) > 0)
                outputs[output]["fieldnames"] = get_output_fieldnames(outputs[output]["Output Variables"], variables, compute_names, output_type)
            else
                @warn "No output variables are defined for " * output * "."
            end

        end
    end
    return outputs
end

"""
    get_output_frequency(params::Dict, nsteps::Int64)

Gets the output frequency.

# Arguments
- `params::Dict`: The parameters
- `nsteps::Int64`: The number of steps
# Returns
- `freq::Vector{Int64}`: The output frequency
"""
function get_output_frequency(params::Dict, nsteps::Int64)

    if haskey(params::Dict, "Outputs")
        outputs = params["Outputs"]
        freq = zeros(Int64, length(keys(outputs)))
        for (id, output) in enumerate(keys(outputs))
            output_options = Dict("Output Frequency" => false, "Number of Output Steps" => false)
            freq[id] = 1

            if (haskey(outputs[output], "Output Frequency") && haskey(outputs[output], "Number of Output Steps"))
                output_options["Number of Output Steps"] = true
                @warn "Double output step / frequency definition. First option is used. ''Output Frequency'' is ignored."
            else
                for output_option in keys(output_options)
                    if haskey(outputs[output], output_option)
                        output_options[output_option] = true
                    end
                end
            end
            for output_option in keys(output_options)
                if !output_options[output_option]
                    continue
                end
                freq[id] = outputs[output][output_option]
                if output_options["Number of Output Steps"]
                    freq[id] = Int64(ceil(nsteps / freq[id]))
                    if freq[id] < 1
                        freq[id] = 1
                    end
                end
                if freq[id] > nsteps
                    freq[id] = nsteps
                end
            end
        end

    end

    return freq
end