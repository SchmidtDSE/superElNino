# Claude notes (AI->AI)

## Data inventory (checked 2026-11-24; paths relative to /Users/lucialayr/Desktop/NPS)

- PRISM 4km monthly ppt/tmean 1950-2025 GeoTIFF: `JOSH-JOTR/data/prism/{ppt,tmean}/<year>/prism_<var>_<yyyymm>_{clipped,jotr_distribution_clipped}.tif`.
  `clipped` = JOTR bbox (33.65-34.15N, -116.48..-115.23). `jotr_distribution_clipped` = 141x104 px, 33.77-38.10N, -118.81..-112.94 (covers DEVA + most of Mojave).
- PRISM 800m monthly 1950-2025 nc (LOCA2 units: tas K, pr = monthly mm/86400): `josh-models/data/nc/{jotr,deva}/monthly/prism_{tas,pr}_<park>_monthly.nc`. Made by `josh-models/scripts/intake_prism.py` (uses nps_boundary.shp, could add moja).
- LOCA2 (CalAdapt) monthly, 1/32 deg, gridded park bbox: `climate_futures/caladapt/<gcm>_<member>_loca2_<scen>_{pr,tas}_{jotr,deva,moja}_monthly.nc`. 15 GCMs; historical 1950-2014 (780 steps); ssp245/370/585 (not all GCMs). Dims (member_id,time,lat,lon). deva bbox 35.58-37.33N, -117.92..-116.27.
  `climate_data_pipeline/caladapt` = older subset (jotr, moja only).
- ISIMIP3b W5E5 bias-adjusted, daily 0.5deg, region "southus" 25.25-41.75N, -124.75..-93.25, decadal files 1850-2100: `climate_futures/isimip/data/interim/` (pr, tas; gfdl-esm4, ipsl-cm6a-lr, mpi-esm1-2-hr, mri-esm2-0, ukesm1-0-ll; hist, ssp126/370/585). Processed monthly for jotr and "mojave" (= MOJA-ish box) in `.../processed/`. Identical copy in climate_data_pipeline/isimip.
- Raw CMIP6 daily pr, historical, native global grid: `climate_data_pipeline/cmip6/data/raw/` (GFDL-ESM4, IPSL-CM6A-LR, MPI-ESM1-2-HR complete; MRI-ESM2-0 3/4 files 0 bytes).
- Climate futures classifications: `climate_futures/outputs/climate_futures_{jotr,deva}.csv` etc.
- Not found: ERA5, Pierce et al. (2021 JHM), Livneh, gridMET.
- I&M plots: `JOSH-JOTR/data/validation/2025_records-2311298/MOJN_IU_SOP07_*` (markers UTM 11N NAD83; ~6 markers/site; 35 sites each JOTR/DEVA/~34 MOJA). LPI JOTR 2015-2024, MOJA 2015-2022, DEVA 2025 only. Site coords also in SiteEstablishment XCOORD/YCOORD. DEVA elevations: DEVA_IU_SiteElevation.xlsx.
  `josh-models/data/grids/{deva,im_plots,...}` per-site grids; `josh-models/notebooks/analysis/im_plots_climatology.qmd` per-site climatology; `josh-models/DATA_COMPARISON.md` gap table (partly outdated: DEVA grids now exist).
- `josh-mojn-eval/{JOTR,DEVA}/data/climate/` per-plot LOCA2 GFDL-ESM4 + PRISM 800m pr. `YUBR_range/` PRISM 4km annual over the western Joshua tree range.
- Boundaries: `JOSH-JOTR/data/boundaries/` (jotr, deva, nps_boundary, us_eco_l3 ecoregions -> can define Mojave Basin & Range L3 for whole-Mojave domain), `climate_futures/boundaries/` (jotr, deva, moja).

## Repo layout (superElNino)
- data/raw/boundaries: copied sources (originals in JOSH-JOTR). data/raw/im_plots/polygons: 70 x 500m squares from josh-models (deva/_polygons, im_validation/im_plots_500m_uniform/_polygons, no JOTREXTRA). data/boundaries: outputs of code/01_boundaries.R (EPSG:4326 shapefiles: mojave, mojave_ca, parks, parks_ca, im_plots[park, plot] polygons).
- Run R scripts from repo root (relative paths). Style: StyleGuideR.md (copy of climate_futures version, newest): `=`, %>%, snake_case, <=80 chars, no line ending with ( or starting with ), few comments.
- Decisions: parks JOTR+DEVA; water years Oct-Sep (WY named by end year); ref WY1951-1980; obs event WY1983; models: wettest hist year outside ref period; CalAdapt only CA part (mojave_ca, parks_ca).
- Pierce: https://cirrus.ucsd.edu/~pierce/nonsplit_precip/precip/livneh_unsplit_precip.2021-05-02.YYYY.nc, 1915-2018, ~570MB/yr CONUS, no subsetting.
- Note: SiteEstablishment Elevation_m looks like feet for some DEVA sites (DEVAB002 = 5290).

## Processing (2026-11-24)
- env: conda `superelnino` (environment.yml). Run via `/opt/miniconda3/bin/conda run -n superelnino python code/XX.py` (conda run needed: base PROJ_DATA env var otherwise breaks pyproj).
- climate_tools.py: load_units (regions, parks, plots all polygons; GOTCHA use d['plot'] not d.plot on GeoDataFrame), standardise_grid, monthly_total_mm, water_year_totals (WY = year + (month>=10), only complete 12-month WYs), summarise_units via exactextract 'mean' (coverage-fraction weighted; my old shapely code misplaced coarse cell edges), share_of_unit_with_data, save_water_year_map. Naming: 'grid' = cell layout only; one year of values = 'map'.
- Pipeline: 01 boundaries (R), 02-07 download -> save_grid, 08_summarise_units.py -> *_units.csv, 09_timeseries.R, 10_anomaly_maps.R, 11_gauges.py (incl. 3 mountain stations), 12_gauge_timeseries.R, 13_gauge_map.R. R style: functions for >2-line tidyverse steps, no anonymous functions.
- Output: data/processed/<dataset>/<dataset>[_<model>_<member>]_water_year_pr.nc + _units.csv (cols dataset, model, level[region/park/plot], unit, park, california_only, water_year, pr_mm, coverage).
- Units checks: CalAdapt mon = mean daily rate kg m-2 s-1 (verified vs day). ERA5 monthly means tp = m/day. Pierce PRCP mm/day, var dims (Time, lat, lon), contiguous uncompressed HDF5 -> fsspec range reads. ISIMIP pr kg m-2 s-1 daily. PRISM mm.
- NOTE climate_futures/caladapt files were made with resample().sum() of daily rates -> value*86400 = mm (different from CalAdapt 'mon' table).
- Logs in logs/.

## data/final + git (2026-11-25)
- Figure scripts 09/10/12/13: '# Processing' functions write data/final/*, '# Plotting' functions read only data/final. 01_boundaries.R writes data/final/boundaries.gpkg (mojave, parks, im_plots, im_plot_centres).
- .gitignore tracks data/final, data/raw/boundaries, data/raw/im_plots only. User must run `git rm -r --cached data logs` to untrack previously committed data (history keeps them).
