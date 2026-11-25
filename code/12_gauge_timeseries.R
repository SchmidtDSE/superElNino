library(tidyverse)

event_year = 1983
timeseries_file = 'data/final/gauges_timeseries.csv'
event_year_file = 'data/final/gauges_water_year_1983.csv'
gauge_label = 'Rain gauge (NOAA GHCN-Daily)'
observation_labels = c(gauge = gauge_label, prism_4km = 'PRISM 4 km',
                       pierce = 'Pierce et al. 2021', era5_land = 'ERA5-Land',
                       era5 = 'ERA5')
model_labels = c(caladapt_loca2 = 'CalAdapt LOCA2-Hybrid (15 model runs)',
                 isimip3b = 'ISIMIP3b (5 model runs)')
sources_without_models = unname(observation_labels)
sources_with_models = c(setdiff(observation_labels, 'ERA5'),
                        unname(model_labels))
source_colours = set_names(
  c('black', '#9B2226', '#E05256', '#CA6702', '#FFB000', '#0f8096',
    '#17a769'), c(observation_labels, model_labels))
observation_shapes = set_names(c(15, 16, 17, 18, 16), observation_labels)
gauge_caption = str_glue('Gridded datasets: value of the grid cell that ',
                         'contains the gauge. Gauge: only water years with ',
                         'at least 335 days of readings. Dashed: water year ',
                         '{event_year}.')

# Processing

describe_location = function(distance_km, is_mountain_station) {
  location = if_else(distance_km == 0, 'inside park',
                     str_glue('{distance_km} km outside park'))
  if_else(is_mountain_station, str_glue('{location}, mountain station'),
          location)
}

read_stations = function() {
  read_csv('data/processed/gauges/gauge_stations.csv',
           show_col_types = FALSE) %>%
    mutate(is_mountain_station = str_starts(selection, 'mountain'),
           label = str_glue('{park}: {str_to_title(name)}\n',
                            '{round(elevation_m)} m, ',
                            '{describe_location(distance_km, ',
                            'is_mountain_station)}')) %>%
    arrange(park, is_mountain_station, elevation_m) %>%
    mutate(panel_order = row_number()) %>%
    select(id, label, panel_order)
}

read_observed = function(stations) {
  read_csv('data/processed/gauges/gauges_water_year_pr.csv',
           show_col_types = FALSE) %>%
    inner_join(stations, by = 'id') %>%
    mutate(source = observation_labels[source])
}

read_model_runs = function(stations) {
  read_csv('data/processed/gauges/gauges_model_runs_water_year_pr.csv',
           show_col_types = FALSE) %>%
    filter(source %in% names(model_labels)) %>%
    inner_join(stations, by = 'id') %>%
    mutate(source = model_labels[source], line_type = 'model run')
}

complete_gauge_lines = function(observed) {
  observed %>%
    filter(source == gauge_label, complete) %>%
    group_by(id, label, panel_order, source) %>%
    complete(water_year = full_seq(water_year, 1)) %>%
    ungroup() %>%
    mutate(line_type = 'gauge')
}

gridded_observation_lines = function(observed) {
  observed %>%
    filter(source != gauge_label) %>%
    mutate(line_type = 'observation')
}

prepare_gauge_timeseries = function(observed, model_runs) {
  bind_rows(complete_gauge_lines(observed),
            gridded_observation_lines(observed), model_runs) %>%
    mutate(model = replace_na(model, ''),
           in_figure_without_models = source %in% sources_without_models,
           in_figure_with_models = source %in% sources_with_models) %>%
    select(id, label, panel_order, source, line_type, model,
           in_figure_without_models, in_figure_with_models, water_year,
           pr_mm)
}

gauge_status = function(event_values) {
  event_values %>%
    filter(source == gauge_label) %>%
    mutate(status = if_else(complete, 'complete', 'incomplete'))
}

stations_without_readings = function(stations, event_values) {
  stations %>%
    filter(!id %in% event_values$id[event_values$source == gauge_label]) %>%
    mutate(source = gauge_label, status = 'no readings')
}

prepare_event_year = function(observed, stations) {
  event_values = filter(observed, water_year == event_year)
  bind_rows(filter(event_values, source != gauge_label),
            gauge_status(event_values),
            stations_without_readings(stations, event_values)) %>%
    mutate(status = replace_na(status, 'gridded dataset')) %>%
    select(id, label, panel_order, source, status, days_reported, pr_mm)
}

# Plotting

