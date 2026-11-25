# Log

## 2026-11-24: Which data do we already have?

I checked four neighbouring folders (`climate_futures`, `climate_data_pipeline`, `JOSH-JOTR`, `josh-models`, plus `josh-mojn-eval`) for climate data and I&M plot data covering the Mojave, Joshua Tree (JOTR) and Death Valley (DEVA). I only looked; I did not change anything.

**Historical/observed climate**
- PRISM monthly precipitation and mean temperature, 1950–2025, is available in two forms:
  - 4 km grids in `JOSH-JOTR/data/prism/`, cut to JOTR and to a larger box around the Joshua tree range (about 33.8–38.1°N, 118.8–112.9°W). That box covers DEVA and most of the Mojave.
  - 800 m grids in `josh-models/data/nc/{jotr,deva}/monthly/prism_*.nc` (JOTR and DEVA only).
- No ERA5 data and no Pierce et al. data exist anywhere in these folders.

**Climate models**
- CalAdapt LOCA2 (about 3 km, monthly, precipitation and temperature): 15 models, historical (1950–2014) plus SSP2-4.5, 3-7.0 and 5-8.5, in `climate_futures/caladapt/`. Each file covers a box around one park: JOTR, DEVA or Mojave National Preserve. `climate_data_pipeline/caladapt/` holds an older, smaller copy (no DEVA).
- ISIMIP3b (0.5°, daily, 1850–2100): 5 models, historical plus SSP1-2.6, 3-7.0 and 5-8.5. The data covers the whole southwestern US, so it includes the full Mojave. It is in `climate_futures/isimip/data/interim/`. The same files are copied in `climate_data_pipeline`.
- Raw CMIP6 (global, daily, precipitation only, historical only): 4 models in `climate_data_pipeline/cmip6/data/raw/`. The MRI-ESM2-0 download is incomplete: 3 of its 4 files are empty.

**I&M plots**
- There are about 35 plots each in JOTR, DEVA and Mojave National Preserve. Plot locations are in `JOSH-JOTR/data/validation/2025_records-2311298/`.
- Vegetation survey data runs from 2015 to 2024 for JOTR. For DEVA there is only 2025.
- `josh-models` and `josh-mojn-eval` already pull climate data (PRISM and one LOCA2 model) for each plot in JOTR and DEVA.

## 2026-11-24: Plan for yearly rainfall over the whole Mojave

- Study area: we have a Mojave outline (EPA level III ecoregion "Mojave Basin and Range") in `JOSH-JOTR/data/boundaries/us_eco_l3_state_boundaries.shp`. Its bounding box is about 33.7–37.5°N and 118.7–113.0°W. The California part ends at about 114.5°W.
- The idea is to fetch, for each dataset, only that area, add the months up to yearly totals, and keep only the totals.
- Still to decide before writing scripts: calendar year or water year (Oct–Sep), a map per year or one average per region, which models and scenarios to include, and where the Pierce et al. data is hosted.

## 2026-11-24: Decisions

- Study area: the whole Mojave wherever a dataset covers it. CalAdapt covers only the California part, so it is used only there.
- Water years (October to September) instead of calendar years.
- Outputs: for each spatial level (Mojave, parks, I&M plots), one yearly rainfall time series per dataset, plus an anomaly map showing all spatial units.
- Outlines found on disk: Mojave = EPA ecoregion; parks = official NPS outlines (`nps_boundary.shp`); plots = the centre coordinates of the 35 plots in each park.
- Pierce et al. 2021 data: https://cirrus.ucsd.edu/~pierce/nonsplit_precip/precip/. There is one file per year for 1915–2018, about 0.57 GB each, covering the whole US. The server cannot crop files to the Mojave. (Later it turned out each file can be read in part, so only the Mojave rows are downloaded, about 90 MB per year; see below.)

## 2026-11-24: Outlines (boundaries) set up

- Parks: JOTR and DEVA only.
- Anomaly maps: the reference period is water years 1951–1980. For observation datasets the event year is water year 1983 (Oct 1982 to Sep 1983). For climate models I use the wettest year in each historical run outside the reference period.
- I copied the source files into this repo so it doesn't depend on other folders. The originals are untouched.
  - `data/raw/boundaries/`: the EPA ecoregions and the NPS park outlines, from `JOSH-JOTR`.
  - `data/raw/im_plots/`: the MOJN plot table (`MOJN_IU_SOP07_SiteEstablishment_Data.csv`).
- `code/01_boundaries.R` turns these into the outlines we use, in `data/boundaries/`:
  - `mojave`: the whole Mojave ecoregion, 127,700 km²
  - `mojave_ca`: the California part, 74,800 km², for CalAdapt
  - `parks`: JOTR and DEVA
  - `parks_ca`: the California part of the parks. DEVA loses a 450 km² strip in Nevada; JOTR is entirely in California.
  - `im_plots`: one point per plot, 35 in each park
