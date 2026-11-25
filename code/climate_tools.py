from pathlib import Path

import geopandas as gpd
import numpy as np
import pandas as pd
import rioxarray
import xarray as xr
from exactextract import exact_extract

repo = Path(__file__).resolve().parents[1]
boundaries_dir = repo / 'data' / 'boundaries'
processed_dir = repo / 'data' / 'processed'

mojave_box = dict(west=-120.0, east=-112.0, south=33.0, north=38.5)
equal_area_crs = 'EPSG:5070'
seconds_per_day = 86400


def load_units():
    region = gpd.read_file(boundaries_dir / 'mojave.shp').assign(
        level='region', unit='Mojave', park='', california_only=False)
    region_ca = gpd.read_file(boundaries_dir / 'mojave_ca.shp').assign(
        level='region', unit='Mojave', park='', california_only=True)
    parks = gpd.read_file(boundaries_dir / 'parks.shp').assign(
        level='park', unit=lambda d: d['park'], california_only=False)
    parks_ca = gpd.read_file(boundaries_dir / 'parks_ca.shp').assign(
        level='park', unit=lambda d: d['park'], california_only=True)
    plots = gpd.read_file(boundaries_dir / 'im_plots.shp').assign(
        level='plot', unit=lambda d: d['plot'], california_only=False)
    units = pd.concat([region, region_ca, parks, parks_ca, plots])
    columns = ['level', 'unit', 'park', 'california_only', 'geometry']
    return gpd.GeoDataFrame(units[columns], crs='EPSG:4326').reset_index(
        drop=True)


def standardise_coordinates(data, lat='lat', lon='lon'):
    data = data.rename({lat: 'lat', lon: 'lon'})
    if float(data.lon.max()) > 180:
        data = data.assign_coords(lon=((data.lon + 180) % 360) - 180)
    return data.sortby(['lat', 'lon'])


def crop_to_mojave(data):
    lat_spacing = float(np.abs(np.diff(data.lat.values)).max())
    lon_spacing = float(np.abs(np.diff(data.lon.values)).max())
    return data.sel(
        lat=slice(mojave_box['south'] - lat_spacing,
                  mojave_box['north'] + lat_spacing),
        lon=slice(mojave_box['west'] - lon_spacing,
                  mojave_box['east'] + lon_spacing))


def monthly_total_mm(monthly_rate):
    return monthly_rate * seconds_per_day * monthly_rate.time.dt.days_in_month


def water_year(time):
    october_to_december = time.dt.month >= 10
    return xr.where(october_to_december, time.dt.year + 1,
                    time.dt.year).rename('water_year')


def water_year_totals(monthly_mm):
    water_years = water_year(monthly_mm.time)
    totals = monthly_mm.groupby(water_years).sum('time', min_count=1)
    months_present = monthly_mm.time.groupby(water_years).count()
    complete_years = months_present.water_year[months_present == 12]
    totals = totals.sel(water_year=complete_years.values)
    totals.attrs = {'long_name': 'water-year precipitation total',
                    'units': 'mm',
                    'water_year': 'October of previous year to September'}
    return totals.rename('pr')


def mean_by_unit_with_partial_cells(water_year_values, units, value_name):
    raster = (water_year_values.rename(lat='y', lon='x')
              .transpose('water_year', 'y', 'x')
              .rio.write_crs('EPSG:4326'))
    table = exact_extract(raster, units, 'mean', output='pandas')
    table.columns = water_year_values.water_year.values
    return (table.join(units.drop(columns='geometry'))
            .melt(id_vars=['level', 'unit', 'park', 'california_only'],
                  var_name='water_year', value_name=value_name))


def mean_precipitation_by_unit(water_year_pr, units):
    return mean_by_unit_with_partial_cells(water_year_pr, units, 'pr_mm')


def share_of_unit_with_data(water_year_pr, units):
    has_data = water_year_pr.notnull().astype('float32')
    return mean_by_unit_with_partial_cells(has_data, units, 'coverage')


def summarise_units(water_year_pr, units):
    return mean_precipitation_by_unit(water_year_pr, units).merge(
        share_of_unit_with_data(water_year_pr, units))


def save_water_year_map(water_year_pr, dataset, model=None):
    out_dir = processed_dir / dataset
    out_dir.mkdir(parents=True, exist_ok=True)
    stem = f'{dataset}_{model}' if model else dataset
    stem = stem.lower().replace(' ', '_')
    water_year_pr = water_year_pr.astype('float32').load()
    extra_coords = [c for c in water_year_pr.coords
                    if c not in ('water_year', 'lat', 'lon')]
    water_year_pr = water_year_pr.reset_coords(extra_coords, drop=True)
    water_year_pr.attrs.update({'dataset': dataset, 'model': model or ''})
    water_year_pr.to_netcdf(out_dir / f'{stem}_water_year_pr.nc')
    print(f'saved {stem}: water years {int(water_year_pr.water_year.min())}-'
          f'{int(water_year_pr.water_year.max())}, '
          f'{water_year_pr.lat.size}x{water_year_pr.lon.size} grid cells')
