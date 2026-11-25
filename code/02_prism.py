import sys
from concurrent.futures import ThreadPoolExecutor

import pandas as pd
import rioxarray
import xarray as xr

import climate_tools as ct

resolution = sys.argv[1] if len(sys.argv) > 1 else '4km'
prism_file_resolution = {'4km': '25m', '800m': '30s'}[resolution]
base_url = ('https://data.prism.oregonstate.edu/time_series/us/an/'
            f'{resolution}/ppt/monthly')
first_month, last_month = sys.argv[2:4] or ['1950-01-01', '2025-09-01']
months = pd.date_range(first_month, last_month, freq='MS')


def read_month(month):
    name = f'prism_ppt_us_{prism_file_resolution}_{month:%Y%m}'
    url = f'/vsizip//vsicurl/{base_url}/{month:%Y}/{name}.zip/{name}.tif'
    with rioxarray.open_rasterio(url, masked=True) as source:
        precipitation = ct.standardise_coordinates(
            source.squeeze('band', drop=True), lat='y', lon='x')
        precipitation = ct.crop_to_mojave(precipitation).load()
    return precipitation.drop_vars('spatial_ref').expand_dims(time=[month])


with ThreadPoolExecutor(max_workers=8) as pool:
    monthly_mm = xr.concat(list(pool.map(read_month, months)), dim='time')

ct.save_water_year_map(ct.water_year_totals(monthly_mm), f'prism_{resolution}')
