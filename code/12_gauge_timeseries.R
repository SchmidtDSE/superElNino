library(tidyverse)

event_year = 1983
gauge_label = 'Rain gauge (NOAA GHCN-Daily)'
observation_labels = c(gauge = gauge_label, prism_4km = 'PRISM 4 km',
                       pierce = 'Pierce et al. 2021', era5_land = 'ERA5-Land',
                       era5 = 'ERA5')
model_labels = c(caladapt_loca2 = 'CalAdapt LOCA2-Hybrid (15 model runs)',
                 isimip3b = 'ISIMIP3b (5 model runs)')
source_colours = set_names(
  c('black', '#9B2226', '#E05256', '#CA6702', '#FFB000', '#0f8096',
    '#17a769'), c(observation_labels, model_labels))
observation_colours = source_colours[observation_labels]
observation_shapes = set_names(c(15, 16, 17, 18, 16), observation_labels)
gauge_caption = str_glue('Gridded datasets: value of the grid cell that ',
                         'contains the gauge. Gauge: only water years with ',
                         'at least 335 days of readings. Dashed: water year ',
                         '{event_year}.')

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
    arrange(park, is_mountain_station, elevation_m)
}

order_panels = function(data, stations) {
  data %>%
    inner_join(stations, by = 'id') %>%
    mutate(label = factor(label, levels = stations$label))
}

read_observed = function(stations) {
  read_csv('data/processed/gauges/gauges_water_year_pr.csv',
           show_col_types = FALSE) %>%
    order_panels(stations) %>%
    mutate(source = observation_labels[source])
}

read_model_runs = function(stations) {
  read_csv('data/processed/gauges/gauges_model_runs_water_year_pr.csv',
           show_col_types = FALSE) %>%
    filter(source %in% names(model_labels)) %>%
    order_panels(stations) %>%
    mutate(source = model_labels[source])
}

complete_gauge_lines = function(observed) {
  observed %>%
    filter(source == gauge_label, complete) %>%
    group_by(id, label, source) %>%
    complete(water_year = full_seq(water_year, 1)) %>%
    ungroup()
}

lines_to_plot = function(observed) {
  observed %>%
    filter(source != gauge_label) %>%
    bind_rows(complete_gauge_lines(observed))
}

add_model_runs = function(plot, model_runs) {
  plot +
    geom_line(data = model_runs, aes(group = model), linewidth = 0.2,
              alpha = 0.5)
}

plot_gauge_timeseries = function(lines, colours, model_runs = NULL) {
  gauge = filter(lines, source == gauge_label)
  plot = ggplot(lines, aes(x = water_year, y = pr_mm, colour = source)) +
    geom_vline(xintercept = event_year, colour = 'grey40',
               linetype = 'dashed', linewidth = 0.3)
  if (!is.null(model_runs)) plot = add_model_runs(plot, model_runs)
  plot +
    geom_line(data = filter(lines, source != gauge_label), linewidth = 0.4) +
    geom_line(data = gauge, linewidth = 0.7) +
    geom_point(data = filter(gauge, !is.na(pr_mm)), size = 0.8) +
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

plot_with_model_runs = function(lines, model_runs) {
  without_era5 = filter(lines, source != observation_labels['era5'])
  colours = source_colours[names(source_colours) !=
                             observation_labels['era5']]
  plot_gauge_timeseries(without_era5, colours, model_runs) +
    labs(caption = str_glue('{gauge_caption} Climate models: one thin ',
                            'line per model run.')) +
    guides(colour = guide_legend(ncol = 4, byrow = TRUE,
                                 override.aes = list(alpha = 1,
                                                     linewidth = 0.7)))
}

gauges_without_readings = function(event_values, stations) {
  measured = filter(event_values, source == gauge_label)$id
  stations %>%
    filter(!id %in% measured) %>%
    mutate(label = factor(label, levels = stations$label))
}

plot_event_year = function(observed, stations) {
  event_values = filter(observed, water_year == event_year)
  incomplete = filter(event_values, source == gauge_label, !complete)
  event_values %>%
    filter(source != gauge_label | complete) %>%
    ggplot(aes(x = pr_mm, y = label, colour = source, shape = source)) +
    geom_point(size = 2.5) +
    geom_point(data = incomplete, shape = 0, size = 2.5, stroke = 0.8,
               show.legend = FALSE) +
    geom_text(data = incomplete, aes(label = str_glue('{days_reported} days')),
              size = 2.5, nudge_y = 0.3, show.legend = FALSE) +
    geom_text(data = gauges_without_readings(event_values, stations),
              aes(x = -Inf, y = label), label = 'no gauge readings',
              hjust = -0.05, size = 2.8, nudge_y = 0.33, colour = 'grey40',
              inherit.aes = FALSE) +
    scale_colour_manual(values = observation_colours,
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
  ggsave(str_glue('outputs/figures/{name}.png'), plot, width = width,
         height = height, dpi = 200)
}

dir.create('outputs/figures', recursive = TRUE, showWarnings = FALSE)
stations = read_stations()
observed = read_observed(stations)
lines = lines_to_plot(observed)

plot_gauge_timeseries(lines, observation_colours) %>%
  save_figure('gauges_timeseries', width = 14, height = 14)
plot_with_model_runs(lines, read_model_runs(stations)) %>%
  save_figure('gauges_timeseries_with_models', width = 14, height = 14.5)
plot_event_year(observed, stations) %>%
  save_figure('gauges_water_year_1983', width = 9, height = 7.5)
