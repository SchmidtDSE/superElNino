library(tidyverse)
library(sf)
library(ggrepel)
library(patchwork)

map_margin_degrees = 0.1
selection_shapes = c('in park or within 3 km' = 21,
                     'mountain station used by PRISM' = 24)

mojave = st_read('data/boundaries/mojave.shp', quiet = TRUE)
parks = st_read('data/boundaries/parks.shp', quiet = TRUE)
im_plots = st_read('data/boundaries/im_plots.shp', quiet = TRUE)

read_gauges = function() {
  read_csv('data/processed/gauges/gauge_stations.csv',
           show_col_types = FALSE) %>%
    distinct(id, .keep_all = TRUE) %>%
    mutate(label = str_glue('{str_to_title(name)} ({round(elevation_m)} m)'))
}

map_extent = function(park_code, gauges) {
  park_box = st_bbox(filter(parks, park == park_code))
  park_gauges = filter(gauges, park == park_code)
  c(xmin = min(park_box['xmin'], park_gauges$lon) - map_margin_degrees,
    xmax = max(park_box['xmax'], park_gauges$lon) + map_margin_degrees,
    ymin = min(park_box['ymin'], park_gauges$lat) - map_margin_degrees,
    ymax = max(park_box['ymax'], park_gauges$lat) + map_margin_degrees)
}

plot_park_gauges = function(park_code, gauges) {
  extent = map_extent(park_code, gauges)
  park_gauges = filter(gauges, park == park_code)
  ggplot() +
    geom_sf(data = mojave, fill = 'grey95', colour = 'black',
            linewidth = 0.6) +
    geom_sf(data = parks, fill = NA, colour = '#e31a1c', linewidth = 0.6) +
    geom_sf(data = im_plots, fill = 'grey30', colour = 'grey30') +
    geom_point(data = park_gauges, aes(x = lon, y = lat, shape = selection),
               fill = 'white', colour = 'black', size = 2.5, stroke = 0.8) +
    geom_label_repel(data = park_gauges, aes(x = lon, y = lat, label = label),
                     size = 2.6, min.segment.length = 0, box.padding = 0.5,
                     label.size = 0, fill = alpha('white', 0.8), seed = 1) +
    scale_shape_manual(values = selection_shapes,
                       limits = names(selection_shapes), drop = FALSE,
                       name = NULL) +
    coord_sf(xlim = extent[c('xmin', 'xmax')],
             ylim = extent[c('ymin', 'ymax')]) +
    labs(title = park_code, x = NULL, y = NULL) +
    theme_bw() +
    theme(axis.text = element_text(size = 7))
}

combine_park_maps = function(gauges) {
  deva_map = plot_park_gauges('DEVA', gauges) + guides(shape = 'none')
  (deva_map | plot_park_gauges('JOTR', gauges)) +
    plot_layout(guides = 'collect') +
    plot_annotation(caption = str_glue(
      'Black: Mojave (EPA ecoregion). Red: park boundaries. Dark grey ',
      'squares: I&M plots (500 m). Labels: gauge name and elevation.')) &
    theme(legend.position = 'top', plot.caption = element_text(hjust = 0))
}

dir.create('outputs/figures', recursive = TRUE, showWarnings = FALSE)
gauge_map = combine_park_maps(read_gauges())
ggsave('outputs/figures/gauges_map.png', gauge_map, width = 14, height = 6.5,
       dpi = 200)
