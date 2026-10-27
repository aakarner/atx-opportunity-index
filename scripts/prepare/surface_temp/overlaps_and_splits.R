#
# library of functions 
#
get_overlap_fraction_table<-function(xls_file,shape1,shape2){
  wrksheet<-paste(shape1,'_',shape2,'_fracs',sep='')
  print(paste('looking for ',wrksheet))
  if(!(wrksheet %in% xls_file$sheet_names)){
    wrksheet<-paste(shape2,'_',shape1,'_fracs',sep='')
    if(!(wrksheet %in% xls_file$sheet_names)){
      wrksheet<-'none'     
    }
  }
  wrksheet
}

get_overlap_fractions<-function(xls_file,shape1,shape2,ndx1,ndx2,write_xls){
  #
  # get the sheet that is needed or create it if it not there
  #
  #xls_file<-gz_scenario
  #shape1<-'blkgrps'
  #ndx1<-'geoid'
  #shape2<-'gzs'
  #ndx2<-'gz_id'
  #
  # get tiger path
  #
  #index<-wb_read(xls_file,sheet='index')
  tiger_path<-'./gis/'
  #
  # now get the correct overlap worksheet
  #
  wrksheet<-get_overlap_fraction_table(xls_file,shape1,shape2)
  if(wrksheet == 'none'){
    #
    # get shape files
    #
    shp1<-st_read(dsn = paste(tiger_path,shape1,'.gpkg',sep=''))
    shp2<-st_read(dsn = paste(tiger_path,shape2,'.gpkg',sep=''))
    #
    # now shp1 and shp2 fracs
    #
    wrksheet<-paste(shape1,'_',shape2,'_fracs',sep='')
    fracs <- intersect_polygons(shp1,shp2,ndx1,ndx2,shape1,shape2)
    head(fracs)
    if(write_xls==1){
      add_xls_tab(xls_file,wrksheet,fracs)
      index<-wb_read(xls_file,sheet='index')
      location<-index$value[2]
      wb_save(xls_file,file=location,overwrite = TRUE)
    }
  }
  else {fracs<-wb_read(xls_file,sheet=wrksheet)}
  fracs
}

sum_var_using_fractions<-function(xls_file,shape1,ndx1,shape2,ndx2,data_tab,var_name,write_xls=1){
  # 
  # xls_file is the excel file
  # shape1 is the name of the shape file that we want to aggregate to 
  # ndx1 is the index of shape1
  # shape2 is the name of the shape file that we want to aggregate over
  # ndx2 is the index of shape2 
  # data_tab is the data we are aggregating, with index ndx2
  # var_name is the data field we are summing up
  #
  # for example
  # gz_scenario,'gzs','gz_id ','blkgrps','geoid', blkgrp_hhs_2023,'households'
  #xls_file<-gz_scenario
  #shape1<-'gzs'
  #ndx1<-'gz_id'
  #shape2<-'blkgrps'
  #ndx2<-'geoid'
  #data_tab<-blkgrp_hhs_2023
  #var_name<-'households'
  #
  fracs<-get_overlap_fractions(xls_file,shape1,shape2,ndx1,ndx2,write_xls)
  fracs<-merge(fracs,subset(data_tab,select=c(ndx2,var_name)),ndx2)
  head(fracs)
  fracs[[var_name]]<-fracs[[paste('frac_of_',shape2,sep='')]]*fracs[[var_name]]
  head(fracs)
  sm<-aggregate(x = fracs[[var_name]], by = list(Category = fracs[[ndx1]]), FUN = sum)
  names(sm)<-c(ndx1,var_name)
  sm
}

