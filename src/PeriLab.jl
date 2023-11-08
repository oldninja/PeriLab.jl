# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

"""
    PeriLab

A module for managing and executing peridynamic simulations in PeriLab.

This module provides functionality for running simulations in the PeriLab environment. It includes functions for initializing simulations, processing data, running solvers, and managing results.

## Modules

- `Support/data_manager.jl`: Data manager module for data management and access.
- `IO/logging.jl`: Module for setting up and managing logging.
- `IO/IO.jl`: Input/output functions for handling data files.
- `Core/Solver/Solver_control.jl`: Solver control module for managing simulation solvers.

## Dependencies

This module depends on the following external packages and modules:
- `MPI`: Message Passing Interface for distributed computing.
- `Pkg`: Julia's package manager for managing project dependencies.
- `TimerOutputs`: Module for measuring and displaying code execution times.
- `Logging`: Julia's built-in logging framework.
- `ArgParse`: Module for parsing command-line arguments.

## Usage

To run a simulation using PeriLab, you can use the `main()` function, which takes several optional parameters to control the simulation process. You can specify whether the simulation should be a dry run, enable verbose output, enable debugging, and run in silent mode.

For example:
```julia
main("examples/Dogbone/Dogbone.yaml", dry_run=true, verbose=true, debug=true, silent=true)
"""

module PeriLab
include("./Support/data_manager.jl")
include("./IO/logging.jl")
include("./IO/IO.jl")
include("./Core/Solver/Solver_control.jl")
# external packages
using MPI
using Pkg
using TimerOutputs
using Logging
using ArgParse
const to = TimerOutput()
# internal packages
using .Data_manager
import .Logging_module
import .IO
import .Solver
# end

export main

"""
    print_banner()

Prints a banner displaying information about the PeriLab application.

This function prints a banner containing details about the PeriLab application, including its name, version, copyright, contact information, and license. It provides a visual introduction to the application.

## Arguments

None.

## Returns

None.

## Usage

```julia
"""

function print_banner()
    println("""\e[]
    \e[1;36mPeriLab. \e[0m                  \e[1;32md8b \e[1;36m888               888\e[0m       |  Version: """ * string(Pkg.project().version) * """ 
    \e[1;36m888   Y88b\e[0m                 \e[1;32mY8P \e[1;36m888               888\e[0m       |
    \e[1;36m888    888\e[0m                     \e[1;36m888               888\e[0m       |  Copyright: Dr.-Ing. Christian Willberg, M.Sc. Jan-Timo Hesse 
    \e[1;36m888   d88P\e[0m \e[1;36m.d88b.\e[0m  \e[1;36m888d888 888 888       \e[1;36m8888b.\e[0m  \e[1;36m88888b.\e[0m   |  Contact: christian.willberg@dlr.de, jan-timo.hesse@dlr.de
    \e[1;36m8888888P"\e[0m \e[1;36md8P  Y8b\e[0m \e[1;36m888P"   888 888          \e[1;36m"88b\e[0m \e[1;36m888 "88b\e[0m  |  
    \e[1;36m888\e[0m       \e[1;36m88888888\e[0m \e[1;36m888\e[0m     \e[1;36m888\e[0m \e[1;36m888\e[0m      \e[1;36m.d888888\e[0m \e[1;36m888  888\e[0m  |  License: BSD-3-Clause
    \e[1;36m888\e[0m       \e[1;36mY8b.\e[0m     \e[1;36m888\e[0m     \e[1;36m888\e[0m \e[1;36m888\e[0m      \e[1;36m888  888\e[0m \e[1;36m888 d88P\e[0m  |  
    \e[1;36m888\e[0m        \e[1;36m"Y8888\e[0m  \e[1;36m888\e[0m     \e[1;36m888\e[0m \e[1;36m88888888\e[0m \e[1;36m"Y888888\e[0m \e[1;36m88888P"\e[0m   |  Gitlab: https://gitlab.com/dlr-perihub/perilab                                                
    """)
end

"""
    parse_commandline()

Parse command-line arguments using the ArgParse package.

This function sets up argument parsing options for various command-line arguments and returns the parsed arguments as a dictionary.

## Arguments

None.

## Returns

- `Dict{String, Any}`: A dictionary containing the parsed command-line arguments.

## Command-Line Arguments

- `--dry_run`: If provided, it stores `true` in the dictionary.
- `--verbose` or `-v`: If provided, it stores `true` in the dictionary.
- `--debug` or `-d`: If provided, it stores `true` in the dictionary.
- `--silent` or `-s`: If provided, it stores `true` in the dictionary.
- `filename`: A required argument that stores the provided filename in the dictionary.

## Usage

```julia
parsed_args = parse_commandline()
"""

