library(tidyverse)
library(sf)

sf_use_s2(FALSE)

parks_of_interest = c('JOTR', 'DEVA')

ecoregions = st_read('data/raw/boundaries/us_eco_l3_state_boundaries.shp') %>%
  st_transform(crs = 4326) %>%
  st_make_valid()

california = ecoregions %>%
  filter(STATE_NAME == 'California') %>%
  summarise(geometry = st_union(geometry))

mojave = ecoregions %>%
  filter(US_L3NAME == 'Mojave Basin and Range') %>%
  summarise(geometry = st_union(geometry)) %>%
  mutate(name = 'Mojave')

mojave_ca = st_intersection(mojave, california) %>%
  st_collection_extract('POLYGON') %>%
  summarise(geometry = st_union(geometry)) %>%
  mutate(name = 'Mojave (California)')

parks = st_read('data/raw/boundaries/nps_boundary.shp') %>%
  filter(UNIT_CODE %in% parks_of_interest) %>%
  st_transform(crs = 4326) %>%
  st_make_valid() %>%
  group_by(park = UNIT_CODE) %>%
  summarise(geometry = st_union(geometry), .groups = 'drop')

parks_ca = st_intersection(parks, california) %>%
  st_collection_extract('POLYGON') %>%
  group_by(park) %>%
  summarise(geometry = st_union(geometry), .groups = 'drop')

read_plot_square = function(path) {
  st_read(path, quiet = TRUE) %>%
    transmute(plot = tools::file_path_sans_ext(basename(path)))
}

im_plots = list.files('data/raw/im_plots/polygons', pattern = '.geojson$',
                      full.names = TRUE) %>%
  map(read_plot_square) %>%
  bind_rows() %>%
  st_transform(crs = 4326) %>%
  mutate(park = str_sub(plot, 1, 4)) %>%
  filter(park %in% parks_of_interest) %>%
  select(park, plot)

plots_outside_park = im_plots %>%
  st_centroid() %>%
  st_join(parks %>% rename(park_boundary = park)) %>%
  filter(is.na(park_boundary) | park != park_boundary)

if (nrow(plots_outside_park) > 0) {
  print(plots_outside_park)
  stop('Some I&M plots fall outside their park boundary')
}

save_boundary = function(boundary, name) {
  st_write(boundary, str_glue('data/boundaries/{name}.shp'),
           delete_dsn = TRUE, quiet = TRUE)
}

save_final_boundary = function(boundary, name) {
  st_write(boundary, 'data/final/boundaries.gpkg', layer = name,
           append = FALSE, quiet = TRUE)
}

list(mojave = mojave, mojave_ca = mojave_ca, parks = parks,
     parks_ca = parks_ca, im_plots = im_plots) %>%
  iwalk(save_boundary)

dir.create('data/final', showWarnings = FALSE)
list(mojave = mojave, parks = parks, im_plots = im_plots,
     im_plot_centres = st_centroid(im_plots)) %>%
  iwalk(save_final_boundary)