read_final_table = function(file) {
  read_csv(file, show_col_types = FALSE) %>%
    mutate(label = fct_reorder(label, panel_order))
}

plot_gauge_timeseries = function(lines, colours) {
  ggplot(lines, aes(x = water_year, y = pr_mm, colour = source)) +
    geom_vline(xintercept = event_year, colour = 'grey40',
               linetype = 'dashed', linewidth = 0.3) +
    geom_line(data = filter(lines, line_type == 'model run'),
              aes(group = model), linewidth = 0.2, alpha = 0.5) +
    geom_line(data = filter(lines, line_type == 'observation'),
              linewidth = 0.4) +
    geom_line(data = filter(lines, line_type == 'gauge'), linewidth = 0.7) +
    geom_point(data = filter(lines, line_type == 'gauge'), size = 0.8,
               na.rm = TRUE) +
    scale_colour_manual(values = colours, breaks = names(colours),
                        name = NULL) +
    facet_wrap(~label, ncol = 3) +
    labs(x = 'Water year (October to September)',
         y = 'Precipitation (mm per water year)', caption = gauge_caption) +
    theme_bw() +
    theme(legend.position = 'top',
          panel.grid.minor = element_blank(),
          strip.background = element_rect(fill = 'white'),
          strip.text = element_text(size = 8),
          plot.caption = element_text(hjust = 0))
}

plot_without_models = function(lines) {
  lines %>%
    filter(in_figure_without_models) %>%
    plot_gauge_timeseries(source_colours[sources_without_models])
}

plot_with_models = function(lines) {
  lines %>%
    filter(in_figure_with_models) %>%
    plot_gauge_timeseries(source_colours[sources_with_models]) +
    labs(caption = str_glue('{gauge_caption} Climate models: one thin ',
                            'line per model run.')) +
    guides(colour = guide_legend(ncol = 4, byrow = TRUE,
                                 override.aes = list(alpha = 1,
                                                     linewidth = 0.7)))
}

plot_event_year = function(event_values) {
  ggplot(filter(event_values, status %in% c('complete', 'gridded dataset')),
         aes(x = pr_mm, y = label, colour = source, shape = source)) +
    geom_point(size = 2.5) +
    geom_point(data = filter(event_values, status == 'incomplete'),
               shape = 0, size = 2.5, stroke = 0.8, show.legend = FALSE) +
    geom_text(data = filter(event_values, status == 'incomplete'),
              aes(label = str_glue('{days_reported} days')), size = 2.5,
              nudge_y = 0.3, show.legend = FALSE) +
    geom_text(data = filter(event_values, status == 'no readings'),
              aes(x = -Inf, y = label), label = 'no gauge readings',
              hjust = -0.05, size = 2.8, nudge_y = 0.33, colour = 'grey40',
              inherit.aes = FALSE) +
    scale_colour_manual(values = source_colours[observation_labels],
                        breaks = unname(observation_labels), name = NULL) +
    scale_shape_manual(values = observation_shapes,
                       breaks = unname(observation_labels), name = NULL) +
    scale_y_discrete(limits = rev) +
    labs(x = str_glue('Precipitation in water year {event_year} (mm)'),
         y = NULL,
         caption = str_glue('Hollow square: incomplete gauge record (fewer ',
                            'than 335 days), sum of the days reported.\n',
                            'Gridded datasets: value of the grid cell that ',
                            'contains the gauge.')) +
    theme_bw() +
    theme(legend.position = 'top',
          panel.grid.minor = element_blank(),
          plot.caption = element_text(hjust = 0))
}

save_figure = function(plot, name, width, height) {
  ggsave(str_glue('figures/{name}.png'), plot, width = width,
         height = height, dpi = 200)
}

dir.create('data/final', showWarnings = FALSE)
stations = read_stations()
observed = read_observed(stations)
prepare_gauge_timeseries(observed, read_model_runs(stations)) %>%
  write_csv(timeseries_file)
prepare_event_year(observed, stations) %>%
  write_csv(event_year_file)

dir.create('figures', showWarnings = FALSE)
lines = read_final_table(timeseries_file)
plot_without_models(lines) %>%
  save_figure('gauges_timeseries', width = 14, height = 14)
plot_with_models(lines) %>%
  save_figure('gauges_timeseries_with_models', width = 14, height = 14.5)
read_final_table(event_year_file) %>%
  plot_event_year() %>%
  save_figure('gauges_water_year_1983', width = 9, height = 7.5)
