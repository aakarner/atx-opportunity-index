

# ======== About r5r ===========

# r5r is an R package for rapid realistic routing on multimodal transport networks (walk, bike, public transport and car). 
# It provides a simple and friendly interface to R5, the Rapid Realistic Routing on Real-world and Reimagined networks, the routing engine developed independently by Conveyal.
# r5r is a simple way to run R5 locally, allowing R users to generate detailed routing analysis or calculate travel time matrices and accessibility using seamless parallel computing.

#Installation: You can install r5r from CRAN
#install.packages("r5r")


#Please bear in mind that you need to have Java Development Kit (JDK) 21 installed on your computer to use r5r. 
#No worries, you don't have to pay for it. There are numerous open-source JDK implementations, any of which should work with r5r. 
#If you don't already have a preferred JDK, we recommend Adoptium/Eclipse Temurin. Other open-source JDK implementations include Amazon Corretto, and Oracle OpenJDK. 
#You only need to install one JDK.
#The easiest way to install JDK is using the new {rJavaEnv} package in R:
  # install.packages('rJavaEnv')
  
  # check version of Java currently installed (if any) 
  #rJavaEnv::java_check_version_rjava()

# install Java 21
#rJavaEnv::java_quick_install(version = 21)
#==============================



options(java.parameters = '-Xmx12G')
Sys.setenv(TZ = 'America/Chicago')

library(r5r)

# ===== SETUP =====
set.seed(732)


data_path <- "accessibility/data/r5_setup"  # Where GTFS and OSM data stored

#https://download.geofabrik.de/north-america/us/texas.html (this website for downloading latest OSM data)

r5r_core <- setup_r5(data_path = data_path, verbose = FALSE)

dir.create(data_path, recursive = TRUE, showWarnings = FALSE)

