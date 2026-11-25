import tempfile
import time
import zipfile
from pathlib import Path

import requests
import xarray as xr

import climate_tools as ct

api_url = 'https://files.isimip.org/api/v2'
models = {'GFDL-ESM4': 'r1i1p1f1', 'IPSL-CM6A-LR': 'r1i1p1f1',
          'MPI-ESM1-2-HR': 'r1i1p1f1', 'MRI-ESM2-0': 'r1i1p1f1',
          'UKESM1-0-LL': 'r1i1p1f2'}
decades = ['1941_1950', '1951_1960', '1961_1970', '1971_1980', '1981_1990',
           '1991_2000', '2001_2010', '2011_2014']
box = ct.mojave_box


def isimip_path(model, member, decade):
    return ('ISIMIP3b/InputData/climate/atmosphere/bias-adjusted/global/daily/'
            f'historical/{model}/{model.lower()}_{member}_w5e5_historical_pr_'
            f'global_daily_{decade}.nc')


def request_cutout(paths):
    job = {'paths': paths, 'operations': [{
        'operation': 'select_bbox',
        'bbox': [box['west'], box['east'], box['south'], box['north']]}]}
    while True:
        response = requests.post(api_url, json=job, timeout=120).json()
        if response.get('errors') or response['status'] == 'failed':
            raise RuntimeError(response)
        if response['status'] == 'finished':
            return response['file_url']
        time.sleep(30)


paths = [isimip_path(model, member, decade)
         for model, member in models.items() for decade in decades]
zip_url = request_cutout(paths)

with tempfile.TemporaryDirectory() as tmp:
    archive = Path(tmp) / 'isimip.zip'
    archive.write_bytes(requests.get(zip_url, timeout=600).content)
    zipfile.ZipFile(archive).extractall(tmp)
    for model, member in models.items():
        files = sorted(Path(tmp).rglob(f'{model.lower()}_{member}_*.nc'))
        daily_rate = xr.open_mfdataset(files)['pr'].sel(
            time=slice('1950-01', '2014-12'))
        daily_rate = ct.crop_to_mojave(ct.standardise_coordinates(daily_rate))
        daily_mm = daily_rate.load() * ct.seconds_per_day
        monthly_mm = daily_mm.resample(time='MS').sum(min_count=1)
        ct.save_water_year_map(ct.water_year_totals(monthly_mm),
                               'isimip3b', f'{model}_{member}')
