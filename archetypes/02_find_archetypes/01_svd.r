## -----------------------------------------------------------------------------------------------------------------
# Seasonality Classification
# 01_svd.r
# 
# Amelia Bertozzi-Villa, Institute for Disease Modeling, University of Oxford
# June 2018
# 
# Extending the work described in the link below, this script takes the tsi and rainfall covariates 
# extracted in extract_raster_values and runs svd on the joint dataset. 
# 
# https://paper.dropbox.com/doc/Cluster-MAP-pixels-by-seasonality-zga4UM1DnBx8pc11rStOS
## -----------------------------------------------------------------------------------------------------------------------

library(gdistance)
library(data.table)
library(stringr)
library(stats)
library(Hmisc)
library(ggplot2)

rm(list=ls())

theme_set(theme_minimal(base_size = 16))
root_dir <- ifelse(Sys.getenv("USERPROFILE")=="", Sys.getenv("HOME"))
base_dir <- file.path(root_dir, 
                      "Dropbox (IDM)/Malaria Team Folder/projects/map_intervention_impact/archetypes/")

overwrite <- T
rescale <- F
out_subdir <- "original_megatrends"

out_dir <- file.path(base_dir, "results", out_subdir)
guide <- fread(file.path(out_dir, "instructions.csv"))

for (this_continent in guide$continent){
  print(paste("running svd on", this_continent))
  cov_dir <- file.path(base_dir, "covariates", unique(guide$cov_directory), this_continent)
  this_out_dir <- file.path(out_dir, this_continent, "01_svd")
  dir.create(this_out_dir, showWarnings=F, recursive=T)
  
  these_covs <- unlist(strsplit(guide[continent==this_continent]$covariates, "/"))
  full_label <- paste(these_covs, collapse=".")
  if (rescale==T & "rainfall" %in% these_covs){
    full_label <- paste0(full_label, ".rescaled")
  }
  
  # load datasets, merge
  all_vals_fname <- file.path(this_out_dir, paste0(full_label, ".vals.csv"))
  if (file.exists(all_vals_fname) & overwrite==F){
    print("loading extracted values")
    all_vals <- fread(all_vals_fname)
  }else{
    print("appending datasets")
    all_vals <- lapply(these_covs, function(cov_name){
      vals <- fread(file.path(cov_dir, cov_name, paste0(cov_name, "_vals.csv")))
      if (rescale==T & cov_name=="rainfall"){
        # cap outliers in rainfall data; rescale to [0,1]
        vals[value>400, value:=400]
        vals[, value:=value/max(value)]
      }
      return(vals)
    })
    
    # keep only those pixels with values for all covariates
    non_null_ids <- lapply(all_vals, function(df){
      return(unique(df$id))
    })
    shared_ids <- Reduce(intersect, non_null_ids)
    all_vals <- rbindlist(all_vals)
    all_vals <- all_vals[id %in% shared_ids]
    
    # to ensure replication
    all_vals[variable_name=="month", variable_val:= str_pad(variable_val, 2, side="left", pad="0")]
    all_vals <- all_vals[order(cov, variable_name, variable_val)]
    # print("saving appended dataset")
    # write.csv(all_vals, file=all_vals_fname, row.names=F)
  }
  
  # plot distribution of values
  print("plotting distributions")
  pdf(file=file.path(this_out_dir, "covariate_distributions.pdf"))
  
  distplot <- ggplot(all_vals, aes(x=value)) + 
              geom_density(aes(color=cov, fill=cov), alpha=0.5) +
              facet_grid(cov~., scales="free") +
              theme_minimal() + 
              theme(legend.position = "none") + 
              labs(title="Distribution of SVD variables",
                   x="Rescaled Covariate Value",
                   y="Density") 
  print(distplot)
  
  graphics.off()
  
  # svd
  svd_out_fname <- file.path(this_out_dir, "svd_output.rdata")
  if (file.exists(svd_out_fname) & overwrite==F){
    print("loading svd outputs")
    load(svd_out_fname)
  }else{
    print("reshaping and filling nulls")
    svd_wide_datatable <- dcast(all_vals, cov + variable_name + variable_val ~ id)
    print("running svd")
    svd_out <- svd(svd_wide_datatable[, 4:ncol(svd_wide_datatable)])
    save(svd_out, svd_wide_datatable, file=svd_out_fname)
  }
  
  print("plotting")
  init_variance <- svd_out$d^2/sum(svd_out$d^2)
  variance <- data.table(continent=capitalize(this_continent),
                         vector=1:length(init_variance), 
                         variance_explained=init_variance)
  
  pdf(file=file.path(this_out_dir, "svd_variance_explained.pdf"))
  varplot <- ggplot(variance[vector<=5], aes(x=vector, y=variance_explained)) +
    geom_line(size=2) +
    geom_point(size=5) +
    theme(legend.position = "none") +
    labs(x="Singular Vector", 
         y="Variance Explained",
         title=paste("Variance Explained,", capitalize(this_continent))
         )
  print(varplot)
  
  graphics.off()
  print(varplot)
}



