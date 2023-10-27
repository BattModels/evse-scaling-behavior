# Scaling Behavior for Electric Vehicle Chargers and Road Map to Addressing the Infrastructure Gap

![Paper](https://img.shields.io/badge/Paper-10.1093%2Fpnasnexus%2Fpgad341-purple)
[![Dataset](https://img.shields.io/badge/Data-10.5281%2Fzenodo.5784659-blue)](https://doi.org/10.5281/zenodo.5784659)
![GitHub](https://img.shields.io/github/license/BattModels/evse-scaling-behavior)

<p align="center">
    <a href="https://battmodels.github.io/evse-scaling-behavior/map.html">
        <img src="docs/assets/ev_pop_residuals.svg" width="60%">
    </a>
</p>

Source code and [interactive demo](https://battmodels.github.io/evse-scaling-behavior/map.html) for [_Scaling Behavior for Electric Vehicle Chargers and Road Map to Addressing the Infrastructure Gap_](https://doi.org/10.1093/pnasnexus/pgad341).

## Getting the Data

The processed dataset, as used in the paper for model fitting, is available at
[data/dataset.csv](data/dataset.csv). The source datasets, as documented in the [supporting
information](https://academic.oup.com/pnasnexus/article-lookup/doi/10.1093/pnasnexus/pgad341#supplementary-data), were collected from the following sources:

| Source | Relevant Files | Source |
|--------|----------------|--------|
| US Bureau of Labor Statistics, Quarterly Census of Labor Statistics | `data/blc_qcew` | https://www.bls.gov/cew/ |
| Atlas State EV Registration Data | `data/ev_registration` | https://www.atlasevhub.com/materials/state-ev-registration-data/ |
| US Census Bureau | `data/census` | https://www.census.gov/ |
| NREL's Alternative Fuel API dataset | `data/nrel_ev_stations.csv` | https://developer.nrel.gov/docs/transportation/alt-fuel-stations-v1/ |
| State Registration | `data/census` | Various, See SI |

> More precise references, particularly for US Census data, are available in the
> supporting information.

Script for processing the various raw source datasets have also been provided.
Please note that this remains a largely manual process. For example, the PA
passenger vehicle registration reports were manually transcribed from the
source pdf. Further,
the data extraction scripts, particularly for state registration data, are highly
sensitive to data inputs, and their outputs should be manually verified.

- State Registrations:
    - State-By-State Preprocessing: See the `parse*` scripts located in the State's folder.
    - Collating States: `data/state_registration/extract_passenger_vehicles.py`
- EV Registrations
    - Makefile for fetching new results: `data/ev_registration/makefile`
    - From within `data/ev_registration` run `make all`
- BLS Datafiles:
    - Script: `data/fetch_bls_data.jl]`
    - Makefile for running: `data/makefile`, run `make ./bls_qcew` from within `data/`
- Census Bureau:
    - Shapefiles can be downloaded by running `make fetch-data` from within `data/`

## Unprocessed Data

Due to size constraints, this repository does not provide the unprocessed data files
used to develop our dataset. It can be found at: <https://doi.org/10.5281/zenodo.5784659>

## Replicating the Analysis

Collating the processed datasets (See above), model fitting and plotting was
handled by the [paper.jl](paper.jl) script making heavy use of the code located in
[src/](src/) using [Julia](https://julialang.org/). The code was developed using
v1.8.5, and may or may not work with other versions (although we suspect it
will).

To run the analysis, from the root directory run the following:

```shell
julia --project -L ./paper.jl -e 'using Pkg; Pkg.instantiate(); main()'
```

Update plots will be saved to [img/](img/) and tabulated predictions will be saved
to [charger_scaling_predictions.csv](charger_scaling_predictions.csv). Further inspection of the models, fit
statistics, and more is possible by entering the Julia REPL as shown below:

```shell
> julia --project -L ./paper.jl

julia> fig, models, model_comparisons, df, df_out = main();
[...]
julia> models["county"]["population"] # To inspect the stations vs. population fits
[...]
julia> models["county"]["population"] |> ChargerScale.Models.model_report # Useful summary stats
[...]
```

## Docker Container

We have provided a [Docker](https://www.docker.com/) container for replicating
the above analysis. To use, follow the relevant Docker [installation
instructions](https://docs.docker.com/get-docker/) for your system. Then:

1. Download and extract the container and complete dataset from: https://doi.org/10.5281/zenodo.5784659
1. Import the container image: `docker import evse-scaling-docker.tar.gz evse-scaling:latest`
2. Run the container with the following command

```shell
docker run --rm -it \
    --volume="$(pwd)/data:/data:ro" \
    --volume="$(pwd)/img-docker:/img" \
    evse-scaling:latest
```

This will mount the [data/](data/) directory as read-only and save any generated images
to the `img-docker/` directory on the host machine.

### Building the Container

The docker image can be built using: `docker build -t evse-scaling:latest .`