- Things to know:
  - All 70 plots lie in California.
  - One DEVA plot (DEVAB001, at the northern tip of the park) lies just outside the Mojave ecoregion.
  - Parts of both parks also lie outside the ecoregion. This only matters if the parks are meant to be part of the "Mojave" average.
- The R style guide (`StyleGuideR.md`) is copied from `climate_futures`, the newest version (10 Aug 2026).

## 2026-11-24: Processing the rainfall data

**Setup**
- Python environment: `environment.yml`. Create it with `conda env create -f environment.yml`, then run the scripts from the repo folder with `conda run -n superelnino python code/<script>.py`.
- Scripts:
  - `code/climate_tools.py`: steps shared by all datasets
  - `02_prism.py`, `03_era5.py`, `04_pierce.py`, `05_caladapt.py`, `06_cmip6.py`, `07_isimip.py`: one per dataset
- Each script fetches only a box around the Mojave (33–38.5°N, 120–112°W), adds the months up to water-year totals (October to September, named by the year in which September falls), and saves two files to `data/processed/<dataset>/`:
  - `*_water_year_pr.nc`: a map of water-year totals (mm) at the dataset's own resolution.
  - `*_water_year_pr_units.csv`: one value per water year for the Mojave, the two parks and each of the 70 plots, each with and without the Nevada/Arizona parts (`california_only`). For the Mojave and the parks the value is an area-weighted average over all grid cells touching the outline; partly covered cells count less. For a plot it is the value of the grid cell the plot falls in. `coverage` is the share of the area that has data.
- Run messages are in `logs/`.

**What I found while checking access**
- CalAdapt (LOCA2-Hybrid) is not limited to California. Its grid has values over most of the Mojave, including Nevada and Arizona. I therefore compute it for the whole Mojave as well; the `coverage` column shows how complete it is.
- CalAdapt monthly values are average daily rates (kg m⁻² s⁻¹), not monthly sums. I multiply them by the seconds in each month.
- Pierce files can be read in part over the internet, about 90 MB per year instead of 600 MB. Nothing is stored temporarily.
- The ISIMIP server crops the files to the Mojave itself, so the repo doesn't need the copy in `climate_futures`.

**Periods and models**
- Observations:
  - PRISM 4 km: water years 1951–2025
  - ERA5: 1941–2025
  - ERA5-Land: 1951–2025
  - Pierce: 1951–2018
- Models, all water years 1951–2014, first run of each model:
  - CalAdapt LOCA2: 15 models
  - CMIP6: the same models plus UKESM1-0-LL, 16 in total
  - ISIMIP3b: 5 models
- PRISM 800 m is possible with `02_prism.py 800m`, but it means about 45 GB of downloading, so I haven't run it.
- Pierce update: the first full run failed after 1984 because the connection to the UCSD server timed out. `04_pierce.py` now saves each year to `data/interim/pierce/` as soon as it is read (about 1 MB per year), retries a year up to 5 times, and skips years it already has when run again.
- Pierce update 2: reading one year at a time slowed to about 5 minutes per year. `04_pierce.py` can now take a range of years (`04_pierce.py 1954 1970`), so several ranges download side by side. Run it without a range to combine all years. With 4 ranges in parallel it reads about 4 years per minute.

## 2026-11-24: Figures

- `code/08_timeseries.R` makes one time-series figure per spatial level, saved in `outputs/figures/`:
  - `timeseries_mojave.png` and `timeseries_parks.png`: observations in blue; for climate models, single runs in thin grey and the model median in black.
  - `timeseries_im_plots.png`: one line per plot; for climate models, the median over all models.
  - In all three, the reference period 1951–1980 is shaded and water year 1983 is marked with a dashed line.
- `code/09_anomaly_maps.R` makes the anomaly maps: rainfall in the event year as a percentage of the 1951–1980 average.
  - For observations the event year is water year 1983 (`anomaly_observations.png`).
  - For each climate model it is the wettest water year in the Mojave after 1980 (`anomaly_caladapt_loca2.png`, `anomaly_cmip6.png`, `anomaly_isimip3b.png`). The year is shown in each panel title.
  - Each map shows the Mojave outline, both parks and all 70 I&M plots.
