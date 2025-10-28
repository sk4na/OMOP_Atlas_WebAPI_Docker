FROM rocker/r-ver:4.3

# System libs for DB + SSL + XML + curl
RUN apt-get update && apt-get install -y --no-install-recommends \
    libssl-dev libpq-dev libcurl4-openssl-dev libxml2-dev \
  && rm -rf /var/lib/apt/lists/*

# R packages
RUN R -q -e "install.packages('remotes', repos='https://cloud.r-project.org')"
RUN R -q -e "remotes::install_cran(c('DatabaseConnector','SqlRender','ParallelLogger','jsonlite'))"

# Achilles (from GitHub; you can pin a tag/commit if you prefer)
RUN R -q -e "remotes::install_github('OHDSI/Achilles')"

