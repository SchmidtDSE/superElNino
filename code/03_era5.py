import tempfile
from pathlib import Path

import cdsapi
import xarray as xr

import climate_tools as ct

products = {
    'era5': ('reanalysis-era5-single-levels-monthly-means', 1940),
    'era5_land': ('reanalysis-era5-land-monthly-means', 1950)}
last_year = 2025
box = ct.mojave_box
client = cdsapi.Client(quiet=True)

for dataset, (cds_name, first_year) in products.items():
    request = {
        'product_type': ['monthly_averaged_reanalysis'],
        'variable': ['total_precipitation'],
        'year': [str(y) for y in range(first_year, last_year + 1)],
        'month': [f'{m:02d}' for m in range(1, 13)],
        'time': ['00:00'],
        'area': [box['north'], box['west'], box['south'], box['east']],
        'data_format': 'netcdf', 'download_format': 'unarchived'}
    with tempfile.TemporaryDirectory() as tmp:
        target = Path(tmp) / f'{dataset}.nc'
        client.retrieve(cds_name, request, str(target))
        metres_per_day = xr.open_dataset(target)['tp'].load()
    metres_per_day = metres_per_day.rename(valid_time='time')
    metres_per_day = ct.crop_to_mojave(ct.standardise_coordinates(
        metres_per_day, lat='latitude', lon='longitude'))
    monthly_mm = metres_per_day * 1000 * metres_per_day.time.dt.days_in_month
    ct.save_water_year_map(ct.water_year_totals(monthly_mm), dataset)
