library(tidyverse)

reference_years = c(1951, 1980)
event_year = 1983
observation_colour = '#1f5a96'
dataset_labels = c(prism_4km = 'PRISM 4 km', era5 = 'ERA5',
                   era5_land = 'ERA5-Land', pierce = 'Pierce et al. 2021',
                   caladapt_loca2 = 'CalAdapt LOCA2-Hybrid',
                   cmip6 = 'CMIP6', isimip3b = 'ISIMIP3b')

read_unit_summary = function(file) {
  read_csv(file, col_types = cols(model = 'c', park = 'c'))
}

read_unit_summaries = function() {
  list.files('data/processed', pattern = '_units.csv$', recursive = TRUE,
             full.names = TRUE) %>%
    map(read_unit_summary) %>%
    bind_rows()
}

label_datasets = function(water_year_pr) {
  water_year_pr %>%
    filter(!california_only) %>%
    mutate(model = replace_na(model, ''),
           is_model = model != '',
           dataset = factor(dataset_labels[dataset], levels = dataset_labels))
}

ensemble_median = function(water_year_pr) {
  water_year_pr %>%
    filter(is_model) %>%
    group_by(dataset, level, park, unit, water_year) %>%
    summarise(pr_mm = median(pr_mm), .groups = 'drop')
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

add_model_runs = function(plot, water_year_pr) {
  plot +
    geom_line(data = filter(water_year_pr, is_model),
              aes(group = interaction(unit, model)), colour = 'grey65',
              linewidth = 0.2)
}

plot_timeseries = function(water_year_pr, facet_rows, show_model_runs) {
  line_width = if_else(show_model_runs, 0.5, 0.2)
  subtitle = if_else(show_model_runs,
                     str_glue('Blue: observations. Grey: single model runs, ',
                              'black: median over all model runs.'),
                     str_glue('One line per I&M plot. Blue: observations. ',
                              'Black: median over all model runs.'))
  plot = ggplot(mapping = aes(x = water_year, y = pr_mm, group = unit)) %>%
    add_timeseries_layout()
  if (show_model_runs) plot = add_model_runs(plot, water_year_pr)
  plot +
    geom_line(data = ensemble_median(water_year_pr), colour = 'black',
              linewidth = line_width) +
    geom_line(data = filter(water_year_pr, !is_model),
              colour = observation_colour, linewidth = line_width) +
    facet_grid(reformulate('dataset', facet_rows), scales = 'free_y') +
    labs(subtitle = subtitle)
}

save_figure = function(plot, name, width, height) {
  ggsave(str_glue('outputs/figures/{name}.png'), plot, width = width,
         height = height, dpi = 200)
}

dir.create('outputs/figures', recursive = TRUE, showWarnings = FALSE)
water_year_pr = read_unit_summaries() %>%
  label_datasets()

water_year_pr %>%
  filter(level == 'region') %>%
  plot_timeseries(facet_rows = 'unit', show_model_runs = TRUE) %>%
  save_figure('timeseries_mojave', width = 16, height = 3.8)

water_year_pr %>%
  filter(level == 'park') %>%
  plot_timeseries(facet_rows = 'unit', show_model_runs = TRUE) %>%
  save_figure('timeseries_parks', width = 16, height = 6)

water_year_pr %>%
  filter(level == 'plot') %>%
  plot_timeseries(facet_rows = 'park', show_model_runs = FALSE) %>%
  save_figure('timeseries_im_plots', width = 16, height = 6)