average_var_using_fractions<-function(xls_file,shape1,ndx1,shape2,ndx2,data_tab,var_name){
  # 
  # xls_file is the excel file
  # shape1 is the name of the shape file that we want to aggregate to 
  # ndx1 is the index of shape1
  # shape2 is the name of the shape file that we want to aggregate over
  # ndx2 is the index of shape2 
  # data_tab is the data we are aggregating, with index ndx2
  # var_name is the data field we are averaging
  #
  # for example
  #
  #xls_file<-pda_scenario
  #shape1<-'sdistricts'
  #ndx1<-'suprdistid'
  #shape2<-'agg_geom'
  #ndx2<-'obj_id'
  #data_tab<-sdistricts_projections
  #var_name<-'hh_rat'
  #
  this_frac<-paste('frac_of_',shape1,sep='')  
  fracs<-get_overlap_fractions(xls_file,shape1,shape2,ndx1,ndx2)
  fracs<-subset(fracs,select=c(ndx1,ndx2,this_frac))
  fracs<-merge(fracs,subset(data_tab,select=c(ndx2,var_name)),ndx2)
  fracs[[var_name]]<-fracs[[this_frac]]*fracs[[var_name]]
  agg_data<-aggregate(x = fracs[[var_name]], by = list(Category = fracs[[ndx1]]), FUN = sum)
  names(agg_data)<-c(ndx1,var_name)
  agg_dataf<-aggregate(x = fracs[[this_frac]], by = list(Category = fracs[[ndx1]]), FUN = sum)
  names(agg_dataf)<-c(ndx1,'wt')
  agg_data<-merge(agg_data,agg_dataf,ndx1)
  agg_data[[var_name]]<-agg_data[[var_name]]/agg_data$wt
  agg_data$wt<-NULL
  head(agg_data)
  agg_data
}


get_acs_variable<-function(acs_geo,acs_var,var_name,ndx,yr,st,cnts){
  #
  #
  #
  # acs_geo<-'block group'
  # acs_var<-'B25009_001'
  # var_name<-'households'
  # ndx<-'GEOID'
  # yr<-2023
  # st<-'06'
  # cnts<-mtc_counties$fipco
  #
  acs_data<-get_acs(geography = acs_geo, variables = acs_var,
                                          state=st,county =cnts, geometry = FALSE, year = yr)
  names(acs_data)[4]<-var_name
  acs_data<-subset(acs_data,select=c(ndx,var_name))
  acs_data
}



intersect_polygons<-function(p1,p2,ndx1,ndx2,nm1,nm2){
  #print(paste('inputs are:',p1,p2,ndx1,ndx2,nm1,nm2))
  #
  # this function makes a data.frame with the area of intersection of two polygons, and the fraction that 
  #  it covers for each polygon is for each
  #
  #   p1 - is one polygon layer
  #   p2 - is the other polygon layer
  #   ndx1 - the index into layer p1
  #   ndx2 - the index into layer p2
  #   nm1 - the name of layer p1
  #   nm2 - the name of layer p2
  #   
  # for example if you want to find the fraction of jurisdictions covered by pdas:
  # blkgrps,agg_geom,"geoid",'obj_id','blkgrps','agg_geom'
  #p1<-shp1
  #p2<-shp2
  #ndx1<-ndx1
  #ndx2<-ndx2
  #nm1<-shape1
  #nm2<-shape2
  #
  p2<-st_transform(p2,st_crs(p1))
  p2<-st_set_crs(p2,st_crs(p1))
  p1$geom<-st_make_valid(p1$geom)
  p2$geom<-st_make_valid(p2$geom)
  sf_use_s2(FALSE)
  p1$acres1<-set_units(st_area(p1$geom),'acre')
  p2$acres2<-set_units(st_area(p2$geom),'acre')
  p1$rowid1<-as.integer(rownames(p1))
  p2$rowid2<-as.integer(rownames(p2))
  p1_p2_intersecting <- {}
  p1_p2_intersecting<-st_intersection(p1,p2)
  p1_p2_intersecting$geom<-st_make_valid(p1_p2_intersecting$geom)
  p1_p2_intersecting$intersection_acres<-set_units(st_area(p1_p2_intersecting$geom),'acre')
  sf_use_s2(TRUE)
  p1_p2_intersecting<-st_drop_geometry(p1_p2_intersecting)
  p1_p2_intersecting<-subset(p1_p2_intersecting,
                             as.numeric(p1_p2_intersecting$intersection_acres)>0.01,
                             select = c(ndx1,ndx2,'acres1','acres2','intersection_acres'))
  
  p1_p2_intersecting[[paste('frac_of_',nm1,sep='')]]<-as.numeric(
    p1_p2_intersecting$intersection_acres/p1_p2_intersecting$acres1)
  p1_p2_intersecting[[paste('frac_of_',nm2,sep='')]]<-as.numeric(
    p1_p2_intersecting$intersection_acres/p1_p2_intersecting$acres2)
  p1_p2_intersecting
}