function parse_commandline()
    s = ArgParseSettings()

    @add_arg_table! s begin
        "--dry_run"
        help = "dry_run"
        action = :store_true
        "--verbose", "-v"
        help = "verbose"
        action = :store_true
        "--debug", "-d"
        help = "debug"
        action = :store_true
        "--silent", "-s"
        help = "silent"
        action = :store_true
        "filename"
        help = "filename"
        required = true
    end

    return parse_args(s)
end
"""
    main()

Entry point for the PeriLab application.

This function serves as the entry point for the PeriLab application. It parses command-line arguments using `parse_commandline`, processes the arguments, and calls the core `main` function with the parsed arguments.

## Arguments

None.

## Returns

None.

## Usage

```julia
main()
"""
function main()
    parsed_args = parse_commandline()
    if parsed_args["verbose"]
        @info "Parsed args:"
        for (arg, val) in parsed_args
            @info "  $arg  =>  $val"
        end
    end
    main(parsed_args["filename"], parsed_args["dry_run"], parsed_args["verbose"], parsed_args["debug"], parsed_args["silent"])
end

"""
    main(filename, dry_run, verbose, debug, silent)

Main function that performs the core functionality of the program.
# Arguments
- `filename`: The name of the file to process.
- `to`: The destination directory.
- `dry_run`: If `true`, performs a dry run without actually moving the file. Default is `false`.
- `verbose`: If `true`, prints additional information during the execution. Default is `false`.
"""
function main(filename, dry_run=false, verbose=false, debug=false, silent=false)

    @timeit to "PeriLab" begin

        # init MPI as always ...
        MPI.Init()
        comm = MPI.COMM_WORLD
        rank = MPI.Comm_rank(comm)
        size = MPI.Comm_size(comm)

        if !silent
            @timeit to "Logging.init_logging" Logging_module.init_logging(filename, debug, rank, size)
            if rank == 0
                print_banner()
                @info "\n PeriLab version: " * string(Pkg.project().version) * "\n Copyright: Dr.-Ing. Christian Willberg, M.Sc. Jan-Timo Hesse\n Contact: christian.willberg@dlr.de, jan-timo.hesse@dlr.de\n Gitlab: https://gitlab.com/dlr-perihub/perilab\n doi: \n License: BSD-3-Clause\n ---------------------------------------------------------------"
            end
        else
            Logging.disable_logging(Logging.Error)
        end
        #global juliaPath = Base.Filesystem.pwd() * "/"
        global juliaPath = "./"

        ################################
        filename = juliaPath * filename
        filedirectory = dirname(filename)
        # @info filename

        @timeit to "IO.initialize_data" datamanager, params = IO.initialize_data(filename, filedirectory, Data_manager, comm, to)
        @info "Solver init"
        @timeit to "Solver.init" blockNodes, bcs, datamanager, solver_options = Solver.init(params, datamanager)
        if verbose && rank == 0
            IO.show_block_summary(solver_options, params, datamanager)
        end
        @info "Init write results"
        @timeit to "IO.init_write_results" result_files, outputs = IO.init_write_results(params, filedirectory, datamanager, solver_options["nsteps"])
        Logging_module.set_result_files(result_files)

        if dry_run
            nsteps = solver_options["nsteps"]
            solver_options["nsteps"] = 10
            elapsed_time = @elapsed begin
                @timeit to "Solver.solver" result_files = Solver.solver(solver_options, blockNodes, bcs, datamanager, outputs, result_files, IO.write_results, to, silent)
            end

            @info "Estimated runtime: " * string((elapsed_time / 10) * nsteps) * " [s]"
            file_size = IO.get_file_size(result_files)
            @info "Estimated filesize: " * string((file_size / 10) * nsteps) * " [b]"

        else
            @timeit to "Solver.solver" result_files = Solver.solver(solver_options, blockNodes, bcs, datamanager, outputs, result_files, IO.write_results, to, silent)
        end

        IO.close_result_files(result_files)

        if dry_run
            IO.delete_files(result_files)
        end

        if size > 1 && rank == 0
            IO.merge_exodus_files(result_files)
        end
        MPI.Barrier(comm)
        if size > 1
            # IO.delete_files(exos)
        end
        MPI.Finalize()
    end

    if verbose
        @info to
    end
end

end # module