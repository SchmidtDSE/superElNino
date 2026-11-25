library(tidyverse)
library(sf)
library(ncdf4)

reference_years = 1951:1980
event_year = 1983
dataset_labels = c(prism_4km = 'PRISM 4 km', era5 = 'ERA5',
                   era5_land = 'ERA5-Land', pierce = 'Pierce et al. 2021',
                   caladapt_loca2 = 'CalAdapt LOCA2-Hybrid',
                   cmip6 = 'CMIP6', isimip3b = 'ISIMIP3b')
observations = c('prism_4km', 'era5', 'era5_land', 'pierce')

mojave = st_read('data/boundaries/mojave.shp', quiet = TRUE)
parks = st_read('data/boundaries/parks.shp', quiet = TRUE)
im_plot_centres = st_read('data/boundaries/im_plots.shp', quiet = TRUE) %>%
  st_centroid()
map_extent = st_bbox(mojave)

pr_attribute = function(nc, name) {
  attribute = ncatt_get(nc, 'pr', name)
  if_else(attribute$hasatt, as.character(attribute$value), '')
}

read_water_year_map = function(path) {
  nc = nc_open(path)
  on.exit(nc_close(nc))
  expand_grid(water_year = as.vector(ncvar_get(nc, 'water_year')),
              lat = as.vector(ncvar_get(nc, 'lat')),
              lon = as.vector(ncvar_get(nc, 'lon'))) %>%
    mutate(pr_mm = as.vector(ncvar_get(nc, 'pr')),
           dataset = pr_attribute(nc, 'dataset'),
           model = pr_attribute(nc, 'model'))
}

read_mojave_mean = function(file) {
  read_csv(file, col_types = cols(model = 'c', park = 'c')) %>%
    filter(level == 'region', !california_only) %>%
    mutate(model = replace_na(model, ''))
}

wettest_model_years = function(mojave_means) {
  mojave_means %>%
    filter(!dataset %in% observations, water_year > max(reference_years)) %>%
    group_by(dataset, model) %>%
    slice_max(pr_mm, n = 1) %>%
    ungroup() %>%
    select(dataset, model, map_year = water_year)
}

find_map_years = function() {
  mojave_means = list.files('data/processed', pattern = '_units.csv$',
                            recursive = TRUE, full.names = TRUE) %>%
    map(read_mojave_mean) %>%
    bind_rows()
  observation_years = tibble(dataset = observations, model = '',
                             map_year = event_year)
  bind_rows(wettest_model_years(mojave_means), observation_years)
}

reference_mean = function(water_year_map) {
  water_year_map %>%
    filter(water_year %in% reference_years) %>%
    group_by(lat, lon) %>%
    summarise(reference_mm = mean(pr_mm), .groups = 'drop')
}

calculate_anomaly_map = function(path, map_years) {
  water_year_map = read_water_year_map(path)
  map_year = water_year_map %>%
    distinct(dataset, model) %>%
    left_join(map_years, by = c('dataset', 'model')) %>%
    pull(map_year)
  water_year_map %>%
    filter(water_year == map_year) %>%
    left_join(reference_mean(water_year_map), by = c('lat', 'lon')) %>%
    mutate(ratio = pr_mm / reference_mm)
}

label_panels = function(anomalies) {
  anomalies %>%
    mutate(panel = if_else(model == '', dataset_labels[dataset],
                           str_glue('{model} ({water_year})')))
}

read_anomaly_maps = function(map_years) {
  list.files('data/processed', pattern = '_water_year_pr.nc$',
             recursive = TRUE, full.names = TRUE) %>%
    map(calculate_anomaly_map, map_years = map_years) %>%
    bind_rows() %>%
    label_panels()
}

plot_anomaly = function(anomalies, title) {
  ggplot(anomalies) +
    geom_tile(aes(x = lon, y = lat, fill = ratio)) +
    geom_sf(data = mojave, fill = NA, colour = 'black', linewidth = 0.9) +
    geom_sf(data = parks, fill = NA, colour = '#e31a1c', linewidth = 0.7) +
    geom_sf(data = im_plot_centres, shape = 21, size = 0.7, fill = 'white',
            colour = 'black', stroke = 0.2) +
    scale_fill_distiller(palette = 'BrBG', direction = 1, trans = 'log2',
                         limits = c(0.25, 4), oob = scales::squish,
                         breaks = c(0.25, 0.5, 1, 2, 4),
                         labels = scales::percent, na.value = 'grey85',
                         name = 'Precipitation\nrelative to\n1951-1980') +
    scale_x_continuous(breaks = c(-118, -116, -114)) +
    coord_sf(xlim = map_extent[c('xmin', 'xmax')],
             ylim = map_extent[c('ymin', 'ymax')], expand = TRUE) +
    facet_wrap(~panel, ncol = 4) +
    labs(title = title, x = NULL, y = NULL,
         caption = str_glue('Black: Mojave (EPA ecoregion). Red: Joshua ',
                            'Tree and Death Valley. Points: centres of the ',
                            'I&M plots.')) +
    theme_bw() +
    theme(strip.background = element_rect(fill = 'white'),
          axis.text = element_text(size = 6),
          plot.caption = element_text(hjust = 0))
}

save_observation_map = function(anomalies) {
  observation_map = anomalies %>%
    filter(dataset %in% observations) %>%
    mutate(panel = factor(panel, levels = dataset_labels)) %>%
    plot_anomaly(str_glue('Observations: water year {event_year}'))
  ggsave('outputs/figures/anomaly_observations.png', observation_map,
         width = 14, height = 4.5, dpi = 200)
}

save_model_map = function(model_dataset, anomalies) {
  model_map = anomalies %>%
    filter(dataset == model_dataset) %>%
    plot_anomaly(str_glue('{dataset_labels[model_dataset]}: wettest water ',
                          'year after {max(reference_years)} per model'))
  ggsave(str_glue('outputs/figures/anomaly_{model_dataset}.png'), model_map,
         width = 14, height = 10, dpi = 200)
}

dir.create('outputs/figures', recursive = TRUE, showWarnings = FALSE)
anomalies = read_anomaly_maps(find_map_years())
save_observation_map(anomalies)
setdiff(unique(anomalies$dataset), observations) %>%
  walk(save_model_map, anomalies = anomalies)
