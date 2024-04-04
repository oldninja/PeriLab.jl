# SPDX-FileCopyrightText: 2023 Christian Willberg <christian.willberg@dlr.de>, Jan-Timo Hesse <jan-timo.hesse@dlr.de>
#
# SPDX-License-Identifier: BSD-3-Clause

using Documenter, PeriLab, DocumenterCitations, DocumenterMermaid

bib = CitationBibliography(joinpath(@__DIR__, "src", "refs.bib"))

makedocs(
    plugins=[bib],
    modules=[PeriLab],
    authors="Christian Willberg <christian.willberg@dlr.de> and Jan-Timo Hesse <jan-timo.hesse@dlr.de>",
    doctest=true,
    checkdocs=:none, # :all, :exports, :none
    sitename="PeriLab",
    repo=Documenter.Remotes.GitHub("PeriHub", "PeriLab.jl"), format=Documenter.HTML(
        canonical="https://github.com/PeriHub/PeriLab.jl",
        assets=["assets/favicon.ico"],
        edit_link="main"
    ),
    pages=Any[
        "Introduction"=>"index.md",
        "First Steps with PeriLab"=>"man/basics.md",
        "User Guide"=>Any[
            "Getting Started"=>"man/getting_started.md",
            "Input File"=>"man/input_yaml.md",
            "Mesh and Nodesets"=>"man/mesh_input.md",
            "Bond-Filter"=>"man/bond_filter.md",
            "Physics"=>Any[
                "Overview"=>"man/physics/overview.md",
                "Material Models"=>"man/physics/materials.md",
                "Damage Models"=>"man/physics/damage.md",
                "Thermal Models"=>"man/physics/thermal.md",
                "Additive Models"=>"man/physics/additive.md",
            ],
            "Solver"=>"man/solver/solver.md",
        ],
        "Theory"=>Any[
            "Basics"=>"theory/theory.md",
            "Peridynamic Basics"=>Any[
                "Bond-based"=>"theory/theory_bondbased.md",
                "Ordinary state-based"=>"theory/theory_ordinary.md",
                "Non-Ordinary state-based"=>"theory/theory_correspondence.md",
            ],
        ],
        "FAQ"=>"lib/faq.md",
        "Glossar"=>"lib/glossar.md",
        "References"=>"lib/references.md",
        "Useful Links"=>"lib/links.md",
        # "Dev Log"=>"devLog.md",
        "Development"=>Any[
            "Guide"=>"man/dev/developement_guide.md",
            "Datamanager"=>"man/dev/datamanager.md",
            "Module integration"=>"man/dev/module_integration.md",
        ],
        "API"=>Any[
            # "Types" => "lib/types.md",
            "Functions"=>"lib/functions.md",
            "IO Functions"=>"lib/io_functions.md",
            "Physics Functions"=>"lib/physics_functions.md",
            # "Indexing" => "lib/indexing.md",
            # "Metadata" => "lib/metadata.md",
            # hide("Internals" => "lib/internals.md"),
        ],
    ]
)
deploydocs(
    repo="github.com/PeriHub/PeriLab.jl.git",
)