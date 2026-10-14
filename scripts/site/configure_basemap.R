# Browser basemap keys are necessarily visible to site visitors. Use a CARTO
# basemap-only key restricted to the publishing host, never a private API token.
args <- commandArgs(trailingOnly=TRUE)
if(length(args)>1) stop("Usage: Rscript scripts/site/configure_basemap.R [environment-file]")
if(length(args)) readRenviron(args[1])
key <- trimws(Sys.getenv("CARTO_BASEMAP_API_KEY"))
if(!nzchar(key)) stop("Set CARTO_BASEMAP_API_KEY or pass its environment file.")
dir.create("site/assets",recursive=TRUE,showWarnings=FALSE)
jsonlite::write_json(list(provider="CARTO Positron",
  url=paste0("https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png?key=",utils::URLencode(key,reserved=TRUE)),
  attribution='&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors &copy; <a href="https://carto.com/attributions">CARTO</a>'),
  "site/assets/basemap.json",auto_unbox=TRUE,pretty=TRUE)
cat("Configured CARTO browser basemap (key not printed).\n")