- All figures use the whole Mojave and whole parks, not the California-only versions. The tables contain both.
- Pierce finished: water years 1951–2018, no gaps. One year (1989) needed a retry after a dropped connection. Both figure scripts have been re-run with Pierce included.
- Map style: the Mojave outline is drawn thicker in black, and the parks in solid red. The small red dot east of DEVA is Devils Hole, a detached part of Death Valley National Park in Nevada.
- Park averages for water year 1983 (mm):
  - JOTR: PRISM 450 mm, Pierce 406, ERA5-Land 337, ERA5 324
  - DEVA: ERA5-Land 366, ERA5 365, PRISM 295, Pierce 286

## 2026-11-24: Rain gauges as a check

- `code/10_gauges.py` downloads daily NOAA rain-gauge records (GHCN-Daily) for gauges inside the two parks or up to 3 km outside them. Only gauges with at least 10 years of record are included.
  - Joshua Tree has only 2 gauges strictly inside the park, and only one of those measured in 1983, so the gauges just outside the boundary are needed.
  - A water year counts only if at least 335 days were reported. Gauges with fewer than 5 such years are dropped.
  - That leaves 12 gauges: 6 for DEVA and 6 for JOTR.
  - The raw daily files are in `data/raw/gauges/`. The results are in `data/processed/gauges/`, with each gridded observation dataset's value at the grid cell containing each gauge.
- `code/11_gauge_timeseries.R` makes `gauges_timeseries.png` (one panel per gauge) and `gauges_water_year_1983.png` (all sources at each gauge in 1983). Colours: PRISM #FC4E07 (orange-red), Pierce #00AFBB (teal), ERA5-Land #E7B800 (yellow), ERA5 #8B4769 (plum), taken from the `expevo` palette of the ltc collection (github.com/loukesio/ltc-color-palettes); the gauge is black. Checked to stay distinguishable for colour-blind readers.
- Findings:
  - In JOTR in 1983, PRISM matches the gauges closely where gauges existed: Twentynine Palms 331 vs 329 mm, Eagle Mountain 325 vs 332 mm. All of these gauges are below 620 m.
  - The very high 1983 values (PRISM up to 690 mm at about 1000 m, where most I&M plots are) can't be checked directly: no gauge above 620 m has a complete record for water year 1983.
  - Over all years with data, PRISM's average is within 2–10 % of every JOTR gauge, including the highest one at 1039 m (16 years, 2010–2026). So PRISM's increase in rain with elevation agrees with the gauges on average.
  - PRISM and Pierce are built from these same gauges, so they're expected to match them. ERA5 and ERA5-Land are not, and they are about twice as wet as the gauges on the Death Valley floor (for example 126 vs 57 mm per year at Furnace Creek), because their grid cells include the surrounding mountains.
