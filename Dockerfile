FROM julia:1.8.5

COPY /src /src
COPY README.md /
COPY Project.toml /
COPY Manifest.toml /
COPY paper.jl /
RUN julia --project -e 'using Pkg; Pkg.instantiate()'

VOLUME ["/img", "/data"]

ENTRYPOINT julia --project -L /paper.jl -e 'main()'
