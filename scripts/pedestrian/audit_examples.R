# Build inspectable category examples from the original dated source.
.libPaths(c('.R-library',.libPaths()))
suppressPackageStartupMessages({library(sf);library(ggplot2);library(patchwork)})
source('R/pedestrian_gaps.R');spec<-yaml::read_yaml('config/burdens.yml')$pedestrian
# Reuse the targets inventory when available, otherwise perform the checksummed read.
x<-tryCatch(targets::tar_read(pedestrian_inventory)$lines,error=function(e)read_pedestrian_inventory(pedestrian_inventory_files(spec),spec)$lines)
streets<-c('RUSTLING RD','ULLRICH AVE','HAZELHURST DR','W 46TH ST')
colors<-c(EXISTING_SIDEWALK='#277c69',DRIVEWAY='#86b7a6',PLANNED_SIDEWALK='#c55b34',PLANNED_SHARED_STREET='#b98621',POTENTIAL_SIDEWALK='#8f78ac',SHARED_STREET='#246b9c',PROTECTED_STREET_PATH='#165345',SHARED_USE_PATH='#4ca9aa')
plots<-lapply(streets,function(street){z<-x[!is.na(x$FULL_STREET_NAME)&x$FULL_STREET_NAME==street,];ggplot(z)+geom_sf(aes(color=PEDESTRIAN_FACILITY_TYPE),linewidth=.9,show.legend='line')+scale_color_manual(values=colors,limits=names(colors),breaks=names(colors),drop=FALSE,labels=gsub('_',' ',names(colors)))+labs(title=street,color='Facility category')+theme_void()+theme(plot.title=element_text(face='bold'),plot.margin=margin(12,12,12,12))})
p<-(wrap_plots(plots,ncol=2,guides='collect') & theme(legend.position='bottom'))+plot_annotation(title='Inventory category checks',caption='Original linework for named streets. Parallel street-side records are retained; shared-street length is not automatically doubled.\nPotential segments are shown for review, not counted as gaps in the main score.')
dir.create('output/components/pedestrian-gaps',recursive=TRUE,showWarnings=FALSE)
ggsave('output/components/pedestrian-gaps/inventory_examples.png',p,width=12,height=9,dpi=160,bg='white')