- `gauges_timeseries_with_models.png` adds the multi-model mean of each climate model dataset at each gauge (the grid cell containing the gauge, averaged over all model runs: 15 CalAdapt, 16 CMIP6, 5 ISIMIP3b). `10_gauges.py` saves these to `data/processed/gauges/gauges_model_means_water_year_pr.csv`.
  - Colours: observations in reds and oranges (PRISM #9B2226, Pierce #E05256, ERA5-Land #CA6702, ERA5 #FFB000); model means in blue and green (CalAdapt #0f8096, CMIP6 #4e54ac, ISIMIP3b #17a769); gauges in black. All taken from the ltc collection. I chose them by computer search so that all 8 lines stay distinguishable for colour-blind readers.
- `gauges_timeseries_with_models.png` now shows every single model run as a thin line in its dataset's colour, instead of the model means: 15 CalAdapt, 16 CMIP6 and 5 ISIMIP3b runs. `10_gauges.py` saves the single runs to `data/processed/gauges/gauges_model_runs_water_year_pr.csv`; the means file is still written. For every dataset, the value at a gauge is that of the grid cell whose centre is closest to the gauge, which is the cell the gauge lies in.
- CMIP6 runs are left out of `gauges_timeseries_with_models.png` for now; the figure shows the 15 CalAdapt and 5 ISIMIP3b runs. The CMIP6 values at the gauges are still saved in `gauges_model_runs_water_year_pr.csv`.
- Removed my unrequested interpretations from this log, following the new rule in `instructions.md`.
- ERA5 is also left out of `gauges_timeseries_with_models.png`; ERA5-Land stays.
- All gauge figures now use the same colours: observations in reds and oranges (PRISM #9B2226, Pierce #E05256, ERA5-Land #CA6702, ERA5 #FFB000), model runs in teal (CalAdapt #0f8096) and green (ISIMIP3b #17a769), gauges in black. All panels of the gauge time series now share the same y-axis range.

## 2026-11-25: I&M plots as areas, code clean-up

- I&M plots are now 500 m × 500 m squares instead of points. They are copied from `josh-models` (DEVA: `data/grids/deva/_polygons/`; JOTR: `data/grids/im_validation/im_plots_500m_uniform/_polygons/`, without the 10 `JOTREXTRA` sites) into `data/raw/im_plots/polygons/`. Each square is centred on the plot's surveyed marker. The square centres are 50 m (at most 135 m) from the points used before. The old plot table was removed.
- Plots are now summarised like the parks and the Mojave: an area-weighted average of the grid cells that overlap each square.
- Summarising is now a separate step, `code/08_summarise_units.py`, which reads the saved yearly maps. The download scripts (02–07) only save the maps. Later scripts are renumbered: `09_timeseries.R`, `10_anomaly_maps.R`, `11_gauges.py`, `12_gauge_timeseries.R`.
- All tables and figures for the Mojave, parks and plots have been re-made. Gauge figures are unchanged, because they don't use the plots.
- PRISM log: the 120 "Error in sys.excepthook" messages appeared because the script didn't close the PRISM files it opened over the internet. Python reported them while shutting down. Tested: the values read are identical with and without closing. `02_prism.py` now closes each file.

## 2026-11-25: Code review changes

- Averages over the Mojave, parks and plots are now computed with the `exactextract` package (the same method as `terra::extract(exact = TRUE)` and `exactextractr` in R) instead of my own code. It weights each grid cell by the share that lies inside an outline, and skips cells without data. `coverage` is now the share of an outline that has data, computed the same way.
  - Results agree with the previous version to within 0.3 mm, except for plots on the coarse CMIP6 and ISIMIP3b grids. There, my own code had placed the edges of the large grid cells slightly wrong, so plots near a cell edge were assigned to the wrong cell. The new values are correct.
  - The tables in `data/processed/` and all figures have been re-made.
- Water year is now assigned explicitly: October–December count towards the following year (`water_year()` in `climate_tools.py`).
- Naming: "grid" now only means the layout of cells. One year of precipitation values on that grid is a "map" (`save_water_year_map`, `read_water_year_map`, `calculate_anomaly_map`). `standardise_grid` is split into `standardise_coordinates` and `crop_to_mojave`. In `02_prism.py`, `file_code` is renamed `prism_file_resolution`.
- R scripts (`09`, `10`, `12`) are restructured into named functions. The time series now use a single function for the Mojave, parks and plots; for plots it leaves out the single model runs (70 plots × up to 16 runs would be over 1000 lines per panel). Two rules were added to `StyleGuideR.md`: steps longer than two lines of tidyverse code become named functions, and no anonymous functions (`\(x)`).
- Gauges: three mountain stations southwest of JOTR were added: Deep Canyon Lab (366 m, 28.5 km), Snow Creek Upper (591 m, 23.4 km) and Idyllwild Fire Dept (1640 m, 33.4 km). In January 1983, PRISM used 17 stations within 40 km of JOTR; all above 700 m are in that area. `11_gauges.py` was also restructured into functions and records how each gauge was selected.
- New: `code/13_gauge_map.R` makes `gauges_map.png`, showing where all gauges are relative to the parks and the I&M plots.
- `data/interim/pierce/` is kept for now.
- Renamed the internal helper `extract_by_unit` to `mean_by_unit_with_partial_cells` in `climate_tools.py`.

## 2026-11-25: Processing separated from plotting, data/final, .gitignore

- Each figure script (`09`, `10`, `12`, `13`) now has a processing part and a plotting part. Processing prepares everything a figure needs and writes it to `data/final/`. Plotting reads only from `data/final/` and draws. `01_boundaries.R` also writes the outlines used in the maps to `data/final/boundaries.gpkg` (Mojave, parks, plot squares, plot centres).
- `data/final/` (12 MB):
  - `timeseries_water_year_pr.csv.gz`: yearly totals for the Mojave, parks and plots, including the model medians. A `line_type` column says whether each line is an observation, a model run or a model median.
  - `anomaly_maps.csv.gz`: the plotted maps. One water year per dataset or model run, with the 1951–1980 average and the percentage.
  - `gauges_timeseries.csv` and `gauges_water_year_1983.csv`: data of the gauge figures. The 1983 status of each gauge (complete, incomplete, no readings) is decided in processing.
  - `gauge_map_stations.csv` and `gauge_map_extents.csv`: data of the gauge map.
  - `boundaries.gpkg`.
- All figures were re-made. They look the same as before.
- `StyleGuideR.md` now has two sections: general rules (always), and additional rules for final analysis code (functions, no anonymous functions, processing separate from plotting).
- New `.gitignore`: only `data/final/`, `data/raw/boundaries/` and `data/raw/im_plots/` are tracked in `data/`. `logs/` and Python cache files are ignored.
- Figures moved from `outputs/figures/` to `figures/` (the only output folder); they are tracked in git.
