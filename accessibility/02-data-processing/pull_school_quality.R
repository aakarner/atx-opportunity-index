library(tidyverse)
library(janitor)
setwd("./accessibility/02-data-processing")

#open school accountability csv file
school_q <- read_csv("C:\\Users\\JHage.CNTPROJECTS\\OneDrive - CNT\\CNT Team Site - 1684 Austin Housing\\data\\2025-accountability.csv")

view(school_q)
colnames(school_q)

school_q_clean <-clean_names(school_q)

school_q_austin <- school_q_clean %>%
  filter(distname == "AUSTIN ISD")

view(school_q_austin)  
