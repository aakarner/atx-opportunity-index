library(tidyverse)
library(janitor)
setwd("./accessibility/02-data-processing")

#open school accountability csv file
school_q <- read_csv("2025-accountability.csv")

view(school_q)
colnames(school_q)

school_q_clean <-clean_names(school_q)

school_q_austin <- school_q_clean %>%
  filter(distname == "AUSTIN ISD")

view(school_q_austin)  



library(httr2)
req <- request("https://schoolsdata2-tea-texas.opendata.arcgis.com/api/search/v1/catalog")
resp <- req |> req_perform()
data <- resp_body_json(resp)


