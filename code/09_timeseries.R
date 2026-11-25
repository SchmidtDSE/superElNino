library(tidyverse)

reference_years = c(1951, 1980)
event_year = 1983
final_file = 'data/final/timeseries_water_year_pr.csv.gz'
dataset_labels = c(prism_4km = 'PRISM 4 km', era5 = 'ERA5',
                   era5_land = 'ERA5-Land', pierce = 'Pierce et al. 2021',
                   caladapt_loca2 = 'CalAdapt LOCA2-Hybrid',
                   cmip6 = 'CMIP6', isimip3b = 'ISIMIP3b')
line_types = c('model run', 'model median', 'observation')
line_colours = c('model run' = 'grey65', 'model median' = 'black',
                 'observation' = '#1f5a96')

# Processing

read_unit_summary = function(file) {
  read_csv(file, col_types = cols(model = 'c', park = 'c'))
}

read_unit_summaries = function() {
  list.files('data/processed', pattern = '_units.csv$', recursive = TRUE,
             full.names = TRUE) %>%
    map(read_unit_summary) %>%
    bind_rows()
}

whole_units = function(unit_summaries) {
  unit_summaries %>%
    filter(!california_only) %>%
    mutate(model = replace_na(model, ''),
           line_type = if_else(model == '', 'observation', 'model run'))
}

ensemble_median = function(water_year_pr) {
  water_year_pr %>%
    filter(line_type == 'model run') %>%
    group_by(dataset, level, park, unit, water_year) %>%
    summarise(pr_mm = median(pr_mm), .groups = 'drop') %>%
    mutate(model = 'median', line_type = 'model median')
}

drop_model_runs_for_plots = function(water_year_pr) {
  water_year_pr %>%
    filter(!(level == 'plot' & line_type == 'model run'))
}

prepare_timeseries = function(unit_summaries) {
  water_year_pr = whole_units(unit_summaries)
  bind_rows(water_year_pr, ensemble_median(water_year_pr)) %>%
    drop_model_runs_for_plots() %>%
    mutate(dataset_label = dataset_labels[dataset]) %>%
    select(dataset, dataset_label, model, line_type, level, park, unit,
           water_year, pr_mm)
}

# Plotting

read_final_timeseries = function() {
  read_csv(final_file, col_types = cols(model = 'c', park = 'c')) %>%
    mutate(model = replace_na(model, ''),
           dataset_label = factor(dataset_label, levels = dataset_labels),
           line_type = factor(line_type, levels = line_types))
}

add_timeseries_layout = function(plot) {
  plot +
    annotate('rect', xmin = reference_years[1] - 0.5,
             xmax = reference_years[2] + 0.5, ymin = -Inf, ymax = Inf,
             fill = 'grey92') +
    geom_vline(xintercept = event_year, colour = 'grey40',
               linetype = 'dashed', linewidth = 0.3) +
    labs(x = 'Water year (October to September)',
         y = 'Precipitation (mm per water year)',
         caption = str_glue('Shaded: reference period {reference_years[1]}-',
                            '{reference_years[2]}. Dashed: water year ',
                            '{event_year}.')) +
    theme_bw() +
    theme(panel.grid.minor = element_blank(),
          strip.background = element_rect(fill = 'white'),
          plot.caption = element_text(hjust = 0))
}

plot_timeseries = function(timeseries, facet_rows, line_widths, subtitle) {
  plot = ggplot(timeseries,
                aes(x = water_year, y = pr_mm, colour = line_type,
                    linewidth = line_type,
                    group = interaction(line_type, unit, model)))
  add_timeseries_layout(plot) +
    geom_line() +
    scale_colour_manual(values = line_colours, guide = 'none') +
    scale_linewidth_manual(values = line_widths, guide = 'none') +
    facet_grid(reformulate('dataset_label', facet_rows), scales = 'free_y') +
    labs(subtitle = subtitle)
}

plot_area_timeseries = function(timeseries) {
  plot_timeseries(timeseries, facet_rows = 'unit',
                  line_widths = c(0.2, 0.5, 0.5),
                  subtitle = str_glue('Blue: observations. Grey: single ',
                                      'model runs, black: median over all ',
                                      'model runs.'))
}

plot_im_plot_timeseries = function(timeseries) {
  plot_timeseries(timeseries, facet_rows = 'park',
                  line_widths = c(0.2, 0.2, 0.2),
                  subtitle = str_glue('One line per I&M plot. Blue: ',
                                      'observations. Black: median over all ',
                                      'model runs.'))
}

save_figure = function(plot, name, width, height) {
  ggsave(str_glue('figures/{name}.png'), plot, width = width,
         height = height, dpi = 200)
}

dir.create('data/final', showWarnings = FALSE)
read_unit_summaries() %>%
  prepare_timeseries() %>%
  write_csv(final_file)

dir.create('figures', showWarnings = FALSE)
timeseries = read_final_timeseries()

timeseries %>%
  filter(level == 'region') %>%
  plot_area_timeseries() %>%
  save_figure('timeseries_mojave', width = 16, height = 3.8)

timeseries %>%
  filter(level == 'park') %>%
  plot_area_timeseries() %>%
  save_figure('timeseries_parks', width = 16, height = 6)

timeseries %>%
  filter(level == 'plot') %>%
  plot_im_plot_timeseries() %>%
  save_figure('timeseries_im_plots', width = 16, height = 6)