add_xls_tab<-function(xls_file,this_sheet,sheet_data){
  #
  # this function add a sheet to the xls_file and returns it
  #
  # example
  #
  #xls_file<-pda_scenario
  #this_sheet<-'blkgrp_23_50'
  #sheet_data<-blkgrp_23_50
  #
  if(this_sheet %in% xls_file$sheet_names){
    xls_file$remove_worksheet(this_sheet)
  }
  xls_file$add_worksheet(this_sheet)
  xls_file$add_data(paste(this_sheet),as.data.frame(sheet_data),colNames = TRUE)
  xls_file
}

cut_polygons_rmapshaper <- function(polygons, cutters) {
  require("rmapshaper")
  
  # 1. Align Coordinate Reference Systems (CRS)
  if (st_crs(polygons) != st_crs(cutters)) {
    cutters <- st_transform(cutters, st_crs(polygons))
  }
  
  # 2. Fix invalid geometries 
  polygons <- st_make_valid(polygons)
  cutters <- st_make_valid(cutters)
  
  # 3. Combine the cutter polygons into a single mask [st_union is a big bottleneck!]

  # Convert linestrings to polygons before dissolving
  #cutters <- cutters %>% 
  #  st_cast("MULTIPOLYGON")
  
  cutters_combined <- ms_dissolve(cutters)
  
  # 4. Use ms_erase to punch out the water
  result <- ms_erase(target = polygons, erase = cutters_combined)
  
  # 5. Fix invalid geometries that result from the cutting
  result <- st_make_valid(result)
  
  return(result)
}
#
# This function makes a simple choropleth
#
choropleth <- function(polygon,theme,theme_name,map_title,map_subtitle,bin_mins){
  ggplot(polygon) +
    geom_sf(aes(fill = theme), linewidth = 0, alpha = 0.9) +
    theme_void() +
    scale_fill_viridis_c(
      trans = "log", breaks = bin_mins,
      name = theme_name,
      guide = guide_legend(
        keyheight = unit(3, units = "mm"),
        keywidth = unit(3, units = "mm"),
        label.position = "bottom",
        title.position = "top",
        nrow = 2
      )
    ) +
    labs(
      title = map_title,
      subtitle = map_subtitle,
      caption = ""
    ) +
    theme(
      text = element_text(color = "#22211d"),
      plot.background = element_rect(fill = "#f5f5f2", color = NA),
      panel.background = element_rect(fill = "#f5f5f2", color = NA),
      legend.background = element_rect(fill = "#f5f5f2", color = NA),
      plot.title = element_text(
        size = 20, hjust = 0.01, color = "#4e4d47",
        margin = margin(
          b = -0.1, t = 0.4, l = 2,
          unit = "cm"
        )
      ),
      plot.subtitle = element_text(
        size = 15, hjust = 0.01,
        color = "#4e4d47",
        margin = margin(
          b = -0.1, t = 0.43, l = 2,
          unit = "cm"
        )
      ),
      plot.caption = element_text(
        size = 10,
        color = "#4e4d47",
        margin = margin(
          b = 0.3, r = -99, t = 0.3,
          unit = "cm"
        )
      ),
      legend.position = c(0.7, 0.09)
    )
}
