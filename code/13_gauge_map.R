library(tidyverse)
library(sf)
library(ggrepel)
library(patchwork)

map_margin_degrees = 0.1
stations_file = 'data/final/gauge_map_stations.csv'
extents_file = 'data/final/gauge_map_extents.csv'
boundaries_file = 'data/final/boundaries.gpkg'
selection_shapes = c('in park or within 3 km' = 21,
                     'mountain station used by PRISM' = 24)

# Processing

prepare_map_stations = function() {
  read_csv('data/processed/gauges/gauge_stations.csv',
           show_col_types = FALSE) %>%
    distinct(id, .keep_all = TRUE) %>%
    transmute(id, park, selection, lon, lat,
              label = str_glue('{str_to_title(name)} ',
                               '({round(elevation_m)} m)'))
}

park_extent = function(park_code, stations) {
  park_box = st_read('data/boundaries/parks.shp', quiet = TRUE) %>%
    filter(park == park_code) %>%
    st_bbox()
  park_stations = filter(stations, park == park_code)
  tibble(park = park_code,
         xmin = min(park_box['xmin'], park_stations$lon) - map_margin_degrees,
         xmax = max(park_box['xmax'], park_stations$lon) + map_margin_degrees,
         ymin = min(park_box['ymin'], park_stations$lat) - map_margin_degrees,
         ymax = max(park_box['ymax'], park_stations$lat) + map_margin_degrees)
}

prepare_map_extents = function(stations) {
  unique(stations$park) %>%
    map(park_extent, stations = stations) %>%
    bind_rows()
}

# Plotting

read_final_boundary = function(layer) {
  st_read(boundaries_file, layer = layer, quiet = TRUE)
}

plot_park_gauges = function(park_code, stations, extents) {
  extent = filter(extents, park == park_code)
  park_stations = filter(stations, park == park_code)
  ggplot() +
    geom_sf(data = read_final_boundary('mojave'), fill = 'grey95',
            colour = 'black', linewidth = 0.6) +
    geom_sf(data = read_final_boundary('parks'), fill = NA,
            colour = '#e31a1c', linewidth = 0.6) +
    geom_sf(data = read_final_boundary('im_plots'), fill = 'grey30',
            colour = 'grey30') +
    geom_point(data = park_stations, aes(x = lon, y = lat, shape = selection),
               fill = 'white', colour = 'black', size = 2.5, stroke = 0.8) +
    geom_label_repel(data = park_stations,
                     aes(x = lon, y = lat, label = label), size = 2.6,
                     min.segment.length = 0, box.padding = 0.5,
                     label.size = 0, fill = alpha('white', 0.8), seed = 1) +
    scale_shape_manual(values = selection_shapes,
                       limits = names(selection_shapes), drop = FALSE,
                       name = NULL) +
    coord_sf(xlim = c(extent$xmin, extent$xmax),
             ylim = c(extent$ymin, extent$ymax)) +
    labs(title = park_code, x = NULL, y = NULL) +
    theme_bw() +
    theme(axis.text = element_text(size = 7))
}

combine_park_maps = function(stations, extents) {
  deva_map = plot_park_gauges('DEVA', stations, extents) +
    guides(shape = 'none')
  (deva_map | plot_park_gauges('JOTR', stations, extents)) +
    plot_layout(guides = 'collect') +
    plot_annotation(caption = str_glue(
      'Black: Mojave (EPA ecoregion). Red: park boundaries. Dark grey ',
      'squares: I&M plots (500 m). Labels: gauge name and elevation.')) &
    theme(legend.position = 'top', plot.caption = element_text(hjust = 0))
}

dir.create('data/final', showWarnings = FALSE)
map_stations = prepare_map_stations()
write_csv(map_stations, stations_file)
write_csv(prepare_map_extents(map_stations), extents_file)

dir.create('figures', showWarnings = FALSE)
gauge_map = combine_park_maps(read_csv(stations_file, show_col_types = FALSE),
                              read_csv(extents_file, show_col_types = FALSE))
ggsave('figures/gauges_map.png', gauge_map, width = 14, height = 6.5,
       dpi = 200)
